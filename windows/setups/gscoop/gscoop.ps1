<#
.SYNOPSIS
    gscoop - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force ; iex "& {$(irm get.scoop.sh)} -RunAsAdmin -ScoopDir 'F:\backup\windowsapps\installed\scoop' -ScoopGlobalDir 'F:\backup\windowsapps\installed\global'" ; scoop install git -g ; scoop bucket add scoop-apps https://github.com/Ash258/Scoop-Ash258 ; scoop install scoop-apps -g
