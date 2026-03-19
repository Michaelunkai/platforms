<#
.SYNOPSIS
    stopstart
#>
<#
    .SYNOPSIS
        Removes applications from Windows startup that were added by the onstart function.
    .DESCRIPTION
        This function removes Task Scheduler tasks created by onstart.
        If no parameters are provided, it lists all FastStartup tasks and allows selection.
    .PARAMETER AppNames
        Optional. Names or paths of applications to remove from startup.
        If providing a full path, the function will extract just the application name.
        If no names are provided, the function will list all startup tasks for selection.
    .PARAMETER All
        Switch to remove all FastStartup tasks.
    .EXAMPLE
        stopstart "fix-wifi-autoconnect" "GHelper"
    .EXAMPLE
        stopstart "F:\backup\windowsapps\installed\ghelper\GHelper.exe"
    .EXAMPLE
        stopstart -All
    .EXAMPLE
        stopstart
        # Lists all startup tasks and prompts for selection
    #>
    [CmdletBinding(DefaultParameterSetName='Names')]
    param (
        [Parameter(ParameterSetName='Names', Position=0, ValueFromRemainingArguments=$true)]
        [string[]]$AppNames,
        [Parameter(ParameterSetName='All')]
        [switch]$All
    )
    # Function to get clean app name from a full path or app name
    function Get-CleanAppName {
        param ([string]$AppNameOrPath)
        if ($AppNameOrPath -like "*.*" -and $AppNameOrPath -match "\\") {
            # It's likely a path, extract filename without extension
            return [System.IO.Path]::GetFileNameWithoutExtension($AppNameOrPath)
        }
        else {
            # It's likely just a name
            return $AppNameOrPath
        }
    }
    # Get all FastStartup tasks
    $allTasks = Get-ScheduledTask -TaskName "FastStartup_*" -ErrorAction SilentlyContinue
    if (-not $allTasks) {
        Write-Host "No startup tasks found." -ForegroundColor Yellow
        return
    }
    # If no parameters provided, show interactive selection
    if (-not $AppNames -and -not $All) {
        Write-Host "Current startup tasks:" -ForegroundColor Cyan
        for ($i=0; $i -lt $allTasks.Count; $i++) {
            $task = $allTasks[$i]
            $appName = $task.TaskName -replace "^FastStartup_", ""
            $action = $task.Actions[0].Execute + " " + $task.Actions[0].Arguments
            Write-Host "[$i] $appName - $action" -ForegroundColor White
        }
        Write-Host "Enter the numbers of items to remove (comma separated), 'all' for all items, or 'q' to quit:" -ForegroundColor Cyan
        $selection = Read-Host
        if ($selection -eq "q") {
            return
        }
        elseif ($selection -eq "all") {
            $All = $true
        }
        else {
            $selectedIndices = $selection -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -match "^\d+$" }
            $AppNames = $selectedIndices | ForEach-Object {
                $allTasks[$_].TaskName -replace "^FastStartup_", ""
            }
        }
    }
    # Process based on parameter set
    if ($All) {
        # Remove all FastStartup tasks
        foreach ($task in $allTasks) {
            try {
                Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false -ErrorAction Stop
                $appName = $task.TaskName -replace "^FastStartup_", ""
                Write-Host "? Removed '$appName' from startup." -ForegroundColor Green
            }
            catch {
                Write-Error "Failed to remove '$($task.TaskName)' from startup: $_"
            }
        }
    }
    else {
        # Process each specified app
        foreach ($appInput in $AppNames) {
            $appName = Get-CleanAppName -AppNameOrPath $appInput
            $taskName = "FastStartup_$appName"
            # Check if this task exists
            $task = $allTasks | Where-Object { $_.TaskName -eq $taskName }
            if ($task) {
                try {
                    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
                    Write-Host "? Removed '$appName' from startup." -ForegroundColor Green
                }
                catch {
                    Write-Error "Failed to remove '$appName' from startup: $_"
                }
            }
            else {
                Write-Warning "App '$appName' not found in startup tasks."
            }
        }
    }
