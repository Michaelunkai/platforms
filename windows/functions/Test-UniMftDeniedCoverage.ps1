param()

$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'uni.ps1')

function Assert-UniMftCoverageTest {
    param([bool]$Condition,[string]$Message)
    if(-not $Condition){throw $Message}
}

$root='C:\Windows\Temp\UniMftDenied-'+[Guid]::NewGuid().ToString('N')
$leaf='UniMftDeniedTarget-'+[Guid]::NewGuid().ToString('N')+'.bin'
$file=Join-Path $root $leaf
$script:UniFailed=New-Object 'System.Collections.Generic.List[string]'

try {
    [void][IO.Directory]::CreateDirectory($root)
    [IO.File]::WriteAllBytes($file,[Text.Encoding]::UTF8.GetBytes('mft denied coverage'))
    Ensure-UniMftCollect
    Assert-UniMftCoverageTest ([bool]$script:UniMftOk) 'MFT collector was unavailable.'
    $exact='(?i)^'+[regex]::Escape($leaf)+'$'
    $deny=@($root)
    $hits=@([UniMftCollectV1]::Collect($exact,$exact,$deny,@()))
    Assert-UniMftCoverageTest (@($hits | Where-Object {[string]::Equals([string]$_,$file,[StringComparison]::OrdinalIgnoreCase)}).Count -eq 1) 'MFT collector silently filtered an exact target inside a denied subtree.'

    # A denied store can also contain a renamed PE whose filename no longer
    # carries the product identity. The MFT fallback must inspect embedded
    # metadata in the explicitly supplied opaque/denied root.
    $renamed=Join-Path $root 'renamed-mft-target.exe'
    Copy-Item -LiteralPath 'C:\Windows\System32\notepad.exe' -Destination $renamed -Force
    $product=[Diagnostics.FileVersionInfo]::GetVersionInfo($renamed).ProductName
    Assert-UniMftCoverageTest (-not [string]::IsNullOrWhiteSpace($product)) 'PE metadata fixture has no product name.'
    [void][UniMftCollectV1]::Collect([regex]::Escape([string]$product),'(?!)',@(),@(),@($root))
    Assert-UniMftCoverageTest (@([UniMftCollectV1]::MetadataMatches | Where-Object {[string]::Equals([string]$_,$renamed,[StringComparison]::OrdinalIgnoreCase)}).Count -eq 1) 'MFT metadata fallback missed a renamed PE in a denied subtree.'
    Assert-UniMftCoverageTest ([UniMftCollectV1]::MetadataErrors -eq 0) ('MFT metadata fallback reported unexpected errors: '+[UniMftCollectV1]::MetadataErrors)
} finally {
    if(Test-Path -LiteralPath $root -ErrorAction SilentlyContinue){Remove-Item -LiteralPath $root -Recurse -Force}
}

'UNI_MFT_DENIED_COVERAGE_TEST_OK'
