<#
.SYNOPSIS
    getvc - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
winget install --id abbodi1406.vcredist --silent --accept-source-agreements --force; Write-Host "All VC++ Redistributables installed via AIO installer!" -ForegroundColor Green
