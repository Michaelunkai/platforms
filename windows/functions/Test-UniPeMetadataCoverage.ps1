$ErrorActionPreference='Stop'
$path='F:\study\Platforms\windows\functions\uni.ps1'
. $path
Ensure-UniSweepCollect
$source='C:\Windows\System32\notepad.exe'
if(-not [IO.File]::Exists($source)){throw 'notepad.exe fixture is unavailable'}
$info=[Diagnostics.FileVersionInfo]::GetVersionInfo($source)
$identity=@($info.ProductName,$info.FileDescription,$info.CompanyName,$info.InternalName,$info.OriginalFilename) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
if([string]::IsNullOrWhiteSpace($identity)){throw 'notepad.exe exposes no PE product metadata fixture'}
$root=Join-Path $env:TEMP ('uni-pe-metadata-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
$renamed=Join-Path $root 'renamed-target.exe'
try {
    Copy-Item -LiteralPath $source -Destination $renamed -Force
    [UniSweepCollectV12]::Collect($root,'normal',[regex]::Escape([string]$identity),'(?!)',@(),@(),@(),2)|Out-Null
    if(@([UniSweepCollectV12]::MetadataMatches) -notcontains $renamed){throw 'renamed PE metadata candidate was not surfaced'}
    if([UniSweepCollectV12]::MetadataErrors -ne 0){throw ('unexpected PE metadata coverage errors: '+[UniSweepCollectV12]::MetadataErrors)}
    'PE_METADATA_OK'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
