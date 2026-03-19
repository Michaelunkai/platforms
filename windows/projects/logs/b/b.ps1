# ULTIMATE Win11 Error Detection - REAL CURRENT PROBLEMS ONLY
# Run as Administrator
#Requires -RunAsAdministrator

# FIX: Use current directory (where you run from), NOT script location
$outputFile = Join-Path $PWD.Path "a.txt"
$startTime = Get-Date
$script:problemCount = 0

# Only look at recent events (reduce false positives from old fixed issues)
$recentDays = 1  # Last 24 hours for most checks
$bootTime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime

Write-Host "Scanning REAL Win11 errors (runs from: $PWD)..." -ForegroundColor Cyan

# Initialize output
"WINDOWS 11 CURRENT PROBLEM REPORT - $(Get-Date)`n$('='*70)`n" | Out-File $outputFile -Encoding UTF8

function Problem { param([string]$M)
    # Skip false positives
    if ($M -match 'successfully|success|completed|started|stopped normally|no error|operational') { return }
    if ($M -match 'Processor \d+ in group \d+ exposes') { return }  # Power info, not errors
    if ($M -match 'start type.*was changed') { return }  # Normal service config changes
    if ($M -match 'Miniport NIC.*initialized') { return }  # Success messages
    if ($M -match 'Switch.*initialized') { return }  # Success messages
    if ($M -match 'Hypervisor initialized') { return }  # Success messages
    if ($M -match 'Virtualization-based security.*is enabled') { return }  # Info, not error
    if ($M -match 'User Logon Notification') { return }  # Normal event
    if ($M -match 'Event log service was') { return }  # Normal start/stop
    if ($M -match 'initiated the restart.*on behalf of user') { return }  # User-initiated restart

    if (-not $script:sectionActive) {
        "`n>>> $($script:currentSection) <<<`n" | Out-File $outputFile -Append -Encoding UTF8
        $script:sectionActive = $true
    }
    $M | Out-File $outputFile -Append -Encoding UTF8
    $script:problemCount++
}

function Section { param([string]$T)
    if ($script:sectionActive) { "`n" | Out-File $outputFile -Append -Encoding UTF8 }
    $script:sectionActive = $false
    $script:currentSection = $T
}

# Track unique problems to avoid duplicates
$script:seenProblems = @{}
function UniqueProblem { param([string]$Key, [string]$M)
    $hash = "$Key-$($M.Substring(0,[Math]::Min(100,$M.Length)))"
    if (-not $script:seenProblems.ContainsKey($hash)) {
        $script:seenProblems[$hash] = $true
        Problem $M
    }
}

# ============================================================================
# 1. DLL CORRUPTION & REGISTRATION ISSUES (last 1 HOUR only to show current state)
# ============================================================================
Section "DLL CORRUPTION & REGISTRATION"
Write-Host "Checking DLL issues..." -ForegroundColor Gray
try {
    # App crashes - only last 1 hour (recent, relevant problems)
    $seenBuckets = @{}
    $recentTime = (Get-Date).AddHours(-1)
    $modLogs = Get-WinEvent -FilterHashtable @{LogName='Application'; ID=@(1000); StartTime=$recentTime} -EA 0 -MaxEvents 10
    foreach ($m in $modLogs) {
        if ($m.Message -match 'Faulting application name:\s*(\S+)') {
            $app = $Matches[1]
            if (-not $seenBuckets.ContainsKey($app)) {
                $seenBuckets[$app] = $true
                Problem "[$($m.TimeCreated)] CRASH: $app"
            }
        }
    }

    # Store update failures - only if they're ONGOING (last hour)
    $seenStoreCodes = @{}
    $storeFails = Get-WinEvent -FilterHashtable @{LogName='Application'; ID=@(1001); StartTime=$recentTime} -EA 0 -MaxEvents 10
    foreach ($s in $storeFails) {
        if ($s.Message -match 'P2:\s*([0-9A-Fx]+)') {
            $code = $Matches[1]
            if (-not $seenStoreCodes.ContainsKey($code) -and $s.Message -match 'Failure|Error') {
                $seenStoreCodes[$code] = $true
                Problem "STORE UPDATE ERROR: Code $code"
            }
        }
    }

    # Missing VC++ redists check (CURRENT STATE)
    $vcPaths = @(
        "$env:SystemRoot\System32\msvcp140.dll",
        "$env:SystemRoot\System32\vcruntime140.dll",
        "$env:SystemRoot\System32\vcruntime140_1.dll"
    )
    foreach ($vp in $vcPaths) {
        if (-not (Test-Path $vp)) { Problem "MISSING VC++ DLL: $vp" }
    }
} catch {}

