[CmdletBinding()]
param(
    [string]$Token,
    [switch]$PersistToken
)

$implementation = Join-Path $PSScriptRoot 'Invoke-Gitlog.ps1'
if (-not (Test-Path -LiteralPath $implementation -PathType Leaf)) {
    throw "gitlog implementation is missing: $implementation"
}

& $implementation -Token $Token -PersistToken:$PersistToken
$global:LASTEXITCODE = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
