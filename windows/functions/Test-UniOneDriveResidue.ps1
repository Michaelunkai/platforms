param()

$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot 'uni.ps1'
. $scriptPath

function Assert-UniTest {
    param([bool]$Condition,[string]$Message)
    if(-not $Condition){throw $Message}
}

$required=@(
    'Get-UniOneDriveClientRoots',
    'Remove-UniOneDriveRegistryValue',
    'Remove-UniOneDriveListToken',
    'Test-UniOneDriveEnvironmentName',
    'Test-UniOneDriveEphemeralTracePath',
    'Test-UniOneDriveWindowsOwnedPath',
    'Test-UniOneDriveWindowsRegistryReference',
    'Test-UniOneDriveWindowsRegistryKey',
    'Test-UniOneDriveUninstallExitAcceptable',
    'Invoke-UniOneDriveKnownRegistryResidue'
)
foreach($name in $required){
    Assert-UniTest ([bool](Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)) ('Missing OneDrive residue function: '+$name)
}

$script:UniRequestedIdentities=@('onedrive')
$script:UniWindowsOwnedArtifacts=New-Object 'System.Collections.Generic.List[string]'
$script:UniStats=@{RegValues=0}

$roots=@(Get-UniOneDriveClientRoots -ProfileRoots @('C:\Users\Admin','C:\Users\Other'))
Assert-UniTest ($roots -contains 'C:\Users\Admin\AppData\Local\Microsoft\OneDrive') 'Current-profile OneDrive client data root was not included.'
Assert-UniTest ($roots -contains 'C:\Users\Other\AppData\Roaming\Microsoft\OneDrive') 'Other-profile OneDrive client data root was not included.'
Assert-UniTest ($roots -contains 'C:\ProgramData\Microsoft OneDrive') 'Machine OneDrive client data root was not included.'
Assert-UniTest ($roots -notcontains 'C:\Users\Admin\OneDrive') 'User sync content must not be classified as client-owned data.'

$cleaned=Remove-UniOneDriveListToken -Value 'AppData\Local;OneDrive;Work Folders;MyOneDrive' -Token 'OneDrive'
Assert-UniTest ($cleaned -ceq 'AppData\Local;Work Folders;MyOneDrive') 'Exact OneDrive token was not removed surgically.'
Assert-UniTest ((Remove-UniOneDriveListToken -Value 'MyOneDrive;OneDriveBackup' -Token 'OneDrive') -ceq 'MyOneDrive;OneDriveBackup') 'Substring list entries were removed.'

foreach($name in @('OneDrive','OneDriveConsumer','OneDriveCommercial')){
    Assert-UniTest (Test-UniOneDriveEnvironmentName $name) ('Known OneDrive environment name was rejected: '+$name)
}
Assert-UniTest (-not(Test-UniOneDriveEnvironmentName 'MyOneDrive')) 'A merely similar environment name was accepted.'

Assert-UniTest (Test-UniOneDriveEphemeralTracePath 'C:\Windows\Prefetch\ONEDRIVESETUP.EXE-2F4C4906.pf') 'OneDriveSetup prefetch trace was not recognized.'
Assert-UniTest (Test-UniOneDriveEphemeralTracePath 'C:\Windows\Prefetch\ONEDRIVE.EXE-01234567.pf') 'OneDrive prefetch trace was not recognized.'
Assert-UniTest (-not(Test-UniOneDriveEphemeralTracePath 'C:\Windows\Prefetch\NOTONEDRIVESETUP.EXE-2F4C4906.pf')) 'Similar prefetch file was accepted.'
Assert-UniTest (-not(Test-UniOneDriveEphemeralTracePath 'C:\Windows\System32\OneDriveSetup.exe')) 'Windows setup binary was classified as an ephemeral trace.'

