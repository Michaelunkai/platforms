# ULTIMATE Win11 Error Detection v3.0 - CATCHES ALL REAL PROBLEMS
# ENHANCED: Kernel-mode exception, LoadLibrary, Driver/Service stopping detection
# Run as Administrator
#Requires -RunAsAdministrator

$outputFile = Join-Path $PWD.Path "a.txt"
$startTime = Get-Date
$script:problemCount = 0
$script:criticalCount = 0  # Track CRITICAL issues separately
$bootTime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
$lastHour = (Get-Date).AddHours(-1)
$last24h = (Get-Date).AddDays(-1)
$last7d = (Get-Date).AddDays(-7)
$last30d = (Get-Date).AddDays(-30)
$last90d = (Get-Date).AddDays(-90)

Write-Host "Scanning ALL REAL Win11 errors (v3.0 - Enhanced)..." -ForegroundColor Cyan
Write-Host "  Includes: KMODE exceptions, LoadLibrary, Driver/Service stopping" -ForegroundColor DarkCyan

"WINDOWS 11 COMPLETE PROBLEM REPORT - $(Get-Date)`n$('='*70)`n" | Out-File $outputFile -Encoding UTF8

# Smart filter - only skip ACTUAL false positives
function Problem { param([string]$M, [switch]$Critical)
    # Only skip messages that are definitively NOT problems
    if ($M -match '^\s*$') { return }
    if ($M -match 'Processor \d+ in group \d+ exposes.*power management') { return }
    if ($M -match 'start type of the .* service was changed') { return }
    if ($M -match 'Miniport NIC.*successfully initialized') { return }
    if ($M -match 'Switch.*successfully initialized') { return }
    if ($M -match 'Hypervisor initialized I/O remapping') { return }
    if ($M -match 'Virtualization-based security.*is enabled due to') { return }
    if ($M -match 'User Logon Notification for Customer Experience') { return }
    if ($M -match 'Event log service was (started|stopped)') { return }
    if ($M -match 'initiated the restart.*on behalf of user') { return }
    if ($M -match 'The following boot-start.*did not load:.*dam.*luafv.*WinSetupMon') { return }

    if (-not $script:sectionActive) {
        "`n>>> $($script:currentSection) <<<`n" | Out-File $outputFile -Append -Encoding UTF8
        $script:sectionActive = $true
    }

    if ($Critical) {
        "[!!!CRITICAL!!!] $M" | Out-File $outputFile -Append -Encoding UTF8
        $script:criticalCount++
    } else {
        $M | Out-File $outputFile -Append -Encoding UTF8
    }
    $script:problemCount++
}

# Critical problem shorthand
function CriticalProblem { param([string]$M)
    Problem -M $M -Critical
}

function Section { param([string]$T)
    if ($script:sectionActive) { "`n" | Out-File $outputFile -Append -Encoding UTF8 }
    $script:sectionActive = $false
    $script:currentSection = $T
}

# Deduplication
$script:seen = @{}
function Unique { param([string]$K, [string]$M)
    if (-not $script:seen.ContainsKey($K)) { $script:seen[$K] = $true; Problem $M }
}

# ============================================================================
# 0A. KERNEL-MODE EXCEPTION DETECTION (KMODE_EXCEPTION_NOT_HANDLED)
# ============================================================================
Section "KERNEL-MODE EXCEPTIONS & BSOD TRIGGERS"
Write-Host "Checking kernel-mode exceptions (KMODE_EXCEPTION)..." -ForegroundColor Magenta

# Check for BugCheck events (actual BSOD occurrences) - use generic System log filter
try {
    Get-WinEvent -FilterHashtable @{LogName='System'; Id=1001; StartTime=$last90d} -EA SilentlyContinue -MaxEvents 50 | ForEach-Object {
        if ($_.ProviderName -match 'WER|Error' -and $_.Message -match 'KMODE_EXCEPTION|0x0000001E|BugCheck|bugcheck|blue.?screen') {
            CriticalProblem "KMODE EXCEPTION: $($_.Message.Substring(0,[Math]::Min(300,$_.Message.Length)))"
        }
    }
} catch { }

# Check minidump files for KMODE exceptions
try {
    $miniDumpPath = "$env:SystemRoot\Minidump"
    if (Test-Path $miniDumpPath) {
        Get-ChildItem $miniDumpPath -Filter "*.dmp" -EA SilentlyContinue | Where-Object { $_.LastWriteTime -gt $last30d } | ForEach-Object {
            CriticalProblem "BSOD DUMP FOUND: $($_.Name) [$($_.LastWriteTime)] - CHECK FOR KMODE EXCEPTION"
        }
    }
} catch { }

# Check MEMORY.DMP for recent kernel crash
try {
    $memDumpPath = "$env:SystemRoot\MEMORY.DMP"
    if (Test-Path $memDumpPath) {
        $dmpInfo = Get-Item $memDumpPath -EA SilentlyContinue
        if ($dmpInfo -and $dmpInfo.LastWriteTime -gt $last7d) {
            CriticalProblem "RECENT KERNEL CRASH DUMP: $memDumpPath [$($dmpInfo.LastWriteTime)]"
        }
    }
} catch { }

# Check for driver verifier bugchecks (can cause KMODE exceptions)
try {
    $verifierState = verifier /querysettings 2>&1 | Out-String
    # Only flag if actual drivers are being verified (flags > 0 AND drivers listed)
    if ($verifierState -notmatch 'No drivers are currently verified|No settings|Flags: 0x00000000' -and
        $verifierState -match 'verified' -and
        $verifierState -match 'Flags: 0x[0-9A-Fa-f]+[1-9]') {
        Problem "DRIVER VERIFIER ACTIVE: May cause KMODE exceptions - $($verifierState.Substring(0,[Math]::Min(100,$verifierState.Length)))"
    }
} catch { }

# Check for kernel-mode driver crashes in System log (Level 1=Critical, 2=Error)
try {
    Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=$last7d} -EA SilentlyContinue -MaxEvents 200 | ForEach-Object {
        if ($_.Message -match 'kernel.*exception|kernel.*fault|bugcheck|blue screen|STOP.*0x|fatal.*error.*kernel|DRIVER_IRQL|IRQL_NOT_LESS_OR_EQUAL|SYSTEM_SERVICE_EXCEPTION|PAGE_FAULT_IN_NONPAGED_AREA|KERNEL_DATA_INPAGE_ERROR|UNEXPECTED_KERNEL_MODE_TRAP') {
            CriticalProblem "[$($_.TimeCreated)] KERNEL ERROR: $($_.Message.Substring(0,[Math]::Min(250,$_.Message.Length)))"
        }
    }
} catch { }

# Check for watchdog timeouts (can lead to KMODE) - without ProviderName filter
try {
    Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$last7d} -EA SilentlyContinue -MaxEvents 500 | Where-Object {
        $_.ProviderName -match 'Watchdog' -and $_.Message -match 'timeout|deadlock|hang'
    } | Select-Object -First 20 | ForEach-Object {
        CriticalProblem "KERNEL WATCHDOG: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }
} catch { }

# Check for DPC/ISR issues (common KMODE triggers) - without ProviderName filter
try {
    Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2,3; StartTime=$last7d} -EA SilentlyContinue -MaxEvents 300 | Where-Object {
        $_.ProviderName -match 'Kernel-Processor-Power' -and $_.Message -match 'exceeded|timeout|error'
    } | Select-Object -First 20 | ForEach-Object {
        Problem "KERNEL PROCESSOR: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }
} catch { }

Write-Host "  Kernel checks complete" -ForegroundColor DarkGray

# ============================================================================
# 0B. LOADLIBRARY ERROR 126 & DLL MODULE DETECTION
# ============================================================================
Section "LOADLIBRARY ERRORS & MISSING MODULES (ERROR 126)"
Write-Host "Checking LoadLibrary errors (Error 126, missing modules)..." -ForegroundColor Magenta
try {
    # Critical DLLs that cause LoadLibrary 126 errors
    # NOTE: api-ms-win-crt-* DLLs live in System32\downlevel on Win10/11, NOT System32 directly
    # NOTE: hostfxr.dll/hostpolicy.dll are .NET SDK components, not required if .NET not installed
    $criticalDLLs = @(
        # Visual C++ Runtime (these SHOULD be in System32)
        "$env:SystemRoot\System32\msvcp140.dll",
        "$env:SystemRoot\System32\vcruntime140.dll",
        "$env:SystemRoot\System32\vcruntime140_1.dll",
        "$env:SystemRoot\System32\concrt140.dll",
        # Universal CRT base (this SHOULD be in System32)
        "$env:SystemRoot\System32\ucrtbase.dll",
        # DirectX (these SHOULD be in System32)
        "$env:SystemRoot\System32\d3d11.dll",
        "$env:SystemRoot\System32\d3d12.dll",
        "$env:SystemRoot\System32\dxgi.dll",
        "$env:SystemRoot\System32\d3dcompiler_47.dll",
        "$env:SystemRoot\System32\xinput1_4.dll",
        # Windows Core (these MUST be in System32)
        "$env:SystemRoot\System32\kernel32.dll",
        "$env:SystemRoot\System32\kernelbase.dll",
        "$env:SystemRoot\System32\ntdll.dll",
        "$env:SystemRoot\System32\user32.dll",
        "$env:SystemRoot\System32\gdi32.dll",
        "$env:SystemRoot\System32\advapi32.dll",
        "$env:SystemRoot\System32\shell32.dll",
        "$env:SystemRoot\System32\ole32.dll",
        "$env:SystemRoot\System32\oleaut32.dll",
        "$env:SystemRoot\System32\combase.dll",
        "$env:SystemRoot\System32\rpcrt4.dll",
        "$env:SystemRoot\System32\msvcrt.dll",
        # WoW64 VC++ equivalents (needed for 32-bit apps)
        "$env:SystemRoot\SysWOW64\msvcp140.dll",
        "$env:SystemRoot\SysWOW64\vcruntime140.dll",
        "$env:SystemRoot\SysWOW64\vcruntime140_1.dll",
        "$env:SystemRoot\SysWOW64\ucrtbase.dll",
        "$env:SystemRoot\SysWOW64\d3d11.dll",
        "$env:SystemRoot\SysWOW64\dxgi.dll"
    )

    foreach ($dll in $criticalDLLs) {
        if (-not (Test-Path $dll)) {
            CriticalProblem "MISSING DLL (LoadLibrary 126): $dll"
        }
    }

    # Check for corrupted DLLs (zero-size or very small)
    $criticalDLLs | Where-Object { Test-Path $_ } | ForEach-Object {
        $info = Get-Item $_ -EA 0
        if ($info.Length -lt 1024) {
            CriticalProblem "CORRUPTED DLL (too small): $_ [Size: $($info.Length) bytes]"
        }
    }

    # Check Event logs for LoadLibrary errors
    Get-WinEvent -FilterHashtable @{LogName='Application'; Level=1,2,3; StartTime=$last7d} -EA 0 -MaxEvents 200 | ForEach-Object {
        if ($_.Message -match 'LoadLibrary.*failed.*error\s*(\d+)|error\s*(\d+).*LoadLibrary|module could not be found|The specified module|entry point.*could not be located|procedure entry point|ordinal.*could not be located|DLL.*not found|Error 126|Error 127|Error 193|Error 998|is not a valid Win32 application') {
            $errCode = if ($Matches[1]) { $Matches[1] } elseif ($Matches[2]) { $Matches[2] } else { "unknown" }
            CriticalProblem "LOADLIBRARY ERROR $errCode`: $($_.Message.Substring(0,[Math]::Min(250,$_.Message.Length)))"
        }
    }

    # Check System log for module errors
    # SKIP: WUDFRd/UsbXhciCompanion errors - these are boot-time race conditions (fixed by changing Start type to SYSTEM)
    Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2,3; StartTime=$last7d} -EA 0 -MaxEvents 200 | ForEach-Object {
        if ($_.Message -match 'LoadLibrary|specified module|DLL.*not found|module could not be found|entry point.*could not be located|failed to load|cannot load') {
            # Skip known boot-time race condition errors (WUDFRd, UsbXhciCompanion, HID_DEVICE_SYSTEM_VHF)
            if ($_.Message -notmatch 'WUDFRd|UsbXhciCompanion|HID_DEVICE_SYSTEM_VHF|VHF|WINDOWSHELLOFACESOFTWAREDRIVER|VID_0B05') {
                CriticalProblem "SYSTEM LOADLIBRARY: $($_.Message.Substring(0,[Math]::Min(250,$_.Message.Length)))"
            }
        }
    }

    # Check SideBySide errors (often cause LoadLibrary issues) - without ProviderName filter for compatibility
    try {
        Get-WinEvent -FilterHashtable @{LogName='Application'; Level=1,2,3; StartTime=$last7d} -EA SilentlyContinue -MaxEvents 500 | Where-Object {
            $_.ProviderName -eq 'SideBySide'
        } | Select-Object -First 30 | ForEach-Object {
            CriticalProblem "SIDEBYSIDE DLL ERROR: $($_.Message.Substring(0,[Math]::Min(250,$_.Message.Length)))"
        }
    } catch { }

    # Check for Visual C++ Redistributables
    $vcRedists = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" -EA 0
    if (-not $vcRedists) {
        Problem "VC++ REDISTRIBUTABLE: 2015-2022 x64 may not be installed - can cause LoadLibrary 126"
    }
    $vcRedists32 = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x86" -EA 0
    if (-not $vcRedists32) {
        Problem "VC++ REDISTRIBUTABLE: 2015-2022 x86 may not be installed - can cause LoadLibrary 126"
    }

    # Check PATH environment for DLL search issues
    $pathVar = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    if ($pathVar -match ';;') {
        Problem "PATH VARIABLE: Contains empty entries (;;) which can cause DLL loading issues"
    }
    if ($pathVar.Length -gt 2000) {
        Problem "PATH VARIABLE: Very long ($($pathVar.Length) chars) - may cause DLL search issues"
    }
} catch { Write-Host "  Error checking LoadLibrary issues: $_" -ForegroundColor DarkRed }

# ============================================================================
# 0C. DRIVER STOPPING/SERVICE DEPENDENCY ISSUES
# ============================================================================
Section "DRIVER STOPPING & SERVICE DEPENDENCY FAILURES"
Write-Host "Checking driver stopping & service dependencies..." -ForegroundColor Magenta
try {
    # Check for driver stopping/terminated unexpectedly events
    Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2,3; StartTime=$last7d} -EA 0 -MaxEvents 300 | ForEach-Object {
        if ($_.Message -match 'driver.*stop|driver.*terminat|driver.*fail.*before|stop.*before.*depend|service.*terminat.*depend|depend.*not.*start|depend.*fail|network.*depend|net.*service.*fail|driver.*unload|driver.*crash') {
            CriticalProblem "DRIVER/SERVICE STOPPING: $($_.Message.Substring(0,[Math]::Min(300,$_.Message.Length)))"
        }
    }

    # Service Control Manager dependency errors
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Service Control Manager'; ID=7000,7001,7002,7003,7009,7011,7016,7022,7023,7024,7026,7031,7034,7043; StartTime=$last7d} -EA 0 -MaxEvents 50 | ForEach-Object {
        if ($_.Message -match 'depend|failed to start|timeout|terminate|did not start|not running') {
            CriticalProblem "SERVICE DEPENDENCY ERROR: $($_.Message.Substring(0,[Math]::Min(250,$_.Message.Length)))"
        }
    }

    # Check for specific network service dependency issues
    $netDependentServices = @('LanmanWorkstation', 'LanmanServer', 'Browser', 'Netlogon', 'Dnscache', 'NlaSvc', 'Dhcp', 'WinHttpAutoProxySvc', 'iphlpsvc', 'netprofm')
    foreach ($svcName in $netDependentServices) {
        $svc = Get-Service -Name $svcName -EA 0
        if ($svc) {
            # Check if service that should be running is stopped
            if ($svc.StartType -eq 'Automatic' -and $svc.Status -ne 'Running') {
                CriticalProblem "NETWORK SERVICE DOWN: $($svc.DisplayName) [$svcName] - Status: $($svc.Status)"
            }
            # Check dependencies
            $deps = $svc.ServicesDependedOn
            foreach ($dep in $deps) {
                $depSvc = Get-Service -Name $dep.Name -EA 0
                if ($depSvc -and $depSvc.Status -ne 'Running') {
                    Problem "DEPENDENCY NOT RUNNING: $($svc.DisplayName) depends on $($depSvc.DisplayName) which is $($depSvc.Status)"
                }
            }
        }
    }

    # Check for driver failures in boot sequence
    Get-WinEvent -FilterHashtable @{LogName='System'; ID=7000,7026; StartTime=$bootTime} -EA 0 -MaxEvents 20 | ForEach-Object {
        if ($_.Message -notmatch 'dam|luafv|WinSetupMon') {
            CriticalProblem "BOOT DRIVER FAILURE: $($_.Message.Substring(0,[Math]::Min(250,$_.Message.Length)))"
        }
    }

    # Check for drivers in error state - but exclude Hyper-V virtual drivers which are legitimately stopped when not in use
    $ignoredDrivers = @('l1vhlwf', 'NetworkPrivacyPolicy', 'hvservice', 'HvHost', 'vmicguestinterface', 'vmicheartbeat', 'vmickvpexchange', 'vmicrdv', 'vmicshutdown', 'vmictimesync', 'vmicvmsession', 'vmicvss', 'WinNat', 'WinRM')
    Get-CimInstance Win32_SystemDriver -EA 0 | Where-Object { $_.State -eq 'Stopped' -and $_.StartMode -eq 'Auto' -and $_.Name -notin $ignoredDrivers } | ForEach-Object {
        CriticalProblem "DRIVER STOPPED (should be Auto): $($_.DisplayName) [$($_.Name)]"
    }

    # Check for drivers that failed to load - without ProviderName filter for compatibility
    # SKIP: WUDFRd/UsbXhciCompanion - known boot-time race condition (fixed by changing Start type to SYSTEM)
    try {
        Get-WinEvent -FilterHashtable @{LogName='System'; Level=2,3; StartTime=$bootTime} -EA SilentlyContinue -MaxEvents 300 | Where-Object {
            $_.ProviderName -eq 'Microsoft-Windows-Kernel-PnP' -and
            $_.Message -match 'failed to start|failed to load|cannot start|not loaded' -and
            $_.Message -notmatch 'WUDFRd|UsbXhciCompanion|VHF|HID_DEVICE_SYSTEM_VHF|WINDOWSHELLOFACESOFTWAREDRIVER|VID_0B05'
        } | Select-Object -First 30 | ForEach-Object {
            CriticalProblem "PNP DRIVER FAILURE: $($_.Message.Substring(0,[Math]::Min(250,$_.Message.Length)))"
        }
    } catch { }

    # Check service startup order issues
    $criticalOrderServices = @(
        @{Name='RpcSs'; Desc='RPC'},
        @{Name='DcomLaunch'; Desc='DCOM Launcher'},
        @{Name='RpcEptMapper'; Desc='RPC Endpoint Mapper'},
        @{Name='nsi'; Desc='Network Store Interface'},
        @{Name='Tcpip'; Desc='TCP/IP'},
        @{Name='Afd'; Desc='Ancillary Function Driver'},
        @{Name='NetBT'; Desc='NetBIOS over TCP/IP'}
    )
    foreach ($svcInfo in $criticalOrderServices) {
        $svc = Get-Service -Name $svcInfo.Name -EA 0
        if ($svc -and $svc.Status -ne 'Running') {
            CriticalProblem "CRITICAL FOUNDATION SERVICE DOWN: $($svcInfo.Desc) [$($svcInfo.Name)] - $($svc.Status)"
        }
    }
} catch { Write-Host "  Error checking driver/service dependencies: $_" -ForegroundColor DarkRed }

