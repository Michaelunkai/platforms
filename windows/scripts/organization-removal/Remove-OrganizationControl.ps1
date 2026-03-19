#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Removes all organizational control from Windows (MDM, Azure AD, workplace accounts)

.DESCRIPTION
    Safely removes:
    - Workplace/School accounts
    - MDM (Mobile Device Management) enrollment
    - Azure AD joins
    - Organizational policies
    - Enterprise management
    
.NOTES
    Author: OpenClaw/Till
    Date: 2026-03-12
    REQUIRES ADMIN RIGHTS
#>

[CmdletBinding()]
param(
    [switch]$WhatIf,
    [switch]$Force
)

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
    if ($Details) { Write-Host "    → $Details" -ForegroundColor Gray }
}

# Check admin rights
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script requires Administrator rights!" -ForegroundColor Red
    Write-Host "Run PowerShell as Administrator and try again." -ForegroundColor Yellow
    exit 1
}

Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Windows Organization Control Removal Tool                    ║" -ForegroundColor Cyan
Write-Host "║  Removes: MDM, Azure AD, Workplace Accounts, Policies         ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

if ($WhatIf) {
    Write-Host "RUNNING IN WHATIF MODE - No changes will be made`n" -ForegroundColor Yellow
}

# ============================================================
# 1. CHECK CURRENT ORGANIZATIONAL STATUS
# ============================================================
Write-Status "Checking current organizational status..." "Yellow"

$mdmEnrolled = $false
$azureADJoined = $false
$workplaceJoined = $false

# Check MDM enrollment
try {
    $mdmStatus = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Enrollments\*" -ErrorAction SilentlyContinue
    if ($mdmStatus) {
        $mdmEnrolled = $true
        Write-Host "  ⚠️  MDM Enrollment detected" -ForegroundColor Red
    } else {
        Write-Host "  ✓ No MDM enrollment found" -ForegroundColor Green
    }
} catch {
    Write-Host "  ✓ No MDM enrollment found" -ForegroundColor Green
}

# Check Azure AD join
try {
    $dsregStatus = dsregcmd /status
    if ($dsregStatus -match "AzureAdJoined\s*:\s*YES") {
        $azureADJoined = $true
        Write-Host "  ⚠️  Azure AD Joined" -ForegroundColor Red
    } else {
        Write-Host "  ✓ Not Azure AD joined" -ForegroundColor Green
    }
    
    if ($dsregStatus -match "DomainJoined\s*:\s*YES") {
        Write-Host "  ⚠️  Domain Joined (Active Directory)" -ForegroundColor Red
    }
    
    if ($dsregStatus -match "WorkplaceJoined\s*:\s*YES") {
        $workplaceJoined = $true
        Write-Host "  ⚠️  Workplace Joined" -ForegroundColor Red
    }
} catch {
    Write-Host "  ℹ️  Could not check Azure AD status" -ForegroundColor Yellow
}

# Check for work/school accounts
$workAccounts = Get-ChildItem -Path "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WorkplaceJoin" -ErrorAction SilentlyContinue
if ($workAccounts) {
    Write-Host "  ⚠️  Work/School accounts detected" -ForegroundColor Red
} else {
    Write-Host "  ✓ No work/school accounts found" -ForegroundColor Green
}

if (-not $mdmEnrolled -and -not $azureADJoined -and -not $workplaceJoined -and -not $workAccounts) {
    Write-Host "`n✅ System is already clean - no organizational control detected!" -ForegroundColor Green
    if (-not $Force) {
        exit 0
    }
}

if (-not $Force -and -not $WhatIf) {
    Write-Host "`n⚠️  WARNING: This will remove organizational management from this device." -ForegroundColor Yellow
    Write-Host "This may:" -ForegroundColor Yellow
    Write-Host "  - Remove access to work resources" -ForegroundColor Yellow
    Write-Host "  - Delete organizational policies" -ForegroundColor Yellow
    Write-Host "  - Require reconfiguration if you need to rejoin" -ForegroundColor Yellow
    $confirm = Read-Host "`nContinue? (yes/no)"
    if ($confirm -ne 'yes') {
        Write-Host "Aborted by user." -ForegroundColor Red
        exit 0
    }
}

