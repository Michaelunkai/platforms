# Diagnose what's blocking PowerShell system-wide

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "DIAGNOSING POWERSHELL BLOCK" -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan

# Check 1: AppLocker Policies
Write-Host "[1] Checking AppLocker..." -ForegroundColor Yellow
try {
    $appLockerPolicy = Get-AppLockerPolicy -Effective -ErrorAction SilentlyContinue
    if ($appLockerPolicy) {
        Write-Host "  ⚠ AppLocker is ACTIVE - may be blocking PowerShell!" -ForegroundColor Red
        $appLockerPolicy.RuleCollections | ForEach-Object {
            Write-Host "    Policy: $($_.RuleCollectionType)" -ForegroundColor Gray
        }
    } else {
        Write-Host "  ✓ AppLocker not active" -ForegroundColor Green
    }
} catch {
    Write-Host "  ✓ AppLocker not configured" -ForegroundColor Green
}

# Check 2: Software Restriction Policies
Write-Host "`n[2] Checking Software Restriction Policies..." -ForegroundColor Yellow
$srpPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers"
if (Test-Path $srpPath) {
    Write-Host "  ⚠ SRP policies detected!" -ForegroundColor Red
    Get-ItemProperty $srpPath | Format-List
} else {
    Write-Host "  ✓ No SRP policies" -ForegroundColor Green
}

# Check 3: Windows Defender Application Control (WDAC)
Write-Host "`n[3] Checking WDAC/Device Guard..." -ForegroundColor Yellow
$ci = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction SilentlyContinue
if ($ci) {
    if ($ci.CodeIntegrityPolicyEnforcementStatus -ne 0) {
        Write-Host "  ⚠ WDAC/Device Guard is ACTIVE!" -ForegroundColor Red
        Write-Host "    Status: $($ci.CodeIntegrityPolicyEnforcementStatus)" -ForegroundColor Gray
    } else {
        Write-Host "  ✓ WDAC not enforcing" -ForegroundColor Green
    }
} else {
    Write-Host "  ✓ WDAC not active" -ForegroundColor Green
}

# Check 4: Check PowerShell file permissions
Write-Host "`n[4] Checking PowerShell.exe permissions..." -ForegroundColor Yellow
$psPath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
$acl = Get-Acl $psPath
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$hasAccess = $acl.Access | Where-Object {
    $_.IdentityReference -like "*$env:USERNAME*" -or
    $_.IdentityReference -eq "BUILTIN\Users" -or
    $_.IdentityReference -eq "Everyone"
}
if ($hasAccess) {
    Write-Host "  ✓ User has permissions" -ForegroundColor Green
} else {
    Write-Host "  ⚠ User may lack permissions!" -ForegroundColor Red
}

# Check 5: Antivirus/Defender real-time protection
Write-Host "`n[5] Checking Windows Defender..." -ForegroundColor Yellow
try {
    $defenderStatus = Get-MpComputerStatus
    if ($defenderStatus.RealTimeProtectionEnabled) {
        Write-Host "  ⚠ Real-time protection enabled" -ForegroundColor Yellow
        Write-Host "    May be blocking PowerShell execution" -ForegroundColor Yellow
    }
    $threats = Get-MpThreatDetection -ErrorAction SilentlyContinue
    if ($threats) {
        Write-Host "  ⚠ Recent threat detections:" -ForegroundColor Red
        $threats | Select-Object -First 5 | ForEach-Object {
            Write-Host "    - $($_.ThreatName)" -ForegroundColor Gray
        }
    }
} catch {
    Write-Host "  ℹ Could not check Defender status" -ForegroundColor Gray
}

# Check 6: Event Log for recent access denied errors
Write-Host "`n[6] Checking Event Log..." -ForegroundColor Yellow
$events = Get-WinEvent -FilterHashtable @{
    LogName='System','Application','Security'
    ID=4688,4689,4656,5140
    StartTime=(Get-Date).AddHours(-1)
} -MaxEvents 20 -ErrorAction SilentlyContinue | Where-Object {
    $_.Message -like '*powershell*' -or $_.Message -like '*0x80070005*'
}
if ($events) {
    Write-Host "  ⚠ Found $($events.Count) related events:" -ForegroundColor Red
    $events | Select-Object -First 3 | ForEach-Object {
        Write-Host "    Time: $($_.TimeCreated) - $($_.Message.Substring(0,100))..." -ForegroundColor Gray
    }
} else {
    Write-Host "  ℹ No recent related events" -ForegroundColor Gray
}

# Check 7: Try to actually launch PowerShell
Write-Host "`n[7] Testing PowerShell launch..." -ForegroundColor Yellow
try {
    $testProcess = Start-Process powershell.exe -ArgumentList "-Command exit" -PassThru -Wait -ErrorAction Stop
    Write-Host "  ✓ PowerShell launched successfully!" -ForegroundColor Green
    Write-Host "    Exit code: $($testProcess.ExitCode)" -ForegroundColor Gray
} catch {
    Write-Host "  ✗ FAILED TO LAUNCH: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "    This is the error you're seeing!" -ForegroundColor Red
}

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "DIAGNOSIS COMPLETE" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
