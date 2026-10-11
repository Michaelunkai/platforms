param()

$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'uni.ps1')

function Assert-UniOfflineScanTest {
    param([bool]$Condition,[string]$Message)
    if(-not $Condition){throw $Message}
}

Assert-UniOfflineScanTest ([bool](Get-Command Get-UniOfflineHiveMatches -CommandType Function -ErrorAction SilentlyContinue)) 'Missing offline-hive scanner.'
Assert-UniOfflineScanTest ([bool](Get-Command Remove-UniOfflineHiveKey -CommandType Function -ErrorAction SilentlyContinue)) 'Missing offline-hive key remover.'
Assert-UniOfflineScanTest ([bool](Get-Command Remove-UniOfflineHiveValue -CommandType Function -ErrorAction SilentlyContinue)) 'Missing offline-hive value remover.'
Assert-UniOfflineScanTest ([bool](Get-Command Remove-UniOfflineAppListBackupValue -CommandType Function -ErrorAction SilentlyContinue)) 'Missing offline AppListBackup record remover.'
Assert-UniOfflineScanTest ([bool](Get-Command Remove-UniOfflineEnvironmentValue -CommandType Function -ErrorAction SilentlyContinue)) 'Missing offline environment-value remover.'

$regExe=Join-Path $env:SystemRoot 'System32\reg.exe'
$id=[Guid]::NewGuid().ToString('N').Substring(0,8)
$sourceProvider='HKCU:\UHS'+$id
$sourceNative='HKCU\UHS'+$id
$ownedKey=Join-Path $sourceProvider 'ContosoTargetCache'
$appListKey=Join-Path $sourceProvider 'Software\Microsoft\Windows\CurrentVersion\AppListBackup\ListOfEventDrivenBackedUpApps_0'
$targetOnlyAppListKey=Join-Path $sourceProvider 'Software\Microsoft\Windows\CurrentVersion\AppListBackup\ListOfEventDrivenBackedUpApps_1'
$environmentKey=Join-Path $sourceProvider 'Environment'
$appListValueName='Apps'
$appListJson='[{"appName":"ContosoTarget","appId":"contosotarget_is1","publisher":"Contoso"},{"appName":"UnrelatedApp","appId":"unrelated_is1","publisher":"Elsewhere"}]'
$targetOnlyAppListJson='[{"appName":"ContosoTarget","appId":"contosotarget_is1","publisher":"Contoso"}]'
$environmentPath='C:\Windows;C:\ProgramData\ContosoTarget\bin;;C:\Unrelated\bin'
$hiveFile=Join-Path ([IO.Path]::GetTempPath()) ('uhs-'+$id+'.hiv')
$coverageHiveFile=Join-Path ([IO.Path]::GetTempPath()) ('uhs-coverage-'+$id+'.hiv')
$oldRequestedIdentities=@($script:UniRequestedIdentities)
$oldTargetRegex=$script:UniTargetRegex
$oldOrphanRegex=$script:UniOrphanRegex
$oldFailed=$script:UniFailed
$oldProtectedArtifacts=$script:UniProtectedArtifacts
$oldStats=$script:UniStats
$oldOwnedRoots=@($script:UniOwnedRoots)
$oldOtherRoots=@($script:UniOtherRoots)
$oldOwnedFiles=$script:UniOwnedFiles

