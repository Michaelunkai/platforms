<#
.SYNOPSIS
    Creates a desktop shortcut for the organization removal tool

.DESCRIPTION
    Creates a right-click-to-run-as-admin shortcut on your desktop
#>

$desktopPath = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktopPath "Remove Organization Control.lnk"
$targetPath = "F:\study\Platforms\windows\scripts\organization-removal\QUICK-RUN.ps1"

$WScriptShell = New-Object -ComObject WScript.Shell
$Shortcut = $WScriptShell.CreateShortcut($shortcutPath)
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$targetPath`""
$Shortcut.WorkingDirectory = "F:\study\Platforms\windows\scripts\organization-removal"
$Shortcut.Description = "Remove organizational control from Windows"
$Shortcut.IconLocation = "shell32.dll,47"  # Shield icon
$Shortcut.Save()

Write-Host "✅ Desktop shortcut created!" -ForegroundColor Green
Write-Host "`nLocation: $shortcutPath" -ForegroundColor Cyan
Write-Host "`nRight-click the shortcut and select 'Run as administrator'" -ForegroundColor Yellow
