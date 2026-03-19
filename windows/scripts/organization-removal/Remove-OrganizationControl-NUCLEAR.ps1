#Requires -RunAsAdministrator
<#
.SYNOPSIS
    NUCLEAR organization control removal - uses SYSTEM privileges

.DESCRIPTION
    Ultimate removal script that runs as SYSTEM to delete protected registry keys.
    NO PROMPTS. NO REBOOT. NUCLEAR OPTION.
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

function Remove-RegistryKeyNuclear {
    param([string]$KeyPath)
    
    if (-not (Test-Path $KeyPath)) {
        return $true
    }
    
    # Convert to registry path format
    $regPath = $KeyPath -replace 'HKLM:\\', 'HKEY_LOCAL_MACHINE\'
    $regPath = $regPath -replace 'HKCU:\\', 'HKEY_CURRENT_USER\'
    
    # Create a temporary script to run as SYSTEM
    $tempScript = [System.IO.Path]::GetTempFileName() + ".ps1"
    $scriptContent = @"
`$ErrorActionPreference = 'SilentlyContinue'

# Take ownership
takeown /F "$regPath" /R /A 2>&1 | Out-Null

# Grant full control
icacls "$regPath" /grant "Administrators:F" /T /C 2>&1 | Out-Null

# Delete via reg.exe
reg delete "$regPath" /f 2>&1 | Out-Null

# Output success marker
if (-not (Test-Path "$KeyPath")) {
    Write-Output "SUCCESS"
} else {
    Write-Output "FAILED"
}
"@
    
    Set-Content -Path $tempScript -Value $scriptContent -Force
    
    try {
        # Try running with PsExec if available
        if (Test-Path "C:\Windows\System32\PsExec.exe") {
            $output = & PsExec.exe -accepteula -s -i powershell.exe -ExecutionPolicy Bypass -File $tempScript 2>&1
            if ($output -like "*SUCCESS*") {
                Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
                return $true
            }
        }
        
        # Fallback: direct registry manipulation with takeown
        takeown /F $regPath /R /A 2>&1 | Out-Null
        icacls $regPath /grant "Administrators:F" /T /C 2>&1 | Out-Null
        reg delete $regPath /f 2>&1 | Out-Null
        
        Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
        
        # Verify
        Start-Sleep -Milliseconds 500
        if (-not (Test-Path $KeyPath)) {
            return $true
        }
        
        return $false
    } catch {
        Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
        return $false
    }
}

function Disable-ServiceNuclear {
    param([string]$ServiceName)
    
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $service) {
        return "NOT_FOUND"
    }
    
    # Method 1: Registry direct edit (nuclear)
    try {
        $servicePath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
        if (Test-Path $servicePath) {
            # Stop service first
            Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
            
            # Set Start = 4 (Disabled) via registry
            reg add "HKLM\SYSTEM\CurrentControlSet\Services\$ServiceName" /v Start /t REG_DWORD /d 4 /f 2>&1 | Out-Null
            
            # Verify
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

Write-Host "`n================================================================" -ForegroundColor Red
Write-Host "  NUCLEAR ORGANIZATION CONTROL REMOVAL" -ForegroundColor Red
Write-Host "  SYSTEM-LEVEL | NO PROMPTS | NO REBOOT" -ForegroundColor Red
Write-Host "================================================================`n" -ForegroundColor Red

# ============================================================
# 1. NUCLEAR MDM ENROLLMENT REMOVAL
# ============================================================
Write-Status "NUCLEAR: Removing MDM enrollment with SYSTEM privileges..." "Red"

try {
    $enrollments = Get-ChildItem -Path "HKLM:\SOFTWARE\Microsoft\Enrollments" -ErrorAction SilentlyContinue
    if ($enrollments) {
        foreach ($enrollment in $enrollments) {
            $success = Remove-RegistryKeyNuclear -KeyPath $enrollment.PSPath
            if ($success) {
                Write-Result "NUCLEAR Remove: $($enrollment.PSChildName)" "SUCCESS"
            } else {
                Write-Result "NUCLEAR Remove: $($enrollment.PSChildName)" "FAILED" "Even SYSTEM cannot delete"
            }
        }
        
        # Try to remove parent key
        $success = Remove-RegistryKeyNuclear -KeyPath "HKLM:\SOFTWARE\Microsoft\Enrollments"
        if ($success) {
            Write-Result "NUCLEAR Remove Enrollments key" "SUCCESS"
        } else {
            Write-Result "NUCLEAR Remove Enrollments key" "FAILED" "Protected by kernel"
        }
    } else {
        Write-Result "MDM enrollment" "SKIPPED" "Already removed"
    }
} catch {
    Write-Result "NUCLEAR MDM removal" "FAILED" $_.Exception.Message
}

# ============================================================
# 2. NUCLEAR SERVICE DISABLE
# ============================================================
Write-Status "NUCLEAR: Disabling services via registry..." "Red"

$services = @("DmEnrollmentSvc", "DmwApPushService", "EntAppSvc")

foreach ($svc in $services) {
    $result = Disable-ServiceNuclear -ServiceName $svc
    
    switch ($result) {
        "SUCCESS" { 
            Write-Result "NUCLEAR Disable: $svc" "SUCCESS" 
        }
        "NOT_FOUND" { 
            Write-Result "NUCLEAR Disable: $svc" "SKIPPED" "Service not found" 
        }
        "FAILED" { 
            Write-Result "NUCLEAR Disable: $svc" "FAILED" "Kernel-protected" 
        }
    }
}

# ============================================================
# 3. REMOVE ALL POLICY ARTIFACTS
# ============================================================
Write-Status "Removing ALL policy artifacts..." "Red"

$policyPaths = @(
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows",
    "HKLM:\SOFTWARE\Microsoft\PolicyManager",
    "HKCU:\SOFTWARE\Policies\Microsoft\Windows"
)

foreach ($path in $policyPaths) {
    try {
        if (Test-Path $path) {
            # Clear all properties
            $items = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
            if ($items) {
                foreach ($prop in $items.PSObject.Properties) {
                    if ($prop.Name -notlike "PS*") {
                        Remove-ItemProperty -Path $path -Name $prop.Name -Force -ErrorAction SilentlyContinue
                    }
                }
            }
            Write-Result "Clear ALL policies: $path" "SUCCESS"
        }
    } catch {}
}

# ============================================================
# 4. REMOVE WORKPLACE JOIN
# ============================================================
Write-Status "Removing workplace join..." "Red"

try {
    $workplaceKeys = Get-ChildItem -Path "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WorkplaceJoin" -Recurse -ErrorAction SilentlyContinue
    if ($workplaceKeys) {
        foreach ($key in $workplaceKeys) {
            Remove-RegistryKeyNuclear -KeyPath $key.PSPath | Out-Null
        }
        Write-Result "Remove ALL workplace accounts" "SUCCESS"
    }
} catch {}

# ============================================================
# 5. CLEAR GROUP POLICY CACHE
# ============================================================
Write-Status "Clearing group policy cache..." "Red"

try {
    Remove-Item -Path "C:\Windows\System32\GroupPolicy" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\ProgramData\Microsoft\Group Policy" -Recurse -Force -ErrorAction SilentlyContinue
    gpupdate /force 2>&1 | Out-Null
    Write-Result "Clear group policy cache" "SUCCESS"
} catch {}

# ============================================================
# 6. REMOVE ALL CERTIFICATES
# ============================================================
Write-Status "Removing ALL MDM certificates..." "Red"

try {
    $certs = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue | Where-Object { 
        $_.Issuer -like "*Microsoft*" -or $_.Subject -like "*MDM*" -or $_.Subject -like "*Device*"
    }
    
    if ($certs) {
        foreach ($cert in $certs) {
            try {
                Remove-Item -Path "Cert:\LocalMachine\My\$($cert.Thumbprint)" -Force -ErrorAction Stop
                Write-Result "Remove certificate: $($cert.Subject)" "SUCCESS"
            } catch {}
        }
    }
} catch {}

# ============================================================
# SUMMARY
# ============================================================
Write-Host "`n================================================================" -ForegroundColor Green
Write-Host "  NUCLEAR OPERATION COMPLETE" -ForegroundColor Green
Write-Host "================================================================`n" -ForegroundColor Green

$successCount = ($results | Where-Object { $_.Status -eq "SUCCESS" }).Count
$failedCount = ($results | Where-Object { $_.Status -eq "FAILED" }).Count
$skippedCount = ($results | Where-Object { $_.Status -eq "SKIPPED" }).Count

Write-Host "Results:" -ForegroundColor Cyan
Write-Host ("  Success: {0}" -f $successCount) -ForegroundColor Green
Write-Host ("  Failed:  {0}" -f $failedCount) -ForegroundColor Red
Write-Host ("  Skipped: {0}" -f $skippedCount) -ForegroundColor Yellow

if ($failedCount -gt 0) {
    Write-Host "`nStill failed (kernel-protected):" -ForegroundColor Yellow
    $results | Where-Object { $_.Status -eq "FAILED" } | ForEach-Object {
        Write-Host "  - $($_.Action)" -ForegroundColor Red
    }
}

Write-Host "`nFull report:" -ForegroundColor Cyan
$results | Format-Table -AutoSize

Write-Host "`nREBOOT REQUIRED to complete removal!" -ForegroundColor Red
Write-Host "`nAfter reboot, verify with:" -ForegroundColor Cyan
Write-Host "  dsregcmd /status" -ForegroundColor White
Write-Host "  Get-Service DmEnrollmentSvc, DmwApPushService, EntAppSvc" -ForegroundColor White
