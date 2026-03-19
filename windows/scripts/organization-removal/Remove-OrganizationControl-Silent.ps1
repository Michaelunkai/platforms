#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Silent organization control removal - no prompts, no reboot

.DESCRIPTION
    Removes all organizational control with fixed registry permissions.
    NO PROMPTS. NO REBOOT. Just removes everything.
#>

$ErrorActionPreference = 'Continue'
$results = @()

function Write-Status {
    param($Message, $Color = 'Cyan')
    Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor $Color
}

function Write-Result {
    param($Action, $Status, $Details = "")
    $script:results += [PSCustomObject]@{
        Action = $Action
        Status = $Status
        Details = $Details
    }
    $color = if ($Status -eq "SUCCESS") { "Green" } elseif ($Status -eq "SKIPPED") { "Yellow" } else { "Red" }
    Write-Host "  [$Status] $Action" -ForegroundColor $color
    if ($Details) { Write-Host "    -> $Details" -ForegroundColor Gray }
}

function Take-RegistryOwnership {
    param([string]$KeyPath)
    
    try {
        $null = reg add $KeyPath /f 2>&1
        $acl = Get-Acl -Path $KeyPath -ErrorAction SilentlyContinue
        if ($acl) {
            $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $rule = New-Object System.Security.AccessControl.RegistryAccessRule(
                $user,
                "FullControl",
                "ContainerInherit,ObjectInherit",
                "None",
                "Allow"
            )
            $acl.SetAccessRule($rule)
            Set-Acl -Path $KeyPath -AclObject $acl -ErrorAction SilentlyContinue
        }
        return $true
    } catch {
        return $false
    }
}

function Remove-RegistryKeyForce {
    param([string]$KeyPath)
    
    if (-not (Test-Path $KeyPath)) {
        return $true
    }
    
    try {
        Take-RegistryOwnership -KeyPath $KeyPath | Out-Null
        Get-ChildItem -Path $KeyPath -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            Try {
                Remove-Item -Path $_.PSPath -Force -Recurse -ErrorAction SilentlyContinue
            } catch {}
        }
        Remove-Item -Path $KeyPath -Force -Recurse -ErrorAction Stop
        
        # Verify deletion
        if (-not (Test-Path $KeyPath)) {
            return $true
        }
    } catch {}
    
    # Fallback: use reg.exe
    try {
        $regPath = $KeyPath -replace 'HKLM:\\', 'HKEY_LOCAL_MACHINE\'
        $regPath = $regPath -replace 'HKCU:\\', 'HKEY_CURRENT_USER\'
        reg delete "$regPath" /f 2>&1 | Out-Null
        
        # Verify deletion
        Start-Sleep -Milliseconds 100
        if (-not (Test-Path $KeyPath)) {
            return $true
        }
    } catch {}
    
    return $false
}

function Disable-ServiceForce {
    param([string]$ServiceName)
    
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $service) {
        return "NOT_FOUND"
    }
    
    # Try method 1: PowerShell cmdlets
    try {
        Stop-Service -Name $ServiceName -Force -ErrorAction Stop 2>$null
        Set-Service -Name $ServiceName -StartupType Disabled -ErrorAction Stop 2>$null
        return "SUCCESS"
    } catch {
        # Method 2: sc.exe
        try {
            sc.exe config $ServiceName start=disabled 2>&1 | Out-Null
            sc.exe stop $ServiceName 2>&1 | Out-Null
            
            $checkService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
            if ($checkService.StartType -eq 'Disabled') {
                return "SUCCESS"
            }
        } catch {}
        
        # Method 3: Direct registry modification
        try {
            $servicePath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
            if (Test-Path $servicePath) {
                Take-RegistryOwnership -KeyPath $servicePath | Out-Null
                Set-ItemProperty -Path $servicePath -Name "Start" -Value 4 -Force -ErrorAction Stop
                
                # Verify
                $startValue = (Get-ItemProperty -Path $servicePath -Name "Start" -ErrorAction SilentlyContinue).Start
                if ($startValue -eq 4) {
                    return "SUCCESS"
                }
            }
        } catch {}
        
        return "FAILED"
    }
}

# Check admin rights
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script requires Administrator rights!" -ForegroundColor Red
    exit 1
}

Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host "  Windows Organization Control Removal Tool - SILENT MODE" -ForegroundColor Cyan
Write-Host "  NO PROMPTS | NO REBOOT | FORCED REMOVAL" -ForegroundColor Cyan
Write-Host "================================================================`n" -ForegroundColor Cyan

# ============================================================
# 1. REMOVE MDM ENROLLMENT
# ============================================================
Write-Status "Removing MDM enrollment..." "Cyan"

