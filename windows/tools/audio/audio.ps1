<#
.SYNOPSIS
    audio
#>
# Import the AudioDeviceCmdlets module, forcefully to ensure it's loaded
    Import-Module AudioDeviceCmdlets -Force
    # Attempt to retrieve the playback device named 'Speakers (Realtek(R) Audio)'
    # Adjust the matching pattern as needed for flexibility
    $desiredDevice = Get-AudioDevice -Playback | Where-Object { $_.Name -like '*Realtek*' } | Select-Object -First 1
    if ($desiredDevice) {
        try {
            # Attempt to set the audio device using its ID
            Set-AudioDevice -Id $desiredDevice.Id
            Write-Output "Switched audio output to: $($desiredDevice.Name)" -ForegroundColor Green
        }
        catch {
            Write-Output "Failed to set audio device. Error: $_" -ForegroundColor Red
        }
    }
    else {
        Write-Output "Could not find a playback device containing 'Realtek' in its name." -ForegroundColor Yellow
        Write-Output "Available playback devices:" -ForegroundColor Cyan
        try {
            # List all available playback devices
            Get-AudioDevice -Playback | ForEach-Object { Write-Output " - $($_.Name)" }
        }
        catch {
            Write-Output "Failed to retrieve playback devices. Error: $_" -ForegroundColor Red
        }
    }
