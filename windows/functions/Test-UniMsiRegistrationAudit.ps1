$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'uni.ps1')
$script:UniFailed=New-Object 'System.Collections.Generic.List[string]'
$script:UniSelectedPrograms=@([pscustomobject]@{Name='MSI fixture';WindowsInstaller=1;KeyName='{12345678-1234-ABCD-EF01-23456789ABCD}'})
$packed=Get-UniMsiPackedProductCode $script:UniSelectedPrograms[0].KeyName
$fixture='HKCU:\Software\Classes\Installer\Products\'+$packed
try {
    New-Item -Path $fixture -Force | Out-Null
    Invoke-UniMsiRegistrationAudit
    $matches=@($script:UniFailed | Where-Object {$_ -match 'MSI product registration remains'})
    if(-not $matches.Count){throw 'MSI registration audit missed an exact packed product registration.'}
    Write-Output 'UNI_MSI_REGISTRATION_AUDIT_TEST_OK'
} finally {Remove-Item -Path ('HKCU:\Software\Classes\Installer\Products') -Recurse -Force -ErrorAction SilentlyContinue}
