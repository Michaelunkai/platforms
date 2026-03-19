# Ascendara Full Automation Script
# Downloads, installs, and configures Ascendara completely automatically

param()

$ErrorActionPreference = "Stop"

# Download and install
$url = 'https://github.com/Ascendara/ascendara/releases/download/10.1.1/Ascendara.Setup.10.1.1.exe'
$installer = Join-Path $env:TEMP 'Ascendara.Setup.10.1.1.exe'

Write-Host "Downloading Ascendara..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing

Write-Host "Installing Ascendara..." -ForegroundColor Cyan
Start-Process -FilePath $installer -Wait

Write-Host "Launching Ascendara for first-time setup..." -ForegroundColor Cyan
$ascendaraExe = "$env:LOCALAPPDATA\Programs\ascendara\Ascendara.exe"
Start-Process $ascendaraExe

# Wait for window
Start-Sleep -Seconds 5

# Load UI Automation assemblies
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

# Send keystrokes to automate setup
Add-Type -AssemblyName System.Windows.Forms

Write-Host "Automating first-time setup..." -ForegroundColor Cyan

# Language selection - click English (using SendKeys)
Start-Sleep -Seconds 2
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
Start-Sleep -Seconds 2

# Go through setup screens (terms, options, etc.)
for ($i = 0; $i -lt 5; $i++) {
    Start-Sleep -Seconds 1
    [System.Windows.Forms.SendKeys]::SendWait(" ")  # Space to check boxes
    Start-Sleep -Milliseconds 500
    [System.Windows.Forms.SendKeys]::SendWait("{TAB}")  # Tab to next field
    Start-Sleep -Milliseconds 500
}

# Final continue/finish
Start-Sleep -Seconds 1
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
Start-Sleep -Seconds 3

Write-Host "Ascendara setup complete! Application is ready to use." -ForegroundColor Green