# ============================================================
# 2. REMOVE MDM ENROLLMENT
# ============================================================
Write-Status "Removing MDM enrollment..." "Cyan"

try {
    $enrollments = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Enrollments\*" -ErrorAction SilentlyContinue
    if ($enrollments) {
        foreach ($enrollment in $enrollments) {
            $enrollmentPath = $enrollment.PSPath
            if (-not $WhatIf) {
                Remove-Item -Path $enrollmentPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            Write-Result "Remove MDM enrollment: $enrollmentPath" "SUCCESS"
        }
    } else {
        Write-Result "Remove MDM enrollment" "SKIPPED" "No enrollments found"
    }
} catch {
    Write-Result "Remove MDM enrollment" "FAILED" $_.Exception.Message
}

# Remove MDM related registry keys
$mdmKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts\*",
    "HKLM:\SOFTWARE\Microsoft\Enrollments",
    "HKLM:\SOFTWARE\Microsoft\EnterpriseResourceManager\*"
)

foreach ($key in $mdmKeys) {
    try {
        if (Test-Path $key) {
            if (-not $WhatIf) {
                Remove-Item -Path $key -Recurse -Force -ErrorAction Stop
            }
            Write-Result "Remove registry key: $key" "SUCCESS"
        }
    } catch {
        Write-Result "Remove registry key: $key" "FAILED" $_.Exception.Message
    }
}

# ============================================================
# 3. REMOVE AZURE AD JOIN
# ============================================================
Write-Status "Removing Azure AD join..." "Cyan"

if ($azureADJoined) {
    try {
        if (-not $WhatIf) {
            dsregcmd /leave
            Start-Sleep -Seconds 2
        }
        Write-Result "Leave Azure AD" "SUCCESS"
    } catch {
        Write-Result "Leave Azure AD" "FAILED" $_.Exception.Message
    }
} else {
    Write-Result "Leave Azure AD" "SKIPPED" "Not joined"
}

# ============================================================
# 4. REMOVE WORKPLACE ACCOUNTS
# ============================================================
Write-Status "Removing workplace/school accounts..." "Cyan"

