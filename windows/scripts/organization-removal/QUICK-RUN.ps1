#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Quick launcher for organization control removal

.DESCRIPTION
    Simple wrapper that runs the full removal script from anywhere
#>

$scriptPath = "F:\study\Platforms\windows\scripts\organization-removal\Remove-OrganizationControl.ps1"

if (-not (Test-Path $scriptPath)) {
    Write-Host "ERROR: Script not found at $scriptPath" -ForegroundColor Red
    exit 1
}

Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  QUICK LAUNCHER: Organization Control Removal                ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

Write-Host "Choose an option:`n" -ForegroundColor Yellow
Write-Host "  [1] Remove everything (with confirmation)" -ForegroundColor White
Write-Host "  [2] Remove everything (no confirmation - YOLO mode)" -ForegroundColor White
Write-Host "  [3] Preview only (WhatIf - no changes)" -ForegroundColor White
Write-Host "  [4] Cancel`n" -ForegroundColor White

$choice = Read-Host "Enter choice (1-4)"

switch ($choice) {
    "1" {
        Write-Host "`nRunning interactive mode...`n" -ForegroundColor Green
        & $scriptPath
    }
    "2" {
        Write-Host "`nRunning FORCE mode (no confirmations)...`n" -ForegroundColor Red
        & $scriptPath -Force
    }
    "3" {
        Write-Host "`nRunning WhatIf mode (preview only)...`n" -ForegroundColor Cyan
        & $scriptPath -WhatIf
    }
    "4" {
        Write-Host "`nCancelled.`n" -ForegroundColor Yellow
        exit 0
    }
    default {
        Write-Host "`nInvalid choice. Cancelled.`n" -ForegroundColor Red
        exit 1
    }
}
