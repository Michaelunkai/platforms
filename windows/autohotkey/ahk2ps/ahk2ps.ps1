<#
.SYNOPSIS
    ahk2ps
#>
param([string]$ahkPath)
    if (-not (Test-Path $ahkPath)) {
        Write-Output "? AHK file does not exist: $ahkPath" -ForegroundColor Red
        return
    }
    $ps1Path = [System.IO.Path]::ChangeExtension($ahkPath, ".ps1")
    $ahkContent = Get-Content $ahkPath | Where-Object { $_ -match '^Run,' }
    if (-not $ahkContent) {
        Write-Output "? No 'Run,' line found in the AHK file." -ForegroundColor Red
        return
    }
    $commandLine = $ahkContent -replace '^Run,\s*', ''
    $commandLine = $commandLine -replace '`"', '"'  # Unescape quotes if present
    $ps1Content = "Start-Process $commandLine"
    $ps1Content | Out-File -FilePath $ps1Path -Encoding UTF8
    Write-Output "? PS1 created: $ps1Path" -ForegroundColor Green