Assert-UniTest (Test-UniOneDriveWindowsOwnedPath 'C:\Windows\WinSxS\amd64_microsoft-windows-onedrive-setup_31bf3856ad364e35_10.0.1_none_x') 'WinSxS OneDrive component was not classified as Windows-owned.'
Assert-UniTest (Test-UniOneDriveWindowsOwnedPath '\\?\C:\ProgramData\Microsoft\Windows\Containers\Layers\layer\Files\Windows\System32\OneDriveSetup.exe') 'Extended-length container OneDrive path was not classified as Windows-owned.'
Assert-UniTest (Test-UniOneDriveWindowsOwnedPath 'C:\Program Files\WindowsApps\Microsoft.Windows.Photos_1.0_x64__8wekyb3d8bbwe\OneDrive.pri') 'Windows Photos OneDrive resource was not classified as Windows-owned.'
Assert-UniTest (-not(Test-UniOneDriveWindowsOwnedPath 'C:\Users\Admin\AppData\Local\Microsoft\OneDrive')) 'Client data was classified as Windows-owned.'
Assert-UniTest (-not(Test-UniOneDriveWindowsOwnedPath 'C:\Windows\Prefetch\ONEDRIVESETUP.EXE-2F4C4906.pf')) 'Deletable prefetch trace was classified as Windows-owned.'

# The same OS-owned hit may arrive through a collector path that calls the
# generic protected-artifact helper.  It must remain explicitly Windows-owned,
# not become an unexplained ambiguity that poisons the uninstall result.
$script:UniProtectedArtifacts=New-Object 'System.Collections.Generic.List[string]'
$beforeProtected=$script:UniProtectedArtifacts.Count
Add-UniProtectedArtifact 'C:\Windows\System32\OneDriveSetup.exe'
Assert-UniTest ($script:UniProtectedArtifacts.Count -eq $beforeProtected) 'Windows-owned OneDrive component was recorded as a generic protected artifact.'
Assert-UniTest (@($script:UniWindowsOwnedArtifacts | Where-Object {$_ -match 'Windows OneDrive integration binary'}).Count -gt 0) 'Windows-owned OneDrive component was not recorded in the OS-owned audit.'

