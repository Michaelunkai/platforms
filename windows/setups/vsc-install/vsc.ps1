<#
.SYNOPSIS
    vsc - PowerShell utility script
.DESCRIPTION
    Extracted from PowerShell profile for modular organization
.NOTES
    Original function: vsc
    Location: F:\study\Platforms\windows\setups\vsc-install\vsc.ps1
    Extracted: 2026-02-19 20:05
#>
param()
    param(
        [string]$InstallPath = "F:\backup\windowsapps\installed\VSCode",
        [string]$DownloadPath = "$env:TEMP\VSCodeSetup.exe"
    )
    Write-Host "Starting VS Code COMPLETE FRESH reinstallation with Copilot..." -ForegroundColor Green
    Get-Process -Name "Code" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    Write-Host "Performing complete VS Code cleanup..." -ForegroundColor Yellow
    if (Test-Path $InstallPath) {
        try {
            Remove-Item -Path $InstallPath -Recurse -Force
            Write-Host "Removed installation directory" -ForegroundColor Green
        } catch {
            Write-Error "Failed to remove existing installation: $_"
            return
        }
    }
    $UserDataPaths = @("$env:APPDATA\Code","$env:USERPROFILE\.vscode","$env:LOCALAPPDATA\Programs\Microsoft VS Code")
    foreach ($path in $UserDataPaths) {
        if (Test-Path $path) {
            try {
                Remove-Item -Path $path -Recurse -Force
                Write-Host "Removed user data: $path" -ForegroundColor Green
            } catch {
                Write-Warning "Could not remove: $path"
            }
        }
    }
    try {
        $registryPaths = @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*","HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*","HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")
        foreach ($regPath in $registryPaths) {
            Get-ItemProperty $regPath -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*Visual Studio Code*" } | ForEach-Object {
                try {
                    Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                } catch { }
            }
        }
    } catch {
        Write-Warning "Registry cleanup had issues"
    }
    Write-Host "Complete cleanup finished" -ForegroundColor Green
    Write-Host "Downloading latest VS Code..." -ForegroundColor Yellow
    $VSCodeUrl = "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64"
    try {
        Invoke-WebRequest -Uri $VSCodeUrl -OutFile $DownloadPath -UseBasicParsing
        Write-Host "Download completed" -ForegroundColor Green
    } catch {
        Write-Error "Failed to download VS Code: $_"
        return
    }
    Write-Host "Installing VS Code..." -ForegroundColor Yellow
    New-Item -Path $InstallPath -ItemType Directory -Force > $null
    $InstallArgs = @("/VERYSILENT","/NORESTART","/SUPPRESSMSGBOXES","/CLOSEAPPLICATIONS","/RESTARTAPPLICATIONS","/NOCANCEL","/MERGETASKS=!runcode,!addcontextmenufiles,!addcontextmenufolders,!addtopath","/DIR=""$InstallPath""","/LOG=""$env:TEMP\VSCodeInstall.log""")
    try {
        $process = Start-Process -FilePath $DownloadPath -ArgumentList $InstallArgs -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            Write-Host "VS Code installed successfully" -ForegroundColor Green
        } else {
            Write-Error "Installation failed with exit code: $($process.ExitCode)"
            return
        }
    } catch {
        Write-Error "Failed to install VS Code: $_"
        return
    }
    Remove-Item -Path $DownloadPath -Force -ErrorAction SilentlyContinue
    Write-Host "Waiting for installation to complete..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    $VSCodeExe = Join-Path $InstallPath "bin\code.cmd"
    if (-not (Test-Path $VSCodeExe)) {
        $VSCodeExe = Join-Path $InstallPath "Code.exe"
    }
    if (-not (Test-Path $VSCodeExe)) {
        Write-Error "VS Code executable not found"
        return
    }
    Write-Host "Installing GitHub Copilot extensions..." -ForegroundColor Yellow
    $CopilotExtensions = @("GitHub.copilot","GitHub.copilot-chat")
    foreach ($extension in $CopilotExtensions) {
        Write-Host "Installing: $extension" -ForegroundColor Cyan
        try {
            & $VSCodeExe --install-extension $extension --force
        } catch {
            Write-Warning "Failed to install: $extension"
        }
    }
    Write-Host "Installing Python extensions..." -ForegroundColor Yellow
    $PythonExtensions = @("ms-python.python","ms-python.vscode-pylance","ms-python.debugpy","ms-python.black-formatter","ms-python.isort","ms-python.flake8","ms-python.mypy-type-checker","ms-toolsai.jupyter","ms-toolsai.jupyter-keymap","ms-toolsai.jupyter-renderers","ms-toolsai.vscode-jupyter-cell-tags","ms-toolsai.vscode-jupyter-slideshow","ms-python.autopep8","kevinrose.vsc-python-indent","njpwerner.autodocstring","donjayamanne.python-environment-manager","ms-vscode.test-adapter-converter")
    foreach ($extension in $PythonExtensions) {
        Write-Host "Installing: $extension" -ForegroundColor Cyan
        try {
            & $VSCodeExe --install-extension $extension --force
        } catch {
            Write-Warning "Failed to install: $extension"
        }
    }
    Start-Sleep -Seconds 5
    Write-Host "Checking GitHub CLI authentication..." -ForegroundColor Yellow
    $ghInstalled = Get-Command gh -ErrorAction SilentlyContinue
    if ($ghInstalled) {
        try {
            $authStatus = gh auth status 2>&1
            if ($authStatus -notmatch "Logged in") {
                Write-Host "Authenticating with GitHub CLI..." -ForegroundColor Cyan
                gh auth login --web --scopes "user:email,read:org,copilot"
            } else {
                Write-Host "Already authenticated with GitHub CLI" -ForegroundColor Green
            }
        } catch {
            gh auth login --web --scopes "user:email,read:org,copilot"
        }
    } else {
        Write-Warning "GitHub CLI not found. Installing..."
        try {
            winget install --id GitHub.cli --silent --accept-package-agreements --accept-source-agreements
            gh auth login --web --scopes "user:email,read:org,copilot"
        } catch {
            Write-Warning "Could not install GitHub CLI. Please install from https://cli.github.com/"
        }
    }
    Write-Host "Configuring VS Code settings..." -ForegroundColor Yellow
    $settingsDir = "$env:APPDATA\Code\User"
    $settingsFile = Join-Path $settingsDir "settings.json"
    if (-not (Test-Path $settingsDir)) {
        New-Item -Path $settingsDir -ItemType Directory -Force > $null
    }
    $copilotSettings = @{"github.copilot.enable"=@{"*"=$true;"yaml"=$true;"plaintext"=$true;"markdown"=$true;"python"=$true;"javascript"=$true;"typescript"=$true};"github.copilot.editor.enableAutoCompletions"=$true;"editor.inlineSuggest.enabled"=$true;"editor.quickSuggestions"=@{"other"=$true;"comments"=$true;"strings"=$true}}
    if (Test-Path $settingsFile) {
        try {
            $existingSettings = Get-Content $settingsFile -Raw | ConvertFrom-Json
            foreach ($key in $copilotSettings.Keys) {
                $existingSettings | Add-Member -MemberType NoteProperty -Name $key -Value $copilotSettings[$key] -Force
            }
            $existingSettings | ConvertTo-Json -Depth 10 | Set-Content $settingsFile
        } catch {
            $copilotSettings | ConvertTo-Json -Depth 10 | Set-Content $settingsFile
        }
    } else {
        $copilotSettings | ConvertTo-Json -Depth 10 | Set-Content $settingsFile
    }
    Write-Host "Launching VS Code..." -ForegroundColor Green
    try {
        Start-Process -FilePath $VSCodeExe
        Write-Host ""
        Write-Host "=== COPILOT AUTHENTICATION ===" -ForegroundColor Yellow
        Write-Host "1. VS Code will open shortly" -ForegroundColor Cyan
        Write-Host "2. Copilot may prompt Sign in to GitHub" -ForegroundColor Cyan
        Write-Host "3. Click Sign in and authorize in browser" -ForegroundColor Cyan
        Write-Host "4. Return to VS Code after authorization" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "If not prompted: Ctrl+Shift+P -> GitHub Copilot: Sign In" -ForegroundColor Cyan
        Write-Host ""
    } catch {
        Write-Error "Failed to launch VS Code: $_"
    }
    Write-Host ""
    Write-Host "=== INSTALLATION SUMMARY ===" -ForegroundColor Magenta
    Write-Host "Removed old VS Code completely" -ForegroundColor Green
    Write-Host "Installed fresh VS Code" -ForegroundColor Green
    Write-Host "Installed GitHub Copilot extensions" -ForegroundColor Green
    Write-Host "Installed Python extensions" -ForegroundColor Green
    Write-Host "Configured Copilot settings" -ForegroundColor Green
    Write-Host "Authenticated with GitHub CLI" -ForegroundColor Green
    Write-Host "Launched VS Code" -ForegroundColor Green
    Write-Host ""
    Write-Host "Installation path: $InstallPath" -ForegroundColor Cyan
    Write-Host "Fresh VS Code with Copilot ready!" -ForegroundColor Yellow
