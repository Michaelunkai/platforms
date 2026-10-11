$script:InstalledAppRestoreHelper = 'F:\study\Platforms\windows\functions\Invoke-InstalledAppDockerRestoreAndLaunch.ps1'
$script:InstalledAppRegisterHelper = 'F:\study\Platforms\windows\functions\Register-InstalledAppDockerFunction.ps1'
$script:InstalledAppRestoreFolders = @(
    'CodexMonitor',
    'WhisperKeyLocal',
    'Whisper',
    'tv',
    'reflect',
    'FlareSolverr',
    'Obsidian',
    'telegram',
    'Prowlarr',
    'cloudflare',
    'Jackett',
    'kvrt',
    'scoop',
    'BleachBitAutoClean',
    'tailscale',
    'Process Lasso',
    'OpenSpeedy',
    'gamesavemanager',
    'adw',
    'Everything',
    'qBittorrentSearchPluginsWiki',
    'qBittorrentSearchPlugins'
)
$customCatalogPath = Join-Path $PSScriptRoot 'InstalledAppRestoreCatalog.json'
if (Test-Path -LiteralPath $customCatalogPath -PathType Leaf) {
    $script:InstalledAppRestoreFolders += @((Get-Content -LiteralPath $customCatalogPath -Raw | ConvertFrom-Json) | ForEach-Object { [string]$_.Folder })
    $script:InstalledAppRestoreFolders = @($script:InstalledAppRestoreFolders | Select-Object -Unique)
}
foreach ($installedAppFolder in $script:InstalledAppRestoreFolders) {
    $installedAppFunctionName = 'g' + ($installedAppFolder -replace '[^A-Za-z0-9]', '')
    $managedCommand=Join-Path $env:USERPROFILE ('.gmenu\Commands\'+$installedAppFunctionName+'.ps1')
    $managedReceipt=Join-Path $env:USERPROFILE ('.gmenu\Commands\'+$installedAppFunctionName+'.receipt.json')
    if((Test-Path -LiteralPath $managedCommand -PathType Leaf) -and (Test-Path -LiteralPath $managedReceipt -PathType Leaf)) {
        $managedBody=[scriptblock]::Create("& '"+$managedCommand.Replace("'","''")+"' @args")
        Set-Item -LiteralPath ('Function:\global:'+$installedAppFunctionName) -Value $managedBody -Force
        continue
    }
    $capturedFolder = $installedAppFolder
    $capturedHelper = $script:InstalledAppRestoreHelper
    $capturedFunctionName = $installedAppFunctionName
    $installedAppFunction = {
        $installedAppErrorCountBefore = $global:Error.Count
        $installedAppPreviousErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Stop'
            & $capturedHelper -Folder $capturedFolder @args
            $installedAppExitCode = $LASTEXITCODE
            $global:LASTEXITCODE = if ($null -eq $installedAppExitCode) { 0 } else { [int]$installedAppExitCode }
        } catch {
            $installedAppMessage = if ($_.Exception -and $_.Exception.Message) { $_.Exception.Message } else { [string]$_ }
            Write-Host ("[{0}] FAILED: {1}; returning to PowerShell without an exception dump." -f $capturedFunctionName,$installedAppMessage) -ForegroundColor Red
            $global:LASTEXITCODE = 1
        } finally {
            $ErrorActionPreference = $installedAppPreviousErrorActionPreference
            try {
                while ($global:Error.Count -gt $installedAppErrorCountBefore) { $global:Error.RemoveAt(0) }
            } catch {}
        }
    }.GetNewClosure()
    Remove-Item -LiteralPath ('Function:\global:' + $installedAppFunctionName) -Force -ErrorAction SilentlyContinue
    Set-Item -LiteralPath ('Function:\global:' + $installedAppFunctionName) -Value $installedAppFunction -Force
}
$capturedRegisterHelper = $script:InstalledAppRegisterHelper
$capturedLoaderPath = $PSCommandPath
$gappFunction = {
    & $capturedRegisterHelper @args
    . $capturedLoaderPath
}.GetNewClosure()
Remove-Item -LiteralPath 'Function:\global:gapp' -Force -ErrorAction SilentlyContinue
Set-Item -LiteralPath 'Function:\global:gapp' -Value $gappFunction -Force