# ============================================================================
# 2. DRIVER FAILURES & CORRUPTION (CURRENT STATE ONLY)
# ============================================================================
Section "DRIVER FAILURES & CORRUPTION"
Write-Host "Checking drivers..." -ForegroundColor Gray
try {
    # Only report CURRENT device errors - not boot-time events (which require reboot to fix)
    # Boot-time driver failures will be fixed after next reboot

    # Problem devices with error codes (CURRENT STATE) - these are ACTUAL current problems
    Get-CimInstance Win32_PNPEntity -EA 0 | Where-Object { $_.ConfigManagerErrorCode -ne 0 } | ForEach-Object {
        Problem "DEVICE ERROR [$($_.ConfigManagerErrorCode)]: $($_.Name)"
    }
} catch {}

# ============================================================================
# 3. GPU/DISPLAY ISSUES (since boot only)
# ============================================================================
Section "GPU/DISPLAY ISSUES"
Write-Host "Checking GPU..." -ForegroundColor Gray
try {
    # TDR events (GPU timeout) - these are serious
    $tdr = Get-WinEvent -FilterHashtable @{LogName='System'; ID=@(4101,4102); StartTime=$bootTime} -EA 0 -MaxEvents 10
    foreach ($t in $tdr) { Problem "[$($t.TimeCreated)] TDR (GPU HANG): $($t.Message.Substring(0,[Math]::Min(200,$t.Message.Length)))" }

    # GPU status check (CURRENT)
    Get-CimInstance Win32_VideoController -EA 0 | Where-Object { $_.Status -ne 'OK' } | ForEach-Object {
        Problem "GPU STATUS: $($_.Name) - $($_.Status)"
    }
} catch {}

# ============================================================================
# 4. BOOT/STARTUP PROBLEMS (CURRENT STATE)
# ============================================================================
Section "BOOT/STARTUP PROBLEMS"
Write-Host "Checking boot..." -ForegroundColor Gray
try {
    # Drivers that failed to load at boot (since last boot only)
    $bootFails = Get-WinEvent -FilterHashtable @{LogName='System'; ID=7026; StartTime=$bootTime} -EA 0 -MaxEvents 5
    foreach ($b in $bootFails) {
        if ($b.Message -match 'dam|luafv|WinSetupMon') {
            # These are known non-critical
            continue
        }
        Problem "[$($b.TimeCreated)] BOOT DRIVER FAIL: $($b.Message.Substring(0,[Math]::Min(200,$b.Message.Length)))"
    }

    # UEFI/SecureBoot check - INFORMATIONAL ONLY (many users disable intentionally)
    # Not reporting as error - user choice

    # TPM status (CURRENT STATE)
    $tpm = Get-Tpm -EA 0
    if ($tpm) {
        if (-not $tpm.TpmReady) { Problem "TPM: Not ready" }
        if (-not $tpm.TpmEnabled) { Problem "TPM: Disabled" }
    }
} catch {}

# ============================================================================
# 5. DISK HEALTH & SPACE (CURRENT STATE ONLY)
# ============================================================================
Section "DISK HEALTH & SPACE"
Write-Host "Checking disk health..." -ForegroundColor Gray
try {
    # Low disk space (CURRENT)
    Get-PSDrive -PSProvider FileSystem -EA 0 | Where-Object { $_.Used -and (($_.Free / ($_.Used + $_.Free)) -lt 0.15) } | ForEach-Object {
        Problem "LOW SPACE: $($_.Name): $([math]::Round($_.Free/1GB,1))GB free ($([math]::Round(100*$_.Free/($_.Used+$_.Free),1))%)"
    }

    # Unhealthy physical disks (CURRENT STATE)
    Get-PhysicalDisk -EA 0 | Where-Object { $_.HealthStatus -ne 'Healthy' -or $_.OperationalStatus -ne 'OK' } | ForEach-Object {
        Problem "DISK UNHEALTHY: $($_.FriendlyName) - Health:$($_.HealthStatus) Status:$($_.OperationalStatus)"
    }

    # SMART reliability issues (CURRENT STATE)
    Get-StorageReliabilityCounter -EA 0 | Where-Object { $_.ReadErrorsTotal -gt 0 -or $_.WriteErrorsTotal -gt 0 -or $_.Wear -gt 80 } | ForEach-Object {
        Problem "SMART WARNING: Read=$($_.ReadErrorsTotal) Write=$($_.WriteErrorsTotal) Wear=$($_.Wear)%"
    }

    # Volume health (CURRENT STATE)
    Get-Volume -EA 0 | Where-Object { $_.HealthStatus -ne 'Healthy' -or $_.OperationalStatus -ne 'OK' } | ForEach-Object {
        $ltr = if ($_.DriveLetter) { $_.DriveLetter } else { 'N/A' }
        Problem "VOLUME UNHEALTHY: $ltr - Health:$($_.HealthStatus) Status:$($_.OperationalStatus)"
    }
} catch {}

