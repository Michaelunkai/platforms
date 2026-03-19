<#
.SYNOPSIS
    short2 - PowerShell utility script
.NOTES
    Original function: short2
    Extracted: 2026-02-19 20:20
#>
# Get taskbar apps
    $taskbarApps = @()
    $shell = New-Object -ComObject Shell.Application
    $taskbarFolder = $shell.Namespace("shell:::{4234d49b-0245-4df3-b780-3893943456e1}")
    if ($taskbarFolder) {
        $taskbarApps = $taskbarFolder.Items() | ForEach-Object { $_.Name -replace '\.lnk$', '' }
    }
    Get-ChildItem -Path "F:\backup\windowsapps\installed" -Directory | ForEach-Object {
        $folder = $_
        $folderName = $folder.Name
        # Skip if name contains forbidden words
        if ($folderName -match "handle") {
            return
        }
        # Only process folders that contain shortcuts
        $shortcuts = Get-ChildItem -Path $folder.FullName -Filter "*.lnk"
        if (-not $shortcuts) {
            return
        }
        # Skip if shortcut already exists on desktop
        $newShortcutName = "$folderName.lnk"
        $destinationPath = Join-Path $([Environment]::GetFolderPath('Desktop')) $newShortcutName
        if (Test-Path $destinationPath) {
            return
        }
        # Skip if app is already in taskbar
        if ($taskbarApps -contains $folderName) {
            return
        }
        $firstShortcut = $shortcuts | Select-Object -First 1
        # Copy the shortcut - let Windows handle icon display
        Copy-Item $firstShortcut.FullName -Destination $destinationPath
    }
