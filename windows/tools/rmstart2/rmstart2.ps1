<#
.SYNOPSIS
    rmstart2
#>
param([string]$path)
    $taskName = "AutoStart_" + [IO.Path]::GetFileNameWithoutExtension($path)
    SCHTASKS /Delete /TN $taskName /F | Out-Null
    Write-Host "??? Removed startup task for '$path' (task: $taskName)"
