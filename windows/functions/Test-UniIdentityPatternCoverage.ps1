param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'uni.ps1')

function Assert-UniPatternTest {
    param([bool]$Condition,[string]$Message)
    if(-not $Condition){throw $Message}
}

$short=Get-UniPatterns @('AI')
Assert-UniPatternTest ($null -ne $short) 'A short product identity was rejected before ownership discovery.'
$shortExact=New-Object System.Text.RegularExpressions.Regex($short.Exact,[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
Assert-UniPatternTest ($shortExact.IsMatch('AI.exe')) 'Short identity did not match an exact executable name.'
Assert-UniPatternTest (-not $shortExact.IsMatch('AIM.exe')) 'Short identity matched a larger unrelated token.'
Assert-UniPatternTest ($short.Orphan -eq '(?!)') 'Unregistered short identity received an unsafe orphan pattern.'

$normal=Get-UniPatterns @('ContosoTarget')
$normalOrphan=New-Object System.Text.RegularExpressions.Regex($normal.Orphan,[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
Assert-UniPatternTest ($normalOrphan.IsMatch('ContosoTargetSetup.exe')) 'Normal identity lost its bounded orphan suffix matching.'

$generic=Get-UniPatterns @('app')
Assert-UniPatternTest ($null -eq $generic) 'Generic identity was allowed to create a broad cleanup pattern.'

# Windows Installer is a shared cache. A product-shaped filename there must
# never become a direct deletion root from a name-only sweep.
Assert-UniPatternTest (-not (Test-UniSafeRoot 'C:\Windows\Installer\ContosoTarget.msi')) 'Windows Installer cache was treated as a deletable app root.'

$unicode=Get-UniPatterns @('照片工具')
Assert-UniPatternTest ($null -ne $unicode) 'A non-ASCII product identity was discarded before ownership discovery.'
$unicodeExact=New-Object System.Text.RegularExpressions.Regex($unicode.Exact,[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
Assert-UniPatternTest ($unicodeExact.IsMatch('照片工具.exe')) 'Unicode identity did not match an exact executable name.'
Assert-UniPatternTest (-not $unicodeExact.IsMatch('照片工具箱.exe')) 'Unicode identity matched a larger unrelated token.'

# A concrete path in a verified app root is sufficient for a vendor-specific
# registry value; a free-form product mention is not.
$savedOwnedRoots=@($script:UniOwnedRoots)
$savedOtherRoots=@($script:UniOtherRoots)
$savedOwnedFiles=$script:UniOwnedFiles
try {
    $script:UniOwnedRoots=@('C:\ProgramData\ContosoTarget')
    $script:UniOtherRoots=@()
    $script:UniOwnedFiles=$null
    Assert-UniPatternTest (Test-UniRegistryValueOwnedPathReference 'C:\ProgramData\ContosoTarget\agent.exe') 'Owned absolute registry path was not recognized.'
    Assert-UniPatternTest (-not (Test-UniRegistryValueOwnedPathReference 'ContosoTarget is installed somewhere')) 'Free-form registry text was incorrectly treated as an owned path.'
} finally {
    $script:UniOwnedRoots=$savedOwnedRoots
    $script:UniOtherRoots=$savedOtherRoots
    $script:UniOwnedFiles=$savedOwnedFiles
}

# A failed/shared install root must remain vetoed during the aggressive sweep;
# only an exact child candidate explicitly registered by the scanner may pass.
$savedAggressive=$script:UniAggressiveSweep
try {
    $script:UniAggressiveSweep=$true
    $script:UniOwnedRoots=@('C:\ProgramData\FailedApp')
    $script:UniOtherRoots=@('C:\ProgramData\FailedApp')
    $script:UniOwnedFiles=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    Assert-UniPatternTest (-not(Test-UniOwnedPath 'C:\ProgramData\FailedApp')) 'Shared failed-install root bypassed the ownership veto.'
    [void]$script:UniOwnedFiles.Add('C:\ProgramData\FailedApp\exact-target.exe')
    Assert-UniPatternTest (Test-UniOwnedPath 'C:\ProgramData\FailedApp\exact-target.exe') 'Exact scanner-authorized child was incorrectly blocked by the shared-root veto.'
} finally {
    $script:UniAggressiveSweep=$savedAggressive
}

# Permanent WMI consumers are another persistence surface.  A shared host
# carrying a verified app executable is attributable; a host that merely
# mentions the product in free-form arguments is not.
$savedExecutionRoots=@($script:UniExecutionRoots)
$savedRequestedIdentities=@($script:UniRequestedIdentities)
$savedIobit=$script:UniIObitRequested
try {
    $script:UniOwnedRoots=@('C:\ProgramData\ContosoTarget')
    $script:UniOtherRoots=@()
    $script:UniOwnedFiles=$null
    $script:UniExecutionRoots=@()
    $script:UniRequestedIdentities=@('contosotarget')
    $script:UniIObitRequested=$false
    $wmiPattern=New-Object System.Text.RegularExpressions.Regex($normal.Exact,[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    Assert-UniPatternTest (Test-UniWmiConsumerOwned ([pscustomobject]@{Name='ServiceHost';ExecutablePath='C:\ProgramData\ContosoTarget\agent.exe'}) $wmiPattern) 'Owned WMI consumer executable was not recognized.'
    Assert-UniPatternTest (-not(Test-UniWmiConsumerOwned ([pscustomobject]@{Name='ServiceHost';ExecutablePath='C:\Windows\System32\svchost.exe';CommandLineTemplate='-k ContosoTarget'}) $wmiPattern)) 'Free-form WMI command text was incorrectly treated as ownership.'
    Assert-UniPatternTest (-not(Test-UniWmiConsumerOwned ([pscustomobject]@{Name='ContosoTarget Consumer';ExecutablePath='C:\Windows\System32\svchost.exe'}) $wmiPattern)) 'A target-named WMI consumer without an owned executable was incorrectly authorized.'
    Assert-UniPatternTest (Test-UniWmiFilterOwned ([pscustomobject]@{Name='ContosoTarget Filter';Query="SELECT * FROM __InstanceCreationEvent WITHIN 5 WHERE TargetInstance ISA 'Win32_Process' AND TargetInstance.ExecutablePath = 'C:\ProgramData\ContosoTarget\agent.exe'"}) $wmiPattern) 'Owned WMI filter query path was not recognized.'
    Assert-UniPatternTest (-not(Test-UniWmiFilterOwned ([pscustomobject]@{Name='ContosoTarget Filter';Query="SELECT * FROM __InstanceCreationEvent WHERE TargetInstance ISA 'Win32_Process'"}) $wmiPattern)) 'A target-named WMI filter without an owned query path was incorrectly authorized.'
    Assert-UniPatternTest (Test-UniBitsJobOwned ([pscustomobject]@{DisplayName='Background transfer';Files=@([pscustomobject]@{LocalName='C:\ProgramData\ContosoTarget\payload.bin';RemoteName='https://example.invalid/payload.bin'})}) $wmiPattern) 'Owned BITS transfer path was not recognized.'
    Assert-UniPatternTest (-not(Test-UniBitsJobOwned ([pscustomobject]@{DisplayName='Background transfer';Files=@([pscustomobject]@{LocalName='C:\Windows\System32\svchost.exe';RemoteName='https://example.invalid/ContosoTarget'})}) $wmiPattern)) 'Free-form BITS metadata was incorrectly treated as ownership.'
    Assert-UniPatternTest (-not(Test-UniBitsJobOwned ([pscustomobject]@{DisplayName='ContosoTarget transfer';Files=@()}) $wmiPattern)) 'A target-named BITS job without an owned transfer path was incorrectly authorized.'
} finally {
    $script:UniExecutionRoots=$savedExecutionRoots
    $script:UniRequestedIdentities=$savedRequestedIdentities
    $script:UniIObitRequested=$savedIobit
}

foreach($detail in @(
    'HKU\.DEFAULT\Software\Microsoft\SystemCertificates\Root\ProtectedRoots [SecurityException; HRESULT -2146233078]',
    'HKLM\SYSTEM\CurrentControlSet\Services\mpssvc\Parameters\PortKeywords\Teredo [SecurityException; HRESULT -2146233078]',
    'HKLM\SYSTEM\ControlSet001\Services\mpssvc\Parameters\PortKeywords\Teredo [SecurityException; HRESULT -2146233078]'
)){
    Assert-UniPatternTest (Test-UniWindowsOwnedRegistryScanError $detail) ('Known protected registry namespace was not classified: '+$detail)
}

'UNI_IDENTITY_PATTERN_COVERAGE_TEST_OK'