$knownRegistry=@(
    @('Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\RulesEngine\BackgroundData','Data','OneDrive'),
    @('Registry::HKLM\SOFTWARE\Microsoft\PolicyManager\default\System\DisableOneDriveFileSync','RegKeyPathRedirect','OneDrive'),
    @('Registry::HKLM\SOFTWARE\Microsoft\SystemCertificates\AuthRoot\AutoUpdate','PinRulesEncodedCtl',[byte[]](1,2,3)),
    @('Registry::HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\UserDefaults','ExcludeProfileDirs','OneDrive'),
    @('Registry::HKLM\SOFTWARE\Microsoft\WindowsSelfHost\OneSettings','TargetingAttributes','OneDrive'),
    @('Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\BannerStore\OptIn','URL','http://www.onedrive.com'),
    @('Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FolderDescriptions\{A52BBA46-E9E1-435f-B3D9-28DAA648C0F6}','Name','OneDrive'),
    @('Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OneSettings\WSD\SetupPlatform\Settings','MONITORINGEXTRAPATHS','OneDrive'),
    @('Registry::HKEY_USERS\S-1-5-19\Software\Microsoft\Windows\CurrentVersion\Run','OneDriveSetup','C:\Windows\System32\OneDriveSetup.exe /thfirstsetup'),
    @('Registry::HKEY_USERS\S-1-5-20\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run','OneDriveSetup',[byte[]](2,0,0,0))
)
foreach($case in $knownRegistry){
    Assert-UniTest (Test-UniOneDriveWindowsRegistryReference -ProviderPath $case[0] -ValueName $case[1] -Value $case[2]) ('Known Windows-owned registry reference was not classified: '+$case[0]+' :: '+$case[1])
}
Assert-UniTest (Test-UniOwnedRegistryValue -ProviderPath 'Registry::HKCU\Software\Classes\TypeLib\{F904F88C-E60D-4327-9FA2-865AD075B400}\1.0\HELPDIR' -ValueName '' -Value 'C:\Users\Admin\AppData\Local\Microsoft\OneDrive\21.220.1024.0005') 'OneDrive TypeLib HELPDIR was not classified as removable client residue.'
Assert-UniTest (Test-UniOwnedRegistryValue -ProviderPath 'Registry::HKCU\Software\Classes\TypeLib\{F904F88C-E60D-4327-9FA2-865AD075B400}\1.0\HELPDIR' -ValueName '' -Value '') 'Empty OneDrive TypeLib HELPDIR residue was not classified by its exact stable identity.'
Assert-UniTest (Test-UniOwnedRegistryValue -ProviderPath 'Registry::HKCR\TypeLib\{BAE13F6C-0E2A-4DEB-AA46-B8F55319347C}\1.0\HELPDIR' -ValueName '' -Value 'C:\Users\Admin\AppData\Local\Microsoft\OneDrive\18.151.0729.0013') 'Merged HKCR OneDrive TypeLib HELPDIR was not classified as removable client residue.'
Assert-UniTest (Test-UniOwnedRegistryValue -ProviderPath 'Registry::HKCR\WOW6432Node\TypeLib\{F904F88C-E60D-4327-9FA2-865AD075B400}\1.0\HELPDIR' -ValueName '' -Value '') 'Merged HKCR WOW64 empty OneDrive TypeLib HELPDIR was not classified by its exact identity.'
Assert-UniTest (Test-UniOwnedRegistryValue -ProviderPath 'Registry::HKLM\Software\Classes\TypeLib\{909A6CCD-6810-46C4-89DF-05BE7EB61E6C}\1.0\HELPDIR' -ValueName '' -Value 'C:\Users\Admin\AppData\Local\Microsoft\OneDrive\21.220.1024.0005') 'Machine Classes OneDrive TypeLib HELPDIR was not classified as removable client residue.'
Assert-UniTest (Test-UniOwnedRegistryValue -ProviderPath 'Registry::HKLM\Software\Classes\TypeLib\{F904F88C-E60D-4327-9FA2-865AD075B400}\1.0\HELPDIR' -ValueName '' -Value '') 'Machine empty OneDrive TypeLib HELPDIR residue was not classified by its exact identity.'
Assert-UniTest (Test-UniOwnedRegistryValue -ProviderPath 'Registry::HKLM\Software\WOW6432Node\Classes\TypeLib\{F904F88C-E60D-4327-9FA2-865AD075B400}\1.0\HELPDIR' -ValueName '' -Value '') 'WOW64 machine empty OneDrive TypeLib HELPDIR residue was not classified by its exact identity.'
Assert-UniTest (Test-UniOwnedRegistryValue -ProviderPath 'Registry::HKEY_USERS\S-1-5-21-111-222-333-1001_Classes\TypeLib\{C9F3F6BB-3172-4CD8-9EB7-37C9BE601C87}\1.0\HELPDIR' -ValueName '' -Value 'C:\Users\Admin\AppData\Local\Microsoft\OneDrive\21.220.1024.0005') 'Loaded-user Classes OneDrive TypeLib HELPDIR was not classified as removable client residue.'
Assert-UniTest (-not(Test-UniOneDriveWindowsRegistryReference -ProviderPath 'Registry::HKCU\Software\Classes\TypeLib\{F904F88C-E60D-4327-9FA2-865AD075B400}\1.0\HELPDIR' -ValueName '' -Value 'C:\Users\Admin\AppData\Local\Microsoft\OneDrive\21.220.1024.0005')) 'OneDrive TypeLib client residue was incorrectly preserved as Windows-owned state.'
Assert-UniTest (-not(Test-UniOneDriveWindowsRegistryReference -ProviderPath 'Registry::HKCU\Software\Microsoft\Example' -ValueName 'OneDrive' -Value 'OneDrive')) 'Unknown Microsoft registry value was over-classified.'