# ============================================================================
# 0D. OUTDATED DRIVER DETECTION
# ============================================================================
Section "OUTDATED & PROBLEMATIC DRIVERS"
Write-Host "Checking for outdated drivers..." -ForegroundColor Magenta
try {
    # Get all signed drivers with version info
    $drivers = Get-WmiObject Win32_PnPSignedDriver -EA 0 | Where-Object { $_.DeviceName -and $_.DriverVersion }

    # Windows inbox drivers use hardcoded dates like 2006-06-21 even on Win11 - these are NOT outdated
    # Only flag drivers from non-Microsoft providers that are actually old
    $oldDriverDate = (Get-Date).AddYears(-3)

    # Load acknowledged drivers file (created by fixer script for functional-but-old drivers)
    $acknowledgedDrivers = @()
    $acknowledgedPath = "$env:TEMP\acknowledged_drivers.txt"
    if (Test-Path $acknowledgedPath) {
        $acknowledgedDrivers = Get-Content $acknowledgedPath -EA 0 | ForEach-Object { ($_ -split '\|')[0] }
        Write-Host "  Loaded $($acknowledgedDrivers.Count) acknowledged drivers from fixer" -ForegroundColor Gray
    }

    # Microsoft inbox driver patterns to IGNORE (these use 2006 dates by design)
    $inboxDriverPatterns = @(
        'Microsoft',
        'Windows',
        'Standard ',  # "Standard NVM Express Controller", "Standard AHCI"
        'Generic ',   # "Generic software device", "Generic PnP Monitor"
        'PCI ',       # "PCI Express Root Port", etc
        'ACPI ',      # "ACPI Thermal Zone", etc
        'HID-compliant',
        'USB Composite',
        'High Definition Audio',
        'Bluetooth',
        'Volume',
        'Disk drive',
        'System ',    # "System board", "System timer", etc
        'Motherboard',
        'Programmable',
        'Direct memory'
    )

    # Known functional-but-old drivers to skip (handled by fixer, not actual problems)
    $knownFunctionalDrivers = @(
        'Integrated Camera',      # ASUS camera - works fine with old driver, no updates available
        'Logitech Download',      # Logitech bloatware - being removed by fixer
        'Camera'                  # Generic camera reference
    )

    $drivers | ForEach-Object {
        try {
            if ($_.DriverDate) {
                $driverDateParsed = [DateTime]::ParseExact($_.DriverDate.Substring(0,8), "yyyyMMdd", $null)

                # Skip Microsoft/Windows inbox drivers (they use hardcoded 2006 dates - normal behavior)
                $isInboxDriver = $false
                if ($_.DriverProviderName -match 'Microsoft|Windows') { $isInboxDriver = $true }
                foreach ($pattern in $inboxDriverPatterns) {
                    if ($_.DeviceName -like "$pattern*") { $isInboxDriver = $true; break }
                }

                # Skip acknowledged drivers (marked as functional by fixer)
                $isAcknowledged = $false
                foreach ($ack in $acknowledgedDrivers) {
                    if ($_.DeviceName -like "*$ack*") { $isAcknowledged = $true; break }
                }

                # Skip known functional drivers that are handled by fixer
                $isKnownFunctional = $false
                foreach ($known in $knownFunctionalDrivers) {
                    if ($_.DeviceName -like "*$known*") { $isKnownFunctional = $true; break }
                }

                # Only flag non-inbox drivers that are truly outdated AND not acknowledged/known
                if (-not $isInboxDriver -and -not $isAcknowledged -and -not $isKnownFunctional -and $driverDateParsed -lt $oldDriverDate) {
                    $deviceClass = $_.DeviceClass
                    # Flag GPU, Network adapters (not virtual), Storage as critical if outdated
                    if ($deviceClass -match 'Display|Net|SCSIAdapter|HDC' -and $_.DeviceName -notmatch 'Virtual|Loopback|Debug') {
                        CriticalProblem "OUTDATED CRITICAL DRIVER: $($_.DeviceName) - Version: $($_.DriverVersion) from $($driverDateParsed.ToString('yyyy-MM-dd'))"
                    } else {
                        Problem "OUTDATED DRIVER: $($_.DeviceName) - Version: $($_.DriverVersion) from $($driverDateParsed.ToString('yyyy-MM-dd'))"
                    }
                }
            }
        } catch {}
    }

    # Check for unsigned drivers (security/stability risk) - but only if they're not Microsoft inbox
    $drivers | Where-Object { $_.IsSigned -eq $false -and $_.DriverProviderName -notmatch 'Microsoft|Windows' } | ForEach-Object {
        CriticalProblem "UNSIGNED DRIVER: $($_.DeviceName) [$($_.InfName)] - Security/Stability Risk"
    }

    # Note: GPU driver info is informational only, not a problem. GPU drivers are logged elsewhere if needed.
    # Note: "Unknown provider" drivers are often inbox drivers and not inherently problematic.

    # Check for devices with driver issues (Code 28 = no driver, etc)
    Get-CimInstance Win32_PnPEntity -EA 0 | Where-Object { $_.ConfigManagerErrorCode -ne 0 } | ForEach-Object {
        $errorDesc = switch ($_.ConfigManagerErrorCode) {
            1 { "not configured correctly" }
            3 { "driver corrupted" }
            10 { "cannot start" }
            12 { "cannot find free resources" }
            14 { "requires restart" }
            18 { "reinstall driver" }
            19 { "registry corrupted" }
            21 { "Windows removing device" }
            22 { "device disabled" }
            24 { "not present/not working" }
            28 { "NO DRIVER INSTALLED" }
            29 { "disabled in firmware" }
            31 { "not working properly" }
            32 { "driver disabled" }
            33 { "cannot determine resources" }
            34 { "cannot determine IRQ" }
            35 { "cannot determine memory" }
            36 { "IRQ needs config" }
            37 { "cannot initialize" }
            38 { "cannot load driver" }
            39 { "driver corrupted" }
            40 { "no registry entry" }
            41 { "unrecognized device" }
            42 { "duplicate device" }
            43 { "generic driver issue" }
            44 { "driver stopped" }
            45 { "not connected" }
            46 { "not accessible" }
            47 { "cannot use - safe mode" }
            48 { "cannot verify digital signature" }
            49 { "cannot load/too big" }
            50 { "cannot start - corrupt" }
            51 { "waiting for device" }
            52 { "cannot sign driver" }
            53 { "modified by driver" }
            54 { "cannot stop" }
            default { "error code $($_.ConfigManagerErrorCode)" }
        }
        CriticalProblem "DEVICE DRIVER ERROR: $($_.Name) - $errorDesc"
    }
} catch { Write-Host "  Error checking outdated drivers: $_" -ForegroundColor DarkRed }

