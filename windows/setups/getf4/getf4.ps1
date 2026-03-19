<#
.SYNOPSIS
    getf4
#>
$super4fExe = "F:\backup\windowsapps\installed\SuperF4\SuperF4.exe"
    $super4fWD = "F:\backup\windowsapps\installed\SuperF4"
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries -RunOnlyIfNetworkAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -Command `"Start-Process -FilePath '$super4fExe' -WorkingDirectory '$super4fWD' -WindowStyle Minimized`"" -WorkingDirectory $super4fWD
    Register-ScheduledTask -TaskName "Start_SuperF4" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force
    Write-Output "Startup task for SuperF4 has been registered."
