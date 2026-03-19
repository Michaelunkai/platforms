<#
.SYNOPSIS
    asus - PowerShell utility script
.DESCRIPTION
    Extracted from PowerShell profile for modular organization
.NOTES
    Original function: asus
    Location: F:\study\Platforms\windows\tools\asus-tools\asus.ps1
    Extracted: 2026-02-19 20:05
#>
param()
    <#
      .SYNOPSIS
        Uninstalls any currently-installed ASUS drivers/utilities that match each
        installer found under F:\backup\windowsapps\install\Asus, then installs
        the new packages silently and without a reboot.
      .NOTES
          Run from an elevated PowerShell session.
          Handles .exe (Inno/NSIS/InstallShield/Squirrel) and .msi installers.
    #>
    param(
        [string]$Source = 'F:\backup\windowsapps\install\Asus'   # ? new default path
    )
    #----- find every installer (.exe / .msi) in the source tree -----
    Get-ChildItem -Path $Source -Recurse -File |
        Where-Object { $_.Extension -match '^(?i)\.(exe|msi)$' } |
        ForEach-Object {
            $installer   = $_
            $baseName    = $installer.BaseName
            Write-Host "`n=== Processing $($installer.Name) ===" -ForegroundColor Cyan
            #--- 1) remove matching Plug-and-Play driver packages (pnputil) ----
            $pn = $prov = $disp = $null
            foreach ($line in (pnputil /enum-drivers)) {
                if     ($line -match '^Published Name\s*:\s*(oem\d+\.inf)') { $pn   = $Matches[1] }
                elseif ($line -match '^Driver Package Provider\s*:\s*(.+)')  { $prov = $Matches[1].Trim() }
                elseif ($line -match '^Driver Package Display Name\s*:\s*(.+)'){ $disp = $Matches[1].Trim() }
                elseif ([string]::IsNullOrWhiteSpace($line)) {
                    if ($disp -like "*$baseName*" -or $prov -like '*ASUS*') {
                        Write-Host "Removing driver package $pn ($disp)" -ForegroundColor Yellow
                        pnputil /delete-driver $pn /uninstall /force /reboot:never | Out-Null
                    }
                    $pn = $prov = $disp = $null
                }
            }
            #--- 2) remove matching software via its UninstallString (registry) -
            $uninstRoots = @(
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
            )
            foreach ($root in $uninstRoots) {
                Get-ItemProperty $root -ErrorAction SilentlyContinue |
                    Where-Object { $_.DisplayName -like "*$baseName*" } |
                    Select-Object -First 1 |
                    ForEach-Object {
                        $cmd = $_.UninstallString
                        if ($cmd) {
                            Write-Host "Uninstalling $_.DisplayName" -ForegroundColor Yellow
                            Start-Process cmd.exe -ArgumentList '/c', $cmd, '/quiet', '/norestart' -Wait
                        }
                    }
            }
            #--- 3) install the new package silently ---------------------------
            if ($installer.Extension -ieq '.msi') {
                Write-Host "Installing (MSI)..." -ForegroundColor Green
                Start-Process msiexec.exe -ArgumentList "/i `"$($installer.FullName)`" /qn /norestart" -Wait
            } else {
                Write-Host "Installing (EXE)..." -ForegroundColor Green
                Start-Process $installer.FullName -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-' -Wait
            }
        }
    Write-Host "`nAll ASUS packages processed." -ForegroundColor Cyan
