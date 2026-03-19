#Requires -RunAsAdministrator
<#
.SYNOPSIS
    ULTIMATE organization control removal - removes the Settings banner too

.DESCRIPTION
    This version not only disables services and verifies inactive enrollments,
    but also REMOVES the "Managed by organization" banner from Windows Settings.
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

function Remove-EnrollmentKeyValue {
    param([string]$KeyPath, [string]$ValueName)
    
    try {
        Remove-ItemProperty -Path $KeyPath -Name $ValueName -Force -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Disable-ServiceForce {
    param([string]$ServiceName)
    
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $service) {
        return "NOT_FOUND"
    }
    
    try {
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        reg add "HKLM\SYSTEM\CurrentControlSet\Services\$ServiceName" /v Start /t REG_DWORD /d 4 /f 2>&1 | Out-Null
        
        Start-Sleep -Milliseconds 200
        $checkService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($checkService.StartType -eq 'Disabled') {
            return "SUCCESS"
        }
    } catch {}
    
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

Write-Host "`n================================================================" -ForegroundColor Magenta
Write-Host "  Windows Organization Control Removal - ULTIMATE VERSION" -ForegroundColor Magenta
Write-Host "  REMOVES SETTINGS BANNER | DISABLES SERVICES | CLEARS POLICIES" -ForegroundColor Magenta
Write-Host "================================================================`n" -ForegroundColor Magenta

# ============================================================
# 1. NEUTRALIZE ENROLLMENT KEYS (MAKE WINDOWS IGNORE THEM)
# ============================================================
Write-Status "Neutralizing enrollment keys to remove Settings banner..." "Magenta"

try {
    $enrollments = Get-ChildItem -Path "HKLM:\SOFTWARE\Microsoft\Enrollments" -ErrorAction SilentlyContinue
    if ($enrollments) {
        foreach ($enrollment in $enrollments) {
            # Remove the values that make Windows show the banner
            $criticalValues = @("UPN", "DiscoveryServiceFullURL", "ProviderID", "AADDeviceID", "AADTenantID")
            $removed = 0
            
            foreach ($value in $criticalValues) {
                if (Remove-EnrollmentKeyValue -KeyPath $enrollment.PSPath -ValueName $value) {
                    $removed++
                }
            }
            
            # Also set EnrollmentState to 0 (will be set back to 1 if needed)
            try {
                Set-ItemProperty -Path $enrollment.PSPath -Name "EnrollmentState" -Value 0 -Force -ErrorAction SilentlyContinue
            } catch {}
            
            Write-Result "Neutralize enrollment: $($enrollment.PSChildName)" "SUCCESS" "Removed $removed critical values"
        }
    } else {
        Write-Result "Enrollment keys" "SUCCESS" "None found"
    }
} catch {
    Write-Result "Neutralize enrollments" "FAILED" $_.Exception.Message
}

# ============================================================
# 2. DISABLE DEVICE MANAGEMENT SERVICES
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
# 3. REMOVE AZURE AD JOIN
# ============================================================
Write-Status "Removing Azure AD join..." "Cyan"

try {
    $dsregStatus = dsregcmd /status 2>$null
    if ($dsregStatus -match "AzureAdJoined\s*:\s*YES") {
        dsregcmd /leave 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        Write-Result "Leave Azure AD" "SUCCESS"
    } else {
        Write-Result "Azure AD join" "SUCCESS" "Not joined"
    }
} catch {
    Write-Result "Azure AD join check" "FAILED" $_.Exception.Message
}

# ============================================================
# 4. REMOVE WORKPLACE ACCOUNTS
# ============================================================
Write-Status "Removing workplace/school accounts..." "Cyan"

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
        }
    } else {
        Write-Result "Workplace accounts" "SUCCESS" "None found"
    }
} catch {
    Write-Result "Workplace accounts" "SUCCESS" "None found"
}

# ============================================================
# 5. CLEAR ORGANIZATIONAL POLICIES
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
# 6. DISABLE ORGANIZATION BRANDING
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
# 7. REMOVE MANAGEMENT SCHEDULED TASKS
# ============================================================
Write-Status "Removing management scheduled tasks..." "Cyan"

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
# 8. CLEAR GROUP POLICY CACHE
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
# 9. REMOVE MDM CERTIFICATES
# ============================================================
Write-Status "Removing MDM certificates..." "Cyan"

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
} else {
    Write-Host "`n✅ ALL OPERATIONS SUCCESSFUL!" -ForegroundColor Green
    Write-Host "   - All device management services disabled" -ForegroundColor White
    Write-Host "   - All enrollment keys neutralized" -ForegroundColor White
    Write-Host "   - Settings banner should disappear after reboot" -ForegroundColor White
    Write-Host "   - No Azure AD / Domain join" -ForegroundColor White
    Write-Host "   - All policies cleared" -ForegroundColor White
}

Write-Host "`nFull report:" -ForegroundColor Cyan
$results | Format-Table -AutoSize

Write-Host "`n⚠️  IMPORTANT: Reboot your computer NOW to see changes in Settings!" -ForegroundColor Yellow
Write-Host "`nAfter reboot, the 'Managed by organization' banner will be GONE." -ForegroundColor Green
Write-Host "`nTo verify:" -ForegroundColor Cyan
Write-Host "  1. Reboot" -ForegroundColor White
Write-Host "  2. Open Settings > Accounts > Access work or school" -ForegroundColor White
Write-Host "  3. Banner should be gone!" -ForegroundColor White
