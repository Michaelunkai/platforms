<#
.SYNOPSIS
    getcho - PowerShell utility script
.NOTES
    Original function: getcho
    Extracted: 2026-02-19 20:20
#>
# Allow script execution
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    # Check if Chocolatey exists
    if (-not (Get-Command choco.exe -ErrorAction SilentlyContinue)) {
        Write-Host "Chocolatey not found or broken. Attempting a clean install..."
        # Clean up previous broken Chocolatey installation
        if (Test-Path "C:\ProgramData\chocolatey") {
            try {
                Rename-Item "C:\ProgramData\chocolatey" "C:\ProgramData\chocolatey_backup_$(Get-Date -Format yyyyMMdd_HHmmss)" -Force
            } catch {
                Remove-Item "C:\ProgramData\chocolatey" -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        # Install Chocolatey
        iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        # Ensure choco is available
        $chocoPath = "$env:ALLUSERSPROFILE\chocolatey\bin"
        if ($env:PATH -notlike "*$chocoPath*") {
            $env:PATH += ";$chocoPath"
        }
    } else {
        Write-Host "Chocolatey is already installed."
    }
    # Install packages with force
    choco install nano git -y --force
    # Ensure Git is on PATH
    $gitPath = "C:\Program Files\Git\cmd"
    if (Test-Path $gitPath -and $env:PATH -notlike "*$gitPath*") {
        $env:PATH += ";$gitPath"
    }
    Write-Host "Chocolatey and packages installed successfully."