# ============================================================================
# 1. APPLICATION CRASHES & DLL ISSUES (since boot only - not historical)
# ============================================================================
Section "APPLICATION CRASHES & DLL ISSUES"
Write-Host "Checking crashes & DLLs..." -ForegroundColor Gray
# Use 45 minutes after boot as cutoff to skip repair-induced transient crashes
$postBootCutoff = $bootTime.AddMinutes(45)
try {
    # Application Error (Event 1000) - crashes - only after 10min post-boot
    Get-WinEvent -FilterHashtable @{LogName='Application'; ID=1000; StartTime=$postBootCutoff} -EA 0 -MaxEvents 50 | ForEach-Object {
        if ($_.Message -match 'Faulting application name:\s*(\S+)') {
            Unique "crash-$($Matches[1])" "CRASH: $($Matches[1]) at $($_.TimeCreated)"
        }
    }

    # Application Hang (Event 1002)
    Get-WinEvent -FilterHashtable @{LogName='Application'; ID=1002; StartTime=$postBootCutoff} -EA 0 -MaxEvents 30 | ForEach-Object {
        if ($_.Message -match 'application.*stopped responding') {
            Unique "hang-$($_.TimeCreated.ToString('HHmm'))" "HANG: $($_.Message.Substring(0,[Math]::Min(150,$_.Message.Length)))"
        }
    }

    # Windows Error Reporting faults (Event 1001) - only after 10min post-boot
    Get-WinEvent -FilterHashtable @{LogName='Application'; ID=1001; StartTime=$postBootCutoff} -EA 0 -MaxEvents 50 | ForEach-Object {
        $msg = $_.Message
        if ($msg -match 'APPCRASH|CLR20r3|MoAppCrash|StoreAgent.*Failure') {
            if ($msg -match 'P1:\s*(\S+)') {
                Unique "wer-$($Matches[1])" "WER FAULT: $($Matches[1])"
            }
        }
    }

    # SideBySide/DLL errors
    Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='SideBySide'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 20 | ForEach-Object {
        Unique "sxs-$($_.Id)" "SXS/DLL: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # .NET Runtime errors
    Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='.NET Runtime'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 20 | ForEach-Object {
        Unique "dotnet-$($_.TimeCreated.ToString('MMddHH'))" ".NET ERROR: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # Missing critical DLLs
    @("$env:SystemRoot\System32\msvcp140.dll","$env:SystemRoot\System32\vcruntime140.dll","$env:SystemRoot\System32\vcruntime140_1.dll",
      "$env:SystemRoot\System32\mfc140u.dll","$env:SystemRoot\System32\ucrtbase.dll") | ForEach-Object {
        if (-not (Test-Path $_)) { Problem "MISSING DLL: $_" }
    }

    # LoadLibrary failures (Error 126, 127, 193, etc)
    Get-WinEvent -FilterHashtable @{LogName='Application'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 100 | ForEach-Object {
        if ($_.Message -match 'LoadLibrary.*failed.*error\s*(\d+)|error\s*(\d+).*LoadLibrary|module could not be found|The specified module|entry point|procedure entry point') {
            $errCode = if ($Matches[1]) { $Matches[1] } elseif ($Matches[2]) { $Matches[2] } else { "unknown" }
            Unique "loadlib-$errCode-$($_.TimeCreated.ToString('MMddHH'))" "LOADLIBRARY ERROR $errCode`: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    }

    # Specific LoadLibrary errors in System log
    Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2,3; StartTime=$last7d} -EA 0 -MaxEvents 100 | ForEach-Object {
        if ($_.Message -match 'LoadLibrary|specified module|DLL.*not found|module could not be found|entry point.*could not be located') {
            Unique "loadlib-sys-$($_.TimeCreated.ToString('MMddHHmm'))" "LOADLIBRARY: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    }
} catch {}

# ============================================================================
# 2. DRIVER & DEVICE PROBLEMS
# ============================================================================
Section "DRIVER & DEVICE PROBLEMS"
Write-Host "Checking drivers..." -ForegroundColor Gray
try {
    # Current device errors (ConfigManagerErrorCode != 0)
    Get-CimInstance Win32_PNPEntity -EA 0 | Where-Object { $_.ConfigManagerErrorCode -ne 0 } | ForEach-Object {
        Problem "DEVICE ERROR [$($_.ConfigManagerErrorCode)]: $($_.Name)"
    }

    # Driver load failures (since boot) - skip VHF virtual HID errors (benign boot-time event)
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-PnP'; Level=2,3; StartTime=$bootTime} -EA 0 -MaxEvents 30 | ForEach-Object {
        if ($_.Message -match 'failed to load|failed to start|cannot start') {
            if ($_.Message -notmatch 'WUDFRd|VHF|HID_DEVICE_SYSTEM_VHF') {
                Unique "pnp-$($_.Id)-$($_.TimeCreated.ToString('HHmm'))" "DRIVER: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
            }
        }
    }

    # WDF/UMDF errors - skip VHF (Virtual HID Framework) errors which are benign boot-time events
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-DriverFrameworks-UserMode'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 20 | ForEach-Object {
        if ($_.Message -notmatch 'WUDFRd|VHF|HID_DEVICE_SYSTEM_VHF|Virtual HID') {
            Unique "wdf-$($_.Id)" "WDF: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    }

    # Unsigned drivers (potential security/stability risk)
    Get-WmiObject Win32_PnPSignedDriver -EA 0 | Where-Object { $_.IsSigned -eq $false -and $_.DeviceName -and $_.DeviceName -notmatch 'Unknown' } | ForEach-Object {
        Unique "unsigned-$($_.DeviceName)" "UNSIGNED DRIVER: $($_.DeviceName)"
    }
} catch {}

# ============================================================================
# 3. GPU/DISPLAY/DXGI ISSUES
# ============================================================================
Section "GPU/DISPLAY/DXGI ISSUES"
Write-Host "Checking GPU/DXGI..." -ForegroundColor Gray
try {
    # TDR (GPU timeout/reset) - serious
    Get-WinEvent -FilterHashtable @{LogName='System'; ID=4101,4102; StartTime=$last30d} -EA 0 -MaxEvents 20 | ForEach-Object {
        Problem "[$($_.TimeCreated)] GPU TDR: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # DXGI errors - check Application log for DirectX/DXGI crashes
    Get-WinEvent -FilterHashtable @{LogName='Application'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 100 | ForEach-Object {
        if ($_.Message -match 'DXGI|DirectX|D3D11|D3D12|dxgi\.dll|d3d11\.dll|d3d12\.dll') {
            Unique "dxgi-$($_.TimeCreated.ToString('MMddHHmm'))" "DXGI: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    }

    # DXGI in System log
    Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2,3; StartTime=$last7d} -EA 0 -MaxEvents 100 | ForEach-Object {
        if ($_.Message -match 'DXGI|dxgkrnl|dxgmms|Display driver.*stopped responding') {
            Unique "dxgi-sys-$($_.TimeCreated.ToString('MMddHHmm'))" "DXGI/DISPLAY: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    }

    # Display/DWM errors
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Dwm-Core'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 10 | ForEach-Object {
        Unique "dwm-$($_.Id)" "DWM: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # NVIDIA/AMD/Intel driver errors
    @('nvlddmkm','amdkmdag','igfx','dxgkrnl','dxgmms1','dxgmms2') | ForEach-Object {
        Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName=$_; Level=1,2,3; StartTime=$last7d} -EA 0 -MaxEvents 10 | ForEach-Object {
            Unique "gpu-$($_.ProviderName)-$($_.Id)" "GPU DRIVER: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    }

    # GPU hardware status
    Get-CimInstance Win32_VideoController -EA 0 | Where-Object { $_.Status -ne 'OK' } | ForEach-Object {
        Problem "GPU STATUS: $($_.Name) - $($_.Status)"
    }
} catch {}

# ============================================================================
# 4. DISK & STORAGE ISSUES (C: and F: only)
# ============================================================================
Section "DISK & STORAGE ISSUES"
Write-Host "Checking disks (C: F: only)..." -ForegroundColor Gray
try {
    # Low disk space (<15%) - ONLY C: and F: drives
    Get-PSDrive -PSProvider FileSystem -EA 0 | Where-Object { $_.Name -in @('C','F') -and $_.Used -gt 0 -and (($_.Free / ($_.Used + $_.Free)) -lt 0.15) } | ForEach-Object {
        Problem "LOW SPACE: $($_.Name): $([math]::Round($_.Free/1GB,1))GB free ($([math]::Round(100*$_.Free/($_.Used+$_.Free),1))%)"
    }

    # Unhealthy physical disks
    Get-PhysicalDisk -EA 0 | Where-Object { $_.HealthStatus -ne 'Healthy' } | ForEach-Object {
        Problem "DISK UNHEALTHY: $($_.FriendlyName) - $($_.HealthStatus)"
    }

    # SMART errors
    Get-StorageReliabilityCounter -EA 0 | Where-Object { $_.ReadErrorsTotal -gt 0 -or $_.WriteErrorsTotal -gt 0 -or $_.Wear -gt 80 } | ForEach-Object {
        Problem "SMART: ReadErr=$($_.ReadErrorsTotal) WriteErr=$($_.WriteErrorsTotal) Wear=$($_.Wear)%"
    }

    # Volume issues - ONLY C: and F: drives
    Get-Volume -EA 0 | Where-Object { $_.HealthStatus -ne 'Healthy' -and $_.DriveLetter -in @('C','F') } | ForEach-Object {
        Problem "VOLUME: $($_.DriveLetter): $($_.HealthStatus)"
    }

    # NTFS errors
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Ntfs'; Level=1,2,3; StartTime=$last7d} -EA 0 -MaxEvents 20 | ForEach-Object {
        if ($_.Message -notmatch 'successfully') {
            Unique "ntfs-$($_.Id)-$($_.TimeCreated.ToString('MMdd'))" "NTFS: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    }

    # Disk I/O errors (Event IDs 7, 9, 11, 15, 51, 52, 55, 129, 153)
    Get-WinEvent -FilterHashtable @{LogName='System'; ID=7,9,11,15,51,52,55,129,153; StartTime=$last7d} -EA 0 -MaxEvents 30 | ForEach-Object {
        if ($_.Message -notmatch 'successfully|initialized|exposes') {
            Unique "diskio-$($_.Id)-$($_.TimeCreated.ToString('MMdd'))" "DISK I/O: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    }
} catch {}

# ============================================================================
# 5. SERVICE FAILURES
# ============================================================================
Section "SERVICE FAILURES"
Write-Host "Checking services..." -ForegroundColor Gray
try {
    # Critical services that should be running
    $critical = @('wuauserv','Winmgmt','Schedule','EventLog','Dnscache','BITS','MpsSvc','WinDefend','Dhcp','NlaSvc','LanmanWorkstation','RpcSs','PlugPlay','BFE','SamSs','CryptSvc','TrustedInstaller','Spooler','AudioSrv','W32Time')
    Get-Service -EA 0 | Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' -and $_.Name -in $critical } | ForEach-Object {
        Problem "SERVICE DOWN: $($_.DisplayName) [$($_.Name)]"
    }

    # Service crash/fail events (7000-7043 range)
    Get-WinEvent -FilterHashtable @{LogName='System'; ID=7000,7001,7009,7011,7022,7023,7024,7031,7034,7043; StartTime=$bootTime} -EA 0 -MaxEvents 30 | ForEach-Object {
        Unique "svc-$($_.Id)-$($_.TimeCreated.ToString('HHmm'))" "SVC FAIL: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # Service Control Manager errors
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Service Control Manager'; Level=1,2; StartTime=$last24h} -EA 0 -MaxEvents 20 | ForEach-Object {
        if ($_.Message -notmatch 'start type.*was changed') {
            Unique "scm-$($_.Id)-$($_.TimeCreated.ToString('HHmm'))" "SCM: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    }
} catch {}

# ============================================================================
# 6. SECURITY ISSUES
# ============================================================================
Section "SECURITY ISSUES"
Write-Host "Checking security..." -ForegroundColor Gray
try {
    # Active threats
    Get-MpThreat -EA 0 | ForEach-Object { Problem "THREAT DETECTED: $($_.ThreatName) - $($_.Resources -join ',')" }

    # Defender status
    $def = Get-MpComputerStatus -EA 0
    if ($def) {
        if (-not $def.RealTimeProtectionEnabled) { Problem "DEFENDER: Real-time protection OFF" }
        if (-not $def.AntivirusEnabled) { Problem "DEFENDER: Antivirus OFF" }
        if (-not $def.BehaviorMonitorEnabled) { Problem "DEFENDER: Behavior monitor OFF" }
        if (-not $def.IoavProtectionEnabled) { Problem "DEFENDER: Download scanning OFF" }
        if ($def.AntispywareSignatureAge -gt 7) { Problem "DEFENDER: Signatures $($def.AntispywareSignatureAge) days old" }
    }

    # Defender operational errors
    Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Windows Defender/Operational'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 20 | ForEach-Object {
        Unique "defender-$($_.Id)" "DEFENDER: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # Firewall issues
    Get-NetFirewallProfile -EA 0 | Where-Object { $_.Enabled -eq $false } | ForEach-Object {
        Problem "FIREWALL OFF: $($_.Name) profile"
    }

    # Failed logins (brute force indicator)
    $failedLogins = @(Get-WinEvent -FilterHashtable @{LogName='Security'; ID=4625; StartTime=$last24h} -EA 0 -MaxEvents 500).Count
    if ($failedLogins -gt 10) { Problem "SECURITY: $failedLogins failed logins in 24h" }

    # Audit policy failures
    Get-WinEvent -FilterHashtable @{LogName='Security'; ID=4719; StartTime=$last7d} -EA 0 -MaxEvents 5 | ForEach-Object {
        Problem "AUDIT POLICY CHANGED: $($_.TimeCreated)"
    }
} catch {}

# ============================================================================
# 7. WINDOWS UPDATE ISSUES
# ============================================================================
Section "WINDOWS UPDATE ISSUES"
Write-Host "Checking updates..." -ForegroundColor Gray
try {
    # Windows Update errors
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WindowsUpdateClient'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 20 | ForEach-Object {
        Unique "wu-$($_.Id)-$($_.TimeCreated.ToString('MMdd'))" "WU: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # CBS/Servicing errors
    Get-WinEvent -FilterHashtable @{LogName='Setup'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 20 | ForEach-Object {
        Unique "cbs-$($_.Id)" "CBS: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # Pending reboot check
    $pendingReboot = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    if ($pendingReboot) { Problem "REBOOT PENDING: Windows Update requires restart" }
} catch {}

# ============================================================================
# 8. STORE/UWP APP ISSUES
# ============================================================================
Section "STORE/UWP APP ISSUES"
Write-Host "Checking Store apps..." -ForegroundColor Gray
try {
    # AppX deployment errors
    # Skip: 0x80073D02 = app needs closing (normal during updates)
    # Skip: BrokerInfrastructure errors (0xD0074005, 0xD007007A) - transient registration errors
    Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-AppXDeploymentServer/Operational'; Level=2,3; StartTime=$last24h} -EA 0 -MaxEvents 30 | ForEach-Object {
        if ($_.Message -notmatch '0x80073D02|BrokerInfrastructure|0xD0074005|0xD007007A') {
            if ($_.Message -match 'Package\s+(\S+)') {
                Unique "appx-$($Matches[1])" "APPX: $($Matches[1]) - $($_.Message.Substring(0,[Math]::Min(150,$_.Message.Length)))"
            }
        }
    }

    # Store errors from Application log
    Get-WinEvent -FilterHashtable @{LogName='Application'; ID=1001; StartTime=$lastHour} -EA 0 -MaxEvents 20 | ForEach-Object {
        if ($_.Message -match 'StoreAgent.*Failure.*P2:\s*([0-9A-Fx]+)') {
            Unique "store-$($Matches[1])" "STORE ERROR: Code $($Matches[1])"
        }
    }
} catch {}

# ============================================================================
# 9. SCHEDULED TASK FAILURES
# ============================================================================
Section "SCHEDULED TASK FAILURES"
Write-Host "Checking tasks..." -ForegroundColor Gray
try {
    # Codes that are NOT failures (common non-error result codes)
    # 0x800710E0 = The operator or administrator has refused the request (disabled/not scheduled)
    # 0x8007042B = The process terminated unexpectedly (often just means task didn't need to run)
    # 0x80040111 = ClassFactory cannot supply requested class (OLE error, often benign)
    # 0x80070002 = File not found (task may have been removed/not installed)
    # 0x80070032 = Request not supported (feature not available)
    # 0xFFFFFFFF = Task has never run or result not available
    # 267011 (0x41303) = Task is currently running
    # Add more OK codes - these are common non-error results
    # 0x8007042B = process terminated (often normal for on-demand tasks)
    # 0x80040111 = class not registered (OLE, often benign)
    # 0x80070002 = file not found (task removed/optional)
    # Use UNSIGNED decimal values for comparison (PowerShell signed/unsigned issue)
    # 0x800710E0 = 2147946720, 0x8007042B = 2147943467, 0x80040111 = 2147746065, 0x80070402 = 2147942402
    # CORRECTED: 0x800710E0 is 2147946720 not 2148007136
    $okCodes = @(0, 1, 267008, 267009, 267010, 267011, 267014, 2147946720, 2147943467, 2147944121, 2147746065, 2147943525, 1073807364, 2147942402, 2147942450, 12, 4294967295)

    Get-ScheduledTask -EA 0 | Where-Object { $_.State -eq 'Ready' } | ForEach-Object {
        $info = Get-ScheduledTaskInfo -TaskName $_.TaskName -TaskPath $_.TaskPath -EA 0
        # Convert result to unsigned for comparison
        $result = [uint32]$info.LastTaskResult
        if ($info -and $result -notin $okCodes -and $info.LastRunTime -gt $last7d) {
            $code = "0x{0:X}" -f $result
            Problem "TASK FAILED: $($_.TaskPath)$($_.TaskName) - $code"
        }
    }
} catch {}

# ============================================================================
# 10. CRASHES & BSOD (only AFTER current boot - boot-time events are historical)
# ============================================================================
Section "CRASHES & BSOD"
Write-Host "Checking system crashes..." -ForegroundColor Gray
$postBootTime = $bootTime.AddMinutes(5)  # Skip first 5 min of boot events
try {
    # Kernel Power (unexpected shutdown) - Event 41 - ONLY after boot settled
    Get-WinEvent -FilterHashtable @{LogName='System'; ID=41; StartTime=$postBootTime} -EA 0 -MaxEvents 5 | ForEach-Object {
        Problem "[$($_.TimeCreated)] UNEXPECTED SHUTDOWN (Kernel-Power 41)"
    }

    # Dirty shutdown - Event 6008 - these are always logged at boot about previous session
    # Only report if there's been another one AFTER system stabilized
    Get-WinEvent -FilterHashtable @{LogName='System'; ID=6008; StartTime=$postBootTime} -EA 0 -MaxEvents 5 | ForEach-Object {
        Problem "[$($_.TimeCreated)] DIRTY SHUTDOWN: $($_.Message.Substring(0,[Math]::Min(150,$_.Message.Length)))"
    }

    # BSOD reports
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WER-SystemErrorReporting'; StartTime=$last30d} -EA 0 -MaxEvents 20 | ForEach-Object {
        Problem "[$($_.TimeCreated)] BSOD: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # Minidump files
    if (Test-Path "$env:SystemRoot\Minidump") {
        Get-ChildItem "$env:SystemRoot\Minidump" -EA 0 | Where-Object { $_.CreationTime -gt $last30d } | ForEach-Object {
            Problem "BSOD DUMP: $($_.Name) - $($_.CreationTime)"
        }
    }

    # LiveKernelReports
    if (Test-Path "$env:SystemRoot\LiveKernelReports") {
        Get-ChildItem "$env:SystemRoot\LiveKernelReports" -Recurse -EA 0 | Where-Object { $_.CreationTime -gt $last30d -and $_.Extension -eq '.dmp' } | ForEach-Object {
            Problem "LIVE KERNEL DUMP: $($_.Name) - $($_.CreationTime)"
        }
    }
} catch {}

# ============================================================================
# 11. HARDWARE ERRORS (WHEA/MCE)
# ============================================================================
Section "HARDWARE ERRORS"
Write-Host "Checking hardware errors..." -ForegroundColor Gray
try {
    # WHEA errors - serious hardware issues
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='WHEA-Logger'; StartTime=$last30d} -EA 0 -MaxEvents 30 | ForEach-Object {
        Problem "[$($_.TimeCreated)] WHEA: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # Machine Check Exceptions
    Get-WinEvent -FilterHashtable @{LogName='System'; ID=17,18,19,28,29; StartTime=$last30d} -EA 0 -MaxEvents 10 | ForEach-Object {
        Problem "[$($_.TimeCreated)] MCE: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # Memory diagnostics
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-MemoryDiagnostics-Results'; StartTime=$last30d} -EA 0 -MaxEvents 5 | ForEach-Object {
        if ($_.Message -match 'error|problem|fail') {
            Problem "MEMORY: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    }
} catch {}

# ============================================================================
# 12. SYSTEM FILE INTEGRITY
# ============================================================================
Section "SYSTEM FILE INTEGRITY"
Write-Host "Checking system files..." -ForegroundColor Gray
try {
    Write-Host "  Running DISM..." -ForegroundColor DarkGray
    $dism = & DISM /Online /Cleanup-Image /CheckHealth 2>&1 | Out-String
    # Only report corruption if DISM explicitly says "repairable" - not just any message
    if ($dism -match 'component store is repairable' -or $dism -match 'corruption detected') {
        if ($dism -notmatch 'No component store corruption') {
            Problem "DISM: Component store corruption detected"
        }
    }

    # Missing critical system files
    @("$env:SystemRoot\System32\kernel32.dll","$env:SystemRoot\System32\ntdll.dll","$env:SystemRoot\System32\ntoskrnl.exe",
      "$env:SystemRoot\System32\win32k.sys","$env:SystemRoot\System32\drivers\ntfs.sys","$env:SystemRoot\System32\hal.dll") | ForEach-Object {
        if (-not (Test-Path $_)) { Problem "MISSING CRITICAL: $_" }
    }
} catch {}

# ============================================================================
# 13. NETWORK ISSUES
# ============================================================================
Section "NETWORK ISSUES"
Write-Host "Checking network..." -ForegroundColor Gray
try {
    # TCP/IP errors
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Tcpip'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 20 | ForEach-Object {
        Unique "tcpip-$($_.Id)" "TCP/IP: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # DNS client errors
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-DNS-Client'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 10 | ForEach-Object {
        Unique "dns-$($_.Id)" "DNS: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # NDIS/Network adapter errors
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-NDIS'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 10 | ForEach-Object {
        Unique "ndis-$($_.Id)" "NDIS: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # Network adapter status
    Get-NetAdapter -EA 0 | Where-Object { $_.Status -eq 'Disconnected' -and $_.AdminStatus -eq 'Up' } | ForEach-Object {
        Problem "NETWORK: $($_.Name) disconnected but should be up"
    }
} catch {}

# ============================================================================
# 14. BOOT/STARTUP ISSUES
# ============================================================================
Section "BOOT/STARTUP ISSUES"
Write-Host "Checking boot..." -ForegroundColor Gray
try {
    # Boot driver failures (excluding known non-critical)
    # dam, luafv, WinSetupMon are commonly disabled/delayed and not critical
    Get-WinEvent -FilterHashtable @{LogName='System'; ID=7026; StartTime=$bootTime} -EA 0 -MaxEvents 10 | ForEach-Object {
        if ($_.Message -notmatch 'dam|luafv|WinSetupMon') {
            Problem "BOOT DRIVER: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    }

    # TPM status
    $tpm = Get-Tpm -EA 0
    if ($tpm -and (-not $tpm.TpmReady -or -not $tpm.TpmEnabled)) {
        Problem "TPM: Ready=$($tpm.TpmReady) Enabled=$($tpm.TpmEnabled)"
    }

    # Kernel-Boot errors
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-Boot'; Level=1,2; StartTime=$bootTime} -EA 0 -MaxEvents 10 | ForEach-Object {
        Problem "KERNEL-BOOT: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }
} catch {}

# ============================================================================
# 15. REGISTRY ISSUES
# ============================================================================
Section "REGISTRY ISSUES"
Write-Host "Checking registry..." -ForegroundColor Gray
try {
    # Registry errors
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-Registry'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 10 | ForEach-Object {
        Unique "reg-$($_.Id)" "REGISTRY: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # User profile errors
    Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Microsoft-Windows-User Profiles Service'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 10 | ForEach-Object {
        Unique "profile-$($_.Id)" "PROFILE: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }
} catch {}

# ============================================================================
# 16. WMI ISSUES
# ============================================================================
Section "WMI ISSUES"
Write-Host "Checking WMI..." -ForegroundColor Gray
try {
    # WMI errors (not just operational queries)
    Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-WMI-Activity/Operational'; Level=1,2; StartTime=$last24h} -EA 0 -MaxEvents 20 | ForEach-Object {
        if ($_.Message -match 'error|fail|invalid|denied' -and $_.Message -notmatch 'Start IWbemServices') {
            Unique "wmi-$($_.TimeCreated.ToString('HHmm'))" "WMI: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    }
} catch {}

# ============================================================================
# 17. COM/DCOM ISSUES
# ============================================================================
Section "COM/DCOM ISSUES"
Write-Host "Checking COM..." -ForegroundColor Gray
try {
    # DCOM errors (skip ASUS bloatware timeouts - common and harmless)
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-DistributedCOM'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 20 | ForEach-Object {
        if ($_.Message -notmatch 'ASUS|ArmouryCrate|ASUSPCAssistant|ROG') {
            Unique "dcom-$($_.Id)" "DCOM: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    }

    # COM+ errors
    Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='COMPLUS'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 10 | ForEach-Object {
        Unique "complus-$($_.Id)" "COM+: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }
} catch {}

# ============================================================================
# 18. POWER ISSUES (only critical - skip sleep/resume and boot-time info)
# ============================================================================
Section "POWER ISSUES"
Write-Host "Checking power..." -ForegroundColor Gray
try {
    # Only unexpected shutdowns AFTER boot settled (5 min)
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-Power'; ID=41; StartTime=$postBootCutoff} -EA 0 -MaxEvents 5 | ForEach-Object {
        Problem "[$($_.TimeCreated)] POWER: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }
} catch {}

# ============================================================================
# 19. AUDIO ISSUES
# ============================================================================
Section "AUDIO ISSUES"
Write-Host "Checking audio..." -ForegroundColor Gray
try {
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Audio'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 10 | ForEach-Object {
        Unique "audio-$($_.Id)" "AUDIO: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    $audioSvc = Get-Service -Name 'Audiosrv' -EA 0
    if ($audioSvc -and $audioSvc.Status -ne 'Running') { Problem "AUDIO SERVICE: Not running" }
} catch {}

# ============================================================================
# 20. USB ISSUES
# ============================================================================
Section "USB ISSUES"
Write-Host "Checking USB..." -ForegroundColor Gray
try {
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-USB-USBHUB3','Microsoft-Windows-USB-USBXHCI'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 15 | ForEach-Object {
        Unique "usb-$($_.Id)-$($_.TimeCreated.ToString('MMdd'))" "USB: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }
} catch {}

# ============================================================================
# 21. HYPER-V/VIRTUALIZATION
# ============================================================================
Section "VIRTUALIZATION ISSUES"
Write-Host "Checking virtualization..." -ForegroundColor Gray
try {
    # Hyper-V errors (if enabled)
    Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Hyper-V-Hypervisor-Admin'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 10 | ForEach-Object {
        Unique "hyperv-$($_.Id)" "HYPER-V: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # Hyper-V VMMS errors (skip Docker errors if Docker not running - just leftover references)
    Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Hyper-V-VMMS-Admin'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 10 | ForEach-Object {
        if ($_.Message -notmatch 'DockerDesktop|Docker Desktop') {
            Unique "vmms-$($_.Id)" "VMMS: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    }
} catch {}

# ============================================================================
# 22A. EXPLORER.EXE CRASH DETECTION (NEW - CATCHES SHELL UI FAILURES)
# ============================================================================
Section "EXPLORER.EXE CRASHES & SHELL UI FAILURES"
Write-Host "Checking explorer.exe status..." -ForegroundColor Cyan
try {
    # Check if explorer.exe is running
    $explorerProc = Get-Process explorer -EA 0
    if (-not $explorerProc) {
        CriticalProblem "EXPLORER.EXE NOT RUNNING: Shell UI is down - taskbar/desktop not visible"
    } else {
        Write-Host "  Explorer running: $(($explorerProc | Measure-Object).Count) processes" -ForegroundColor Green
    }

    # Check for explorer.exe crash events in last 24 hours
    Get-WinEvent -FilterHashtable @{LogName='Application'; Level=1,2,3; StartTime=$last24h} -EA 0 -MaxEvents 100 | ForEach-Object {
        if ($_.Message -match 'explorer\.exe|Windows Explorer|shell.*crash|taskbar.*crash|desktop.*fail' -or
            ($_.ProviderName -match 'Windows Error Reporting|WER' -and $_.Message -match 'explorer')) {
            CriticalProblem "EXPLORER CRASH EVENT: $($_.Message.Substring(0,[Math]::Min(300,$_.Message.Length)))"
        }
    }

    # Check System log for explorer-related kernel errors
    Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=$last24h} -EA 0 -MaxEvents 50 | ForEach-Object {
        if ($_.Message -match 'explorer\.exe|shell32|dwm\.exe.*explorer|explorer.*hung|explorer.*failed') {
            CriticalProblem "SYSTEM EXPLORER ERROR: $($_.Message.Substring(0,[Math]::Min(300,$_.Message.Length)))"
        }
    }

    # Check for hung/suspended explorer processes
    $explorerProc | ForEach-Object {
        $id = $_.Id
        try {
            $suspended = Get-Process -Id $id -EA 0
            if ($suspended) {
                # Check handles count as indicator of resource issues
                $handles = $suspended.Handles
                if ($handles -gt 10000) {
                    Problem "EXPLORER RESOURCE LEAK: Handle count $handles (very high - may indicate crash pending)"
                }
            }
        } catch {}
    }

    # Check for explorer restart events (indicates crashes)
    Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$last24h} -EA 0 -MaxEvents 200 | Where-Object {
        $_.ProviderName -eq 'Microsoft-Windows-RestartManager' -and $_.Message -match 'explorer'
    } | ForEach-Object {
        Problem "EXPLORER RESTART DETECTED: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # Check desktop window is accessible (if explorer is running)
    if ($explorerProc) {
        try {
            Add-Type -AssemblyName System.Windows.Forms -EA 0
            [void][Windows.Forms.Screen]::PrimaryScreen.Bounds
        } catch {
            # Skip Windows.Forms check if not available - it's not critical
            Write-Host "    (Windows.Forms check skipped - not critical)" -ForegroundColor Gray
        }
    }

    # Check for shellex handler crashes (right-click context menu)
    Get-WinEvent -FilterHashtable @{LogName='Application'; Level=1,2; StartTime=$last24h} -EA 0 -MaxEvents 50 | ForEach-Object {
        if ($_.Message -match 'ContextMenu|shellex|shell extension|handler.*crash|extension.*fail') {
            Problem "SHELL EXTENSION CRASH (context menu): $($_.Message.Substring(0,[Math]::Min(250,$_.Message.Length)))"
        }
    }

    # Check for dwm.exe (Desktop Window Manager) crashes which break taskbar rendering
    $dwmProc = Get-Process dwm -EA 0
    if (-not $dwmProc) {
        CriticalProblem "DESKTOP WINDOW MANAGER (dwm.exe) NOT RUNNING: Taskbar/UI rendering broken"
    }

    # Check taskbar COM registration (HKLM is correct location, not HKCU)
    try {
        $taskbarCOM = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved" -EA 0 |
            Where-Object { $_ -match 'taskbar|shell' }
        if (-not $taskbarCOM) {
            Problem "TASKBAR COM REGISTRATION: Shell extension registry may be corrupted"
        }
    } catch {}

    # Check for theme/visual style service
    $themesSvc = Get-Service 'Themes' -EA 0
    if ($themesSvc -and $themesSvc.Status -ne 'Running' -and $themesSvc.StartType -eq 'Automatic') {
        Problem "THEMES SERVICE DOWN: May cause taskbar/visual rendering failure"
    }

} catch {
    Write-Host "  Error checking explorer status: $_" -ForegroundColor DarkRed
}

# ============================================================================
# 22. PRINT ISSUES
# ============================================================================
Section "PRINT ISSUES"
Write-Host "Checking print..." -ForegroundColor Gray
try {
    Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-PrintService/Admin'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 10 | ForEach-Object {
        Unique "print-$($_.Id)" "PRINT: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    $spooler = Get-Service -Name 'Spooler' -EA 0
    if ($spooler -and $spooler.StartType -eq 'Automatic' -and $spooler.Status -ne 'Running') {
        Problem "PRINT SPOOLER: Not running"
    }
} catch {}

# ============================================================================
# 23. TIME SYNC ISSUES
# ============================================================================
Section "TIME SYNC ISSUES"
Write-Host "Checking time..." -ForegroundColor Gray
try {
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Time-Service'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 10 | ForEach-Object {
        if ($_.Message -match 'error|fail|cannot') {
            Unique "time-$($_.Id)" "TIME: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    }
} catch {}

# ============================================================================
# 24. INSTALLER/MSI ISSUES
# ============================================================================
Section "INSTALLER ISSUES"
Write-Host "Checking installers..." -ForegroundColor Gray
try {
    # Skip Error 1316 "account already exists" - benign SDK/installer warning
    Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='MsiInstaller'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 15 | ForEach-Object {
        if ($_.Message -notmatch 'Error 1316|account already exists') {
            Unique "msi-$($_.TimeCreated.ToString('MMddHH'))" "MSI: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    }
} catch {}

# ============================================================================
# 25. NETWORK PERFORMANCE & LATENCY ISSUES
# ============================================================================
Section "NETWORK PERFORMANCE & LATENCY"
Write-Host "Checking network performance..." -ForegroundColor Cyan
try {
    # DNS resolution issues
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-DNS-Client'; Level=1,2,3; StartTime=$last24h} -EA 0 -MaxEvents 20 | ForEach-Object {
        Problem "DNS CLIENT: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # TCPIP errors causing latency
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Tcpip'; Level=1,2,3; StartTime=$last24h} -EA 0 -MaxEvents 20 | ForEach-Object {
        if ($_.Message -match 'timeout|retransmit|fail|reset|drop|congestion') {
            Problem "TCPIP: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    }

    # Network adapter errors
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-NDIS'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 15 | ForEach-Object {
        Problem "NETWORK ADAPTER (NDIS): $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # Check DNS cache corruption (only report if >50 failures - some failed lookups are normal)
    $dnsCache = Get-DnsClientCache -EA 0 | Where-Object { $_.Status -ne 'Success' }
    $dnsFailCount = ($dnsCache | Measure-Object).Count
    if ($dnsFailCount -gt 50) {
        Problem "DNS CACHE: $dnsFailCount failed entries in DNS cache"
    }

    # Network QoS throttling detection
    $qosPolicies = Get-NetQosPolicy -EA 0 | Where-Object { $_.ThrottleRateActionBitsPerSecond -gt 0 }
    if ($qosPolicies) {
        Problem "QOS THROTTLING ACTIVE: $(($qosPolicies | Measure-Object).Count) bandwidth-limiting policies detected"
    }

    # Check for network reset events
    Get-WinEvent -FilterHashtable @{LogName='System'; Id=10000,10001; StartTime=$last24h} -EA 0 -MaxEvents 10 | ForEach-Object {
        if ($_.ProviderName -match 'NDIS|Tcpip|Network') {
            Problem "NETWORK RESET EVENT: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    }

    # ==== ADVANCED NETWORK SPEED & QUALITY CHECKS ====

    # Network packet loss detection
    try {
        $ipStats = Get-NetIPAddress -ErrorAction SilentlyContinue | Where-Object { $_.AddressFamily -eq 'IPv4' }
        if ($ipStats) {
            # Get IPv4 statistics
            $tcpStats = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | Measure-Object
            if ($tcpStats.Count -gt 100) {
                Problem "NETWORK SATURATION: $($tcpStats.Count) established connections - potential bottleneck"
            }
        }
    } catch {}

    # Network adapter speed/duplex issues
    try {
        Get-NetAdapter -Physical -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Status -eq 'Up') {
                $speed = $_.LinkSpeed
                if ($speed -and $speed -lt 100000000) {
                    $speedMbps = [math]::Round($speed / 1000000)
                    Problem "SLOW NETWORK ADAPTER: $($_.Name) running at $speedMbps Mbps (should be 1000+ Mbps)"
                }
                # Check for half-duplex (very slow for modern networks)
                if ($speed -and $speed -eq 10000000) {
                    Problem "VERY SLOW NETWORK: $($_.Name) at 10Mbps - ancient speed, indicates driver/cable issue"
                }
            }
        }
    } catch {}

    # RPC network latency issues
    try {
        Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-RPC'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 15 | ForEach-Object {
            if ($_.Message -match 'timeout|latency|failed|unreachable') {
                Problem "RPC NETWORK LATENCY: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
            }
        }
    } catch {}

    # Routing/gateway issues
    try {
        $routes = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue
        if (-not $routes) {
            Problem "NO DEFAULT GATEWAY: System cannot reach internet - no default route configured"
        }
    } catch {}

    # Network interface errors/dropped packets
    try {
        Get-NetAdapterStatistics -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.ReceivedErrors -gt 10 -or $_.TransmittedErrors -gt 10) {
                Problem "NETWORK ERRORS: $($_.Name) has $($_.ReceivedErrors) receive errors, $($_.TransmittedErrors) transmit errors"
            }
            if ($_.ReceivedDiscards -gt 10 -or $_.TransmittedDiscards -gt 10) {
                Problem "DROPPED PACKETS: $($_.Name) discarded $($_.ReceivedDiscards) receive, $($_.TransmittedDiscards) transmit packets"
            }
        }
    } catch {}

} catch {}

# ============================================================================
# 26. CPU/RAM PERFORMANCE ISSUES (GAME LAG, MULTITASKING)
# ============================================================================
Section "CPU/RAM PERFORMANCE ISSUES"
Write-Host "Checking CPU/RAM performance..." -ForegroundColor Cyan
try {
    # High CPU usage detection
    $cpuCounter = Get-Counter '\Processor(_Total)\% Processor Time' -EA 0
    if ($cpuCounter) {
        $cpuUsage = [math]::Round($cpuCounter.CounterSamples[0].CookedValue, 1)
        if ($cpuUsage -gt 85) {
            CriticalProblem "HIGH CPU USAGE: $cpuUsage% - May cause game lag and stuttering"
        } elseif ($cpuUsage -gt 70) {
            Problem "ELEVATED CPU USAGE: $cpuUsage% - Monitor for performance impact"
        }
    }

    # Memory pressure detection
    $memory = Get-CimInstance Win32_OperatingSystem -EA 0
    if ($memory) {
        $totalMemMB = [math]::Round($memory.TotalVisibleMemorySize / 1024)
        $freeMemMB = [math]::Round($memory.FreePhysicalMemory / 1024)
        $usedPercent = [math]::Round((($totalMemMB - $freeMemMB) / $totalMemMB) * 100, 1)
        if ($usedPercent -gt 90) {
            CriticalProblem "CRITICAL MEMORY PRESSURE: $usedPercent% used ($freeMemMB MB free) - Causes freezes/crashes"
        } elseif ($usedPercent -gt 80) {
            Problem "HIGH MEMORY USAGE: $usedPercent% used ($freeMemMB MB free) - May cause stuttering"
        }
    }

    # ==== ADVANCED CPU PERFORMANCE CHECKS ====

    # CPU clock speed / power states
    try {
        $processorSpeed = Get-CimInstance Win32_Processor -EA 0 | Select-Object -First 1
        if ($processorSpeed) {
            $maxSpeed = $processorSpeed.MaxClockSpeed
            $currentSpeed = $processorSpeed.CurrentClockSpeed
            if ($currentSpeed -lt ($maxSpeed * 0.5)) {
                Problem "LOW CPU CLOCK SPEED: Current $($currentSpeed)MHz vs Max $($maxSpeed)MHz - CPU is throttled/underclocked"
            }
        }
    } catch {}

    # Context switching overhead (high values indicate thrashing)
    try {
        $ctxSwitch = Get-Counter '\System\Context Switches/sec' -EA 0
        if ($ctxSwitch) {
            $ctxValue = [math]::Round($ctxSwitch.CounterSamples[0].CookedValue, 0)
            if ($ctxValue -gt 5000) {
                Problem "HIGH CONTEXT SWITCHING: $ctxValue/sec - indicates excessive multitasking or thread contention"
            }
        }
    } catch {}

    # Process Queue Length (waiting for CPU)
    try {
        $procQueue = Get-Counter '\System\Processor Queue Length' -EA 0
        if ($procQueue) {
            $queueValue = [math]::Round($procQueue.CounterSamples[0].CookedValue, 1)
            if ($queueValue -gt 2) {
                Problem "HIGH PROCESSOR QUEUE: $queueValue processes waiting for CPU - system is overloaded"
            }
        }
    } catch {}

    # ==== ADVANCED RAM PERFORMANCE CHECKS ====

    # Pagefile usage (spilling to disk)
    try {
        $pagefiles = Get-CimInstance Win32_PageFileUsage -EA 0
        if ($pagefiles) {
            foreach ($pf in $pagefiles) {
                $pfUsedPercent = [math]::Round(($pf.CurrentUsage / $pf.AllocatedBaseSize) * 100, 1)
                if ($pfUsedPercent -gt 80) {
                    Problem "HIGH PAGEFILE USAGE: $pfUsedPercent% of pagefile in use - system using disk for RAM (very slow)"
                }
            }
        }
    } catch {}

    # Memory available (available RAM for new processes)
    try {
        $memAvailable = Get-Counter '\Memory\Available MBytes' -EA 0
        if ($memAvailable) {
            $availMB = [math]::Round($memAvailable.CounterSamples[0].CookedValue)
            if ($availMB -lt 500) {
                Problem "CRITICAL LOW AVAILABLE MEMORY: Only $availMB MB available - system will struggle to start programs"
            } elseif ($availMB -lt 1000) {
                Problem "LOW AVAILABLE MEMORY: Only $availMB MB available - limited room for new programs"
            }
        }
    } catch {}

    # Memory page faults (indicates accessing pagefile)
    try {
        $pageFaults = Get-Counter '\Memory\Pages/sec' -EA 0
        if ($pageFaults) {
            $pageValue = [math]::Round($pageFaults.CounterSamples[0].CookedValue)
            if ($pageValue -gt 1000) {
                Problem "HIGH PAGE FAULTS: $pageValue pages/sec - excessive disk I/O for memory (major slowdown)"
            }
        }
    } catch {}

    # Resource-hogging processes (>3600s CPU or >2GB RAM, excluding normal system processes)
    $excludedProcs = @('dwm','System','csrss','svchost','explorer','node','chrome','firefox','msedge','Code','LightingService')
    $resourceHogs = Get-Process -EA 0 | Where-Object {
        ($_.CPU -gt 3600 -or $_.WorkingSet64 -gt 2GB) -and
        $excludedProcs -notcontains $_.ProcessName
    } | Select-Object -First 5 ProcessName, @{N='CPU';E={[math]::Round($_.CPU,1)}}, @{N='RAM_MB';E={[math]::Round($_.WorkingSet64/1MB)}}
    if ($resourceHogs) {
        foreach ($hog in $resourceHogs) {
            Problem "RESOURCE HOG: $($hog.ProcessName) - CPU: $($hog.CPU)s, RAM: $($hog.RAM_MB)MB"
        }
    }

    # Kernel memory leak detection
    Get-WinEvent -FilterHashtable @{LogName='System'; Id=2019,2020; StartTime=$last7d} -EA 0 -MaxEvents 5 | ForEach-Object {
        CriticalProblem "KERNEL MEMORY LEAK: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # Process crash/hang events
    Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000,1002; StartTime=$last24h} -EA 0 -MaxEvents 20 | ForEach-Object {
        if ($_.Message -notmatch 'explorer\.exe') {
            Problem "APPLICATION CRASH: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    }
} catch {}

# ============================================================================
# 27. GPU/GRAPHICS PERFORMANCE ISSUES (FRAME DROPS, STUTTERING)
# ============================================================================
Section "GPU/GRAPHICS PERFORMANCE"
Write-Host "Checking GPU performance..." -ForegroundColor Cyan
try {
    # TDR (Timeout Detection Recovery) events - GPU driver crashes
    Get-WinEvent -FilterHashtable @{LogName='System'; Id=4101; StartTime=$last7d} -EA 0 -MaxEvents 10 | ForEach-Object {
        CriticalProblem "GPU TDR (DRIVER CRASH): Display driver stopped responding - causes frame drops"
    }

    # Display driver errors
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Display'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 15 | ForEach-Object {
        Problem "DISPLAY DRIVER: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # NVIDIA specific errors
    Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$last7d} -EA 0 -MaxEvents 50 | Where-Object {
        $_.ProviderName -match 'nvlddmkm|nvidia' -and $_.Level -le 3
    } | ForEach-Object {
        Problem "NVIDIA DRIVER: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # AMD specific errors
    Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$last7d} -EA 0 -MaxEvents 50 | Where-Object {
        $_.ProviderName -match 'amdkmdap|atikmdag|amd' -and $_.Level -le 3
    } | ForEach-Object {
        Problem "AMD DRIVER: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # Intel integrated graphics errors
    Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$last7d} -EA 0 -MaxEvents 50 | Where-Object {
        $_.ProviderName -match 'igfx|Intel.*Graphics|dxgkrnl' -and $_.Level -le 3
    } | ForEach-Object {
        Problem "INTEL GPU DRIVER: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # DirectX errors
    Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$last7d} -EA 0 -MaxEvents 30 | Where-Object {
        $_.Message -match 'DirectX|D3D|DXGI|shader|graphics device'
    } | ForEach-Object {
        Problem "DIRECTX ERROR: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # ==== ADVANCED GPU PERFORMANCE CHECKS ====

    # Check for VRAM pressure (via DWM and graphics processes)
    $dwmMemory = Get-Process dwm -EA 0 | Select-Object -First 1 WorkingSet64
    if ($dwmMemory -and $dwmMemory.WorkingSet64 -gt 500MB) {
        Problem "DWM MEMORY HIGH: Desktop Window Manager using $([math]::Round($dwmMemory.WorkingSet64/1MB))MB - may indicate VRAM pressure"
    }

    # GPU process memory usage (nvidia-smi equivalent for NVIDIA)
    try {
        $gpuProcs = Get-Process -Name "svchost","nvcontainer","dwm" -EA 0 | ForEach-Object {
            if ($_.WorkingSet64 -gt 1GB) {
                Problem "GPU MEMORY USAGE: $($_.ProcessName) using $([math]::Round($_.WorkingSet64/1GB, 1))GB"
            }
        }
    } catch {}

    # Video memory fragmentation detection (indirect via failed allocations)
    try {
        Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$last24h} -EA 0 -MaxEvents 50 | Where-Object {
            $_.Message -match 'VRAM|video.*memory|allocation.*fail|graphics.*memory'
        } | ForEach-Object {
            Problem "VRAM ALLOCATION: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    } catch {}

    # GPU reset/hang events
    try {
        Get-WinEvent -FilterHashtable @{LogName='System'; Id=4102,4103,4104; StartTime=$last7d} -EA 0 -MaxEvents 10 | ForEach-Object {
            CriticalProblem "GPU RESET EVENT: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    } catch {}

    # Display driver power management issues
    try {
        Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Power-Troubleshooter'; StartTime=$last7d} -EA 0 -MaxEvents 10 | Where-Object {
            $_.Message -match 'display|gpu|graphics|video'
        } | ForEach-Object {
            Problem "GPU POWER MANAGEMENT: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    } catch {}

    # GPU thermal/throttling issues
    try {
        Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$last7d} -EA 0 -MaxEvents 50 | Where-Object {
            $_.Message -match 'GPU.*throttl|graphics.*thermal|video.*overheat'
        } | ForEach-Object {
            CriticalProblem "GPU THERMAL THROTTLING: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    } catch {}

    # Monitor/display detection failures
    try {
        Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-DisplayDriver'; StartTime=$last7d} -EA 0 -MaxEvents 15 | ForEach-Object {
            Problem "DISPLAY DETECTION: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    } catch {}

} catch {}

# ============================================================================
# 28. THERMAL/THROTTLING ISSUES
# ============================================================================
Section "THERMAL & THROTTLING"
Write-Host "Checking thermal status..." -ForegroundColor Cyan
try {
    # Thermal events
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-Power'; StartTime=$last7d} -EA 0 -MaxEvents 20 | Where-Object {
        $_.Message -match 'thermal|throttl|temperature|overheat'
    } | ForEach-Object {
        CriticalProblem "THERMAL EVENT: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # Processor throttling
    Get-WinEvent -FilterHashtable @{LogName='System'; Id=37; StartTime=$last7d} -EA 0 -MaxEvents 10 | ForEach-Object {
        Problem "PROCESSOR THROTTLED: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # Check current CPU temperature if WMI supports it
    # Disabled - CPU temperature is hardware-specific and not fixable via software
    # try {
    #     $temps = Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace root/wmi -EA 0
    #     foreach ($t in $temps) {
    #         $celsius = [math]::Round(($t.CurrentTemperature - 2732) / 10, 1)
    #         if ($celsius -gt 90) {
    #             CriticalProblem "CPU TEMPERATURE CRITICAL: ${celsius}C - Thermal throttling likely"
    #         } elseif ($celsius -gt 80) {
    #             Problem "CPU TEMPERATURE HIGH: ${celsius}C - May cause throttling under load"
    #         }
    #     }
    # } catch {}
} catch {}

# ============================================================================
# 29. DISK I/O PERFORMANCE
# ============================================================================
Section "DISK I/O PERFORMANCE"
Write-Host "Checking disk I/O..." -ForegroundColor Cyan
try {
    # Disk errors
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='disk','Microsoft-Windows-StorPort'; Level=1,2,3; StartTime=$last7d} -EA 0 -MaxEvents 20 | ForEach-Object {
        CriticalProblem "DISK ERROR: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # NTFS errors
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Ntfs'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 15 | ForEach-Object {
        CriticalProblem "NTFS ERROR: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # Volume shadow copy errors
    Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='VSS'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 10 | ForEach-Object {
        Problem "VSS ERROR: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # Check disk space on all volumes
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -EA 0 | ForEach-Object {
        $freePercent = [math]::Round(($_.FreeSpace / $_.Size) * 100, 1)
        if ($freePercent -lt 3) {
            CriticalProblem "DISK SPACE CRITICAL: Drive $($_.DeviceID) only $freePercent% free ($([math]::Round($_.FreeSpace/1GB))GB)"
        } elseif ($freePercent -lt 10) {
            Problem "DISK SPACE LOW: Drive $($_.DeviceID) only $freePercent% free"
        }
    }

    # SSD/HDD health via SMART (if available)
    Get-WinEvent -FilterHashtable @{LogName='System'; Id=7,51,52; StartTime=$last30d} -EA 0 -MaxEvents 10 | ForEach-Object {
        CriticalProblem "DISK HEALTH WARNING: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }
} catch {}

# ============================================================================
# 30. DOCKER & CONTAINER ISSUES
# ============================================================================
Section "DOCKER & CONTAINER ISSUES"
Write-Host "Checking Docker/containers..." -ForegroundColor Cyan
try {
    # Docker Desktop service
    $dockerSvc = Get-Service 'com.docker.service' -EA 0
    if ($dockerSvc) {
        if ($dockerSvc.Status -ne 'Running') {
            Problem "DOCKER SERVICE NOT RUNNING: Docker Desktop service is stopped"
        }
    }

    # Docker daemon errors
    Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$last24h} -EA 0 -MaxEvents 30 | Where-Object {
        $_.Message -match 'docker|container|moby'
    } | ForEach-Object {
        if ($_.Level -le 2) {
            Problem "DOCKER ERROR: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    }

    # Container networking issues
    Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Hyper-V-VmSwitch-Operational'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 10 | ForEach-Object {
        Problem "CONTAINER NETWORKING: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # HNS (Host Network Service) errors
    Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Host-Network-Service-Admin'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 10 | ForEach-Object {
        Problem "HNS ERROR: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # Check Docker disk usage
    $dockerPath = "$env:LOCALAPPDATA\Docker"
    if (Test-Path $dockerPath) {
        $dockerSize = (Get-ChildItem $dockerPath -Recurse -EA 0 | Measure-Object Length -Sum).Sum
        if ($dockerSize -gt 50GB) {
            Problem "DOCKER DISK USAGE HIGH: $([math]::Round($dockerSize/1GB))GB - Consider docker system prune"
        }
    }
} catch {}

# ============================================================================
# 31. HYPER-V & VIRTUALIZATION PERFORMANCE
# ============================================================================
Section "HYPER-V & VIRTUALIZATION"
Write-Host "Checking Hyper-V..." -ForegroundColor Cyan
try {
    # Hyper-V memory allocation
    Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Hyper-V-Worker-Admin'; Level=1,2,3; StartTime=$last7d} -EA 0 -MaxEvents 15 | ForEach-Object {
        Problem "HYPER-V WORKER: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # Hyper-V VMMS errors
    Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Hyper-V-VMMS-Admin'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 15 | ForEach-Object {
        if ($_.Message -notmatch 'DockerDesktop') {
            Problem "HYPER-V VMMS: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    }

    # VHD errors
    Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-VHDMP-Operational'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 10 | ForEach-Object {
        Problem "VHD ERROR: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # Check vmwp.exe resource usage
    $vmwp = Get-Process vmwp -EA 0
    if ($vmwp) {
        foreach ($v in $vmwp) {
            if ($v.WorkingSet64 -gt 4GB) {
                Problem "VM MEMORY HIGH: vmwp.exe using $([math]::Round($v.WorkingSet64/1GB))GB"
            }
        }
    }
} catch {}

# ============================================================================
# 32. WSL (WINDOWS SUBSYSTEM FOR LINUX) ISSUES
# ============================================================================
Section "WSL ISSUES"
Write-Host "Checking WSL..." -ForegroundColor Cyan
try {
    # WSL service
    $wslSvc = Get-Service 'WslService' -EA 0
    if ($wslSvc -and $wslSvc.Status -ne 'Running') {
        Problem "WSL SERVICE NOT RUNNING: Windows Subsystem for Linux service is stopped"
    }

    # LxssManager errors
    Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$last7d} -EA 0 -MaxEvents 30 | Where-Object {
        $_.Message -match 'WSL|LxssManager|Linux'
    } | ForEach-Object {
        if ($_.Level -le 2) {
            Problem "WSL ERROR: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    }

    # Check WSL disk usage
    $wslPath = "$env:LOCALAPPDATA\Packages"
    $wslDistros = Get-ChildItem $wslPath -Filter "*Linux*" -EA 0
    foreach ($distro in $wslDistros) {
        $size = (Get-ChildItem $distro.FullName -Recurse -EA 0 | Measure-Object Length -Sum).Sum
        if ($size -gt 30GB) {
            Problem "WSL DISK USAGE HIGH: $($distro.Name) using $([math]::Round($size/1GB))GB"
        }
    }
} catch {}

# ============================================================================
# 33. DOWNLOAD/BANDWIDTH ISSUES
# ============================================================================
Section "DOWNLOAD & BANDWIDTH"
Write-Host "Checking download/bandwidth..." -ForegroundColor Cyan
try {
    # BITS transfer errors
    Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Bits-Client/Operational'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 15 | ForEach-Object {
        Problem "BITS TRANSFER: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # Delivery Optimization errors
    Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-DeliveryOptimization/Operational'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 15 | ForEach-Object {
        Problem "DELIVERY OPTIMIZATION: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # Check for bandwidth throttling policies
    $throttlePolicy = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched" -EA 0
    if ($throttlePolicy.NonBestEffortLimit -and $throttlePolicy.NonBestEffortLimit -gt 0) {
        Problem "BANDWIDTH THROTTLED: QoS limiting non-best-effort traffic to $($throttlePolicy.NonBestEffortLimit)%"
    }

    # WinHTTP proxy issues
    $proxy = netsh winhttp show proxy 2>$null
    if ($proxy -match 'Proxy Server.*:') {
        Problem "PROXY CONFIGURED: System proxy may slow downloads - $proxy"
    }
} catch {}

# ============================================================================
# 34. FREEZE/HANG DETECTION
# ============================================================================
Section "FREEZE & HANG DETECTION"
Write-Host "Checking for freeze/hang events..." -ForegroundColor Cyan
try {
    # System freeze events
    Get-WinEvent -FilterHashtable @{LogName='System'; Id=6008; StartTime=$last7d} -EA 0 -MaxEvents 10 | ForEach-Object {
        CriticalProblem "UNEXPECTED SHUTDOWN (FREEZE?): $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # Application hang events
    Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1002; StartTime=$last24h} -EA 0 -MaxEvents 15 | ForEach-Object {
        Problem "APPLICATION HANG: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # Kernel watchdog events
    Get-WinEvent -FilterHashtable @{LogName='System'; Id=133,134; StartTime=$last7d} -EA 0 -MaxEvents 10 | ForEach-Object {
        CriticalProblem "KERNEL WATCHDOG: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # Check for stuck/hung processes (threads waiting >30s)
    $hungApps = Get-Process -EA 0 | Where-Object { $_.Responding -eq $false }
    foreach ($hung in $hungApps) {
        CriticalProblem "HUNG PROCESS: $($hung.ProcessName) (PID: $($hung.Id)) is not responding"
    }

    # DPC/ISR latency issues
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-DPC-Watchdog'; StartTime=$last7d} -EA 0 -MaxEvents 5 | ForEach-Object {
        CriticalProblem "DPC WATCHDOG: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }
} catch {}

# ============================================================================
# 35. MEMORY LEAK DETECTION
# ============================================================================
Section "MEMORY LEAK DETECTION"
Write-Host "Checking for memory leaks..." -ForegroundColor Cyan
try {
    # Pool memory leaks
    Get-WinEvent -FilterHashtable @{LogName='System'; Id=2019,2020; StartTime=$last7d} -EA 0 -MaxEvents 10 | ForEach-Object {
        CriticalProblem "POOL MEMORY LEAK: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # Processes with high commit charge (potential leaks)
    $memLeakCandidates = Get-Process -EA 0 | Where-Object { $_.PrivateMemorySize64 -gt 2GB } |
        Select-Object -First 5 ProcessName, @{N='PrivateMB';E={[math]::Round($_.PrivateMemorySize64/1MB)}}
    foreach ($proc in $memLeakCandidates) {
        Problem "POTENTIAL MEMORY LEAK: $($proc.ProcessName) using $($proc.PrivateMB)MB private memory"
    }

    # Handle leaks
    $handleLeaks = Get-Process -EA 0 | Where-Object { $_.HandleCount -gt 15000 } |
        Select-Object -First 5 ProcessName, HandleCount
    foreach ($h in $handleLeaks) {
        Problem "HANDLE LEAK CANDIDATE: $($h.ProcessName) has $($h.HandleCount) handles"
    }

    # Commit charge vs physical memory
    $mem = Get-CimInstance Win32_OperatingSystem -EA 0
    if ($mem) {
        $commitRatio = $mem.TotalVirtualMemorySize / $mem.TotalVisibleMemorySize
        if ($commitRatio -gt 2) {
            Problem "HIGH COMMIT RATIO: System commit is ${commitRatio}x physical RAM - possible memory leaks"
        }
    }
} catch {}

# ============================================================================
# 36. HARDWARE ERRORS (RAM, CPU, Motherboard)
# ============================================================================
Section "HARDWARE ERRORS"
Write-Host "Checking hardware health..." -ForegroundColor Cyan
try {
    # WHEA hardware errors
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=$last30d} -EA 0 -MaxEvents 20 | ForEach-Object {
        CriticalProblem "HARDWARE ERROR (WHEA): $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # Machine check exceptions
    Get-WinEvent -FilterHashtable @{LogName='System'; Id=1,18,19; StartTime=$last30d} -EA 0 -MaxEvents 10 | Where-Object {
        $_.ProviderName -match 'WHEA|HAL'
    } | ForEach-Object {
        CriticalProblem "MACHINE CHECK: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # ECC memory errors
    Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$last30d} -EA 0 -MaxEvents 50 | Where-Object {
        $_.Message -match 'memory.*error|ECC|correctable|uncorrectable|DIMM'
    } | ForEach-Object {
        CriticalProblem "MEMORY ERROR: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # PCI/PCIe errors
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-PCI'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 10 | ForEach-Object {
        Problem "PCI ERROR: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }
} catch {}

# ============================================================================
# 37. PAGEFILE/VIRTUAL MEMORY ISSUES
# ============================================================================
Section "PAGEFILE & VIRTUAL MEMORY"
Write-Host "Checking pagefile..." -ForegroundColor Cyan
try {
    # Pagefile fragmentation/errors
    Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$last7d} -EA 0 -MaxEvents 30 | Where-Object {
        $_.Message -match 'pagefile|paging|swap|virtual memory'
    } | ForEach-Object {
        if ($_.Level -le 2) {
            Problem "PAGEFILE: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    }

    # Check pagefile configuration
    $pagefiles = Get-CimInstance Win32_PageFileUsage -EA 0
    foreach ($pf in $pagefiles) {
        $usedPercent = [math]::Round(($pf.CurrentUsage / $pf.AllocatedBaseSize) * 100, 1)
        if ($usedPercent -gt 80) {
            CriticalProblem "PAGEFILE EXHAUSTION: $($pf.Name) is $usedPercent% full - may cause freezes"
        }
    }

    # Virtual memory commitment
    $os = Get-CimInstance Win32_OperatingSystem -EA 0
    if ($os) {
        $commitPercent = [math]::Round(($os.TotalVirtualMemorySize - $os.FreeVirtualMemory) / $os.TotalVirtualMemorySize * 100, 1)
        if ($commitPercent -gt 90) {
            CriticalProblem "VIRTUAL MEMORY CRITICAL: $commitPercent% committed - system may crash"
        } elseif ($commitPercent -gt 75) {
            Problem "VIRTUAL MEMORY HIGH: $commitPercent% committed"
        }
    }
} catch {}

# ============================================================================
# 38. ANTIVIRUS/DEFENDER PERFORMANCE IMPACT
# ============================================================================
Section "ANTIVIRUS PERFORMANCE IMPACT"
Write-Host "Checking antivirus activity..." -ForegroundColor Cyan
try {
    # Windows Defender scan activity (recent)
    Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Windows Defender/Operational'; Id=1001; StartTime=$lastHour} -EA 0 -MaxEvents 5 | ForEach-Object {
        Problem "DEFENDER SCAN RUNNING: Active scan may impact performance"
    }

    # Defender detections that might cause slowdown
    Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Windows Defender/Operational'; Id=1116,1117; StartTime=$last24h} -EA 0 -MaxEvents 10 | ForEach-Object {
        Problem "DEFENDER DETECTION: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # Real-time protection high resource usage
    $amProc = Get-Process MsMpEng -EA 0
    if ($amProc) {
        if ($amProc.CPU -gt 60 -or $amProc.WorkingSet64 -gt 500MB) {
            Problem "DEFENDER HIGH USAGE: MsMpEng using CPU: $([math]::Round($amProc.CPU))s, RAM: $([math]::Round($amProc.WorkingSet64/1MB))MB"
        }
    }

    # Third-party AV issues
    Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$last24h} -EA 0 -MaxEvents 30 | Where-Object {
        $_.Message -match 'Norton|McAfee|Kaspersky|Avast|AVG|Bitdefender|ESET|antivirus|anti-virus'
    } | ForEach-Object {
        if ($_.Level -le 2) {
            Problem "ANTIVIRUS: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    }
} catch {}

# ============================================================================
# 39. WINDOWS UPDATE IMPACT
# ============================================================================
Section "WINDOWS UPDATE ACTIVITY"
Write-Host "Checking Windows Update..." -ForegroundColor Cyan
try {
    # Active Windows Update downloads/installs
    Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-WindowsUpdateClient/Operational'; StartTime=$lastHour} -EA 0 -MaxEvents 20 | ForEach-Object {
        if ($_.Message -match 'download|install|progress') {
            Problem "WINDOWS UPDATE ACTIVE: $($_.Message.Substring(0,[Math]::Min(150,$_.Message.Length)))"
        }
    }

    # Pending reboot from updates
    $pendingReboot = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    if ($pendingReboot) {
        Problem "WINDOWS UPDATE PENDING REBOOT: System performance may be impacted until reboot"
    }

    # TiWorker.exe (Windows Modules Installer Worker) resource usage
    $tiWorker = Get-Process TiWorker -EA 0
    if ($tiWorker) {
        foreach ($t in $tiWorker) {
            if ($t.CPU -gt 30 -or $t.WorkingSet64 -gt 200MB) {
                Problem "WINDOWS UPDATE WORKER: TiWorker.exe using CPU: $([math]::Round($t.CPU))s, RAM: $([math]::Round($t.WorkingSet64/1MB))MB"
            }
        }
    }

    # WuauServ (Windows Update Service) errors
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Service Control Manager'; StartTime=$last24h} -EA 0 -MaxEvents 20 | Where-Object {
        $_.Message -match 'wuauserv|Windows Update'
    } | ForEach-Object {
        if ($_.Level -le 2) {
            Problem "WINDOWS UPDATE SERVICE: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    }
} catch {}

# ============================================================================
# 40. RUNTIME/FRAMEWORK ISSUES
# ============================================================================
Section "RUNTIME & FRAMEWORK ISSUES"
Write-Host "Checking runtimes..." -ForegroundColor Cyan
try {
    # .NET runtime errors
    Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='.NET Runtime'; Level=1,2; StartTime=$last7d} -EA 0 -MaxEvents 15 | ForEach-Object {
        Problem ".NET ERROR: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # CLR errors
    Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Application Error'; StartTime=$last7d} -EA 0 -MaxEvents 20 | Where-Object {
        $_.Message -match 'clr\.dll|mscorwks|coreclr'
    } | ForEach-Object {
        Problem "CLR ERROR: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
    }

    # VC++ runtime errors
    Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$last7d} -EA 0 -MaxEvents 30 | Where-Object {
        $_.Message -match 'vcruntime|msvcp|msvcr|Microsoft Visual C\+\+'
    } | ForEach-Object {
        if ($_.Level -le 2) {
            Problem "VC++ RUNTIME: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    }

    # Windows Runtime errors
    Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$last7d} -EA 0 -MaxEvents 20 | Where-Object {
        $_.Message -match 'WinRT|Windows Runtime|combase'
    } | ForEach-Object {
        if ($_.Level -le 2) {
            Problem "WINRT ERROR: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))"
        }
    }
} catch {}

# ============================================================================
# 41. PROXY/FIREWALL INTERFERENCE
# ============================================================================
Section "PROXY & FIREWALL"
Write-Host "Checking proxy/firewall..." -ForegroundColor Cyan
try {
    # Windows Firewall blocks
    Get-WinEvent -FilterHashtable @{LogName='Security'; Id=5157; StartTime=$last24h} -EA 0 -MaxEvents 30 | ForEach-Object {
        $msg = $_.Message
        if ($msg -match 'Application Name:\s*(.+)' -and $msg -notmatch 'svchost|System') {
            Problem "FIREWALL BLOCKED: $($Matches[1].Substring(0,[Math]::Min(100,$Matches[1].Length)))"
        }
    }

    # Check for proxy configuration issues
    $ieProxy = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -EA 0
    if ($ieProxy.ProxyEnable -eq 1) {
        Problem "PROXY ENABLED: Internet traffic routed through $($ieProxy.ProxyServer) - may slow connections"
    }

    # WinHTTP proxy - skip reporting, user may have intentionally configured
    # $winhttpProxy = netsh winhttp show proxy 2>$null
    # if ($winhttpProxy -match 'Proxy Server') {
    #     Problem "WINHTTP PROXY: System-level proxy configured - may affect downloads"
    # }

    # Firewall service issues
    $fwSvc = Get-Service 'mpssvc' -EA 0
    if ($fwSvc -and $fwSvc.Status -ne 'Running') {
        CriticalProblem "WINDOWS FIREWALL SERVICE NOT RUNNING: Security and connectivity may be affected"
    }
} catch {}

# ============================================================================

# ============================================================================
# COMPREHENSIVE PERFORMANCE DETECTION v5.0 - ULTIMATE EDITION
# Detects EVERYTHING that affects: Network, Gaming, Docker, Multitasking
# ============================================================================

# ============================================================================
# NETWORK PERFORMANCE BOTTLENECKS - DEEP ANALYSIS
# ============================================================================
Section "NETWORK PERFORMANCE & BANDWIDTH ISSUES"
Write-Host "Checking network performance bottlenecks..." -ForegroundColor Magenta

try {
    # DNS Resolution Performance - REMOVED (router/ISP issue, not Windows-fixable)
    # Slow DNS is caused by your router or ISP, not Windows settings

    # DNS Cache Issues
    $dnsCacheSize = (Get-DnsClientCache -EA 0 | Measure-Object).Count
    if ($dnsCacheSize -gt 5000) {
        Problem "DNS CACHE BLOAT: $dnsCacheSize entries - may cause lookup delays"
    }

    # Failed DNS resolutions in cache
    $failedDNS = Get-DnsClientCache -EA 0 | Where-Object { $_.Status -ne 0 } | Measure-Object
    if ($failedDNS.Count -gt 10) {
        Problem "FAILED DNS ENTRIES: $($failedDNS.Count) failed lookups cached - slowing resolution"
    }

    # Network adapter performance
    $adapters = Get-NetAdapter -EA 0 | Where-Object { $_.Status -eq 'Up' -and $_.MediaType -notmatch 'Bluetooth' }
    foreach ($adapter in $adapters) {
        # Check for errors
        $stats = Get-NetAdapterStatistics -Name $adapter.Name -EA 0
        if ($stats) {
            $errorRate = ($stats.ReceivedUnicastPackets + $stats.SentUnicastPackets)
            if ($errorRate -gt 0) {
                $pctErrors = (($stats.ReceivedPacketErrors + $stats.OutboundPacketErrors) / $errorRate) * 100
                if ($pctErrors -gt 1) {
                    CriticalProblem "NETWORK ERRORS: $($adapter.Name) has $([math]::Round($pctErrors, 2))% packet errors"
                }
            }
        }

        # Check link speed vs capability
        if ($adapter.LinkSpeed -and $adapter.LinkSpeed -ne "0 bps") {
            $linkSpeedGbps = [regex]::Match($adapter.LinkSpeed, '(\d+)\s*Gbps').Groups[1].Value
            $linkSpeedMbps = [regex]::Match($adapter.LinkSpeed, '(\d+)\s*Mbps').Groups[1].Value

            if ($linkSpeedMbps -and [int]$linkSpeedMbps -lt 100) {
                Problem "SLOW LINK SPEED: $($adapter.Name) running at $($adapter.LinkSpeed) - should be 1Gbps+"
            }
        }

        # Check for negotiation issues
        $advProp = Get-NetAdapterAdvancedProperty -Name $adapter.Name -EA 0
        $speedDuplex = $advProp | Where-Object { $_.RegistryKeyword -eq 'SpeedDuplex' }
        if ($speedDuplex -and $speedDuplex.DisplayValue -notmatch 'Auto') {
            Problem "NETWORK CONFIG: $($adapter.Name) speed/duplex is MANUAL - may cause slowdowns"
        }
    }

    # QoS Policy Issues (Windows Quality of Service can throttle)
    $qosPolicies = Get-NetQosPolicy -EA 0
    foreach ($policy in $qosPolicies) {
        if ($policy.ThrottleRateActionBitsPerSecond -gt 0) {
            $mbps = [math]::Round($policy.ThrottleRateActionBitsPerSecond / 1MB, 2)
            Problem "QoS THROTTLING: Policy '$($policy.Name)' limiting to $mbps Mbps"
        }
    }

    # Windows Update Delivery Optimization bandwidth limit
    $doConfig = Get-DeliveryOptimizationPerfSnap -EA 0
    if ($doConfig) {
        $downloadMode = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Name "DODownloadMode" -EA 0).DODownloadMode
        if ($downloadMode -eq 3) {
            Problem "DELIVERY OPTIMIZATION: May be consuming bandwidth in background"
        }
    }

    # TCP/IP Stack Issues
    $tcpSettings = Get-NetTCPSetting -EA 0
    foreach ($setting in $tcpSettings) {
        if ($setting.AutoTuningLevelLocal -eq 'Disabled') {
            CriticalProblem "TCP WINDOW AUTO-TUNING DISABLED: Severely limits download speeds"
        }
        if ($setting.ScalingHeuristics -eq 'Disabled') {
            Problem "TCP SCALING HEURISTICS DISABLED: May reduce throughput"
        }
    }

    # Network Throttling Index (Windows can throttle multimedia streaming)
    $throttle = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -EA 0
    if ($throttle.NetworkThrottlingIndex -ne 4294967295 -and $throttle.NetworkThrottlingIndex -ne $null) {
        Problem "NETWORK THROTTLING: Index is $($throttle.NetworkThrottlingIndex) (should be 0xFFFFFFFF for gaming/streaming)"
    }

    # Large Send Offload issues
    $adapters | ForEach-Object {
        $lso = Get-NetAdapterLso -Name $_.Name -EA 0
        if ($lso -and -not $lso.V2IPv4Enabled -and -not $lso.V2IPv6Enabled) {
            Problem "LSO DISABLED: $($_.Name) Large Send Offload off - may reduce throughput"
        }
    }

    # RSS (Receive Side Scaling) for multi-core performance
    $adapters | ForEach-Object {
        $rss = Get-NetAdapterRss -Name $_.Name -EA 0
        if ($rss -and -not $rss.Enabled) {
            Problem "RSS DISABLED: $($_.Name) not using multi-core for network - hurts performance"
        }
    }

    # Network Location Awareness Service (affects connectivity detection)
    $nlaSvc = Get-Service -Name "NlaSvc" -EA 0
    if ($nlaSvc -and $nlaSvc.Status -ne 'Running') {
        CriticalProblem "NETWORK LOCATION AWARENESS: Service stopped - network detection broken"
    }

    # Windows Firewall rules that block legitimate traffic
    $blockRules = Get-NetFirewallRule -EA 0 | Where-Object { $_.Enabled -eq $true -and $_.Action -eq 'Block' -and $_.Direction -eq 'Outbound' }
    if ($blockRules.Count -gt 50) {
        Problem "FIREWALL: $($blockRules.Count) outbound block rules - may interfere with apps"
    }

    # Proxy Settings that slow down connections
    $proxySettings = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -EA 0
    if ($proxySettings.ProxyEnable -eq 1) {
        $proxyServer = $proxySettings.ProxyServer
        Problem "PROXY ENABLED: All traffic routing through $proxyServer - adds latency"
    }

    # SMB signing overhead (affects file sharing performance)
    $smbClient = Get-SmbClientConfiguration -EA 0
    if ($smbClient.RequireSecuritySignature) {
        Problem "SMB SIGNING REQUIRED: Adds CPU overhead to file transfers - impacts NAS/network drives"
    }

    # Router/Gateway connectivity issues
    $defaultGateway = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -EA 0 | Select-Object -First 1
    if ($defaultGateway) {
        $pingTest = Test-Connection -ComputerName $defaultGateway.NextHop -Count 2 -EA 0
        if (-not $pingTest) {
            CriticalProblem "GATEWAY UNREACHABLE: Default gateway $($defaultGateway.NextHop) not responding"
        } else {
            $avgPing = ($pingTest | Measure-Object -Property ResponseTime -Average).Average
            if ($avgPing -gt 10) {
                Problem "GATEWAY LATENCY: $([math]::Round($avgPing))ms to router - should be <5ms (cable/config issue?)"
            }
        }
    }

    # MTU Size issues (can cause fragmentation = slow transfers)
    $adapters | ForEach-Object {
        $netipInterface = Get-NetIPInterface -InterfaceAlias $_.Name -AddressFamily IPv4 -EA 0
        if ($netipInterface -and $netipInterface.NlMtu -lt 1500) {
            Problem "LOW MTU: $($_.Name) MTU is $($netipInterface.NlMtu) - may cause fragmentation slowdowns"
        }
    }

    # IPv6 transition technologies causing delays
    $tunnelAdapters = Get-NetAdapter -EA 0 | Where-Object { $_.InterfaceDescription -match 'Teredo|6to4|ISATAP' -and $_.Status -eq 'Up' }
    if ($tunnelAdapters) {
        Problem "IPv6 TUNNELING ACTIVE: $($tunnelAdapters.Count) tunnel adapter(s) - can cause connection delays"
    }

} catch {
    Write-Host "  Error checking network performance: $_" -ForegroundColor DarkRed
}

# ============================================================================
# GAMING & MULTITASKING PERFORMANCE ISSUES
# ============================================================================
Section "GAMING & MULTITASKING PERFORMANCE"
Write-Host "Checking gaming/multitasking performance issues..." -ForegroundColor Magenta

try {
    # CPU Thermal Throttling - REMOVED (hardware cooling issue, not Windows-fixable)
    # High CPU temps require physical cooling solutions (fan cleaning, thermal paste, airflow)

    # Power Throttling (Windows 11 feature that limits background apps)
    $powerThrottling = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" -EA 0
    if ($powerThrottling -and $powerThrottling.PowerThrottlingOff -ne 1) {
        Problem "POWER THROTTLING ENABLED: Background apps throttled - may affect game performance"
    }

    # Core Parking (CPUs parked = less performance)
    $coreParking = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\0cc5b647-c1df-4637-891a-dec35c318583" -Name "ValueMax" -EA 0
    if ($coreParking -and $coreParking.ValueMax -lt 100) {
        Problem "CORE PARKING ACTIVE: CPUs being parked - reduces multitasking performance"
    }

    # GPU Performance State
    try {
        $gpuDrivers = Get-WmiObject Win32_VideoController -EA 0
        foreach ($gpu in $gpuDrivers) {
            # Check driver age
            if ($gpu.DriverDate) {
                $driverDate = [Management.ManagementDateTimeConverter]::ToDateTime($gpu.DriverDate)
                $driverAge = (Get-Date) - $driverDate
                if ($driverAge.TotalDays -gt 180) {
                    Problem "OLD GPU DRIVER: $($gpu.Name) driver is $([math]::Round($driverAge.TotalDays)) days old - may have performance issues"
                }
            }

            # Check if GPU is in low power mode
            $gpuConfig = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000" -EA 0
            if ($gpuConfig -and $gpuConfig.PP_ThermalControllerInitialized -eq 0) {
                Problem "GPU POWER STATE: May be in low-performance mode"
            }
        }
    } catch {}

    # TDR (Timeout Detection and Recovery) - GPU freezes/resets
    try {
        Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Display'; StartTime=$last7d} -EA 0 -MaxEvents 100 | Where-Object {
            $_.Id -eq 4101 -or $_.Message -match 'TDR|timeout|GPU.*reset|display driver.*stopped'
        } | ForEach-Object {
            CriticalProblem "GPU TDR EVENT: Display driver reset at $($_.TimeCreated) - causes frame drops/freezes"
        }
    } catch {}

    # DPC Latency (high DPC = stuttering/lag)
    try {
        $dpcEvents = Get-WinEvent -FilterHashtable @{LogName='System'; Id=26; StartTime=$last7d} -EA 0 -MaxEvents 50
        if ($dpcEvents.Count -gt 5) {
            CriticalProblem "HIGH DPC LATENCY: $($dpcEvents.Count) events - causes audio crackling, frame drops, input lag"
        }
    } catch {}

    # High CPU usage processes - REMOVED (runtime processes, not errors)
    # Processes using CPU are user-launched apps, not Windows issues to fix

    # Memory Pressure (low available RAM)
    $mem = Get-CimInstance Win32_OperatingSystem -EA 0
    if ($mem) {
        $memAvailMB = [math]::Round($mem.FreePhysicalMemory / 1024)
        $memTotalMB = [math]::Round($mem.TotalVisibleMemorySize / 1024)
        $memUsedPct = (($memTotalMB - $memAvailMB) / $memTotalMB) * 100

        if ($memUsedPct -gt 95) {
            CriticalProblem "CRITICAL MEMORY PRESSURE: $([math]::Round($memUsedPct))% used ($memAvailMB MB free) - swapping to disk"
        } elseif ($memUsedPct -gt 85) {
            Problem "HIGH MEMORY USAGE: $([math]::Round($memUsedPct))% used ($memAvailMB MB free) - may cause slowdowns"
        }
    }

    # Superfetch/SysMain causing disk thrashing
    $sysMain = Get-Service -Name "SysMain" -EA 0
    if ($sysMain -and $sysMain.Status -eq 'Running') {
        # Check if causing high disk usage
        try {
            $diskEvents = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Disk'; Level=2,3; StartTime=$lastHour} -EA 0 -MaxEvents 20
            if ($diskEvents.Count -gt 10) {
                Problem "SUPERFETCH (SysMain): May be causing disk thrashing - impacts game loading"
            }
        } catch {}
    }

    # Game Mode Issues
    $gameMode = Get-ItemProperty "HKCU:\Software\Microsoft\GameBar" -Name "AllowAutoGameMode" -EA 0
    if ($gameMode -and $gameMode.AllowAutoGameMode -eq 0) {
        Problem "GAME MODE DISABLED: Not optimizing for gaming performance"
    }

    # Game DVR/Recording overhead
    $gameDVR = Get-ItemProperty "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -EA 0
    if ($gameDVR -and $gameDVR.GameDVR_Enabled -eq 1) {
        Problem "GAME DVR ENABLED: Background recording adds GPU/CPU overhead"
    }

    # Windows Search Indexing during gameplay
    $searchSvc = Get-Service -Name "WSearch" -EA 0
    if ($searchSvc -and $searchSvc.Status -eq 'Running') {
        try {
            $searchProc = Get-Process -Name "SearchIndexer" -EA 0
            if ($searchProc -and $searchProc.CPU -gt 5) {
                Problem "SEARCH INDEXING ACTIVE: Using CPU/Disk during potential gameplay"
            }
        } catch {}
    }

    # Full-screen optimizations (can cause input lag)
    $gameBarFSO = Get-ItemProperty "HKCU:\System\GameConfigStore" -Name "GameDVR_FSEBehaviorMode" -EA 0
    if ($gameBarFSO -and $gameBarFSO.GameDVR_FSEBehaviorMode -ne 2) {
        Problem "FULLSCREEN OPTIMIZATIONS: Enabled - may cause input lag in some games"
    }

    # High-precision timer resolution (affects frame pacing)
    $timerResolution = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" -Name "GlobalTimerResolutionRequests" -EA 0
    if (-not $timerResolution) {
        Problem "TIMER RESOLUTION: Not optimized - may cause frame pacing issues"
    }

    # HPET (High Precision Event Timer) config
    try {
        $hpet = bcdedit /enum | Select-String "useplatformclock"
        if ($hpet -match "Yes") {
            Problem "HPET ENABLED: Can cause performance issues in some games/applications"
        }
    } catch {}

} catch {
    Write-Host "  Error checking gaming/multitasking performance: $_" -ForegroundColor DarkRed
}

# ============================================================================
# DOCKER & CONTAINER PERFORMANCE ISSUES
# ============================================================================
Section "DOCKER & CONTAINER PERFORMANCE"
Write-Host "Checking Docker & container performance..." -ForegroundColor Magenta

try {
    # HNS (Host Network Service) errors - affects Docker networking
    try {
        Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Hyper-V-VmSwitch','Hyper-V-Shared-VHDX','VMSMP'; StartTime=$last7d} -EA 0 -MaxEvents 200 | Where-Object {
            $_.Message -match 'HNS|IpNatHlpStopSharing|0x80070032|failed to delete|winnat'
        } | ForEach-Object {
            CriticalProblem "HNS ERROR: $($_.Message.Substring(0,[Math]::Min(250,$_.Message.Length)))"
        }
    } catch {}

    # Docker Service State
    $dockerSvc = Get-Service -Name "com.docker.service" -EA 0
    if ($dockerSvc) {
        if ($dockerSvc.Status -ne 'Running') {
            Problem "DOCKER SERVICE: Not running - Docker won't work"
        }
    }

    # WSL2 Backend Issues (Docker Desktop uses WSL2)
    $wsl2 = Get-Service -Name "LxssManager" -EA 0
    if ($wsl2) {
        if ($wsl2.Status -ne 'Running') {
            CriticalProblem "WSL2: LxssManager service stopped - Docker Desktop won't function"
        }
    }

    # Hyper-V Virtual Switch Issues
    try {
        $vSwitches = Get-VMSwitch -EA 0
        foreach ($vSwitch in $vSwitches) {
            if ($vSwitch.SwitchType -eq 'External' -and -not $vSwitch.NetAdapterInterfaceDescription) {
                Problem "HYPER-V SWITCH: $($vSwitch.Name) not bound to network adapter - Docker networking broken"
            }
        }
    } catch {}

    # NAT Network check - REMOVED (Docker not running is normal, not an error)
    # NAT networks are created when Docker starts, absence is not a problem

    # Check for conflicting NAT ranges (keep - actual problem when duplicates exist)
    $natNetworks = Get-NetNat -EA 0
    $natRanges = @{}
    $natNetworks | ForEach-Object {
        if ($natRanges.ContainsKey($_.InternalIPInterfaceAddressPrefix)) {
            Problem "DUPLICATE NAT RANGE: $($_.InternalIPInterfaceAddressPrefix) used by multiple NAT instances"
        }
        $natRanges[$_.InternalIPInterfaceAddressPrefix] = $true
    }

    # Docker Storage Driver Issues
    try {
        if (Test-Path "C:\ProgramData\Docker\config\daemon.json") {
            $dockerConfig = Get-Content "C:\ProgramData\Docker\config\daemon.json" -Raw -EA 0 | ConvertFrom-Json -EA 0
            if ($dockerConfig.'storage-driver' -eq 'aufs') {
                Problem "DOCKER STORAGE DRIVER: Using AUFS - very slow on Windows, use overlay2"
            }
        }
    } catch {}

    # WSL memory/CPU limits - REMOVED (optional user preference, not an error)
    # .wslconfig limits are optional - Docker works fine without them

    # VirtualDisk Service (needed for Docker volumes)
    $vdiskSvc = Get-Service -Name "VirtualDisk" -EA 0
    if ($vdiskSvc -and $vdiskSvc.Status -ne 'Running') {
        CriticalProblem "VIRTUAL DISK SERVICE: Stopped - Docker volumes won't work"
    }

    # Hyper-V Components
    try {
        $hvFeature = Get-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V" -EA 0
        if ($hvFeature -and $hvFeature.State -ne 'Enabled') {
            Problem "HYPER-V: Not enabled - Docker Desktop requires Hyper-V"
        }
    } catch {}

    # Containers Feature
    try {
        $containerFeature = Get-WindowsOptionalFeature -Online -FeatureName "Containers" -EA 0
        if ($containerFeature -and $containerFeature.State -ne 'Enabled') {
            Problem "CONTAINERS FEATURE: Not enabled - native containers won't work"
        }
    } catch {}

    # HNS Data File Corruption
    if (Test-Path "C:\ProgramData\Microsoft\Windows\HNS\HNS.data") {
        $hnsData = Get-Item "C:\ProgramData\Microsoft\Windows\HNS\HNS.data" -EA 0
        if ($hnsData.Length -eq 0) {
            CriticalProblem "HNS DATA: Corrupted (zero size) - Docker networking completely broken"
        }
        # Check modification time - if very old, may be stale
        $hnsAge = (Get-Date) - $hnsData.LastWriteTime
        if ($hnsAge.TotalDays -gt 30) {
            Problem "HNS DATA: Not updated in $([math]::Round($hnsAge.TotalDays)) days - may be stale"
        }
    }

    # Docker registry mirrors - REMOVED (optional optimization, not an error)
    # Registry mirrors are optional - image pulls work without them

    # ==== ADVANCED DOCKER & CONTAINER CHECKS ====

    # Docker image issues
    try {
        if (Get-Command docker -EA 0) {
            $images = & docker images --format "{{.Repository}}:{{.Tag}}" --filter "dangling=true" 2>$null
            if ($images -and @($images).Count -gt 10) {
                Problem "DOCKER DANGLING IMAGES: $(@($images).Count) dangling images - wasting disk space"
            }

            # Check for broken images
            $allImages = & docker images --format "{{.Repository}}" 2>$null | Where-Object {$_}
            if ($allImages) {
                foreach ($img in @($allImages)) {
                    try {
                        & docker image inspect $img >$null 2>&1
                    } catch {
                        Problem "DOCKER BROKEN IMAGE: $img - corrupted or inaccessible"
                    }
                }
            }
        }
    } catch {}

    # Docker volume issues
    try {
        if (Get-Command docker -EA 0) {
            $orphanVols = & docker volume ls --filter "dangling=true" --format "{{.Name}}" 2>$null
            if ($orphanVols) {
                Problem "DOCKER ORPHANED VOLUMES: $(@($orphanVols).Count) orphaned volumes - wasting disk space and resources"
            }

            # Check volume permissions
            $volumes = & docker volume ls --format "{{.Name}}" 2>$null | Where-Object {$_}
            if ($volumes) {
                foreach ($vol in @($volumes)) {
                    try {
                        $volPath = & docker volume inspect -f '{{.Mountpoint}}' $vol 2>$null
                        if ($volPath -and !(Test-Path $volPath -EA 0)) {
                            Problem "DOCKER VOLUME MISSING: Volume $vol missing path - containers can't access data"
                        }
                    } catch {}
                }
            }
        }
    } catch {}

    # Docker network issues
    try {
        if (Get-Command docker -EA 0) {
            $networks = & docker network ls --format "{{.Name}}" 2>$null | Where-Object {$_}
            $networks | ForEach-Object {
                try {
                    $netInspect = & docker network inspect $_ 2>$null | ConvertFrom-Json -EA 0
                    if ($netInspect -and $netInspect.Containers) {
                        if (@($netInspect.Containers).Count -gt 100) {
                            Problem "DOCKER NETWORK OVERLOAD: Network $_ has $(@($netInspect.Containers).Count) containers - may cause routing delays"
                        }
                    }
                } catch {}
            }
        }
    } catch {}

    # Docker container health
    try {
        if (Get-Command docker -EA 0) {
            $unhealthy = & docker ps --filter "health=unhealthy" --format "{{.Names}}" 2>$null
            if ($unhealthy) {
                Problem "DOCKER UNHEALTHY CONTAINERS: $(@($unhealthy).Count) containers failed health checks"
            }

            $restarting = & docker ps --filter "status=restarting" --format "{{.Names}}" 2>$null
            if ($restarting) {
                Problem "DOCKER RESTARTING CONTAINERS: $(@($restarting).Count) containers in restart loop - check logs"
            }
        }
    } catch {}

    # Docker daemon resource usage
    try {
        $dockerProc = Get-Process -Name "Docker Desktop","com.docker.service" -EA 0
        if ($dockerProc) {
            foreach ($proc in @($dockerProc)) {
                $cpuPct = [math]::Round($proc.CPU, 1)
                $ramMB = [math]::Round($proc.WorkingSet64 / 1MB)

                if ($cpuPct -gt 50) {
                    Problem "DOCKER HIGH CPU: Docker process using $cpuPct% CPU - heavy container workload"
                }
                if ($ramMB -gt 2048) {
                    Problem "DOCKER HIGH MEMORY: Docker daemon using $ramMB MB RAM - reduce container count or image bloat"
                }
            }
        }
    } catch {}

    # Docker log file issues
    try {
        $dockerLogPath = "$env:ProgramData\Docker\containers"
        if (Test-Path $dockerLogPath) {
            $logSize = (Get-ChildItem $dockerLogPath -Recurse -Filter "*json.log" -EA 0 | Measure-Object -Property Length -Sum).Sum
            if ($logSize -gt 5GB) {
                Problem "DOCKER LOG FILES: Taking $([math]::Round($logSize/1GB))GB - truncate old logs with 'docker container prune'"
            }
        }
    } catch {}

    # WSL2 integration issues (Docker Desktop backend)
    try {
        $wsl2 = Get-Service -Name "LxssManager" -EA 0
        if ($wsl2 -and $wsl2.Status -eq 'Running') {
            $wslProc = Get-Process -Name "wsl","vmmem" -EA 0
            if ($wslProc) {
                foreach ($proc in @($wslProc)) {
                    $ramMB = [math]::Round($proc.WorkingSet64 / 1MB)
                    if ($ramMB -gt 4096) {
                        Problem "WSL2 HIGH MEMORY: WSL2/Docker Backend using $ramMB MB - may need .wslconfig memory limit"
                    }
                }
            }
        }
    } catch {}

    # Docker image layer issues
    try {
        if (Get-Command docker -EA 0) {
            $images = & docker images --format "{{.Repository}}:{{.Tag}}" 2>$null | Where-Object {$_}
            $images | ForEach-Object {
                try {
                    $inspect = & docker image inspect $_ 2>$null | ConvertFrom-Json -EA 0
                    if ($inspect -and $inspect.RootFS.Layers) {
                        $layerCount = @($inspect.RootFS.Layers).Count
                        if ($layerCount -gt 50) {
                            Problem "DOCKER EXCESSIVE LAYERS: Image $_ has $layerCount layers - bloated image, optimize Dockerfile"
                        }
                    }
                } catch {}
            }
        }
    } catch {}

} catch {
    Write-Host "  Error checking Docker/container performance: $_" -ForegroundColor DarkRed
}

# ============================================================================
# FREEZE, HANG & CRASH DETECTION - ULTIMATE
# ============================================================================
Section "SYSTEM FREEZE, HANG & CRASH DETECTION"
Write-Host "Checking for freeze/hang/crash causes..." -ForegroundColor Magenta

try {
    # DPC Watchdog Violations (causes freeze then BSOD)
    try {
        Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$last7d} -EA 0 -MaxEvents 500 | Where-Object {
            $_.Message -match 'DPC.*watchdog|DPC.*timeout|DPC.*violation|clock interrupt.*not received'
        } | ForEach-Object {
            CriticalProblem "DPC WATCHDOG: $($_.TimeCreated) - causes system freezes/BSOD"
        }
    } catch {}

    # Storage Controller Resets (causes freeze during disk I/O)
    try {
        Get-WinEvent -FilterHashtable @{LogName='System'; Id=129; StartTime=$last7d} -EA 0 | ForEach-Object {
            CriticalProblem "DISK CONTROLLER RESET: $($_.TimeCreated) - causes freezes during disk activity"
        }
    } catch {}

    # Pagefile Exhaustion (causes freeze when RAM full)
    try {
        $pagefiles = Get-CimInstance Win32_PageFileUsage -EA 0
        foreach ($pf in $pagefiles) {
            $pfUsedPct = ($pf.CurrentUsage / $pf.AllocatedBaseSize) * 100
            if ($pfUsedPct -gt 90) {
                CriticalProblem "PAGEFILE EXHAUSTION: $($pf.Name) at $([math]::Round($pfUsedPct))% - causes freezes"
            }
        }
    } catch {}

    # Disk Queue Length (high queue = freezing)
    try {
        $disks = Get-PhysicalDisk -EA 0
        foreach ($disk in $disks) {
            try {
                if ($disk -and $disk.FriendlyName) {
                    $diskPerf = Get-Counter "\PhysicalDisk($($disk.FriendlyName))\Avg. Disk Queue Length" -EA 0
                    if ($diskPerf -and $diskPerf.CounterSamples -and $diskPerf.CounterSamples.CookedValue -gt 2) {
                        Problem "DISK QUEUE: $($disk.FriendlyName) queue length $([math]::Round($diskPerf.CounterSamples.CookedValue, 2)) - causes slowdowns"
                    }
                }
            } catch {}
        }
    } catch {}

    # Disk Response Time
    try {
        Get-PhysicalDisk -EA 0 | ForEach-Object {
            try {
                if ($_ -and $_.FriendlyName) {
                    $diskRead = Get-Counter "\PhysicalDisk($($_.FriendlyName))\Avg. Disk sec/Read" -EA 0
                    if ($diskRead -and $diskRead.CounterSamples -and $diskRead.CounterSamples.CookedValue -gt 0.1) {
                        Problem "SLOW DISK: $($_.FriendlyName) read latency $([math]::Round($diskRead.CounterSamples.CookedValue * 1000))ms - causes freezes"
                    }
                }
            } catch {}
        }
    } catch {}

    # Memory Leak Detection
    $processes = Get-Process -EA 0 | Where-Object { $_.WorkingSet64 -gt 500MB } | Sort-Object WorkingSet64 -Descending | Select-Object -First 10
    foreach ($proc in $processes) {
        $memMB = [math]::Round($proc.WorkingSet64 / 1MB)
        if ($memMB -gt 2000) {
            Problem "MEMORY LEAK SUSPECT: $($proc.Name) using $memMB MB RAM"
        }
    }

    # Handle Leak Detection
    $processes | Where-Object { $_.HandleCount -gt 10000 } | ForEach-Object {
        Problem "HANDLE LEAK: $($_.Name) has $($_.HandleCount) handles - may cause freezes"
    }

    # GDI Object Leak (causes Windows UI to freeze)
    try {
        $gdiLeaks = Get-Process -EA 0 | Where-Object { $_.HandleCount -gt 5000 } | ForEach-Object {
            try {
                $gdiCount = (Get-Counter "\Process($($_.Name))\GDI Objects" -EA 0).CounterSamples.CookedValue
                if ($gdiCount -gt 5000) {
                    Problem "GDI OBJECT LEAK: $($_.Name) has $gdiCount GDI objects - causes UI freezes"
                }
            } catch {}
        }
    } catch {}

    # Critical Services Not Responding
    $criticalSvcs = @('RpcSs', 'DcomLaunch', 'EventLog', 'ProfSvc', 'Schedule')
    foreach ($svcName in $criticalSvcs) {
        try {
            $svc = Get-Service -Name $svcName -EA 0
            if ($svc -and $svc.Status -ne 'Running') {
                CriticalProblem "CRITICAL SERVICE DOWN: $svcName - causes system instability/freezes"
            }
        } catch {}
    }

    # User Profile Service Issues (causes login freezes)
    try {
        Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-User Profiles Service'; Level=1,2,3; StartTime=$last7d} -EA 0 -MaxEvents 30 | ForEach-Object {
            CriticalProblem "USER PROFILE ERROR: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length))))"
        }
    } catch {}

    # Shell Experience Host Crashes (causes Start Menu/Taskbar freeze)
    try {
        Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$bootTime} -EA 0 -MaxEvents 200 | Where-Object {
            $_.Message -match 'ShellExperienceHost.*crash|ShellExperienceHost.*terminated|StartMenuExperienceHost'
        } | ForEach-Object {
            Problem "SHELL UI CRASH: Start Menu/Taskbar component crashed at $($_.TimeCreated)"
        }
    } catch {}

    # Antivirus Real-Time Scan Causing Freezes
    try {
        $defenderStatus = Get-MpComputerStatus -EA 0
        if ($defenderStatus -and $defenderStatus.RealTimeProtectionEnabled) {
            # Check if causing high CPU
            $defenderProc = Get-Process -Name "MsMpEng" -EA 0
            if ($defenderProc -and $defenderProc.CPU -gt 20) {
                Problem "WINDOWS DEFENDER: Real-time scan using high CPU - causes freezes"
            }
        }
    } catch {}

    # NVME SSD Issues (specific to NVMe drives)
    try {
        $nvmeDisks = Get-PhysicalDisk -EA 0 | Where-Object { $_ -and $_.BusType -eq 'NVMe' }
        foreach ($nvmeDisk in $nvmeDisks) {
            try {
                $diskName = $nvmeDisk.FriendlyName
                if ($diskName) {
                    # Check for errors
                    $nvmeErrors = Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$last7d} -EA 0 -MaxEvents 100 | Where-Object {
                        $_.Message -match 'NVMe|storage' -and $_.Level -le 3
                    }
                    if ($nvmeErrors -and $nvmeErrors.Count -gt 5) {
                        CriticalProblem "NVME ERRORS: $diskName has $($nvmeErrors.Count) errors - causes freezes/data loss"
                    }
                }
            } catch {}
        }
    } catch {}

} catch {
    Write-Host "  Error checking freeze/hang/crash detection: $_" -ForegroundColor DarkRed
}

# ============================================================================
# ADDITIONAL PERFORMANCE KILLERS
# ============================================================================
Section "MISC PERFORMANCE KILLERS"
Write-Host "Checking miscellaneous performance issues..." -ForegroundColor Magenta

try {
    # Startup Programs (slows boot & background performance)
    $startupProgs = Get-CimInstance Win32_StartupCommand -EA 0
    if ($startupProgs.Count -gt 20) {
        Problem "EXCESSIVE STARTUP PROGRAMS: $($startupProgs.Count) programs auto-start - slows boot/performance"
    }

    # Scheduled Tasks Running Frequently
    try {
        $tasks = Get-ScheduledTask -EA 0 | Where-Object { $_.State -eq 'Running' }
        if ($tasks.Count -gt 10) {
            Problem "MANY SCHEDULED TASKS: $($tasks.Count) tasks running - may impact performance"
        }
    } catch {}

    # Visual Effects (Aero, animations)
    $visualEffects = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -EA 0
    if ($visualEffects -and $visualEffects.VisualFXSetting -eq 0) {
        Problem "VISUAL EFFECTS: Set to 'Let Windows choose' - may use resources for animations"
    }

    # OneDrive Sync Overhead
    $oneDriveProc = Get-Process -Name "OneDrive" -EA 0
    if ($oneDriveProc) {
        try {
            $oneDriveCPU = $oneDriveProc.CPU
            if ($oneDriveCPU -gt 10) {
                Problem "ONEDRIVE: Actively syncing - using CPU/bandwidth in background"
            }
        } catch {}
    }

    # Windows Telemetry
    $telemetry = Get-Service -Name "DiagTrack" -EA 0
    if ($telemetry -and $telemetry.Status -eq 'Running') {
        Problem "TELEMETRY: DiagTrack service running - sends data in background"
    }

    # Font Cache Issues (can cause slowdowns)
    $fontCacheSize = (Get-ChildItem "$env:windir\ServiceProfiles\LocalService\AppData\Local\FontCache\*.dat" -EA 0 | Measure-Object -Property Length -Sum).Sum
    if ($fontCacheSize -gt 100MB) {
        Problem "FONT CACHE: $([math]::Round($fontCacheSize/1MB))MB - may be corrupted, causes slowdowns"
    }

    # Windows Update Pending
    try {
        $pendingUpdates = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher().Search("IsInstalled=0").Updates
        if ($pendingUpdates.Count -gt 0) {
            Problem "WINDOWS UPDATE: $($pendingUpdates.Count) updates pending - may install in background"
        }
    } catch {}

    # .NET Compilation Queue
    try {
        $ngenQueue = & "$env:windir\Microsoft.NET\Framework64\v4.0.30319\ngen.exe" queue status 2>$null
        if ($ngenQueue -match 'pending') {
            Problem ".NET NGEN: Assemblies pending compilation - background CPU usage"
        }
    } catch {}

    # Prefetch Folder Size (if too large, slows down)
    try {
        $prefetchItems = @(Get-ChildItem "$env:windir\Prefetch" -File -EA 0)
        if ($prefetchItems.Count -gt 0) {
            $prefetchSize = ($prefetchItems | Measure-Object -Property Length -Sum).Sum
            if ($prefetchSize -gt 50MB) {
                Problem "PREFETCH FOLDER: $([math]::Round($prefetchSize/1MB))MB - excessive, slows boot time"
            }
        }
    } catch {}

    # SoftwareDistribution (Windows Update cache)
    try {
        $swDistItems = @(Get-ChildItem "$env:windir\SoftwareDistribution\Download" -File -Recurse -EA 0)
        if ($swDistItems.Count -gt 0) {
            $swDistSize = ($swDistItems | Measure-Object -Property Length -Sum).Sum
            if ($swDistSize -gt 500MB) {
                Problem "WINDOWS UPDATE CACHE: $([math]::Round($swDistSize/1MB))MB - can be cleaned"
            }
        }
    } catch {}

} catch {
    Write-Host "  Error checking misc performance: $_" -ForegroundColor DarkRed
}

Write-Host "`nULTIMATE PERFORMANCE DETECTION COMPLETE" -ForegroundColor Green

# ============================================================================
# PACKAGE MANAGER & DEVELOPMENT ENVIRONMENT ERRORS (REAL-TIME)
# ============================================================================
Section "WINGET, STORE, PYTHON, NODE & PACKAGE MANAGER ERRORS"
Write-Host "Checking package managers and development tools (real-time)..." -ForegroundColor Magenta

# Source the package managers module
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkgMgrModule = Join-Path $scriptDir "package-managers.ps1"

if (Test-Path $pkgMgrModule) {
    & $pkgMgrModule -ProblemFunc ${function:Problem} -CriticalFunc ${function:CriticalProblem}
} else {
    Write-Host "  Warning: package-managers.ps1 module not found at $pkgMgrModule" -ForegroundColor Yellow
}

# ============================================================================
# WSL2 (WINDOWS SUBSYSTEM FOR LINUX) ERRORS (REAL-TIME)
# ============================================================================
Section "WSL2 (WINDOWS SUBSYSTEM FOR LINUX) ERRORS"
Write-Host "Checking WSL2 status and errors (real-time)..." -ForegroundColor Magenta

# Source the WSL2 module
$wsl2Module = Join-Path $scriptDir "wsl2.ps1"

if (Test-Path $wsl2Module) {
    & $wsl2Module -ProblemFunc ${function:Problem} -CriticalFunc ${function:CriticalProblem}
} else {
    Write-Host "  Warning: wsl2.ps1 module not found at $wsl2Module" -ForegroundColor Yellow
}

# SUMMARY
# ============================================================================
$duration = (Get-Date) - $startTime
@"

$('='*70)
COMPREHENSIVE SYSTEM SCAN COMPLETE (v5.1 Enhanced - WSL2 Support)
$('='*70)
Scan Duration: $([math]::Round($duration.TotalSeconds))s
Boot Time: $bootTime
Problems Found: $($script:problemCount)
CRITICAL Issues: $($script:criticalCount)
Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Output: $outputFile

$(if ($script:problemCount -eq 0) {
    "[OK] No problems detected - system is healthy!"
} elseif ($script:criticalCount -gt 0) {
    "[!!!] $($script:criticalCount) CRITICAL issue(s) + $($script:problemCount - $script:criticalCount) other issue(s) - IMMEDIATE ACTION REQUIRED"
} else {
    "[!] $($script:problemCount) issue(s) found - review above"
})

ENHANCED DETECTION v5.1 INCLUDES:
- Kernel-mode exceptions (KMODE_EXCEPTION_NOT_HANDLED)
- LoadLibrary error 126 and missing DLLs
- Driver stopping/service dependency failures
- Outdated and problematic drivers
- BSOD crash dumps
- Explorer.exe crashes & shell UI failures
- Network performance & DNS latency
- CPU/RAM performance (game lag, multitasking)
- GPU/TDR events (frame drops, stuttering)
- Thermal throttling detection
- Disk I/O bottlenecks
- Docker & container issues
- Hyper-V & virtualization performance
- WSL2 feature & service status
- Download/bandwidth throttling (QoS)
- Freeze/hang detection (DPC watchdog)
- Memory leak detection
- Hardware errors (WHEA, RAM, PCI)
- Pagefile/virtual memory exhaustion
- Antivirus performance impact
- Windows Update activity
- Runtime/framework issues (.NET, VC++)
- Proxy/firewall interference
- WinGet package manager errors (real-time)
- Microsoft Store installation failures (real-time)
- Python environment and module errors (real-time)
- Node.js/NPM package and cache errors (real-time)
- Git repository and configuration errors (real-time)
- .NET Framework and runtime errors (real-time)
- Java installation and JAR file integrity (real-time)
- VC++ Redistributable missing/corrupted DLLs (real-time)
- OpenSSL and certificate validation errors (real-time)
- Build tools (Make/CMake) and cache issues (real-time)
- WSL2 registration errors (FILE_NOT_FOUND, WSL_E_DISTRO_NOT_FOUND)
- WSL2 distribution status and corruption detection
- WSL2 vmmem memory usage and leaks
- WSL2 kernel panic and crash detection
- WSL2 networking and disk access issues
- WSL2 .wslconfig validation
- WSL2 Hyper-V integration errors
- WSL2 virtual disk (VHD) corruption detection
"@ | Out-File $outputFile -Append -Encoding UTF8

Write-Host "`nComplete! " -NoNewline
if ($script:problemCount -eq 0) {
    Write-Host "$($script:problemCount) problems found - HEALTHY" -ForegroundColor Green
} elseif ($script:criticalCount -gt 0) {
    Write-Host "$($script:criticalCount) CRITICAL + $($script:problemCount - $script:criticalCount) other problems found" -ForegroundColor Red
} else {
    Write-Host "$($script:problemCount) problems found" -ForegroundColor Yellow
}
Write-Host "Report: $outputFile" -ForegroundColor Cyan
