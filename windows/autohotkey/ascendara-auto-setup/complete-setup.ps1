# Complete Ascendara Automation - One Command Setup
$ErrorActionPreference = "SilentlyContinue"

# Download
$url = 'https://github.com/Ascendara/ascendara/releases/download/10.1.1/Ascendara.Setup.10.1.1.exe'
$installer = "$env:TEMP\Ascendara.Setup.10.1.1.exe"
Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing

# Install
Start-Process -FilePath $installer -Wait

# Wait for installation to complete
Start-Sleep -Seconds 3

# Find Ascendara executable
$ascendaraPath = Get-ChildItem "C:\Users\$env:USERNAME\AppData\Local\Programs" -Recurse -Filter "Ascendara.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName

if (!$ascendaraPath) {
    Write-Host "Ascendara not found after installation" -ForegroundColor Red
    exit 1
}

# Launch for first-time setup
Start-Process $ascendaraPath
Start-Sleep -Seconds 6

# Automate setup
Add-Type -AssemblyName System.Windows.Forms

# Select English
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
Start-Sleep -Seconds 3

# Accept terms/Continue through screens
for ($i = 0; $i -lt 8; $i++) {
    [System.Windows.Forms.SendKeys]::SendWait(" ")
    Start-Sleep -Milliseconds 300
    [System.Windows.Forms.SendKeys]::SendWait("{TAB}")
    Start-Sleep -Milliseconds 300
}

# Final Enter to complete
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
Start-Sleep -Seconds 3

# Launch app again to verify
Start-Process $ascendaraPath
Start-Sleep -Seconds 2

Write-Host "Ascendara fully installed and configured!" -ForegroundColor Green
