# Windows System Error and Warning Log Collector
# Run as Administrator for best results

$outputFile = Join-Path $PSScriptRoot "a.txt"
$startTime = Get-Date

Write-Host "Starting comprehensive system log collection..." -ForegroundColor Green
Write-Host "Output file: $outputFile" -ForegroundColor Yellow

# Initialize output file
@"
===================================================================
WINDOWS SYSTEM ERROR AND WARNING LOG REPORT
Generated: $startTime
Computer: $env:COMPUTERNAME
User: $env:USERNAME
===================================================================

"@ | Out-File $outputFile -Encoding UTF8

function Write-Section {
    param([string]$Title)
    $separator = "`n" + "="*70 + "`n"
    $separator + $Title.ToUpper() + $separator | Out-File $outputFile -Append -Encoding UTF8
}

function Write-Log {
    param([string]$Message)
    $Message | Out-File $outputFile -Append -Encoding UTF8
    Write-Host $Message
}

# 1. Windows Event Logs - System Errors and Warnings
Write-Section "Windows Event Log - System (Errors & Warnings)"
Write-Host "Collecting System event logs..." -ForegroundColor Cyan
try {
    $systemLogs = Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2,3; StartTime=(Get-Date).AddDays(-7)} -ErrorAction SilentlyContinue | Select-Object -First 100
    if ($systemLogs) {
        foreach ($log in $systemLogs) {
            Write-Log ("[{0}] [{1}] {2}" -f $log.TimeCreated, $log.LevelDisplayName, $log.Message)
            Write-Log ("Source: {0} | Event ID: {1}`n" -f $log.ProviderName, $log.Id)
        }
    } else {
        Write-Log "No system errors or warnings found in the last 7 days."
    }
} catch {
    Write-Log "Error accessing System event log: $_"
}

# 2. Windows Event Logs - Application Errors and Warnings
Write-Section "Windows Event Log - Application (Errors & Warnings)"
Write-Host "Collecting Application event logs..." -ForegroundColor Cyan
try {
    $appLogs = Get-WinEvent -FilterHashtable @{LogName='Application'; Level=1,2,3; StartTime=(Get-Date).AddDays(-7)} -ErrorAction SilentlyContinue | Select-Object -First 100
    if ($appLogs) {
        foreach ($log in $appLogs) {
            Write-Log ("[{0}] [{1}] {2}" -f $log.TimeCreated, $log.LevelDisplayName, $log.Message)
            Write-Log ("Source: {0} | Event ID: {1}`n" -f $log.ProviderName, $log.Id)
        }
    } else {
        Write-Log "No application errors or warnings found in the last 7 days."
    }
} catch {
    Write-Log "Error accessing Application event log: $_"
}

# 3. Windows Update Errors
Write-Section "Windows Update Errors"
Write-Host "Collecting Windows Update logs..." -ForegroundColor Cyan
try {
    $updateLogs = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WindowsUpdateClient'; Level=1,2,3; StartTime=(Get-Date).AddDays(-30)} -ErrorAction SilentlyContinue
    if ($updateLogs) {
        foreach ($log in $updateLogs) {
            Write-Log ("[{0}] {1}" -f $log.TimeCreated, $log.Message)
        }
    } else {
        Write-Log "No Windows Update errors found in the last 30 days."
    }
} catch {
    Write-Log "Error accessing Windows Update logs: $_"
}

# 4. Disk Errors (CHKDSK)
Write-Section "Disk Errors and Warnings"
Write-Host "Collecting disk error logs..." -ForegroundColor Cyan
try {
    $diskLogs = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Ntfs','Disk'; Level=1,2,3; StartTime=(Get-Date).AddDays(-30)} -ErrorAction SilentlyContinue
    if ($diskLogs) {
        foreach ($log in $diskLogs) {
            Write-Log ("[{0}] [{1}] {2}" -f $log.TimeCreated, $log.ProviderName, $log.Message)
        }
    } else {
        Write-Log "No disk errors found in the last 30 days."
    }
} catch {
    Write-Log "Error accessing disk logs: $_"
}

# 5. Blue Screen of Death (BSOD) Events
Write-Section "Critical System Failures (BSOD Events)"
Write-Host "Checking for system crashes..." -ForegroundColor Cyan
try {
    $crashLogs = Get-WinEvent -FilterHashtable @{LogName='System'; ID=1001,1003,41; StartTime=(Get-Date).AddDays(-30)} -ErrorAction SilentlyContinue
    if ($crashLogs) {
        foreach ($log in $crashLogs) {
            Write-Log ("[{0}] System Crash/Critical Error Detected" -f $log.TimeCreated)
            Write-Log $log.Message
            Write-Log ""
        }
    } else {
        Write-Log "No system crashes detected in the last 30 days."
    }
} catch {
    Write-Log "Error checking for system crashes: $_"
}

# 6. Hardware Errors
Write-Section "Hardware-Related Errors"
Write-Host "Collecting hardware error logs..." -ForegroundColor Cyan
try {
    $hardwareLogs = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-Power','Microsoft-Windows-Kernel-PnP'; Level=1,2,3; StartTime=(Get-Date).AddDays(-30)} -ErrorAction SilentlyContinue
    if ($hardwareLogs) {
        foreach ($log in $hardwareLogs) {
            Write-Log ("[{0}] [{1}] {2}" -f $log.TimeCreated, $log.ProviderName, $log.Message)
        }
    } else {
        Write-Log "No hardware errors found in the last 30 days."
    }
} catch {
    Write-Log "Error accessing hardware logs: $_"
}

