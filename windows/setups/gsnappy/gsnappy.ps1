<#
.SYNOPSIS
    gsnappy
#>
$sdioDir = "$env:TEMP\SDIO"
    $zipPath = "$env:TEMP\sdio.zip"
    Write-Host "Downloading SDIO..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri "https://www.glenn.delahoy.com/downloads/sdio/SDIO_1.17.2.823.zip" -OutFile $zipPath -UseBasicParsing
    if (Test-Path $sdioDir) { Remove-Item $sdioDir -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $sdioDir -Force
    Remove-Item $zipPath -Force
    $sdio = Get-ChildItem -Path $sdioDir -Recurse -Filter "SDIO_x64_R*.exe" | Select-Object -First 1
    if ($sdio) {
        Write-Host "Launching SDIO - downloading indexes, scanning, auto-installing all needed drivers..." -ForegroundColor Green
        Start-Process -FilePath $sdio.FullName -ArgumentList "-checkupdates -autoupdate -autoinstall" -WorkingDirectory $sdio.DirectoryName -Verb RunAs -WindowStyle Normal
    } else { Write-Host "SDIO exe not found" -ForegroundColor Red }