# Exercise the complete OneDrive-specific registry phase against the exact
# empty-HELPDIR shape from the residue report, not only its ownership helper.
$emptyTypeLibRoot='HKCU:\Software\Classes\TypeLib\{F904F88C-E60D-4327-9FA2-865AD075B400}'
$emptyTypeLibLeaf=$emptyTypeLibRoot+'\1.0\HELPDIR'
try {
    New-Item -Path $emptyTypeLibLeaf -Force -Value '' | Out-Null
    Invoke-UniOneDriveKnownRegistryResidue
    Assert-UniTest (-not(Test-Path -LiteralPath $emptyTypeLibRoot)) 'Empty OneDrive TypeLib tree remained after the OneDrive-specific cleanup phase.'
} finally {
    if(Test-Path -LiteralPath $emptyTypeLibRoot){Remove-Item -LiteralPath $emptyTypeLibRoot -Recurse -Force -ErrorAction SilentlyContinue}
}

$knownWindowsKeys=@(
    'Registry::HKCR\CLSID\{78DE489B-7931-4f14-83B4-C56D38AC9FFA}',
    'Registry::HKCR\CLSID\{86C815AA-4888-4063-B0AB-03C49F788BE4}',
    'Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\Packages\Microsoft-Windows-OneDrive-Setup-Package~31bf3856ad364e35~amd64~~10.0.26100.1',
    'Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\SideBySide\Winners\amd64_microsoft-windows-onedrive-setup_31bf3856ad364e35_none_x',
    'Registry::HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Update\TargetingInfo\PersistentDynamicInstalled\onedrive.amd64',
    'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration\DynamicAppListing\onedrive',
    'Registry::HKEY_USERS\S-1-5-19\Software\Microsoft\OneDrive'
)
foreach($path in $knownWindowsKeys){Assert-UniTest (Test-UniOneDriveWindowsRegistryKey $path) ('Known Windows OneDrive key was not classified: '+$path)}
Assert-UniTest (-not(Test-UniOneDriveWindowsRegistryKey 'Registry::HKCU\Software\Contoso\OneDrive')) 'Unknown OneDrive key was over-classified.'

Assert-UniTest (Test-UniOneDriveUninstallExitAcceptable -ExitCode 0 -ClientPresent $true) 'Successful uninstaller exit was rejected.'
Assert-UniTest (Test-UniOneDriveUninstallExitAcceptable -ExitCode -2147219813 -ClientPresent $false) 'Idempotent nonzero exit was rejected after the client was absent.'
Assert-UniTest (-not(Test-UniOneDriveUninstallExitAcceptable -ExitCode -2147219813 -ClientPresent $true)) 'Nonzero exit was accepted while client files remain.'

$beforeFailures=$script:UniFailed.Count
$invalidPathResult=Test-UniNameOrPathMatch -Path 'not<a>filesystem"path' -Regex ([regex]'onedrive')
Assert-UniTest (-not $invalidPathResult) 'Invalid non-path data matched as a filesystem path.'
Assert-UniTest ($script:UniFailed.Count -eq $beforeFailures) 'Invalid registry data was incorrectly recorded as a path-matching failure.'

$fixture='HKCU:\Software\UniOneDriveResidueTest-'+[Guid]::NewGuid().ToString('N')
try {
    New-Item -Path $fixture -Force | Out-Null
    New-ItemProperty -LiteralPath $fixture -Name 'OneDrive.exe' -Value 11000 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -LiteralPath $fixture -Name 'Sibling.exe' -Value 12000 -PropertyType DWord -Force | Out-Null
    [void](Remove-UniOneDriveRegistryValue -ProviderPath $fixture -ValueName 'OneDrive.exe' -Validator {param($value) $value -eq 11000})
    $key=Get-Item -LiteralPath $fixture
    try {
        Assert-UniTest ($key.GetValueNames() -notcontains 'OneDrive.exe') 'Exact OneDrive registry value remained.'
        Assert-UniTest ($key.GetValueNames() -contains 'Sibling.exe') 'Sibling registry value was removed.'
    } finally {$key.Close()}
} finally {
    if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force}
}

'UNI_ONEDRIVE_RESIDUE_TEST_OK'
