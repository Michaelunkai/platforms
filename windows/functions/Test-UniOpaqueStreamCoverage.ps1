param()

$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'uni.ps1')

function Assert-UniOpaqueStreamTest {
    param([bool]$Condition,[string]$Message)
    if(-not $Condition){throw $Message}
}

$root='C:\Windows\Temp\UniOpaqueStreams-'+[Guid]::NewGuid().ToString('N')
$file=Join-Path $root 'ordinary.bin'
$streamName='OpaqueTarget-'+[Guid]::NewGuid().ToString('N')
$script:UniFailed=New-Object 'System.Collections.Generic.List[string]'

try {
    [void][IO.Directory]::CreateDirectory($root)
    [IO.File]::WriteAllBytes($file,[Text.Encoding]::UTF8.GetBytes('opaque stream host'))
    Set-Content -LiteralPath $file -Stream $streamName -Value 'target stream' -NoNewline
    Ensure-UniSweepCollect
    Assert-UniOpaqueStreamTest ([bool]$script:UniCollectOk) 'Filesystem collector was unavailable.'
    [UniSweepCollectV12]::ResetCounters()
    $exact='(?i)^'+[regex]::Escape($streamName)+'$'
    $hits=@([UniSweepCollectV12]::ScanOpaqueNamedStreams(@($root),[regex]$exact,1))
    Assert-UniOpaqueStreamTest (@($hits | Where-Object {[string]::Equals([string]$_.HostPath,$file,[StringComparison]::OrdinalIgnoreCase) -and [string]::Equals([string]$_.StreamName,$streamName,[StringComparison]::OrdinalIgnoreCase)}).Count -eq 1) 'Opaque-namespace stream audit did not surface the target stream.'

    # Opaque namespaces must surface ordinary exact-name candidates too; MFT
    # path resolution is an independent fallback, not the sole visibility
    # mechanism when a protected store denies a handle open.
    $opaqueTargetFile=Join-Path $root 'OpaqueTargetArtifact.bin'
    [IO.File]::WriteAllBytes($opaqueTargetFile,[Text.Encoding]::UTF8.GetBytes('opaque exact-name candidate'))
    [UniSweepCollectV12]::ResetCounters()
    $opaqueNameHits=@([UniSweepCollectV12]::ScanOpaqueNamedStreams(@($root),([regex]'(?i)^OpaqueTargetArtifact\.bin$'),1))
    Assert-UniOpaqueStreamTest (@([UniSweepCollectV12]::OpaqueMatches | Where-Object {[string]::Equals([string]$_,$opaqueTargetFile,[StringComparison]::OrdinalIgnoreCase)}).Count -eq 1) 'Opaque audit did not surface an exact target-named path.'

    # Opaque roots may also be individual top-level protected files. Verify
    # that the audit inspects the file object itself, not only directories.
    $rootFile=Join-Path $root 'protected-root-file.bin'
    $rootStream='RootFileTarget-'+[Guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllBytes($rootFile,[Text.Encoding]::UTF8.GetBytes('protected root stream host'))
    Set-Content -LiteralPath $rootFile -Stream $rootStream -Value 'root file target stream' -NoNewline
    $rootExact='(?i)^'+[regex]::Escape($rootStream)+'$'
    [UniSweepCollectV12]::ResetCounters()
    $rootHits=@([UniSweepCollectV12]::ScanOpaqueNamedStreams(@($rootFile),[regex]$rootExact,1))
    Assert-UniOpaqueStreamTest (@($rootHits | Where-Object {[string]::Equals([string]$_.HostPath,$rootFile,[StringComparison]::OrdinalIgnoreCase) -and [string]::Equals([string]$_.StreamName,$rootStream,[StringComparison]::OrdinalIgnoreCase)}).Count -eq 1) 'Opaque stream audit skipped an individual protected root file.'

    # Source-control directories are ordinary namespaces, not scan
    # exemptions. Verify the regular collector reaches a .git child and
    # surfaces its target stream without authorizing deletion.
    $gitDir=Join-Path $root '.git'
    $gitFile=Join-Path $gitDir 'config.bin'
    $gitStream='GitTarget-'+[Guid]::NewGuid().ToString('N')
    [void][IO.Directory]::CreateDirectory($gitDir)
    [IO.File]::WriteAllBytes($gitFile,[Text.Encoding]::UTF8.GetBytes('git stream host'))
    Set-Content -LiteralPath $gitFile -Stream $gitStream -Value 'git target stream' -NoNewline
    [UniSweepCollectV12]::ResetCounters()
    $gitExact='(?i)^'+[regex]::Escape($gitStream)+'$'
    $gitTask=[UniSweepCollectV12]::CollectAsync($root,'N',$gitExact,$gitExact,@(),@(),@(),1)
    $gitTask.Wait()
    $gitHits=@([UniSweepCollectV12]::StreamMatches)
    Assert-UniOpaqueStreamTest (@($gitHits | Where-Object {[string]::Equals([string]$_.HostPath,$gitFile,[StringComparison]::OrdinalIgnoreCase) -and [string]::Equals([string]$_.StreamName,$gitStream,[StringComparison]::OrdinalIgnoreCase)}).Count -eq 1) 'Regular collector skipped a target stream under .git.'

    # A nested directory with the same display name as the volume Recycle Bin
    # is still ordinary application data and must not inherit the root-only
    # opaque exception.
    $nestedRecycle=Join-Path $root '$Recycle.Bin'
    $nestedFile=Join-Path $nestedRecycle 'nested.bin'
    $nestedStream='NestedRecycleTarget-'+[Guid]::NewGuid().ToString('N')
    [void][IO.Directory]::CreateDirectory($nestedRecycle)
    [IO.File]::WriteAllBytes($nestedFile,[Text.Encoding]::UTF8.GetBytes('nested recycle stream host'))
    Set-Content -LiteralPath $nestedFile -Stream $nestedStream -Value 'nested target stream' -NoNewline
    $nestedExact='(?i)^'+[regex]::Escape($nestedStream)+'$'
    [UniSweepCollectV12]::ResetCounters()
    $nestedTask=[UniSweepCollectV12]::CollectAsync($root,'N',$nestedExact,$nestedExact,@(),@(),@(),1)
    $nestedTask.Wait()
    $nestedHits=@([UniSweepCollectV12]::StreamMatches)
    Assert-UniOpaqueStreamTest (@($nestedHits | Where-Object {[string]::Equals([string]$_.HostPath,$nestedFile,[StringComparison]::OrdinalIgnoreCase) -and [string]::Equals([string]$_.StreamName,$nestedStream,[StringComparison]::OrdinalIgnoreCase)}).Count -eq 1) 'Regular collector skipped a nested $Recycle.Bin directory.'
} finally {
    if(Test-Path -LiteralPath $root -ErrorAction SilentlyContinue){Remove-Item -LiteralPath $root -Recurse -Force}
}

'UNI_OPAQUE_STREAM_COVERAGE_TEST_OK'