try {
    New-Item -Path $ownedKey -Force | Out-Null
    New-ItemProperty -LiteralPath $ownedKey -Name 'InstallPath' -Value 'C:\ProgramData\ContosoTarget\agent.exe' -PropertyType String -Force | Out-Null
    New-Item -Path $appListKey -Force | Out-Null
    New-ItemProperty -LiteralPath $appListKey -Name $appListValueName -Value $appListJson -PropertyType String -Force | Out-Null
    New-Item -Path $targetOnlyAppListKey -Force | Out-Null
    New-ItemProperty -LiteralPath $targetOnlyAppListKey -Name $appListValueName -Value $targetOnlyAppListJson -PropertyType String -Force | Out-Null
    New-Item -Path $environmentKey -Force | Out-Null
    New-ItemProperty -LiteralPath $environmentKey -Name 'Path' -Value $environmentPath -PropertyType ExpandString -Force | Out-Null
    New-ItemProperty -LiteralPath $environmentKey -Name 'ContosoTargetHome' -Value 'C:\ProgramData\ContosoTarget' -PropertyType String -Force | Out-Null
    New-ItemProperty -LiteralPath $environmentKey -Name 'UNRELATED_HOME' -Value 'C:\Unrelated' -PropertyType String -Force | Out-Null
    $saveOutput=@(& $regExe save $sourceNative $hiveFile /y 2>&1)
    Assert-UniOfflineScanTest ($LASTEXITCODE -eq 0) ('Could not create offline-hive fixture: '+($saveOutput -join ' '))
    Remove-Item -LiteralPath $sourceProvider -Recurse -Force

    $hits=@(Get-UniOfflineHiveMatches -File $hiveFile -Prefix 'HKEY_CURRENT_USER' -ExactPattern '(?:^|[^a-z0-9])contosotarget(?:[^a-z0-9]|$)' -LoosePattern 'contosotarget')
    Assert-UniOfflineScanTest (@($hits | Where-Object {$_.Kind -eq 'K' -and $_.Path -eq 'HKEY_CURRENT_USER\ContosoTargetCache'}).Count -eq 1) 'Offline target-named registry key was missed.'
    Assert-UniOfflineScanTest (@($hits | Where-Object {$_.Kind -eq 'V' -and $_.Path -eq 'HKEY_CURRENT_USER\ContosoTargetCache' -and $_.ValueName -eq 'InstallPath'}).Count -eq 1) 'Offline target-owned registry value was missed.'

    [void](Remove-UniOfflineHiveValue -File $hiveFile -Prefix 'HKEY_CURRENT_USER' -Path 'HKEY_CURRENT_USER\ContosoTargetCache' -ValueName 'InstallPath')
    $afterValue=@(Get-UniOfflineHiveMatches -File $hiveFile -Prefix 'HKEY_CURRENT_USER' -ExactPattern '(?:^|[^a-z0-9])contosotarget(?:[^a-z0-9]|$)' -LoosePattern 'contosotarget')
    Assert-UniOfflineScanTest (@($afterValue | Where-Object {$_.Kind -eq 'V' -and $_.ValueName -eq 'InstallPath'}).Count -eq 0) 'Offline registry value deletion did not persist after reopening the hive.'

    [void](Remove-UniOfflineHiveKey -File $hiveFile -Prefix 'HKEY_CURRENT_USER' -Path 'HKEY_CURRENT_USER\ContosoTargetCache')
    $afterKey=@(Get-UniOfflineHiveMatches -File $hiveFile -Prefix 'HKEY_CURRENT_USER' -ExactPattern '(?:^|[^a-z0-9])contosotarget(?:[^a-z0-9]|$)' -LoosePattern 'contosotarget')
    Assert-UniOfflineScanTest (@($afterKey | Where-Object {$_.Path -eq 'HKEY_CURRENT_USER\ContosoTargetCache'}).Count -eq 0) 'Offline registry key deletion did not persist after reopening the hive.'

    Copy-Item -LiteralPath $hiveFile -Destination $coverageHiveFile -Force
    $script:UniRequestedIdentities=@('contosotarget')
    $script:UniTargetRegex=New-Object System.Text.RegularExpressions.Regex('(?:^|[^a-z0-9])contosotarget(?:[^a-z0-9]|$)',[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $script:UniOrphanRegex=New-Object System.Text.RegularExpressions.Regex('contosotarget',[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $script:UniFailed=New-Object 'System.Collections.Generic.List[string]'
    $script:UniProtectedArtifacts=New-Object 'System.Collections.Generic.List[string]'
    $script:UniStats=@{RegKeys=0;RegValues=0}
    $script:UniOwnedRoots=@('C:\ProgramData\ContosoTarget')
    $script:UniOtherRoots=@()
    $script:UniOwnedFiles=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    Test-UniOfflineHiveCoverageFile -OwnerLabel 'coverage-fixture' -File $coverageHiveFile -Prefix 'HKEY_CURRENT_USER' -ReExact $script:UniTargetRegex -ReLoose $script:UniOrphanRegex
    Assert-UniOfflineScanTest ($script:UniFailed.Count -eq 0) ('Offline AppListBackup coverage integration reported failure: '+($script:UniFailed -join '; '))
    Assert-UniOfflineScanTest ($script:UniProtectedArtifacts.Count -eq 0) ('Offline AppListBackup coverage integration preserved an owned record: '+($script:UniProtectedArtifacts -join '; '))
    $coverageTargetAfter=@(Get-UniOfflineHiveMatches -File $coverageHiveFile -Prefix 'HKEY_CURRENT_USER' -ExactPattern '(?:^|[^a-z0-9])contosotarget(?:[^a-z0-9]|$)' -LoosePattern 'contosotarget')
    Assert-UniOfflineScanTest ($coverageTargetAfter.Count -eq 0) 'Offline coverage integration left a target AppListBackup record.'
    $coverageUnrelatedAfter=@(Get-UniOfflineHiveMatches -File $coverageHiveFile -Prefix 'HKEY_CURRENT_USER' -ExactPattern '(?:^|[^a-z0-9])unrelatedapp(?:[^a-z0-9]|$)' -LoosePattern 'unrelatedapp')
    Assert-UniOfflineScanTest ($coverageUnrelatedAfter.Count -eq 1 -and [string](@(Get-UniAppListBackupRecords $coverageUnrelatedAfter[0].Value)[0].appName) -eq 'UnrelatedApp') 'Offline coverage integration changed the unrelated AppListBackup record.'
    $coverageEnvironmentAfter=@(Get-UniOfflineHiveMatches -File $coverageHiveFile -Prefix 'HKEY_CURRENT_USER' -ExactPattern 'unrelated' -LoosePattern 'unrelated')
    $remainingPath=@($coverageEnvironmentAfter | Where-Object {$_.Path -eq 'HKEY_CURRENT_USER\Environment' -and $_.ValueName -eq 'Path'})
    Assert-UniOfflineScanTest ($remainingPath.Count -eq 1 -and [string]$remainingPath[0].Value -ceq 'C:\Windows;;C:\Unrelated\bin') 'Offline environment Path target segment was not removed exactly or unrelated/empty segments changed.'
    Assert-UniOfflineScanTest ($remainingPath[0].ValueKind -eq [Microsoft.Win32.RegistryValueKind]::ExpandString) 'Offline environment Path registry type changed during rewrite.'
    Assert-UniOfflineScanTest (@($coverageEnvironmentAfter | Where-Object {$_.Path -eq 'HKEY_CURRENT_USER\Environment' -and $_.ValueName -eq 'UNRELATED_HOME' -and [string]$_.Value -eq 'C:\Unrelated'}).Count -eq 1) 'Offline unrelated environment variable changed.'

    $script:UniTargetRegex=$oldTargetRegex
    $script:UniOrphanRegex=$oldOrphanRegex
    $script:UniFailed=$oldFailed
    $script:UniProtectedArtifacts=$oldProtectedArtifacts
    $script:UniStats=$oldStats
    $script:UniOwnedRoots=@($oldOwnedRoots)
    $script:UniOtherRoots=@($oldOtherRoots)
    $script:UniOwnedFiles=$oldOwnedFiles

    $script:UniRequestedIdentities=@('contosotarget')
    $appListPath='HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\AppListBackup\ListOfEventDrivenBackedUpApps_0'
    $appListRemoved=Remove-UniOfflineAppListBackupValue -File $hiveFile -Prefix 'HKEY_CURRENT_USER' -Path $appListPath -ValueName $appListValueName -Value $appListJson
    Assert-UniOfflineScanTest ([bool]$appListRemoved) 'Offline AppListBackup target record was not removed.'
    $targetAfter=@(Get-UniOfflineHiveMatches -File $hiveFile -Prefix 'HKEY_CURRENT_USER' -ExactPattern '(?:^|[^a-z0-9])contosotarget(?:[^a-z0-9]|$)' -LoosePattern 'contosotarget')
    Assert-UniOfflineScanTest (@($targetAfter | Where-Object {$_.Path -eq $appListPath}).Count -eq 0) 'Offline AppListBackup target record remained after reopening the hive.'
    $unrelatedAfter=@(Get-UniOfflineHiveMatches -File $hiveFile -Prefix 'HKEY_CURRENT_USER' -ExactPattern '(?:^|[^a-z0-9])unrelatedapp(?:[^a-z0-9]|$)' -LoosePattern 'unrelatedapp')
    Assert-UniOfflineScanTest ($unrelatedAfter.Count -eq 1) 'Offline AppListBackup unrelated record was removed or duplicated.'
    $remainingRecords=@(Get-UniAppListBackupRecords $unrelatedAfter[0].Value)
    Assert-UniOfflineScanTest ($remainingRecords.Count -eq 1 -and [string]$remainingRecords[0].appName -eq 'UnrelatedApp' -and [string]$remainingRecords[0].appId -eq 'unrelated_is1' -and [string]$remainingRecords[0].publisher -eq 'Elsewhere') 'Offline AppListBackup unrelated record changed.'

    $staleWriteRejected=$false
    try {[void](Remove-UniOfflineAppListBackupValue -File $hiveFile -Prefix 'HKEY_CURRENT_USER' -Path $appListPath -ValueName $appListValueName -Value $appListJson)} catch {$staleWriteRejected=$_.Exception.Message -match 'changed during verification'}
    Assert-UniOfflineScanTest $staleWriteRejected 'Offline AppListBackup stale compare-before-write was not rejected.'
    $unrelatedAfterRejectedWrite=@(Get-UniOfflineHiveMatches -File $hiveFile -Prefix 'HKEY_CURRENT_USER' -ExactPattern '(?:^|[^a-z0-9])unrelatedapp(?:[^a-z0-9]|$)' -LoosePattern 'unrelatedapp')
    Assert-UniOfflineScanTest ($unrelatedAfterRejectedWrite.Count -eq 1 -and [string](@(Get-UniAppListBackupRecords $unrelatedAfterRejectedWrite[0].Value)[0].appName) -eq 'UnrelatedApp') 'Rejected offline AppListBackup rewrite changed the preserved record.'

    $targetOnlyPath='HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\AppListBackup\ListOfEventDrivenBackedUpApps_1'
    [void](Remove-UniOfflineAppListBackupValue -File $hiveFile -Prefix 'HKEY_CURRENT_USER' -Path $targetOnlyPath -ValueName $appListValueName -Value $targetOnlyAppListJson)
    $emptyRecordKey=@(Get-UniOfflineHiveMatches -File $hiveFile -Prefix 'HKEY_CURRENT_USER' -ExactPattern 'ListOfEventDrivenBackedUpApps_1' -LoosePattern 'ListOfEventDrivenBackedUpApps_1')
    Assert-UniOfflineScanTest ($emptyRecordKey.Count -eq 0) 'Empty offline AppListBackup record key remained after its last target record was removed.'

    $cleanHits=@(Get-UniOfflineHiveMatches -File $hiveFile -Prefix 'HKEY_CURRENT_USER' -ExactPattern '(?:^|[^a-z0-9])definitelyabsent(?:[^a-z0-9]|$)' -LoosePattern 'definitelyabsent')
    Assert-UniOfflineScanTest ($cleanHits.Count -eq 0) 'Offline scanner returned an unrelated hit.'
}
finally {
    $script:UniRequestedIdentities=@($oldRequestedIdentities)
    $script:UniTargetRegex=$oldTargetRegex
    $script:UniOrphanRegex=$oldOrphanRegex
    $script:UniFailed=$oldFailed
    $script:UniProtectedArtifacts=$oldProtectedArtifacts
    $script:UniStats=$oldStats
    $script:UniOwnedRoots=@($oldOwnedRoots)
    $script:UniOtherRoots=@($oldOtherRoots)
    $script:UniOwnedFiles=$oldOwnedFiles
    if(Test-Path -LiteralPath $sourceProvider){Remove-Item -LiteralPath $sourceProvider -Recurse -Force}
    if([IO.File]::Exists($hiveFile)){[IO.File]::Delete($hiveFile)}
    if([IO.File]::Exists($coverageHiveFile)){[IO.File]::Delete($coverageHiveFile)}
}

'UNI_OFFLINE_HIVE_SCAN_TEST_OK'