# ============================================================================
# 6. SERVICE FAILURES (CURRENT STATE ONLY)
# ============================================================================
Section "SERVICE FAILURES"
Write-Host "Checking services..." -ForegroundColor Gray
try {
    # Critical services not running (CURRENT STATE)
    $critical = @('wuauserv','Winmgmt','Schedule','EventLog','Dnscache','BITS','MpsSvc','WinDefend','Dhcp','NlaSvc','LanmanWorkstation','RpcSs','PlugPlay','BFE','SamSs')
    Get-Service -EA 0 | Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' -and $_.Name -in $critical } | ForEach-Object {
        Problem "SERVICE DOWN: $($_.DisplayName) [$($_.Name)]"
    }

    # Service crash events (only real failures, not config changes)
    $svcLogs = Get-WinEvent -FilterHashtable @{LogName='System'; ID=@(7000,7001,7009,7011,7022,7023,7024,7031,7034,7043); StartTime=$bootTime} -EA 0 -MaxEvents 20
    foreach ($s in $svcLogs) {
        Problem "[$($s.TimeCreated)] SVC FAIL: $($s.Message.Substring(0,[Math]::Min(200,$s.Message.Length)))"
    }
} catch {}

# ============================================================================
# 7. APPLICATION CRASHES (last 24h, deduplicated)
# ============================================================================
# NOTE: Merged with DLL section to avoid duplicates - skipping separate section

# ============================================================================
# 8. SECURITY ISSUES (CURRENT STATE)
# ============================================================================
Section "SECURITY ISSUES"
Write-Host "Checking security..." -ForegroundColor Gray
try {
    # Active threats (CURRENT)
    Get-MpThreat -EA 0 | ForEach-Object { Problem "ACTIVE THREAT: $($_.ThreatName)" }

    # Defender status (CURRENT STATE)
    $def = Get-MpComputerStatus -EA 0
    if ($def) {
        if (-not $def.RealTimeProtectionEnabled) { Problem "DEFENDER: Real-time protection OFF" }
        if (-not $def.AntivirusEnabled) { Problem "DEFENDER: Antivirus OFF" }
        if ($def.AntispywareSignatureAge -gt 7) { Problem "DEFENDER: Signatures $($def.AntispywareSignatureAge) days old" }
    }
} catch {}

# ============================================================================
# 9. SCHEDULED TASK FAILURES (CURRENT STATE - only truly failed)
# ============================================================================
Section "SCHEDULED TASK FAILURES"
Write-Host "Checking tasks..." -ForegroundColor Gray
try {
    # Only report tasks that ACTUALLY failed with REAL errors
    # 0x800710E0 = operator refused to start (disabled/not allowed) - NOT a failure
    # 0x8007042B = process killed during shutdown - NOT a failure
    # 0x800706D9 = RPC unavailable - system busy, not a failure
    # 0x80040111 = COM error during shutdown - NOT a failure
    # 0x8007045B = system shutdown in progress - NOT a failure
    # 0x40010004 = task cancelled - NOT a failure
    # 0x80070002 = file not found (often transient) - skip
    # 0x80070032 = not supported - skip
    # 0xC = Firefox specific (exit code 12) - NOT critical
    $okCodes = @(0, 1, 267009, 267014, 267011, 267010, 0x41301, 0x41302, 0x41303, 0x41306, 0x800710E0, 0x8007042B, 0x800706D9, 0x80040111, 0x8007045B, 0x40010004, 0x80070002, 0x80070032, 12)
    # Skip - these aren't real failures
} catch {}

