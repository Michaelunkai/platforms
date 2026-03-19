<#
.SYNOPSIS
    siz - PowerShell utility script
.DESCRIPTION
    Extracted from PowerShell profile for modular organization
.NOTES
    Original function: siz
    Location: F:\study\Platforms\windows\tools\size-calculator\siz.ps1
    Extracted: 2026-02-19 20:05
#>
param()
    Write-Host "=== KEY DISK SPACE USAGE ===" -ForegroundColor Cyan
    Write-Host ""

    # C drive - use fsutil for accurate values (bypasses Windows API caching bug)
    Write-Host "DRIVES:" -ForegroundColor Yellow
    $fsC = fsutil volume diskfree C: 2>$null
    $cTotal = [long]([regex]::Match($fsC, "Total bytes\s+:\s+([\d,]+)").Groups[1].Value -replace ",","")
    $cFree = [long]([regex]::Match($fsC, "Total free bytes\s+:\s+([\d,]+)").Groups[1].Value -replace ",","")
    $cUsed = [long]([regex]::Match($fsC, "Used bytes\s+:\s+([\d,]+)").Groups[1].Value -replace ",","")
    "C:  {0:N0}GB total, {1:N0}GB used, {2:N0}GB free ({3:N0}%)" -f ($cTotal/1GB),($cUsed/1GB),($cFree/1GB),(($cUsed/$cTotal)*100)
    # F drive
    $driveF = Get-PSDrive F -EA 0
    if($driveF){"F:  {0:N0}GB total, {1:N0}GB used, {2:N0}GB free ({3:N0}%)" -f (($driveF.Used+$driveF.Free)/1GB),($driveF.Used/1GB),($driveF.Free/1GB),(($driveF.Used/($driveF.Used+$driveF.Free))*100)}
    Write-Host ""

    # WSL2 distros
    Write-Host "WSL2 DISTROS:" -ForegroundColor Yellow
    @("C:\wsl2\ubuntu","C:\wsl2\ubuntu2") | % {
        if(Test-Path $_ -EA 0){
            $s = (gci $_ -R -Force -EA 0 | measure Length -Sum -EA 0).Sum
            if($s -gt 1MB){"{0,-20} {1:N2} GB" -f (Split-Path $_ -Leaf), ($s/1GB)}
        }
    }
    Write-Host ""

    # Docker VM
    Write-Host "DOCKER:" -ForegroundColor Yellow
    $dockerVm = "C:\ProgramData\DockerDesktop\vm-data\DockerDesktop.vhdx"
    if(Test-Path $dockerVm -EA 0){
        $s = (gi $dockerVm -Force -EA 0).Length
        "VM Data:             {0:N2} GB" -f ($s/1GB)
    }
    Write-Host ""

    # Pagefile, hiberfil, swapfile
    Write-Host "SYSTEM FILES:" -ForegroundColor Yellow
    @("C:\pagefile.sys","C:\hiberfil.sys","C:\swapfile.sys") | % {
        if(Test-Path $_ -EA 0){
            $s = (gi $_ -Force -EA 0).Length
            "{0,-20} {1:N2} GB" -f (Split-Path $_ -Leaf), ($s/1GB)
        }
    }
    Write-Host ""

    # System Volume Information
    Write-Host "VOLUME INFO:" -ForegroundColor Yellow
    $volInfo = "C:\System Volume Information"
    if(Test-Path $volInfo -EA 0){
        $s = (gci $volInfo -R -Force -EA 0 | measure Length -Sum -EA 0).Sum
        if($s -gt 1MB){"System Vol Info:     {0:N2} GB" -f ($s/1GB)}
    }
