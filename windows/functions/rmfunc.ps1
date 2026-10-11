param(
    [Parameter(Position = 0, Mandatory, ValueFromRemainingArguments)][string[]]$Name
)
$core = 'F:\study\Learning\01\01\Shells\powershell\profile-functions\Invoke-ProfileFunctionMutation.ps1'
if (-not (Test-Path -LiteralPath $core -PathType Leaf)) { throw "rmfunc core engine missing: $core" }
. $core
Invoke-ProfileFunctionMutation -Operation Remove -Name $Name -Force