# Remove Work Access accounts
try {
    $workplaceKeys = Get-ChildItem -Path "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WorkplaceJoin" -ErrorAction SilentlyContinue
    if ($workplaceKeys) {
        foreach ($key in $workplaceKeys) {
            if (-not $WhatIf) {
                Remove-Item -Path $key.PSPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            Write-Result "Remove workplace account: $($key.PSChildName)" "SUCCESS"
        }
    } else {
        Write-Result "Remove workplace accounts" "SKIPPED" "None found"
    }
} catch {
    Write-Result "Remove workplace accounts" "FAILED" $_.Exception.Message
}

# Remove AAD-related accounts
$aadBrokerPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WorkplaceJoin\AADNGC"
if (Test-Path $aadBrokerPath) {
    try {
        if (-not $WhatIf) {
            Remove-Item -Path $aadBrokerPath -Recurse -Force
        }
        Write-Result "Remove AAD broker account" "SUCCESS"
    } catch {
        Write-Result "Remove AAD broker account" "FAILED" $_.Exception.Message
    }
}

# ============================================================
# 5. REMOVE ORGANIZATIONAL POLICIES
# ============================================================
Write-Status "Removing organizational policies..." "Cyan"

# Clear managed policies
$policyPaths = @(
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent",
    "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device",
    "HKLM:\SOFTWARE\Microsoft\PolicyManager\providers"
)

foreach ($path in $policyPaths) {
    try {
        if (Test-Path $path) {
            if (-not $WhatIf) {
                # Don't delete the key, just clear managed values
                $items = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
                if ($items) {
                    foreach ($prop in $items.PSObject.Properties) {
                        if ($prop.Name -notlike "PS*") {
                            Remove-ItemProperty -Path $path -Name $prop.Name -Force -ErrorAction SilentlyContinue
                        }
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
    if (-not $WhatIf) {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name "NoChangingLockScreen" -Value 0 -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name "LockScreenImage" -Force -ErrorAction SilentlyContinue
    }
    Write-Result "Remove lock screen branding" "SUCCESS"
} catch {
    Write-Result "Remove lock screen branding" "FAILED" $_.Exception.Message
}

# ============================================================
# 7. REMOVE MANAGEMENT SCHEDULED TASKS
# ============================================================
Write-Status "Removing management scheduled tasks..." "Cyan"

$managementTasks = Get-ScheduledTask | Where-Object { 
    $_.TaskPath -like "*Microsoft*Enterprise*" -or 
    $_.TaskPath -like "*Microsoft*MDM*" -or
    $_.TaskName -like "*Enterprise*" -or
    $_.TaskName -like "*MDM*"
}

if ($managementTasks) {
    foreach ($task in $managementTasks) {
        try {
            if (-not $WhatIf) {
                Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false
            }
            Write-Result "Remove task: $($task.TaskName)" "SUCCESS"
        } catch {
            Write-Result "Remove task: $($task.TaskName)" "FAILED" $_.Exception.Message
        }
    }
} else {
    Write-Result "Remove management tasks" "SKIPPED" "None found"
}

# ============================================================
# 8. CLEAR GROUP POLICY CACHE
# ============================================================
Write-Status "Clearing group policy cache..." "Cyan"

if (-not $WhatIf) {
    try {
        Remove-Item -Path "C:\Windows\System32\GroupPolicy" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "C:\ProgramData\Microsoft\Group Policy" -Recurse -Force -ErrorAction SilentlyContinue
        gpupdate /force | Out-Null
        Write-Result "Clear group policy cache" "SUCCESS"
    } catch {
        Write-Result "Clear group policy cache" "FAILED" $_.Exception.Message
    }
}

# ============================================================
# 9. DISABLE DEVICE MANAGEMENT SERVICES
# ============================================================
Write-Status "Disabling device management services..." "Cyan"

$services = @(
    "DmEnrollmentSvc",  # Device Management Enrollment Service
    "DmwApPushService", # Device Management Wireless Application Protocol
    "EntAppSvc"         # Enterprise App Management Service
)

foreach ($svc in $services) {
    try {
        $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($service) {
            if (-not $WhatIf) {
                Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
            }
            Write-Result "Disable service: $svc" "SUCCESS"
        }
    } catch {
        Write-Result "Disable service: $svc" "FAILED" $_.Exception.Message
    }
}

# ============================================================
# SUMMARY
# ============================================================
Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                    OPERATION COMPLETE                         ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Green

$successCount = ($results | Where-Object { $_.Status -eq "SUCCESS" }).Count
$failedCount = ($results | Where-Object { $_.Status -eq "FAILED" }).Count
$skippedCount = ($results | Where-Object { $_.Status -eq "SKIPPED" }).Count

Write-Host "Results:" -ForegroundColor Cyan
Write-Host "  ✓ Success: $successCount" -ForegroundColor Green
Write-Host "  ✗ Failed:  $failedCount" -ForegroundColor Red
Write-Host "  ○ Skipped: $skippedCount" -ForegroundColor Yellow

if ($failedCount -gt 0) {
    Write-Host "`nFailed operations:" -ForegroundColor Red
    $results | Where-Object { $_.Status -eq "FAILED" } | ForEach-Object {
        Write-Host "  - $($_.Action): $($_.Details)" -ForegroundColor Red
    }
}

Write-Host "`n📋 Full report:" -ForegroundColor Cyan
$results | Format-Table -AutoSize

if (-not $WhatIf) {
    Write-Host "`n⚠️  IMPORTANT: Restart your computer to complete the removal process." -ForegroundColor Yellow
    Write-Host "`nTo verify organizational status after restart, run:" -ForegroundColor Cyan
    Write-Host "  dsregcmd /status" -ForegroundColor White
    
    $restart = Read-Host "`nRestart now? (yes/no)"
    if ($restart -eq 'yes') {
        Write-Host "`nRestarting in 10 seconds... (Ctrl+C to cancel)" -ForegroundColor Yellow
        Start-Sleep -Seconds 10
        Restart-Computer -Force
    }
} else {
    Write-Host "`nWhatIf mode - no changes were made. Run without -WhatIf to apply changes." -ForegroundColor Yellow
}
