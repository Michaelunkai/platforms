<#
.SYNOPSIS
    walls - PowerShell utility script
.NOTES
    Original function: walls
    Extracted: 2026-02-19 20:20
#>
# ----- CONSTANTS ---------------------------------------------------------
    $taskName   = 'AutoWallpaperGames'
    $workingDir = 'F:\study\Dev_Toolchain\programming\python\apps\wallpapers\changeWallPaperAutomatically\gamesonly'
    $scriptArg  = 'a.py'
    # Locate python3.exe explicitly
    try {
        $pythonExe = (Get-Command python3.exe -ErrorAction Stop).Source
    } catch {
        Write-Error "?  python3.exe not found in PATH. Add it or install Python 3, then re-run."
        return
    }
    # Remove any stale task
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
    # Build the new Scheduled Task
    $action   = New-ScheduledTaskAction  -Execute $pythonExe `
                                         -Argument $scriptArg `
                                         -WorkingDirectory $workingDir
    $trigger  = New-ScheduledTaskTrigger -AtLogOn          # current user
    $settings = New-ScheduledTaskSettingsSet `
                   -AllowStartIfOnBatteries `
                   -DontStopOnIdleEnd `
                   -Compatibility Win10   # works fine on Windows 11
    Register-ScheduledTask -TaskName  $taskName `
                           -Action    $action `
                           -Trigger   $trigger `
                           -Settings  $settings `
                           -Description 'Changes wallpaper (games only) at every user log-on.' `
                           -RunLevel  LeastPrivilege > $null
    Write-Output "?  '$taskName' scheduled with $pythonExe. Sign out/in or reboot to test." -ForegroundColor Green
