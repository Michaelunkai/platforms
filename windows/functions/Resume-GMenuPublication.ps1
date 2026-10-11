[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$PendingPath,[switch]$VerifyRestore,[switch]$PassThru)
$ErrorActionPreference='Stop'
$state=[IO.Path]::GetFullPath((Split-Path -Parent $PendingPath)).TrimEnd('\')
$leaf=Split-Path -Leaf $PendingPath
if($leaf -notmatch '^Pending-([a-f0-9]{32})\.json$'){throw 'Invalid pending ticket filename.'}
$id=$Matches[1]
$work=Join-Path $state ('.gmenu-work-'+$id)
if(-not [IO.Directory]::Exists($work)){throw 'Pending encrypted workspace is missing.'}
$lock=$null;$completed=$false
try {
 $lock=[IO.File]::Open((Join-Path $work '.resume.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
 $ticket=Get-Content -LiteralPath $PendingPath -Raw|ConvertFrom-Json
 if($ticket.Schema -ne 1 -or $ticket.Function -notmatch '^g[a-zA-Z0-9]+$' -or $ticket.Function -in @('gm','gmenu') -or $ticket.Folder -ne [IO.Path]::GetFileName([string]$ticket.Folder)){throw 'Invalid recovery identity.'}
 if($ticket.Repository -notmatch '^michadockermisha/[a-z0-9._-]+$' -or $ticket.Tag -notmatch '^[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,127}$'){throw 'Invalid recovery registry reference.'}
 $publish=Join-Path $work $ticket.Folder
 $parts=@($ticket.Parts)
 if(-not $parts.Count){throw 'Recovery ticket contains no encrypted parts.'}
 $names=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
 foreach($part in $parts){
  if($part.Name -notmatch '^gmenu-payload-[0-9]+\.bin$' -or -not $names.Add([string]$part.Name)){throw 'Invalid or duplicate encrypted part name.'}
  $file=Join-Path $publish $part.Name
  if(-not [IO.File]::Exists($file) -or (Get-Item -LiteralPath $file).Length -ne [long]$part.Length){throw 'Encrypted recovery part is missing or truncated.'}
  if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ine [string]$part.Sha256){throw 'Encrypted recovery part checksum mismatch.'}
 }
 if(@(Get-ChildItem -LiteralPath $publish -File -Force).Count -ne $parts.Count){throw 'Recovery payload contains unexpected files.'}
 $script:GMenuPayloadSource=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'GMenuPayload.cs'))
 . (Join-Path $PSScriptRoot 'GMenuRuntime.ps1')
 Initialize-GMenuRuntime
 $publisher=Join-Path $PSScriptRoot 'mmenu_chunked_push.ps1'
 $envNames=@('HERMES_MMENU_REPOSITORY_OVERRIDE','HERMES_MMENU_TAG_OVERRIDE','HERMES_MMENU_GMENU','HERMES_MMENU_SOURCE_LABEL_PATH_OVERRIDE')
 $old=@{};foreach($envName in $envNames){$old[$envName]=[Environment]::GetEnvironmentVariable($envName)}
 try {
  $env:HERMES_MMENU_REPOSITORY_OVERRIDE=[string]$ticket.Repository
  $env:HERMES_MMENU_TAG_OVERRIDE=[string]$ticket.Tag
  $env:HERMES_MMENU_GMENU='1'
  $env:HERMES_MMENU_SOURCE_LABEL_PATH_OVERRIDE=[string]$ticket.Target
  Write-Host ('GMENU_RESUME verified_parts={0} image={1}:{2}; existing encrypted payload reused' -f $parts.Count,$ticket.Repository,$ticket.Tag)
  $global:LASTEXITCODE=0
  & $publisher -Path $publish -TargetLayerMiB 256 -EntryPoint gm | Out-Host
  if($LASTEXITCODE -ne 0){throw 'Recovery publication did not complete; encrypted payload retained.'}
 } finally {foreach($envName in $envNames){[Environment]::SetEnvironmentVariable($envName,$old[$envName])}}
 $credential=Get-GMenuLocalHubCredential
 $token=Get-GMenuHubToken $ticket.Repository $credential
 $remote=Get-GMenuManifest $ticket.Repository $ticket.Tag $work $token
 $ticket.Digest=$remote.Digest
 Write-GMenuDurableText -Path $PendingPath -Content ($ticket|ConvertTo-Json -Depth 20)
 $ticketBase64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($ticket|ConvertTo-Json -Depth 20 -Compress)))
 $sourceBase64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script:GMenuPayloadSource))
 $header=@'
# GMENU GENERATED RESTORE COMMAND - PRIVATE RECOVERY KEY INCLUDED. Do not publish this script.
[CmdletBinding()]
param([string]$Destination,[pscredential]$Credential,[switch]$RestoreOnly)
$ErrorActionPreference='Stop'
'@
 $text=$header+[Environment]::NewLine+
  ('$script:GMenuPayloadSource=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+$sourceBase64+'''))')+[Environment]::NewLine+
  ('$script:GMenuTicket=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+$ticketBase64+''')) | ConvertFrom-Json')+[Environment]::NewLine+
  [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'GMenuRuntime.ps1'))+[Environment]::NewLine+
  'Invoke-GMenuRestore -Ticket $script:GMenuTicket -Destination $Destination -Credential $Credential -RestoreOnly:$RestoreOnly'
 $generated=Join-Path $work ($ticket.Function+'.generated.ps1')
 Write-GMenuDurableText -Path $generated -Content $text
 Register-GMenuPortableCommand -Ticket $ticket -SourceScript $generated -UpgradeExisting
 if($VerifyRestore){
  $global:LASTEXITCODE=0
  & $generated -Credential $credential | Out-Host
  if($LASTEXITCODE -ne 0){throw 'Publication saved; restore verification failed; recovery retained.'}
 }
 $completed=$true
} finally {
 if($lock){$lock.Dispose()}
 if($completed){
  Remove-GMenuWork $work $state
  [IO.File]::Delete($PendingPath)
  foreach($dir in @(Get-ChildItem -LiteralPath $state -Directory -Recurse -Force|Sort-Object {$_.FullName.Length} -Descending)){
   if(-not @(Get-ChildItem -LiteralPath $dir.FullName -Force).Count){[IO.Directory]::Delete($dir.FullName)}
  }
  if(-not @(Get-ChildItem -LiteralPath $state -Force).Count){[IO.Directory]::Delete($state)}
 }else{Write-Host ('GMENU_RECOVERY_RETAINED pending='+$PendingPath)}
}
$global:LASTEXITCODE=0
Write-Host ('GMENU_SAVED function={0} image={1}:{2} digest={3} resumed=true cleanup=complete' -f $ticket.Function,$ticket.Repository,$ticket.Tag,$ticket.Digest)
if($PassThru){[pscustomobject]@{Function=$ticket.Function;Source=$ticket.Target;Repository=$ticket.Repository;Tag=$ticket.Tag;Digest=$ticket.Digest;Files=$ticket.Files;Bytes=$ticket.Bytes;Script='embedded-in-profile';Resumed=$true}}
