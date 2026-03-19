<#
.SYNOPSIS
    fixmic
#>
$pythonPath = "C:\Users\micha\AppData\Local\Programs\Python\Python312\python.exe"
    if (Test-Path $pythonPath) {
        & $pythonPath "F:\study\shells\powershell\scripts\Microphone\mic.py"
    } else {
        Write-Host "Python not found at: $pythonPath" -ForegroundColor Red
        Write-Host "Trying 'python' command..." -ForegroundColor Yellow
        python "F:\study\shells\powershell\scripts\Microphone\mic.py"
    }
