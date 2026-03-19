<#
.SYNOPSIS
    android
#>
param(
        [Parameter(ValueFromRemainingArguments=$true)]
        [string[]]$Command
    )
    
    $statePath = "C:\Users\micha\.openclaw\workspace\android-state.json"
    
    # Check connection state
    if (Test-Path $statePath) {
        $state = Get-Content $statePath | ConvertFrom-Json
        if ($state.status -ne "connected") {
            Write-Host "âš ï¸ Android not connected. Last check: $($state.lastCheck)"
            Write-Host "[RELOAD] Attempting reconnect..."
            
            # Try quick reconnect
            adb devices | Out-Null
            Start-Sleep -Seconds 1
            
            $test = adb devices | Select-String -Pattern "device$"
            if (-not $test) {
                Write-Host "[X] Connection failed. Check android-monitor.ps1 status."
                return
            }
        }
    }
    
    # Execute command
    $fullCommand = "adb $($Command -join ' ')"
    Write-Host "[PHONE] Running: $fullCommand"
    
    try {
        Invoke-Expression $fullCommand
    } catch {
        Write-Host "[X] Error: $_"
    }
