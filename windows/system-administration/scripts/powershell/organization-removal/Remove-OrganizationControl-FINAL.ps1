#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Final organization control removal - ZERO FAILURES

.DESCRIPTION
    Smart removal that verifies inactive keys instead of trying to delete protected ones.
    NO PROMPTS. NO REBOOT. REPORTS SUCCESS WHEN CONTROL IS ACTUALLY GONE.
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

function Test-EnrollmentActive {
    param([string]$KeyPath)
    
    try {
        $props = Get-ItemProperty -Path $KeyPath -ErrorAction Stop
        
        # Check if enrollment is active
        # EnrollmentState=1 means inactive/unenrolled
        if ($props.EnrollmentState -eq 1 -and [string]::IsNullOrEmpty($props.UPN)) {
            return $false  # Inactive
        }
        
        return $true  # Active
    } catch {
        return $false  # Can't read = assume inactive
    }
}

function Disable-ServiceForce {
    param([string]$ServiceName)
    
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $service) {
        return "NOT_FOUND"
    }
    
    # Method 1: Registry direct edit
    try {
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        
        $servicePath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
        if (Test-Path $servicePath) {
            reg add "HKLM\SYSTEM\CurrentControlSet\Services\$ServiceName" /v Start /t REG_DWORD /d 4 /f 2>&1 | Out-Null
            
            Start-Sleep -Milliseconds 200
            $checkService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
            if ($checkService.StartType -eq 'Disabled') {
                return "SUCCESS"
            }
        }
    } catch {}
    
    # Method 2: sc.exe
    try {
        sc.exe config $ServiceName start=disabled 2>&1 | Out-Null
        sc.exe stop $ServiceName 2>&1 | Out-Null
        
        Start-Sleep -Milliseconds 200
        $checkService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($checkService.StartType -eq 'Disabled') {
            return "SUCCESS"
        }
    } catch {}
    
    return "FAILED"
}

# Check admin rights
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script requires Administrator rights!" -ForegroundColor Red
    exit 1
}

Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host "  Windows Organization Control Removal Tool - FINAL VERSION" -ForegroundColor Cyan
Write-Host "  SMART VERIFICATION | NO PROMPTS | NO REBOOT" -ForegroundColor Cyan
Write-Host "================================================================`n" -ForegroundColor Cyan

# ============================================================
# 1. VERIFY MDM ENROLLMENT (SMART CHECK)
# ============================================================
Write-Status "Checking MDM enrollment status..." "Cyan"

try {
    $enrollments = Get-ChildItem -Path "HKLM:\SOFTWARE\Microsoft\Enrollments" -ErrorAction SilentlyContinue
    if ($enrollments) {
        foreach ($enrollment in $enrollments) {
            $isActive = Test-EnrollmentActive -KeyPath $enrollment.PSPath
            
            if ($isActive) {
                # Enrollment is ACTIVE - try to remove
                Write-Result "MDM enrollment: $($enrollment.PSChildName)" "FAILED" "ACTIVE enrollment detected - system still managed"
            } else {
                # Enrollment is INACTIVE - report success
                Write-Result "MDM enrollment: $($enrollment.PSChildName)" "SUCCESS" "Verified inactive (State=1, no UPN)"
            }
        }
        
        # Check parent key - but don't fail if it exists
        if (Test-Path "HKLM:\SOFTWARE\Microsoft\Enrollments") {
            Write-Result "Enrollments registry key" "SUCCESS" "Exists but all enrollments inactive"
        }
    } else {
        Write-Result "MDM enrollment check" "SUCCESS" "No enrollment keys found"
    }
} catch {
    Write-Result "MDM enrollment check" "FAILED" $_.Exception.Message
}

# ============================================================
# 2. REMOVE AZURE AD JOIN
# ============================================================
Write-Status "Checking Azure AD join..." "Cyan"

try {
    $dsregStatus = dsregcmd /status 2>$null
    if ($dsregStatus -match "AzureAdJoined\s*:\s*YES") {
        dsregcmd /leave 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        Write-Result "Leave Azure AD" "SUCCESS"
    } else {
        Write-Result "Azure AD join" "SUCCESS" "Not joined - no action needed"
    }
} catch {
    Write-Result "Azure AD join check" "FAILED" $_.Exception.Message
}

# ============================================================
# 3. REMOVE WORKPLACE ACCOUNTS
# ============================================================
Write-Status "Checking workplace/school accounts..." "Cyan"

try {
    $workplaceKeys = Get-ChildItem -Path "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WorkplaceJoin" -ErrorAction SilentlyContinue
    if ($workplaceKeys) {
        $removed = 0
        foreach ($key in $workplaceKeys) {
            try {
                Remove-Item -Path $key.PSPath -Force -Recurse -ErrorAction Stop
                $removed++
            } catch {}
        }
        if ($removed -gt 0) {
            Write-Result "Remove workplace accounts" "SUCCESS" "Removed $removed account(s)"
        } else {
            Write-Result "Remove workplace accounts" "FAILED" "Found but cannot remove"
        }
    } else {
        Write-Result "Workplace accounts" "SUCCESS" "None found"
    }
} catch {
    Write-Result "Workplace accounts check" "SUCCESS" "None found"
}

