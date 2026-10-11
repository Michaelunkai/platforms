param(
    [Parameter(Position = 0, Mandatory)][string]$Name,
    [Parameter(Position = 1, Mandatory)][scriptblock]$Body,
    [switch]$Force
)
$core = 'F:\study\Learning\01\01\Shells\powershell\profile-functions\Invoke-ProfileFunctionMutation.ps1'
if (-not (Test-Path -LiteralPath $core -PathType Leaf)) { throw "addfunc core engine missing: $core" }
. $core
Invoke-ProfileFunctionMutation -Operation Add -Name $Name -Body $Body -Force:$Force
