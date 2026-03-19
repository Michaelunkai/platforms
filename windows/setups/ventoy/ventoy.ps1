<#
.SYNOPSIS
    ventoy
#>
$u='https://github.com/ventoy/Ventoy/releases/download/v1.1.05/ventoy-1.1.05-windows.zip';$n='Ventoy';$d='F:\Downloads';$i='F:\backup\windowsapps\installed';$z=Join-Path $d ($n+'.zip');$f=Join-Path $i $n;Write-Host "Downloading $n...";Invoke-WebRequest -Uri $u -OutFile $z -UseBasicParsing;Write-Host "Extracting to $f...";New-Item -ItemType Directory -Path $f -Force|Out-Null;Expand-Archive -Path $z -DestinationPath $f -Force;$exe=(Get-ChildItem $f -Filter 'Ventoy2Disk.exe' -Recurse|Select-Object -First 1).FullName;if($exe){Start-Process $exe;Write-Host "SUCCESS: $n running from $exe"}else{Write-Host "FAILED"}
