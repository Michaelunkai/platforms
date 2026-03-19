<#
.SYNOPSIS
    getorch
#>
param (
        [string]$CudaVersion = "cu111"
    )
    Invoke-Expression $pipInstallCommand
    Invoke-Expression $pythonCheckCommand