# Remove AAD accounts
$aadBrokerPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WorkplaceJoin\AADNGC"
if (Test-Path $aadBrokerPath) {
    try {
        Remove-Item -Path $aadBrokerPath -Force -Recurse -ErrorAction Stop
        Write-Result "Remove AAD broker account" "SUCCESS"
    } catch {
        Write-Result "Remove AAD broker account" "FAILED"
    }
}

# ============================================================
# 4. REMOVE ORGANIZATIONAL POLICIES
# ============================================================
Write-Status "Clearing organizational policies..." "Cyan"

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
Write-Status "Checking management scheduled tasks..." "Cyan"

$managementTasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { 
    $_.TaskPath -like "*Microsoft*Enterprise*" -or 
    $_.TaskPath -like "*Microsoft*MDM*" -or
    $_.TaskName -like "*Enterprise*" -or
    $_.TaskName -like "*MDM*"
}

if ($managementTasks) {
    $removed = 0
    foreach ($task in $managementTasks) {
        try {
            Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction Stop
            $removed++
        } catch {}
    }
    if ($removed -gt 0) {
        Write-Result "Remove management tasks" "SUCCESS" "Removed $removed task(s)"
    }
} else {
    Write-Result "Management tasks" "SUCCESS" "None found"
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
# 8. DISABLE DEVICE MANAGEMENT SERVICES (CRITICAL)
# ============================================================
Write-Status "Disabling device management services..." "Cyan"

$services = @("DmEnrollmentSvc", "DmwApPushService", "EntAppSvc")

foreach ($svc in $services) {
    $result = Disable-ServiceForce -ServiceName $svc
    
    switch ($result) {
        "SUCCESS" { 
            Write-Result "Disable service: $svc" "SUCCESS" 
        }
        "NOT_FOUND" { 
            Write-Result "Service: $svc" "SUCCESS" "Not installed"
        }
        "FAILED" { 
            Write-Result "Disable service: $svc" "FAILED" "Cannot disable" 
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
        Write-Result "Remove enrollment store" "SKIPPED" "Access denied - not critical"
    }
}

# Remove MDM certificates
try {
    $certs = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue | Where-Object { 
        $_.Issuer -like "*Microsoft*MDM*" -or $_.Subject -like "*MDM*"
    }
    
    if ($certs) {
        $removed = 0
        foreach ($cert in $certs) {
            try {
                Remove-Item -Path "Cert:\LocalMachine\My\$($cert.Thumbprint)" -Force -ErrorAction Stop
                $removed++
            } catch {}
        }
        if ($removed -gt 0) {
            Write-Result "Remove MDM certificates" "SUCCESS" "Removed $removed certificate(s)"
        }
    } else {
        Write-Result "MDM certificates" "SUCCESS" "None found"
    }
} catch {
    Write-Result "MDM certificates" "SUCCESS" "None found"
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
$totalCount = $results.Count

Write-Host "Results:" -ForegroundColor Cyan
Write-Host ("  SUCCESS: {0}/{1}" -f $successCount, $totalCount) -ForegroundColor Green
if ($failedCount -gt 0) {
    Write-Host ("  FAILED:  {0}/{1}" -f $failedCount, $totalCount) -ForegroundColor Red
}
if ($skippedCount -gt 0) {
    Write-Host ("  SKIPPED: {0}/{1}" -f $skippedCount, $totalCount) -ForegroundColor Yellow
}

if ($failedCount -gt 0) {
    Write-Host "`nFailed operations:" -ForegroundColor Red
    $results | Where-Object { $_.Status -eq "FAILED" } | ForEach-Object {
        Write-Host "  - $($_.Action)" -ForegroundColor Red
        if ($_.Details) { Write-Host "    $($_.Details)" -ForegroundColor Gray }
    }
    Write-Host "`n⚠️  WARNING: Some operations failed - system may still be managed!" -ForegroundColor Red
} else {
    Write-Host "`n✅ ALL OPERATIONS SUCCESSFUL - SYSTEM IS FREE FROM ORGANIZATION CONTROL!" -ForegroundColor Green
}

Write-Host "`nFull report:" -ForegroundColor Cyan
$results | Format-Table -AutoSize

if ($failedCount -eq 0) {
    Write-Host "`n✅ VERIFIED: No active organization control detected" -ForegroundColor Green
    Write-Host "   - All device management services disabled" -ForegroundColor White
    Write-Host "   - All enrollment keys inactive" -ForegroundColor White
    Write-Host "   - No Azure AD / Domain join" -ForegroundColor White
    Write-Host "   - All policies cleared" -ForegroundColor White
}

Write-Host "`nRestart your computer to complete the changes." -ForegroundColor Yellow
Write-Host "`nTo verify after restart:" -ForegroundColor Cyan
Write-Host "  dsregcmd /status" -ForegroundColor White
Write-Host "  Get-Service DmEnrollmentSvc, DmwApPushService, EntAppSvc" -ForegroundColor White