# 7. Security Log - Failed Logon Attempts
Write-Section "Security - Failed Logon Attempts"
Write-Host "Collecting security logs..." -ForegroundColor Cyan
try {
    $securityLogs = Get-WinEvent -FilterHashtable @{LogName='Security'; ID=4625; StartTime=(Get-Date).AddDays(-7)} -ErrorAction SilentlyContinue | Select-Object -First 50
    if ($securityLogs) {
        foreach ($log in $securityLogs) {
            Write-Log ("[{0}] Failed Logon Attempt" -f $log.TimeCreated)
            Write-Log $log.Message
            Write-Log ""
        }
    } else {
        Write-Log "No failed logon attempts found in the last 7 days."
    }
} catch {
    Write-Log "Error accessing Security logs (may require Administrator privileges): $_"
}

# 8. Driver Installation Issues
Write-Section "Driver Installation Errors"
Write-Host "Collecting driver error logs..." -ForegroundColor Cyan
try {
    $driverLogs = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-DeviceSetupManager','Microsoft-Windows-DriverFrameworks-UserMode'; Level=1,2,3; StartTime=(Get-Date).AddDays(-30)} -ErrorAction SilentlyContinue
    if ($driverLogs) {
        foreach ($log in $driverLogs) {
            Write-Log ("[{0}] {1}" -f $log.TimeCreated, $log.Message)
        }
    } else {
        Write-Log "No driver installation errors found in the last 30 days."
    }
} catch {
    Write-Log "Error accessing driver logs: $_"
}

# 9. Service Failures
Write-Section "Service Start/Stop Failures"
Write-Host "Collecting service failure logs..." -ForegroundColor Cyan
try {
    $serviceLogs = Get-WinEvent -FilterHashtable @{LogName='System'; ID=7000,7001,7022,7023,7024,7026,7031,7032,7034; StartTime=(Get-Date).AddDays(-7)} -ErrorAction SilentlyContinue
    if ($serviceLogs) {
        foreach ($log in $serviceLogs) {
            Write-Log ("[{0}] {1}" -f $log.TimeCreated, $log.Message)
        }
    } else {
        Write-Log "No service failures found in the last 7 days."
    }
} catch {
    Write-Log "Error accessing service logs: $_"
}

# 10. Windows Defender/Security Alerts
Write-Section "Windows Defender Alerts"
Write-Host "Collecting Windows Defender logs..." -ForegroundColor Cyan
try {
    $defenderLogs = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Windows Defender/Operational'; Level=1,2,3; StartTime=(Get-Date).AddDays(-30)} -ErrorAction SilentlyContinue | Select-Object -First 50
    if ($defenderLogs) {
        foreach ($log in $defenderLogs) {
            Write-Log ("[{0}] [{1}] {2}" -f $log.TimeCreated, $log.LevelDisplayName, $log.Message)
        }
    } else {
        Write-Log "No Windows Defender alerts found in the last 30 days."
    }
} catch {
    Write-Log "Error accessing Windows Defender logs: $_"
}

# 11. Check Disk Space Issues
Write-Section "Disk Space Analysis"
Write-Host "Analyzing disk space..." -ForegroundColor Cyan
try {
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null }
    foreach ($drive in $drives) {
        $percentFree = [math]::Round(($drive.Free / ($drive.Used + $drive.Free)) * 100, 2)
        $status = if ($percentFree -lt 10) { "CRITICAL - LOW SPACE" } elseif ($percentFree -lt 20) { "WARNING" } else { "OK" }
        Write-Log ("Drive {0}: {1}% free - {2:N2} GB free of {3:N2} GB - Status: {4}" -f $drive.Name, $percentFree, ($drive.Free/1GB), (($drive.Used + $drive.Free)/1GB), $status)
    }
} catch {
    Write-Log "Error checking disk space: $_"
}

# 12. Network Errors
Write-Section "Network-Related Errors"
Write-Host "Collecting network error logs..." -ForegroundColor Cyan
try {
    $networkLogs = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Tcpip','Dhcp-Client','DNS-Client'; Level=1,2,3; StartTime=(Get-Date).AddDays(-7)} -ErrorAction SilentlyContinue
    if ($networkLogs) {
        foreach ($log in $networkLogs) {
            Write-Log ("[{0}] [{1}] {2}" -f $log.TimeCreated, $log.ProviderName, $log.Message)
        }
    } else {
        Write-Log "No network errors found in the last 7 days."
    }
} catch {
    Write-Log "Error accessing network logs: $_"
}

# 13. Recently Installed Programs (potential issues)
Write-Section "Recently Installed Software (Last 30 Days)"
Write-Host "Listing recently installed software..." -ForegroundColor Cyan
try {
    $installLogs = Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='MsiInstaller'; StartTime=(Get-Date).AddDays(-30)} -ErrorAction SilentlyContinue | Select-Object -First 30
    if ($installLogs) {
        foreach ($log in $installLogs) {
            Write-Log ("[{0}] {1}" -f $log.TimeCreated, $log.Message)
        }
    } else {
        Write-Log "No software installation logs found in the last 30 days."
    }
} catch {
    Write-Log "Error accessing installation logs: $_"
}

# Final Summary
Write-Section "Collection Complete"
$endTime = Get-Date
$duration = $endTime - $startTime
Write-Log "Report generated: $endTime"
Write-Log "Collection duration: $($duration.TotalSeconds) seconds"
Write-Log "`nReport saved to: $outputFile"

Write-Host "`n====================================================================" -ForegroundColor Green
Write-Host "Log collection complete!" -ForegroundColor Green
Write-Host "Report saved to: $outputFile" -ForegroundColor Yellow
Write-Host "====================================================================" -ForegroundColor Green
