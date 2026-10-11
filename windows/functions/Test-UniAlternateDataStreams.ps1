param()

$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'uni.ps1')

function Assert-UniAdsTest {
    param([bool]$Condition,[string]$Message)
    if(-not $Condition){throw $Message}
}

Assert-UniAdsTest ([bool](Get-Command Get-UniNamedDataStreams -CommandType Function -ErrorAction SilentlyContinue)) 'Missing named-data-stream enumerator.'
Assert-UniAdsTest ([bool](Get-Command Get-UniMatchingAlternateDataStreams -CommandType Function -ErrorAction SilentlyContinue)) 'Missing matching alternate-data-stream collector.'
Assert-UniAdsTest ([bool](Get-Command Remove-UniAlternateDataStream -CommandType Function -ErrorAction SilentlyContinue)) 'Missing alternate-data-stream remover.'

$fixture=Join-Path ([IO.Path]::GetTempPath()) ('uni-ads-test-'+[Guid]::NewGuid().ToString('N'))
$hostFile=Join-Path $fixture 'neutral-host.bin'
$hostContent='host-content-must-survive'
$targetStreamName='ContosoTarget.cache'
$unrelatedStreamName='UnrelatedState'
$directoryStreamName='ContosoTarget.directory'
$deniedDirectoryStreamName='ContosoTarget.denied-directory'
$deniedChildStreamName='ContosoTarget.denied-child'
$listDeniedChildStreamName='ContosoTarget.list-denied-child'
$sharingStreamName='ContosoTarget.sharing-locked'
$targetStreamPath=$hostFile+':'+$targetStreamName
$unrelatedStreamPath=$hostFile+':'+$unrelatedStreamName
$exact='(?:^|[^a-z0-9])contosotarget(?:[^a-z0-9]|$)'
$hardlinkHost=Join-Path $fixture 'hardlink-host.bin'
$hardlinkAlias=Join-Path $fixture 'hardlink-alias.bin'
$hardlinkStreamName='ContosoTarget.hardlinked'

