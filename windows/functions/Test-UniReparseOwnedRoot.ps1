$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'uni.ps1')
$script:UniFailed=New-Object 'System.Collections.Generic.List[string]'
$script:UniProtectedReferences=@()
$script:UniOtherRoots=@()
$script:UniOwnedRoots=@()
$script:UniOwnedFiles=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$script:UniAggressiveSweep=$true
$base=Join-Path (Join-Path $env:WINDIR 'Temp') ('uni-reparse-owned-'+[guid]::NewGuid().ToString('N'))
$owned=Join-Path $base 'owned'
$outside=Join-Path $base 'outside'
$sentinel=Join-Path $outside 'sentinel.txt'
$junction=Join-Path $owned 'shared-link'
$ownedLink=Join-Path $base 'owned-root-link'
try {
    New-Item -Path $owned -ItemType Directory -Force | Out-Null
    New-Item -Path $outside -ItemType Directory -Force | Out-Null
    [IO.File]::WriteAllText($sentinel,'must-survive')
    New-Item -Path $junction -ItemType Junction -Target $outside -Force | Out-Null
    $script:UniOwnedRoots=@($owned)
    if(-not (Remove-UniTarget $owned)){throw 'Owned root with reparse child was not removed'}
    if(Test-Path -LiteralPath $junction){throw 'Reparse child link object remains'}
    if(-not (Test-Path -LiteralPath $sentinel)){throw 'Reparse target was followed or deleted'}
    New-Item -Path $ownedLink -ItemType Junction -Target $outside -Force | Out-Null
    $script:UniOwnedRoots=@($ownedLink)
    if(-not (Remove-UniTarget $ownedLink)){throw 'Authorized reparse root was not unlinked'}
    if(Test-Path -LiteralPath $ownedLink){throw 'Authorized reparse root link remains'}
    if(-not (Test-Path -LiteralPath $sentinel)){throw 'Authorized reparse root target was followed or deleted'}
    Write-Output 'UNI_REPARSE_OWNED_ROOT_TEST_OK'
} finally {
    if(Test-Path -LiteralPath $junction){Remove-Item -LiteralPath $junction -Force -ErrorAction SilentlyContinue}
    if(Test-Path -LiteralPath $ownedLink){Remove-Item -LiteralPath $ownedLink -Force -ErrorAction SilentlyContinue}
    if(Test-Path -LiteralPath $owned){Remove-Item -LiteralPath $owned -Recurse -Force -ErrorAction SilentlyContinue}
    if(Test-Path -LiteralPath $sentinel){Remove-Item -LiteralPath $sentinel -Force -ErrorAction SilentlyContinue}
    if(Test-Path -LiteralPath $outside){Remove-Item -LiteralPath $outside -Recurse -Force -ErrorAction SilentlyContinue}
    if(Test-Path -LiteralPath $base){Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue}
}