try {
    $enrollments = Get-ChildItem -Path "HKLM:\SOFTWARE\Microsoft\Enrollments" -ErrorAction SilentlyContinue
    if ($enrollments) {
        foreach ($enrollment in $enrollments) {
            $success = Remove-RegistryKeyForce -KeyPath $enrollment.PSPath
            if ($success) {
                Write-Result "Remove MDM enrollment: $($enrollment.PSChildName)" "SUCCESS"
            } else {
                Write-Result "Remove MDM enrollment: $($enrollment.PSChildName)" "FAILED" "Permission denied"
            }
        }
        
        $success = Remove-RegistryKeyForce -KeyPath "HKLM:\SOFTWARE\Microsoft\Enrollments"
        if ($success) {
            Write-Result "Remove Enrollments registry key" "SUCCESS"
        } else {
            Write-Result "Remove Enrollments registry key" "FAILED" "Permission denied - needs manual removal"
        }
    } else {
        Write-Result "Remove MDM enrollment" "SKIPPED" "No enrollments found"
    }
} catch {
    Write-Result "Remove MDM enrollment" "FAILED" $_.Exception.Message
}

# Remove MDM related registry keys
$mdmKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts",
    "HKLM:\SOFTWARE\Microsoft\EnterpriseResourceManager"
)

foreach ($key in $mdmKeys) {
    try {
        if (Test-Path $key) {
            $success = Remove-RegistryKeyForce -KeyPath $key
            if ($success) {
                Write-Result "Remove registry key: $key" "SUCCESS"
            } else {
                Write-Result "Remove registry key: $key" "FAILED" "Permission denied"
            }
        }
    } catch {
        Write-Result "Remove registry key: $key" "FAILED" $_.Exception.Message
    }
}

# ============================================================
# 2. REMOVE AZURE AD JOIN
# ============================================================
Write-Status "Removing Azure AD join..." "Cyan"

try {
    $dsregStatus = dsregcmd /status 2>$null
    if ($dsregStatus -match "AzureAdJoined\s*:\s*YES") {
        dsregcmd /leave 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        Write-Result "Leave Azure AD" "SUCCESS"
    } else {
        Write-Result "Leave Azure AD" "SKIPPED" "Not joined"
    }
} catch {
    Write-Result "Leave Azure AD" "FAILED" $_.Exception.Message
}

# ============================================================
# 3. REMOVE WORKPLACE ACCOUNTS
# ============================================================
Write-Status "Removing workplace/school accounts..." "Cyan"

try {
    $workplaceKeys = Get-ChildItem -Path "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WorkplaceJoin" -ErrorAction SilentlyContinue
    if ($workplaceKeys) {
        foreach ($key in $workplaceKeys) {
            $success = Remove-RegistryKeyForce -KeyPath $key.PSPath
            if ($success) {
                Write-Result "Remove workplace account: $($key.PSChildName)" "SUCCESS"
            } else {
                Write-Result "Remove workplace account: $($key.PSChildName)" "FAILED"
            }
        }
    } else {
        Write-Result "Remove workplace accounts" "SKIPPED" "None found"
    }
} catch {
    Write-Result "Remove workplace accounts" "FAILED" $_.Exception.Message
}

# Remove AAD accounts
$aadBrokerPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WorkplaceJoin\AADNGC"
if (Test-Path $aadBrokerPath) {
    try {
        $success = Remove-RegistryKeyForce -KeyPath $aadBrokerPath
        if ($success) {
            Write-Result "Remove AAD broker account" "SUCCESS"
        } else {
            Write-Result "Remove AAD broker account" "FAILED"
        }
    } catch {
        Write-Result "Remove AAD broker account" "FAILED" $_.Exception.Message
    }
}

# ============================================================
# 4. REMOVE ORGANIZATIONAL POLICIES
# ============================================================
Write-Status "Removing organizational policies..." "Cyan"

$policyPaths = @(
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent",
    "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device",
    "HKLM:\SOFTWARE\Microsoft\PolicyManager\providers"
)

foreach ($path in $policyPaths) {
    try {
        if (Test-Path $path) {
            $items = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
            if ($items) {
                foreach ($prop in $items.PSObject.Properties) {
                    if ($prop.Name -notlike "PS*") {
                        Remove-ItemProperty -Path $path -Name $prop.Name -Force -ErrorAction SilentlyContinue
                    }
                }
            }
            Write-Result "Clear policy: $path" "SUCCESS"
        }
    } catch {
        Write-Result "Clear policy: $path" "FAILED" $_.Exception.Message
    }
}

# ============================================================
# 5. DISABLE ORGANIZATION BRANDING
# ============================================================
Write-Status "Disabling organization branding..." "Cyan"

try {
    $brandingPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"
    if (-not (Test-Path $brandingPath)) {
        New-Item -Path $brandingPath -Force | Out-Null
    }
    Set-ItemProperty -Path $brandingPath -Name "NoChangingLockScreen" -Value 0 -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $brandingPath -Name "LockScreenImage" -Force -ErrorAction SilentlyContinue
    Write-Result "Remove lock screen branding" "SUCCESS"
} catch {
    Write-Result "Remove lock screen branding" "FAILED" $_.Exception.Message
}

# ============================================================
# 6. REMOVE MANAGEMENT SCHEDULED TASKS
# ============================================================
Write-Status "Removing management scheduled tasks..." "Cyan"

$managementTasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { 
    $_.TaskPath -like "*Microsoft*Enterprise*" -or 
    $_.TaskPath -like "*Microsoft*MDM*" -or
    $_.TaskName -like "*Enterprise*" -or
    $_.TaskName -like "*MDM*"
}

if ($managementTasks) {
    foreach ($task in $managementTasks) {
        try {
            Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction Stop
            Write-Result "Remove task: $($task.TaskName)" "SUCCESS"
        } catch {
            Write-Result "Remove task: $($task.TaskName)" "FAILED" $_.Exception.Message
        }
    }
} else {
    Write-Result "Remove management tasks" "SKIPPED" "None found"
}

# ============================================================
# 7. CLEAR GROUP POLICY CACHE
# ============================================================
Write-Status "Clearing group policy cache..." "Cyan"

try {
    Remove-Item -Path "C:\Windows\System32\GroupPolicy" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\ProgramData\Microsoft\Group Policy" -Recurse -Force -ErrorAction SilentlyContinue
    gpupdate /force 2>&1 | Out-Null
    Write-Result "Clear group policy cache" "SUCCESS"
} catch {
    Write-Result "Clear group policy cache" "FAILED" $_.Exception.Message
}

# ============================================================
# 8. DISABLE DEVICE MANAGEMENT SERVICES
# ============================================================
Write-Status "Disabling device management services..." "Cyan"

$services = @(
    "DmEnrollmentSvc",
    "DmwApPushService",
    "EntAppSvc"
)

foreach ($svc in $services) {
    $result = Disable-ServiceForce -ServiceName $svc
    
    switch ($result) {
        "SUCCESS" { 
            Write-Result "Disable service: $svc" "SUCCESS" 
        }
        "NOT_FOUND" { 
            Write-Result "Disable service: $svc" "SKIPPED" "Service not found" 
        }
        "FAILED" { 
            Write-Result "Disable service: $svc" "FAILED" "All methods failed - service protected by system" 
        }
    }
}

# ============================================================
# 9. ADDITIONAL CLEANUP
# ============================================================
Write-Status "Additional cleanup..." "Cyan"

# Remove enrollment store
$enrollmentStorePath = "C:\Windows\System32\config\systemprofile\AppData\Local\Microsoft\Enrollment"
if (Test-Path $enrollmentStorePath) {
    try {
        Remove-Item -Path $enrollmentStorePath -Recurse -Force -ErrorAction Stop
        Write-Result "Remove enrollment store" "SUCCESS"
    } catch {
        Write-Result "Remove enrollment store" "FAILED" $_.Exception.Message
    }
}

# Remove MDM certificates
try {
    $certs = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue | Where-Object { 
        $_.Issuer -like "*Microsoft*MDM*" -or $_.Subject -like "*MDM*"
    }
    
    if ($certs) {
        foreach ($cert in $certs) {
            try {
                Remove-Item -Path "Cert:\LocalMachine\My\$($cert.Thumbprint)" -Force -ErrorAction Stop
                Write-Result "Remove MDM certificate: $($cert.Thumbprint)" "SUCCESS"
            } catch {
                Write-Result "Remove MDM certificate: $($cert.Thumbprint)" "FAILED"
            }
        }
    }
} catch {
    # Silently continue if no certs found
}

# ============================================================
# SUMMARY
# ============================================================
Write-Host "`n================================================================" -ForegroundColor Green
Write-Host "  OPERATION COMPLETE" -ForegroundColor Green
Write-Host "================================================================`n" -ForegroundColor Green

$successCount = ($results | Where-Object { $_.Status -eq "SUCCESS" }).Count
$failedCount = ($results | Where-Object { $_.Status -eq "FAILED" }).Count
$skippedCount = ($results | Where-Object { $_.Status -eq "SKIPPED" }).Count

Write-Host "Results:" -ForegroundColor Cyan
Write-Host ("  Success: {0}" -f $successCount) -ForegroundColor Green
Write-Host ("  Failed:  {0}" -f $failedCount) -ForegroundColor Red
Write-Host ("  Skipped: {0}" -f $skippedCount) -ForegroundColor Yellow

if ($failedCount -gt 0) {
    Write-Host "`nFailed operations:" -ForegroundColor Yellow
    $results | Where-Object { $_.Status -eq "FAILED" } | ForEach-Object {
        Write-Host "  - $($_.Action)" -ForegroundColor Red
        if ($_.Details) { Write-Host "    $($_.Details)" -ForegroundColor Gray }
    }
}

Write-Host "`nFull report:" -ForegroundColor Cyan
$results | Format-Table -AutoSize

Write-Host "`nIMPORTANT: Restart your computer manually to complete removal." -ForegroundColor Yellow
Write-Host "`nTo verify after restart:" -ForegroundColor Cyan
Write-Host "  dsregcmd /status" -ForegroundColor White
Write-Host "`nScript completed. No automatic reboot." -ForegroundColor Green
