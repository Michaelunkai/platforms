<#
.SYNOPSIS
    superf4
#>
#--- Define the path and working directory for SuperF4 ---
    $exePath = "F:\backup\windowsapps\installed\SuperF4\SuperF4.exe"
    $exeWD = "F:\backup\windowsapps\installed\SuperF4"
    #--- Create Logon Trigger ---
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    #--- Create Principal with current user, interactive logon, highest privileges ---
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
    #--- Settings: No time limit, allow on battery, run when available ---
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries -RunOnlyIfNetworkAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)
    #--- Action: Launch SuperF4 hidden, minimized ---
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -Command `"Start-Process -FilePath '$exePath' -WorkingDirectory '$exeWD' -WindowStyle Minimized`"" -WorkingDirectory $exeWD
    #--- Register the task ---
    Register-ScheduledTask -TaskName "Start_SuperF4" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force
    #--- Run the app immediately ---
    Start-Process -FilePath $exePath -WorkingDirectory $exeWD -WindowStyle Minimized
    Write-Output "? SuperF4 has been added to startup and launched immediately."