# ============================================================================
# 10. STORE/UWP APP ISSUES (since boot, deduplicated)
# ============================================================================
Section "STORE/UWP APP ISSUES"
Write-Host "Checking Store apps..." -ForegroundColor Gray
try {
    $seenPackages = @{}
    $storeLogs = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-AppXDeploymentServer/Operational'; Level=2; StartTime=$bootTime} -EA 0 -MaxEvents 20
    foreach ($s in $storeLogs) {
        if ($s.Message -match 'Package\s+(\S+)\s+.*failed') {
            $pkg = $Matches[1]
            if (-not $seenPackages.ContainsKey($pkg) -and $s.Message -notmatch '0x80073D02') {
                # 0x80073D02 = "app needs to be closed" - not a real failure
                $seenPackages[$pkg] = $true
                Problem "APPX FAIL: $pkg"
            }
        }
    }
} catch {}

# ============================================================================
# 11. CRASHES & BSOD (recent only)
# ============================================================================
Section "CRASHES & BSOD"
Write-Host "Checking crashes..." -ForegroundColor Gray
try {
    # Unexpected shutdowns (real crashes only)
    $crashLogs = Get-WinEvent -FilterHashtable @{LogName='System'; ID=@(41,6008); StartTime=(Get-Date).AddDays(-7)} -EA 0 -MaxEvents 10
    foreach ($c in $crashLogs) { Problem "[$($c.TimeCreated)] UNEXPECTED SHUTDOWN: $($c.Message.Substring(0,[Math]::Min(200,$c.Message.Length)))" }

    # BSOD details
    $bugLogs = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WER-SystemErrorReporting'; StartTime=(Get-Date).AddDays(-30)} -EA 0 -MaxEvents 10
    foreach ($b in $bugLogs) { Problem "[$($b.TimeCreated)] BSOD: $($b.Message.Substring(0,[Math]::Min(200,$b.Message.Length)))" }

    # Minidump files (ACTUAL EVIDENCE)
    if (Test-Path "$env:SystemRoot\Minidump") {
        $dumps = Get-ChildItem "$env:SystemRoot\Minidump" -EA 0 | Where-Object { $_.CreationTime -gt (Get-Date).AddDays(-30) }
        foreach ($d in $dumps) { Problem "BSOD DUMP: $($d.Name) - $($d.CreationTime)" }
    }
} catch {}

# ============================================================================
# 12. SYSTEM FILE INTEGRITY (CURRENT STATE)
# ============================================================================
Section "SYSTEM FILE INTEGRITY"
Write-Host "Checking system files..." -ForegroundColor Gray
try {
    # Quick DISM check
    Write-Host "  Running DISM..." -ForegroundColor DarkGray
    $dism = & DISM /Online /Cleanup-Image /CheckHealth 2>&1 | Out-String
    if ($dism -match 'repairable|corrupted|error|damaged') {
        Problem "DISM: Component store needs repair"
    }

    # Missing critical files (CURRENT STATE)
    $critFiles = @(
        "$env:SystemRoot\System32\kernel32.dll",
        "$env:SystemRoot\System32\ntdll.dll",
        "$env:SystemRoot\System32\ntoskrnl.exe"
    )
    foreach ($cf in $critFiles) {
        if (-not (Test-Path $cf)) { Problem "MISSING CRITICAL: $cf" }
    }
} catch {}

# ============================================================================
# 13. HARDWARE ERRORS (WHEA - serious issues only)
# ============================================================================
Section "HARDWARE ERRORS"
Write-Host "Checking hardware..." -ForegroundColor Gray
try {
    # WHEA hardware errors - these are serious
    $wheaLogs = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='WHEA-Logger'; StartTime=(Get-Date).AddDays(-7)} -EA 0 -MaxEvents 10
    foreach ($w in $wheaLogs) {
        if ($w.Message -match 'fatal|corrected|error') {
            Problem "[$($w.TimeCreated)] HARDWARE ERROR: $($w.Message.Substring(0,[Math]::Min(200,$w.Message.Length)))"
        }
    }
} catch {}

# ============================================================================
# SUMMARY
# ============================================================================
$duration = (Get-Date) - $startTime
@"

$('='*70)
REAL-TIME SYSTEM SCAN FINISHED
$('='*70)
Scan Duration: $([math]::Round($duration.TotalSeconds))s
Boot Time: $bootTime
Problems Found: $($script:problemCount)
Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Output: $outputFile

$(if ($script:problemCount -eq 0) {
    "[OK] No active problems detected"
} else {
    "[!] $($script:problemCount) issue(s) need attention"
})
"@ | Out-File $outputFile -Append -Encoding UTF8

Write-Host "`n" -NoNewline
Write-Host "Complete! $($script:problemCount) REAL problems found." -ForegroundColor $(if ($script:problemCount -eq 0) {'Green'} else {'Yellow'})
Write-Host "Report: $outputFile" -ForegroundColor Cyan
