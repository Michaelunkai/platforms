<#
.SYNOPSIS
    gpipx - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
$ErrorActionPreference="SilentlyContinue"; winget install Python.Python.3.12 --accept-package-agreements --accept-source-agreements --silent; python -m ensurepip --upgrade; python -m pip install --upgrade pip; python -m pip install --upgrade pipx; python -m pipx ensurepath; $env:PATH += ";$([Environment]::GetEnvironmentVariable('PATH','Machine'))"; pipx --version
