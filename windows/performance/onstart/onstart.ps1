<#
.SYNOPSIS
    onstart
#>
# Register ANY file to run SILENTLY at Windows startup
    # Usage: onstart "C:\path\to\anything.ext" "D:\path\to\script.ahk"
    # Stop mode: onstart "STOP:C:\path\to\app.exe"
    param([Parameter(Mandatory=$true, Position=0, ValueFromRemainingArguments=$true)][string[]]$FilePaths)
    
    $ahkPath = "C:\Program Files\AutoHotkey\v2\AutoHotkey.exe"
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $wrappersDir = "$env:USERPROFILE\.openclaw\startup-wrappers"
    
    if (-not (Test-Path $wrappersDir)) {
        New-Item -ItemType Directory -Path $wrappersDir -Force | Out-Null
    }
    
    foreach ($path in $FilePaths) {
        $isStopTask = $path -match "^STOP:"
        $cleanPath = $path -replace "^STOP:", ""
        
        if (-not (Test-Path $cleanPath)) {
            Write-Warning "Path not found: $cleanPath - Skipping."
            continue
        }
        
        $ext = [System.IO.Path]::GetExtension($cleanPath).ToLower()
        $appName = [System.IO.Path]::GetFileNameWithoutExtension($cleanPath)
        $appDir = [System.IO.Path]::GetDirectoryName($cleanPath)
        
        if ($isStopTask) {
            $taskName = "FastStop_$appName"
            $stopScript = "Stop-Process -Name '$appName' -Force -ErrorAction SilentlyContinue"
            $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"$stopScript`""
            $trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
            $trigger.Delay = "PT5S"
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Seconds 30) -Priority 0 -StartWhenAvailable
            $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
            try {
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
                Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
                Write-Host "'$appName' configured to STOP at startup (Task: $taskName)" -ForegroundColor Yellow
            } catch {
                Write-Error "Failed to create stop task for '$appName': $_"
            }
        } else {
            $taskName = "FastStartup_$appName"
            $usePersistentWrapper = $false
            $execPath = ""
            $arguments = ""
            
            # ALL file types run through hidden PowerShell - ZERO terminal popups guaranteed
            switch ($ext) {
                ".vbs" { $execPath = "powershell.exe"; $arguments = "-NoProfile -WindowStyle Hidden -Command `"Start-Process -FilePath 'wscript.exe' -ArgumentList '//B `"`"$cleanPath`"`"' -WindowStyle Hidden`"" }
                ".bat" { $execPath = "powershell.exe"; $arguments = "-NoProfile -WindowStyle Hidden -Command `"Start-Process -FilePath 'cmd.exe' -ArgumentList '/c `"`"$cleanPath`"`"' -WindowStyle Hidden`"" }
                ".cmd" { $execPath = "powershell.exe"; $arguments = "-NoProfile -WindowStyle Hidden -Command `"Start-Process -FilePath 'cmd.exe' -ArgumentList '/c `"`"$cleanPath`"`"' -WindowStyle Hidden`"" }
                ".ps1" { $execPath = "powershell.exe"; $arguments = "-NoProfile -WindowStyle Hidden -Command `"Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"`"$cleanPath`"`"' -WindowStyle Hidden`"" }
                ".ahk" {
                    if (-not (Test-Path $ahkPath)) {
                        Write-Warning "AutoHotkey not found at '$ahkPath' - skipping"
                        continue
                    }
                    $execPath = "powershell.exe"
                    $arguments = "-NoProfile -WindowStyle Hidden -Command `"Start-Process -FilePath '$ahkPath' -ArgumentList '`"`"$cleanPath`"`"' -WindowStyle Hidden`""
                }
                ".py" { $execPath = "powershell.exe"; $arguments = "-NoProfile -WindowStyle Hidden -Command `"Start-Process -FilePath 'python' -ArgumentList '`"`"$cleanPath`"`"' -WindowStyle Hidden`"" }
                ".js" { $execPath = "powershell.exe"; $arguments = "-NoProfile -WindowStyle Hidden -Command `"Start-Process -FilePath 'node' -ArgumentList '`"`"$cleanPath`"`"' -WindowStyle Hidden`"" }
                ".exe" { $usePersistentWrapper = $true }
                ".lnk" { $execPath = "powershell.exe"; $arguments = "-NoProfile -WindowStyle Hidden -Command `"Start-Process -FilePath '$cleanPath' -WindowStyle Hidden`"" }
                ".url" { $execPath = "powershell.exe"; $arguments = "-NoProfile -WindowStyle Hidden -Command `"Start-Process -FilePath '$cleanPath' -WindowStyle Hidden`"" }
                ".msi" { $execPath = "powershell.exe"; $arguments = "-NoProfile -WindowStyle Hidden -Command `"Start-Process -FilePath 'msiexec.exe' -ArgumentList '/i `"`"$cleanPath`"`" /quiet' -WindowStyle Hidden`"" }
                default { $execPath = "powershell.exe"; $arguments = "-NoProfile -WindowStyle Hidden -Command `"Start-Process -FilePath '$cleanPath' -WindowStyle Hidden`"" }
            }
            
            if ($usePersistentWrapper) {
                $wrapperPath = "$wrappersDir\$appName`_persistent.ps1"
                $wrapperContent = @"
`$ErrorActionPreference = 'SilentlyContinue'
while (`$true) {
    if (-not (Get-Process -Name '$appName' -ErrorAction SilentlyContinue)) {
        Start-Process -FilePath "$cleanPath" -WorkingDirectory "$appDir" -WindowStyle Hidden
    }
    Start-Sleep -Seconds 30
}
"@
                Set-Content -Path $wrapperPath -Value $wrapperContent -Force
                $execPath = "powershell.exe"
                $arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$wrapperPath`""
                Write-Host "'$appName' ($ext) configured for PERSISTENT startup (Task: $taskName)" -ForegroundColor Green
                Write-Host "  Wrapper: $wrapperPath" -ForegroundColor DarkGray
            } else {
                Write-Host "'$appName' ($ext) configured for startup (Task: $taskName)" -ForegroundColor Green
            }
            
            $action = New-ScheduledTaskAction -Execute $execPath -Argument $arguments -WorkingDirectory $appDir
            $trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
            $trigger.Delay = "PT0S"
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -Priority 0 -StartWhenAvailable -DontStopOnIdleEnd
            $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
            try {
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
                Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
            } catch {
                Write-Error "Failed to create startup task for '$appName': $_"
            }
        }
    }
