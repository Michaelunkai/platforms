<#
.SYNOPSIS
    wingit
#>
<#
    .SYNOPSIS
        Installs apps via winget (if not installed) and pins them to taskbar.
    .DESCRIPTION
        1. Fixes PATH for common apps
        2. Checks if each app is installed
        3. Installs missing apps via winget
        4. Finds/creates shortcuts for installed apps
        5. Pins all apps to taskbar using Windows 11 LayoutModification.xml
    #>
    $ErrorActionPreference = "SilentlyContinue"
    Write-Host "`n=== WINGIT: INSTALL + PIN TO TASKBAR ===" -ForegroundColor Cyan
    
    # Define packages with their winget IDs and friendly names for shortcut detection
    $packages = @(
        @{ Id = "Google.Chrome"; Name = "Google Chrome"; LnkSearch = @("*Chrome*", "*Google Chrome*") }
        @{ Id = "Rclone.Rclone"; Name = "Rclone"; LnkSearch = @("*Rclone*") }
        @{ Id = "GitHub.GitHubDesktop"; Name = "GitHub Desktop"; LnkSearch = @("*GitHub Desktop*") }
        @{ Id = "GitHub.cli"; Name = "GitHub CLI"; LnkSearch = @("*GitHub CLI*") }
        @{ Id = "j178.ChatGPT"; Name = "ChatGPT"; LnkSearch = @("*ChatGPT*") }
        @{ Id = "seerge.g-helper"; Name = "G-Helper"; LnkSearch = @("*G-Helper*", "*GHelper*") }
        @{ Id = "KristenMcWilliam.Nyrna"; Name = "Nyrna"; LnkSearch = @("*Nyrna*") }
        @{ Id = "Anthropic.Claude"; Name = "Claude"; LnkSearch = @("*Claude*") }
        @{ Id = "Perplexity.Comet"; Name = "Comet"; LnkSearch = @("*Comet*", "*Perplexity*") }
        @{ Id = "9NCVDN91XZQP"; Name = "WhatsApp"; LnkSearch = @("*WhatsApp*") }
        @{ Id = "9MWF2DWS5Z9N"; Name = "Windows Terminal"; LnkSearch = @("*Terminal*", "*Windows Terminal*") }
        @{ Id = "9N7R5S6B0ZZH"; Name = "OneNote"; LnkSearch = @("*OneNote*") }
        @{ Id = "9WZDNCRDK3WP"; Name = "Instagram"; LnkSearch = @("*Instagram*") }
        @{ Id = "9NHPXCXS27F9"; Name = "Microsoft To Do"; LnkSearch = @("*To Do*", "*ToDo*") }
        @{ Id = "9NT1R1C2HH7J"; Name = "File Explorer"; LnkSearch = @("*File Explorer*", "*Explorer*") }
    )
    
    # PATH fixes
    $pathsToAdd = @(
        "C:\Program Files\GitHub CLI"
        "C:\Program Files\Git\cmd"
        "C:\Program Files (x86)\Google\Chrome\Application"
        "C:\Program Files\Seerge\G-Helper"
    )
    $pathParts = $env:Path -split ';' | Where-Object { $_ -ne '' } | ForEach-Object { $_.Trim() }
    foreach ($p in $pathsToAdd) {
        if (-not ($pathParts -contains $p)) {
            Write-Host "Adding to PATH: $p" -ForegroundColor Yellow
            $pathParts += $p
        }
    }
    $env:Path = ($pathParts -join ';')
    [Environment]::SetEnvironmentVariable('Path', $env:Path, [EnvironmentVariableTarget]::User)
    
    # Check winget
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: winget not found. Install App Installer from Microsoft Store." -ForegroundColor Red
        return
    }
    
    # Track installed apps for pinning
    $installedApps = @()
    
    # Install missing apps
    foreach ($pkg in $packages) {
        Write-Host "`n=== Checking: $($pkg.Name) ($($pkg.Id)) ===" -ForegroundColor Cyan
        $installedOutput = winget list --accept-source-agreements --exact --id $pkg.Id 2>$null
        if (-not $installedOutput -or $installedOutput -match "No installed package found") {
            Write-Host "Installing: $($pkg.Id)" -ForegroundColor Yellow
            winget install --accept-package-agreements --accept-source-agreements --force --skip-dependencies --exact --id $pkg.Id
        } else {
            Write-Host "Already installed: $($pkg.Name)" -ForegroundColor Green
        }
        $installedApps += $pkg
    }
    
    Write-Host "`n=== Finding shortcuts for installed apps ===" -ForegroundColor Cyan
    
    # Search locations for shortcuts
    $searchPaths = @(
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
        "$env:LOCALAPPDATA\Microsoft\Windows\Start Menu\Programs"
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs"
    )
    
    $foundLnkPaths = @()
    
    foreach ($pkg in $installedApps) {
        $found = $false
        foreach ($searchPath in $searchPaths) {
            if (Test-Path $searchPath) {
                foreach ($pattern in $pkg.LnkSearch) {
                    $lnks = Get-ChildItem -Path $searchPath -Filter "*.lnk" -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -like $pattern }
                    if ($lnks) {
                        $lnk = $lnks | Select-Object -First 1
                        # Convert to environment variable path for XML
                        $lnkPath = $lnk.FullName
                        if ($lnkPath -like "$env:ProgramData*") {
                            $lnkPath = $lnkPath -replace [regex]::Escape($env:ProgramData), '%ALLUSERSPROFILE%'
                        } elseif ($lnkPath -like "$env:APPDATA*") {
                            $lnkPath = $lnkPath -replace [regex]::Escape($env:APPDATA), '%APPDATA%'
                        } elseif ($lnkPath -like "$env:LOCALAPPDATA*") {
                            $lnkPath = $lnkPath -replace [regex]::Escape($env:LOCALAPPDATA), '%LOCALAPPDATA%'
                        }
                        Write-Host "Found shortcut for $($pkg.Name): $($lnk.Name)" -ForegroundColor Green
                        $foundLnkPaths += $lnkPath
                        $found = $true
                        break
                    }
                }
            }
            if ($found) { break }
        }
        if (-not $found) {
            Write-Host "No shortcut found for $($pkg.Name)" -ForegroundColor Yellow
        }
    }
    
    # Only proceed with taskbar pinning if we found shortcuts
    if ($foundLnkPaths.Count -gt 0) {
        Write-Host "`n=== Generating LayoutModification.xml for taskbar pinning ===" -ForegroundColor Cyan
        
        # Build XML for taskbar layout
        $xmlContent = @"
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate
    xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"
    xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"
    xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification"
    Version="1">
  <CustomTaskbarLayoutCollection PinListPlacement="Replace">
    <defaultlayout:TaskbarLayout>
      <taskbar:TaskbarPinList>

"@
        foreach ($lnkPath in $foundLnkPaths) {
            $xmlContent += "        <taskbar:DesktopApp DesktopApplicationLinkPath=`"$lnkPath`" />`n"
        }
        
        $xmlContent += @"
      </taskbar:TaskbarPinList>
    </defaultlayout:TaskbarLayout>
  </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
"@
        
        # Save to user's LayoutModification.xml
        $layoutPath = "$env:APPDATA\Microsoft\Windows\Shell\LayoutModification.xml"
        $layoutDir = Split-Path $layoutPath -Parent
        if (-not (Test-Path $layoutDir)) {
            New-Item -ItemType Directory -Path $layoutDir -Force | Out-Null
        }
        $xmlContent | Out-File -FilePath $layoutPath -Encoding utf8 -Force
        Write-Host "Created LayoutModification.xml with $($foundLnkPaths.Count) apps" -ForegroundColor Green
        
        # Also save to default profile for new users
        $defaultLayoutPath = "C:\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml"
        $defaultLayoutDir = Split-Path $defaultLayoutPath -Parent
        if (-not (Test-Path $defaultLayoutDir)) {
            New-Item -ItemType Directory -Path $defaultLayoutDir -Force -ErrorAction SilentlyContinue | Out-Null
        }
        $xmlContent | Out-File -FilePath $defaultLayoutPath -Encoding utf8 -Force -ErrorAction SilentlyContinue
        
        # Apply taskbar layout by resetting it
        Write-Host "`n=== Applying taskbar layout (will restart Explorer) ===" -ForegroundColor Yellow
        Write-Host "WARNING: This will reset your current taskbar pins!" -ForegroundColor Red
        
        # Reset taskbar layout
        Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
        Remove-Item "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\*" -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:APPDATA\Microsoft\Windows\Shell\*.dat" -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Taskband" -Recurse -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TrayNotify" -Name "IconStreams" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TrayNotify" -Name "PastIconsStream" -ErrorAction SilentlyContinue
        
        Start-Sleep -Seconds 2
        Start-Process explorer
        
        Write-Host "`nTaskbar layout applied! Apps should now be pinned." -ForegroundColor Green
    } else {
        Write-Host "`nNo shortcuts found to pin. Apps installed but taskbar not modified." -ForegroundColor Yellow
    }
    
    Write-Host "`n=== WINGIT COMPLETE ===" -ForegroundColor Green
