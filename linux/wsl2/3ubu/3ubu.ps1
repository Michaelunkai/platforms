<#
.SYNOPSIS
    3ubu
#>
Write-Output "Starting WSL2 setup for ubuntu, ubuntu2, and ubuntu3..." -ForegroundColor Green
    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Error "Please run PowerShell as Administrator."
        return
    }
    $wslBasePath = "C:\wsl2"
    $backupPath = "F:\backup\linux\wsl\ubuntu.tar"
    $distros = @(
        @{ Name = "ubuntu"; Path = "$wslBasePath\ubuntu" },
        @{ Name = "ubuntu2"; Path = "$wslBasePath\ubuntu2" },
        @{ Name = "ubuntu3"; Path = "$wslBasePath\ubuntu3" }
    )
    # Unregister existing distros and delete VHDXs
    foreach ($d in $distros) {
        $name = $d.Name
        $path = $d.Path
        if ((wsl --list --quiet 2>$null) -contains $name) {
            wsl --terminate $name 2>$null
            wsl --unregister $name 2>$null
        }
        if (Test-Path "$path\ext4.vhdx") {
            Remove-Item "$path\ext4.vhdx" -Force -ErrorAction SilentlyContinue
        }
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force > $null
        }
    }
    # Ensure WSL-related features are enabled
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
        Write-Warning "Hardware virtualization is not enabled in BIOS/UEFI. Please enable VT-x / AMD-V."
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
    # Import all three Ubuntu distros
    foreach ($d in $distros) {
        try {
            wsl --import $d.Name $d.Path $backupPath
            Write-Output "Imported: $($d.Name)" -ForegroundColor Green
        } catch {
            Write-Error "Failed to import $($d.Name): $_"
        }
    }
    # .wslconfig setup
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
    Write-Output "Setup complete. You can now run 'wsl -d ubuntu', 'ubuntu2', or 'ubuntu3' manually." -ForegroundColor Cyan
