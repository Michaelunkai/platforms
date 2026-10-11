$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'uni.ps1')
$script:UniFailed=New-Object 'System.Collections.Generic.List[string]'
$script:UniProtectedArtifacts=New-Object 'System.Collections.Generic.List[string]'
if(Test-UniShadowCopyOutput 'No items found that satisfy the query.'){throw 'Empty VSS output was classified as non-empty'}
if(-not (Test-UniShadowCopyOutput 'Shadow Copy ID: {00000000-0000-0000-0000-000000000000}')){throw 'VSS snapshot output was not detected'}
Invoke-UniShadowCopyAudit
if($script:UniFailed.Count){throw ('Live VSS audit unexpectedly failed: '+($script:UniFailed -join '; '))}
Write-Output 'UNI_SHADOWCOPY_COVERAGE_TEST_OK'
