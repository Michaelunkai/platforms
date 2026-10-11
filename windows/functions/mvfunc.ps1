param(
    [Parameter(Position = 0)][string]$Name,
    [Parameter(Position = 1)][object]$Replacement,
    [switch]$Force,
    [switch]$SelfTest
)
$core = 'F:\study\Learning\01\01\Shells\powershell\profile-functions\Invoke-ProfileFunctionMutation.ps1'
if (-not (Test-Path -LiteralPath $core -PathType Leaf)) { throw "mvfunc core engine missing: $core" }
. $core
if ($SelfTest) {
    Invoke-ProfileFunctionMutation -Operation Replace -Name '__ProfileMutationSelfTest' -Body { $null } -SelfTest
    return
}
if ([string]::IsNullOrWhiteSpace($Name)) {
    Write-Host 'mvfunc <Name> { replacement body }  OR  mvfunc <Name> <NewName>' -ForegroundColor Cyan
    return
}
if ($Replacement -is [scriptblock]) {
    Invoke-ProfileFunctionMutation -Operation Replace -Name $Name -Body $Replacement -Force:$Force
    return
}
if ($Replacement -is [string] -and -not [string]::IsNullOrWhiteSpace($Replacement)) {
    Invoke-ProfileFunctionMutation -Operation Rename -Name $Name -NewName $Replacement -Force:$Force
    return
}
throw 'mvfunc requires a replacement script block or a new function name.'