try {
    [IO.Directory]::CreateDirectory($fixture) | Out-Null
    [IO.File]::WriteAllText($hostFile,$hostContent)
    [IO.File]::WriteAllText($hardlinkHost,'hardlink-host-content')
    New-Item -ItemType HardLink -Path $hardlinkAlias -Target $hardlinkHost -Force | Out-Null
    Set-Content -LiteralPath $hardlinkHost -Stream $hardlinkStreamName -Value 'hardlink-stream-content' -Encoding UTF8 -NoNewline
    Set-Content -LiteralPath $fixture -Stream $directoryStreamName -Value 'directory-stream-content' -Encoding UTF8 -NoNewline
    Set-Content -LiteralPath $hostFile -Stream $targetStreamName -Value 'target-stream-content' -Encoding UTF8 -NoNewline
    Set-Content -LiteralPath $hostFile -Stream $unrelatedStreamName -Value 'unrelated-stream-content' -Encoding UTF8 -NoNewline
    $sharingHost=Join-Path $fixture 'sharing-locked-host.bin'
    [IO.File]::WriteAllText($sharingHost,'sharing-host-content')
    Set-Content -LiteralPath $sharingHost -Stream $sharingStreamName -Value 'sharing-stream-content' -Encoding UTF8 -NoNewline
    $sharingHandle=[IO.File]::Open($sharingHost,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $listDeniedDirectory=Join-Path $fixture 'list-denied-host'
    [IO.Directory]::CreateDirectory($listDeniedDirectory) | Out-Null
    $listDeniedChild=Join-Path $listDeniedDirectory 'neutral-child.bin'
    [IO.File]::WriteAllText($listDeniedChild,'list-denied-child-host-content')
    Set-Content -LiteralPath $listDeniedChild -Stream $listDeniedChildStreamName -Value 'list-denied-child-stream-content' -Encoding UTF8 -NoNewline
    $listDeniedOriginalAcl=Get-Acl -LiteralPath $listDeniedDirectory
    $listDeniedAcl=New-Object Security.AccessControl.DirectorySecurity
    $listDeniedAcl.SetOwner((New-Object Security.Principal.NTAccount($listDeniedOriginalAcl.Owner)))
    $listDeniedAcl.SetAccessRuleProtection($true,$false)
    $currentIdentity=[Security.Principal.WindowsIdentity]::GetCurrent().Name
    $listDeniedAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($currentIdentity,'ReadAttributes,ReadExtendedAttributes,ReadPermissions','Allow')))
    $listDeniedAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($currentIdentity,'ListDirectory','Deny')))
    Set-Acl -LiteralPath $listDeniedDirectory -AclObject $listDeniedAcl
    $deniedDirectory=Join-Path $fixture 'acl-denied-host'
    [IO.Directory]::CreateDirectory($deniedDirectory) | Out-Null
    Set-Content -LiteralPath $deniedDirectory -Stream $deniedDirectoryStreamName -Value 'denied-directory-stream-content' -Encoding UTF8 -NoNewline
    $deniedChild=Join-Path $deniedDirectory 'neutral-child.bin'
    [IO.File]::WriteAllText($deniedChild,'denied-child-host-content')
    Set-Content -LiteralPath $deniedChild -Stream $deniedChildStreamName -Value 'denied-child-stream-content' -Encoding UTF8 -NoNewline
    $deniedDirectoryOriginalAcl=Get-Acl -LiteralPath $deniedDirectory
    $deniedDirectoryAcl=New-Object Security.AccessControl.DirectorySecurity
    $deniedDirectoryAcl.SetOwner((New-Object Security.Principal.NTAccount($deniedDirectoryOriginalAcl.Owner)))
    $deniedDirectoryAcl.SetAccessRuleProtection($true,$false)
    Set-Acl -LiteralPath $deniedDirectory -AclObject $deniedDirectoryAcl

    $all=@(Get-UniNamedDataStreams -Path $hostFile)
    Assert-UniAdsTest (@($all | Where-Object {$_.StreamName -ceq $targetStreamName -and $_.StreamPath -ceq $targetStreamPath}).Count -eq 1) 'Target named data stream was not enumerated exactly once.'
    Assert-UniAdsTest (@($all | Where-Object {$_.StreamName -ceq $unrelatedStreamName -and $_.StreamPath -ceq $unrelatedStreamPath}).Count -eq 1) 'Unrelated named data stream was not enumerated exactly once.'
    Assert-UniAdsTest (@($all | Where-Object {$_.StreamName -eq '' -or $_.StreamName -eq '$DATA'}).Count -eq 0) 'Unnamed default data stream leaked into named-stream results.'
    Assert-UniAdsTest (@(Get-UniNamedDataStreams -Path $fixture | Where-Object {$_.StreamName -ceq $directoryStreamName}).Count -eq 1) 'Directory named data stream was not enumerated.'
    Assert-UniAdsTest (@(Get-UniNamedDataStreams -Path $sharingHost | Where-Object {$_.StreamName -ceq $sharingStreamName}).Count -eq 1) 'Sharing-locked file named data stream was not enumerated.'
    $sharingHandle.Dispose();$sharingHandle=$null

    $matches=@(Get-UniMatchingAlternateDataStreams -Path $hostFile -ExactPattern $exact)
    Assert-UniAdsTest ($matches.Count -eq 1 -and $matches[0].StreamName -ceq $targetStreamName) 'Exact ADS matcher missed the target stream or included an unrelated stream.'

    Ensure-UniSweepCollect
    Assert-UniAdsTest ([bool]('UniSweepCollectV12' -as [type])) 'Filesystem collector version was not advanced for ADS support.'
    [UniSweepCollectV12]::ResetCounters()
    [void]([UniSweepCollectV12]::Collect($listDeniedDirectory,'N',$exact,'contosotarget',@(),@(),@(),1))
    $listDeniedDetails=@([UniSweepCollectV12]::ErrorDetails) -join '; '
    Assert-UniAdsTest (@([UniSweepCollectV12]::StreamMatches | Where-Object {$_.HostPath -ceq $listDeniedChild -and $_.StreamName -ceq $listDeniedChildStreamName}).Count -eq 1) ('Public filesystem collector missed a target ADS below a list-denied directory whose stream metadata remained readable. errors='+[UniSweepCollectV12]::Errors+' details='+$listDeniedDetails)
    try {$privilegedPaths=@([UniAlternateDataStreamV4]::EnumerateDirectoryPaths($listDeniedDirectory))} catch {throw ('Privileged directory enumeration failed: '+$_.Exception.ToString())}
    Assert-UniAdsTest ($privilegedPaths -contains $listDeniedChild) 'Privileged directory enumerator did not return the child below a list-denied directory.'
    [UniSweepCollectV12]::ResetCounters()
    $secondRoot=Join-Path $fixture 'second-root'
    [IO.Directory]::CreateDirectory($secondRoot) | Out-Null
    $scanOne=[UniSweepCollectV12]::CollectAsync($fixture,'N',$exact,'contosotarget',@(),@(),@('second-root'),1)
    $scanTwo=[UniSweepCollectV12]::CollectAsync($secondRoot,'N',$exact,'contosotarget',@(),@(),@(),1)
    [void][Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($scanOne,$scanTwo))
    [void]$scanOne.Result
    [void]$scanTwo.Result
    $sweepStreams=@([UniSweepCollectV12]::StreamMatches)
    Assert-UniAdsTest (@($sweepStreams | Where-Object {$_.HostPath -ceq $hostFile -and $_.StreamName -ceq $targetStreamName}).Count -eq 1) 'Public filesystem collector missed the target ADS.'
    Assert-UniAdsTest (@($sweepStreams | Where-Object {$_.HostPath -ceq $fixture -and $_.StreamName -ceq $directoryStreamName}).Count -eq 1) 'Public filesystem collector missed a target ADS on its root directory.'
    Assert-UniAdsTest (@($sweepStreams | Where-Object {$_.HostPath -ceq $deniedDirectory -and $_.StreamName -ceq $deniedDirectoryStreamName}).Count -eq 1) 'Public filesystem collector missed a target ADS on an ACL-denied directory.'
    Assert-UniAdsTest (@($sweepStreams | Where-Object {$_.HostPath -ceq $deniedChild -and $_.StreamName -ceq $deniedChildStreamName}).Count -eq 1) 'Public filesystem collector missed a target ADS below an ACL-denied directory.'
    Assert-UniAdsTest ([UniSweepCollectV12]::StreamErrors -eq 0) 'Public filesystem collector reported an ADS coverage error for an ACL-denied directory despite backup privilege.'
    Assert-UniAdsTest (@($sweepStreams | Where-Object {$_.StreamName -ceq $unrelatedStreamName}).Count -eq 0) 'Public filesystem collector included an unrelated ADS.'

    [void](Remove-UniAlternateDataStream -HostPath $hostFile -StreamName $targetStreamName -ExactPattern $exact)
    [void](Remove-UniAlternateDataStream -HostPath $fixture -StreamName $directoryStreamName -ExactPattern $exact)
    [void](Remove-UniAlternateDataStream -HostPath $deniedDirectory -StreamName $deniedDirectoryStreamName -ExactPattern $exact)

    $hardlinkRejected=$false
    try {[void](Remove-UniAlternateDataStream -HostPath $hardlinkHost -StreamName $hardlinkStreamName -ExactPattern $exact)} catch {$hardlinkRejected=$_.Exception.Message -match 'hard-linked'}
    Assert-UniAdsTest $hardlinkRejected 'Alternate data stream deletion did not refuse a hard-linked host file.'
    Assert-UniAdsTest (@(Get-UniNamedDataStreams -Path $hardlinkHost | Where-Object {$_.StreamName -ceq $hardlinkStreamName}).Count -eq 1) 'Hard-linked host stream was removed despite refusal.'

    Assert-UniAdsTest ([IO.File]::Exists($hostFile)) 'Deleting the target ADS deleted its host file.'
    Assert-UniAdsTest ([IO.File]::ReadAllText($hostFile) -ceq $hostContent) 'Deleting the target ADS changed host-file content.'
    Assert-UniAdsTest ([string](Get-Content -LiteralPath $hostFile -Stream $unrelatedStreamName -Raw) -ceq 'unrelated-stream-content') 'Deleting the target ADS changed the unrelated stream.'
    Assert-UniAdsTest (@(Get-UniNamedDataStreams -Path $hostFile | Where-Object {$_.StreamName -ceq $targetStreamName}).Count -eq 0) 'Target ADS remained after deletion.'
    Assert-UniAdsTest (@(Get-UniMatchingAlternateDataStreams -Path $hostFile -ExactPattern $exact).Count -eq 0) 'Target ADS was rediscovered after deletion.'
    Assert-UniAdsTest ([IO.Directory]::Exists($deniedDirectory)) 'Deleting an ACL-denied directory ADS deleted its host directory.'
    Assert-UniAdsTest (@(Get-UniNamedDataStreams -Path $deniedDirectory | Where-Object {$_.StreamName -ceq $deniedDirectoryStreamName}).Count -eq 0) 'Target ADS remained on the ACL-denied directory after backup-semantic deletion.'

    $unsafeRejected=$false
    try {[void](Remove-UniAlternateDataStream -HostPath $hostFile -StreamName $unrelatedStreamName -ExactPattern $exact)} catch {$unsafeRejected=$_.Exception.Message -match 'does not exactly match'}
    Assert-UniAdsTest $unsafeRejected 'Nonmatching ADS deletion was not rejected.'
    Assert-UniAdsTest (@(Get-UniNamedDataStreams -Path $hostFile | Where-Object {$_.StreamName -ceq $unrelatedStreamName}).Count -eq 1) 'Rejected ADS deletion changed the unrelated stream.'
}
finally {
    if($sharingHandle){$sharingHandle.Dispose()}
    if($listDeniedDirectory -and [IO.Directory]::Exists($listDeniedDirectory) -and $listDeniedOriginalAcl){Set-Acl -LiteralPath $listDeniedDirectory -AclObject $listDeniedOriginalAcl -ErrorAction SilentlyContinue}
    if($deniedDirectory -and [IO.Directory]::Exists($deniedDirectory) -and $deniedDirectoryOriginalAcl){Set-Acl -LiteralPath $deniedDirectory -AclObject $deniedDirectoryOriginalAcl -ErrorAction SilentlyContinue}
    if([IO.Directory]::Exists($fixture)){[IO.Directory]::Delete($fixture,$true)}
}

'UNI_ALTERNATE_DATA_STREAM_TEST_OK'
