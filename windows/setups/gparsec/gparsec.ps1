<#
.SYNOPSIS
    gparsec - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
$dest='F:\backup\windowsapps\installed\parsec'; $zip ="$env:TEMP\parsec.zip"; temp download Invoke-WebRequest 'https://builds.parsec.app/package/parsec-flat-windows.zip' -OutFile $zip; `Remove-Item $dest -Recurse -Force ErrorAction SilentlyContinue; `Expand-Archive $zip -DestinationPath $dest -Force; ` Remove-Item $zip; ` $exe = (Get-ChildItem $dest -Recurse -Filter parsecd.exe -ErrorAction Stop)[0].FullName; `
Start-Process $exe
