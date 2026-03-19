<#
.SYNOPSIS
    liststart
#>
<#
    .SYNOPSIS
        Lists all applications configured to run at Windows startup.
    .DESCRIPTION
        Shows all startup items from both Task Scheduler (FastStartup_* tasks) and Registry.
        Displays task name, executable path, and arguments for each item.
    .EXAMPLE
        liststart
    #>
    Write-Host "`n=== STARTUP ITEMS (Task Scheduler) ===" -ForegroundColor Cyan
    $tasks = Get-ScheduledTask -TaskName "FastStartup_*" -ErrorAction SilentlyContinue
    if ($tasks) {
        foreach ($task in $tasks) {
            $appName = $task.TaskName -replace "^FastStartup_", ""
            $action = $task.Actions[0]
            $exe = $action.Execute
            $args = $action.Arguments
            Write-Host "  [TASK] $appName" -ForegroundColor Green
            Write-Host "         $exe $args" -ForegroundColor Gray
        }
    } else {
        Write-Host "  (No Task Scheduler startup items found)" -ForegroundColor Gray
    }
    Write-Host "`n=== STARTUP ITEMS (Registry) ===" -ForegroundColor Cyan
    $registryPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    $regItems = Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue
    if ($regItems) {
        $startupNames = $regItems.PSObject.Properties |
                        Where-Object { $_.Name -ne "PSPath" -and $_.Name -ne "PSParentPath" -and
                                      $_.Name -ne "PSChildName" -and $_.Name -ne "PSDrive" -and
                                      $_.Name -ne "PSProvider" } |
                        Select-Object Name, Value
        if ($startupNames) {
            foreach ($item in $startupNames) {
                Write-Host "  [REG]  $($item.Name)" -ForegroundColor Yellow
                Write-Host "         $($item.Value)" -ForegroundColor Gray
            }
        } else {
            Write-Host "  (No Registry startup items found)" -ForegroundColor Gray
        }
    } else {
        Write-Host "  (No Registry startup items found)" -ForegroundColor Gray
    }
    Write-Host ""
