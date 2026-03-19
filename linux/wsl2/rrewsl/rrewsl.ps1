<#
.SYNOPSIS
    rrewsl
#>
Write-Output "Starting full WSL2 setup..." -ForegroundColor Green
    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Error "Please run PowerShell as Administrator."
        return
    }
    $wslBasePath = "C:\wsl2"
    $ubuntuPath1 = "$wslBasePath\ubuntu"
    $ubuntuPath2 = "$wslBasePath\ubuntu2"
    $backupPath = "F:\backup\linux\wsl\ubuntu.tar"
    foreach ($distro in @("ubuntu", "ubuntu2")) {
        if ((wsl --list --quiet 2>$null) -contains $distro) {
            wsl --terminate $distro 2>$null
            wsl --unregister $distro 2>$null
        }
    }
    foreach ($path in @($ubuntuPath1, $ubuntuPath2)) {
        if (Test-Path "$path\ext4.vhdx") {
            Remove-Item "$path\ext4.vhdx" -Force -ErrorAction SilentlyContinue
        }
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force > $null
        }
    }
    $features = @(
        "Microsoft-Windows-Subsystem-Linux",
        "VirtualMachinePlatform",
        "Microsoft-Hyper-V-All",
        "Containers-DisposableClientVM"
    )
    $restartNeeded = $false
    $enabled = @()
    foreach ($f in $features) {
        $status = Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction SilentlyContinue
        if ($status -and $status.State -ne "Enabled") {
            $result = Enable-WindowsOptionalFeature -Online -FeatureName $f -NoRestart -ErrorAction SilentlyContinue
            if ($result.RestartNeeded) { $restartNeeded = $true }
            $enabled += $f
        }
    }
    foreach ($svc in @("vmms", "vmcompute")) {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s -and $s.Status -ne "Running") {
            try { Start-Service -Name $svc } catch {}
        }
    }
    $hv = (Get-ComputerInfo).HyperVRequirementVirtualizationFirmwareEnabled
    if ($hv -eq $false) {
        Write-Warning "Enable virtualization in BIOS/UEFI."
        return
    }
    if ($restartNeeded) {
        Write-Warning "Restart required after enabling features: $($enabled -join ', ')"
        return
    }
    wsl --update 2>$null
    wsl --set-default-version 2
    if (-not (Test-Path $backupPath)) {
        Write-Warning "Missing backup: $backupPath"
        return
    }
    try {
        wsl --import ubuntu $ubuntuPath1 $backupPath
        wsl --import ubuntu2 $ubuntuPath2 $backupPath
    } catch {
        Write-Error "Failed to import one or both distros: $_"
        return
    }
    Set-Content "$env:USERPROFILE\.wslconfig" @"
[wsl2]
memory=4GB
processors=2
swap=2GB
localhostForwarding=true
[experimental]
autoMemoryReclaim=gradual
networkingMode=mirrored
dnsTunneling=true
firewall=true
autoProxy=true
"@ -Force
    wsl --set-default ubuntu
    wsl --list --verbose
    Write-Output "WSL setup completed. You can start Ubuntu manually via 'wsl -d ubuntu'" -ForegroundColor Cyan
