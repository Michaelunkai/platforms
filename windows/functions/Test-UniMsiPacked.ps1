$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'uni.ps1')
$packed=Get-UniMsiPackedProductCode '{12345678-1234-ABCD-EF01-23456789ABCD}'
if($packed -cne '876543214321DCBAFE1032547698BADC'){throw ('Unexpected packed product code: '+$packed)}
Write-Output 'UNI_MSI_PACKED_TEST_OK'
