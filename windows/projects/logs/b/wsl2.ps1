# WSL2 (Windows Subsystem for Linux) Error Detection Module
# Sourced by: a.ps1
# Purpose: Comprehensive real-time WSL2 error detection

param(
    [scriptblock]$ProblemFunc,
    [scriptblock]$CriticalFunc
)

Write-Host "  Checking WSL2..." -ForegroundColor DarkCyan

try {
    # Check if WSL is enabled
    $wslFeature = Get-WindowsOptionalFeature -Online -FeatureName "Microsoft-Windows-Subsystem-Linux" -EA 0
    if ($wslFeature -and $wslFeature.State -ne 'Enabled') {
        & $ProblemFunc "WSL2: Feature not enabled - run 'wsl --install' to enable"
    }

    # Check if Hyper-V is enabled (required for WSL2)
    $hyperVFeature = Get-WindowsOptionalFeature -Online -FeatureName "Hyper-V" -EA 0
    if ($hyperVFeature -and $hyperVFeature.State -ne 'Enabled') {
        & $ProblemFunc "WSL2: Hyper-V not enabled - WSL2 requires Hyper-V"
    }

    # Check WSL service status
    $wslService = Get-Service -Name "LxssManager" -EA 0
    if ($wslService) {
        if ($wslService.Status -ne 'Running') {
            & $CriticalFunc "WSL2 SERVICE: LxssManager not running - status: $($wslService.Status)"
        }
    }

    # Get WSL version and status
    if (Get-Command wsl -EA 0) {
        try {
            $wslStatus = & wsl --version 2>&1
            if ($wslStatus -match 'error|not found|WSL.*not installed') {
                & $ProblemFunc "WSL2: Installation broken - $($wslStatus.Substring(0, [Math]::Min(150, $wslStatus.Length)))"
            } elseif ($wslStatus -match 'Access is denied|Permission denied|Error code') {
                & $ProblemFunc "WSL2: Permission error - $wslStatus"
            }
        } catch {
            & $ProblemFunc "WSL2: Unable to run - $($_.Exception.Message.Substring(0, 150))"
        }

        # Check WSL distribution list for errors
        try {
            $wslList = & wsl --list --verbose 2>&1
            if ($wslList -match 'Error code|not found|DISTRO_NOT_FOUND') {
                & $ProblemFunc "WSL2 DISTRO ERROR: $($wslList.Substring(0, [Math]::Min(200, $wslList.Length)))"
            }

            # Check for corrupted distributions
            if ($wslList -match 'Stopped|Error|\[Error\]') {
                $wslList -split "`n" | Where-Object { $_ -match 'Stopped|Error' } | ForEach-Object {
                    & $ProblemFunc "WSL2 DISTRO STOPPED: $_"
                }
            }
        } catch {
            & $ProblemFunc "WSL2 LIST FAILED: $($_.Exception.Message.Substring(0, 150))"
        }

        # Check for distribution registration errors
        try {
            $wslShell = & wsl -e id 2>&1
            if ($wslShell -match 'Error|RegisterDistro|CreateVm|FILE_NOT_FOUND|WSL_E_DISTRO_NOT_FOUND') {
                & $ProblemFunc "WSL2 REGISTRATION ERROR: Cannot access default distribution - $($wslShell.Substring(0, [Math]::Min(200, $wslShell.Length)))"
            }
        } catch {
            & $ProblemFunc "WSL2 DEFAULT DISTRO: $($_.Exception.Message.Substring(0, 150))"
        }

        # Check WSL memory configuration
        try {
            if (Test-Path "$env:UserProfile\.wslconfig" -EA 0) {
                $wslConfig = Get-Content "$env:UserProfile\.wslconfig" -Raw -EA 0
                if ($wslConfig) {
                    # Parse memory setting
                    if ($wslConfig -match 'memory\s*=\s*(\d+)') {
                        $memMB = [int]$matches[1]
                        $memGB = $memMB / 1024
                        if ($memGB -gt 16 -or $memGB -lt 0.5) {
                            & $ProblemFunc "WSL2 CONFIG: Memory setting suspicious - $memGB GB"
                        }
                    }

                    # Check for invalid settings
                    if ($wslConfig -match '\[interop\]|\[experimental\]') {
                        if ($wslConfig -match 'enabled\s*=\s*false') {
                            & $ProblemFunc "WSL2 CONFIG: Interop disabled - some Windows-to-Linux calls may fail"
                        }
                    }
                }
            }
        } catch {}

        # Check for WSL update/upgrade issues
        try {
            Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$script:lastHour; ProviderName='Hyper-V-Compute'} -EA 0 -MaxEvents 50 | Where-Object {
                $_.Message -match 'WSL|wsl\.exe|Linux.*error|distribution.*error'
            } | ForEach-Object {
                & $ProblemFunc "WSL2 HYPERV: $($_.Message.Substring(0, [Math]::Min(200, $_.Message.Length)))"
            }
        } catch {}

        # Check for file not found errors
        try {
            Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$script:last7d; ProviderName='Hyper-V-Compute'} -EA 0 -MaxEvents 100 | Where-Object {
                $_.Message -match 'File not found|FILE_NOT_FOUND|CreateVm|RegisterDistro'
            } | ForEach-Object {
                & $ProblemFunc "WSL2 FILE ERROR: $($_.Message.Substring(0, [Math]::Min(200, $_.Message.Length)))"
            }
        } catch {}

        # Check WSL distribution mount errors
        try {
            Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Subsystem-Linux/Operational'; StartTime=$script:lastHour} -EA 0 -MaxEvents 50 | Where-Object {
                $_.Level -le 2
            } | ForEach-Object {
                & $ProblemFunc "WSL2 MOUNT: $($_.Message.Substring(0, [Math]::Min(250, $_.Message.Length)))"
            }
        } catch {}

        # Check for WSL2 vmmem process memory issues
        try {
            $vmmemProc = Get-Process -Name "vmmem" -EA 0
            if ($vmmemProc) {
                foreach ($proc in @($vmmemProc)) {
                    $ramMB = [math]::Round($proc.WorkingSet64 / 1MB)
                    if ($ramMB -gt 8192) {
                        & $ProblemFunc "WSL2 VMMEM HIGH MEMORY: Using $ramMB MB - check .wslconfig memory limit"
                    }
                    if ($ramMB -gt 12288) {
                        & $CriticalFunc "WSL2 VMMEM CRITICAL: Using $ramMB MB - memory leak suspected"
                    }
                }
            }
        } catch {}

        # Check for WSL2 initialization errors
        try {
            Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$script:last7d} -EA 0 -MaxEvents 200 | Where-Object {
                $_.Message -match 'WSL.*failed|WSL.*error|Distribution.*not.*found|VmCompute'
            } | ForEach-Object {
                & $ProblemFunc "WSL2 SYSTEM EVENT: $($_.Message.Substring(0, [Math]::Min(200, $_.Message.Length)))"
            }
        } catch {}

        # Check for WSL2 networking issues
        try {
            Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$script:lastHour; ProviderName='vEthernet'} -EA 0 -MaxEvents 50 | Where-Object {
                $_.Level -le 2
            } | ForEach-Object {
                & $ProblemFunc "WSL2 NETWORK: $($_.Message.Substring(0, [Math]::Min(200, $_.Message.Length)))"
            }
        } catch {}

        # Check for WSL2 disk access issues
        try {
            Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$script:lastHour} -EA 0 -MaxEvents 100 | Where-Object {
                $_.Message -match 'wsl\.exe.*disk|WSL.*mount.*fail|ext4\.vhdx'
            } | ForEach-Object {
                & $ProblemFunc "WSL2 DISK ACCESS: $($_.Message.Substring(0, [Math]::Min(200, $_.Message.Length)))"
            }
        } catch {}

        # Check for WSL2 kernel panic or crash
        try {
            Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$script:last7d} -EA 0 -MaxEvents 100 | Where-Object {
                $_.Message -match 'WSL.*panic|WSL.*crash|Linux.*kernel.*error'
            } | ForEach-Object {
                & $CriticalFunc "WSL2 KERNEL CRASH: $($_.Message.Substring(0, [Math]::Min(200, $_.Message.Length)))"
            }
        } catch {}

        # Check WSL installation location for corruption
        try {
            if (Test-Path "$env:LocalAppData\Packages\*Subsystem*" -EA 0) {
                $wslData = Get-ChildItem "$env:LocalAppData\Packages\*Subsystem*" -Recurse -Filter "*.vhdx" -EA 0
                $wslData | ForEach-Object {
                    if ($_.Length -eq 0) {
                        & $ProblemFunc "WSL2 VHD CORRUPTED: $($_.Name) is zero-size"
                    }
                    if ($_.Length -gt 500GB) {
                        & $ProblemFunc "WSL2 VHD BLOATED: $($_.Name) is $([math]::Round($_.Length/1GB))GB - excessive"
                    }
                }
            }
        } catch {}

    } else {
        & $ProblemFunc "WSL2: wsl.exe not found - may not be installed"
    }

} catch {
    Write-Host "    Error checking WSL2: $_" -ForegroundColor DarkRed
}
