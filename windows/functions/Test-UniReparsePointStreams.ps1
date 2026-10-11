param()
$__codexSafeAddTypePath = 'F:\study\Platforms\windows\functions\Invoke-CodexSafePowerShellAddType.ps1'
if ([IO.File]::Exists($__codexSafeAddTypePath)) { . $__codexSafeAddTypePath }

$ErrorActionPreference='Stop'
$scriptPath=Join-Path $PSScriptRoot 'uni.ps1'
. $scriptPath

function Assert-UniReparseStreamTest {
    param([bool]$Condition,[string]$Message)
    if(-not $Condition){throw $Message}
}

if(-not ('UniReparseStreamFixtureV1' -as [type])){
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class UniReparseStreamFixtureV1
{
    private const uint GENERIC_WRITE=0x40000000;
    private const uint FILE_SHARE_ALL=7;
    private const uint CREATE_ALWAYS=2;
    private const uint FILE_FLAG_OPEN_REPARSE_POINT=0x00200000;
    private const uint FILE_FLAG_BACKUP_SEMANTICS=0x02000000;

    [DllImport("kernel32.dll",EntryPoint="CreateFileW",CharSet=CharSet.Unicode,SetLastError=true)]
    private static extern SafeFileHandle CreateFile(string name,uint access,uint share,IntPtr security,uint creation,uint flags,IntPtr template);
    [DllImport("kernel32.dll",SetLastError=true)]
    private static extern bool WriteFile(SafeFileHandle file,byte[] buffer,uint requested,out uint written,IntPtr overlapped);

    public static void Create(string linkPath,string streamName)
    {
        string streamPath=linkPath+":"+streamName;
        using(var file=CreateFile(streamPath,GENERIC_WRITE,FILE_SHARE_ALL,IntPtr.Zero,CREATE_ALWAYS,FILE_FLAG_OPEN_REPARSE_POINT|FILE_FLAG_BACKUP_SEMANTICS,IntPtr.Zero)) {
            if(file.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error(),"Could not create a stream on the reparse-point object");
            byte[] payload=new byte[] { 0x55,0x4e,0x49 };
            uint written;
            if(!WriteFile(file,payload,(uint)payload.Length,out written,IntPtr.Zero) || written!=(uint)payload.Length)
                throw new Win32Exception(Marshal.GetLastWin32Error(),"Could not write the reparse-point stream fixture");
        }
    }
}
'@
}

$root='C:\Windows\Temp\UniReparsePointStreams-'+[Guid]::NewGuid().ToString('N')
$target=Join-Path $root 'target'
$link=Join-Path $root 'link'
$linkStream='UniReparseProbe'
$targetStream='UniTargetOnly'

try {
    [void][IO.Directory]::CreateDirectory($target)
    New-Item -ItemType Junction -Path $link -Target $target -ErrorAction Stop | Out-Null
    Set-Content -LiteralPath ($target+':'+$targetStream) -Value 'target must remain untouched' -NoNewline
    [UniReparseStreamFixtureV1]::Create($link,$linkStream)

    $targetStreams=@(Get-UniNamedDataStreams -Path $target)
    Assert-UniReparseStreamTest (@($targetStreams | Where-Object {$_.StreamName -ceq $linkStream}).Count -eq 0) 'Fixture leaked the link-object stream onto the target.'
    Assert-UniReparseStreamTest (@($targetStreams | Where-Object {$_.StreamName -ceq $targetStream}).Count -eq 1) 'Target-only control stream was not created.'

    $linkStreams=@(Get-UniNamedDataStreams -Path $link)
    Assert-UniReparseStreamTest (@($linkStreams | Where-Object {$_.StreamName -ceq $linkStream}).Count -eq 1) 'Named stream on the reparse-point object was missed.'
    Assert-UniReparseStreamTest (@($linkStreams | Where-Object {$_.StreamName -ceq $targetStream}).Count -eq 0) 'Named-stream enumeration followed the reparse target.'

    $pattern=[regex]::Escape($linkStream)
    Ensure-UniSweepCollect
    Assert-UniReparseStreamTest $script:UniCollectOk ('Filesystem collector did not initialize: '+$script:UniCollectError)
    $tagMethod=[UniSweepCollectV12].GetMethod('GetReparseTag')
    $policyMethod=[UniSweepCollectV12].GetMethod('ReparseTagCanHaveNamedStreams')
    $aliasMethod=[UniSweepCollectV12].GetMethod('PathNameMatches')
    Assert-UniReparseStreamTest ($null -ne $tagMethod) 'Missing reparse-tag inspection helper.'
    Assert-UniReparseStreamTest ($null -ne $policyMethod) 'Missing reparse stream-host classification helper.'
    Assert-UniReparseStreamTest ($null -ne $aliasMethod) 'Missing short-name candidate matcher bridge.'
    $afUnixTag=[uint32]::Parse('80000023',[Globalization.NumberStyles]::HexNumber)
    $mountPointTag=[uint32]::Parse('A0000003',[Globalization.NumberStyles]::HexNumber)
    Assert-UniReparseStreamTest (-not [UniSweepCollectV12]::ReparseTagCanHaveNamedStreams($afUnixTag)) 'AF_UNIX socket endpoints must not be treated as NTFS named-stream hosts.'
    Assert-UniReparseStreamTest ([UniSweepCollectV12]::ReparseTagCanHaveNamedStreams($mountPointTag)) 'Mount-point stream objects were incorrectly excluded.'
    Assert-UniReparseStreamTest ([UniSweepCollectV12]::GetReparseTag($link) -eq $mountPointTag) 'Junction reparse tag was not read without following its target.'
    [UniSweepCollectV12]::ResetCounters()
    [void][UniSweepCollectV12]::Collect($root,'N',$pattern,$pattern,@(),@(),@(),1)
    $hits=@([UniSweepCollectV12]::StreamMatches)
    Assert-UniReparseStreamTest (@($hits | Where-Object {$_.HostPath -ceq $link -and $_.StreamName -ceq $linkStream}).Count -eq 1) 'Filesystem collector missed a target stream on a reparse-point object.'
    Assert-UniReparseStreamTest (@($hits | Where-Object {$_.StreamName -ceq $targetStream}).Count -eq 0) 'Filesystem collector followed a reparse target while auditing streams.'
    [UniSweepCollectV12]::ResetCounters()
    [void][UniSweepCollectV12]::Collect($link,'N',$pattern,$pattern,@(),@(),@(),1)
    $rootHits=@([UniSweepCollectV12]::StreamMatches)
    Assert-UniReparseStreamTest (@($rootHits | Where-Object {$_.HostPath -ceq $link -and $_.StreamName -ceq $linkStream}).Count -eq 1) 'Reparse-point root did not audit its own named stream.'
    Assert-UniReparseStreamTest (@($rootHits | Where-Object {$_.StreamName -ceq $targetStream}).Count -eq 0) 'Reparse-point root traversal followed its target.'

    # A link object under an authorized root is independently owned even
    # though its lexical path cannot pass Test-UniSafeRoot.  This is the
    # ownership path used by the production stream-removal gate.
    $script:UniOwnedRoots=@($root)
    Assert-UniReparseStreamTest (Test-UniOwnedStreamHost $link) 'Owned reparse-point stream host was not recognized lexically.'

    [void](Remove-UniAlternateDataStream -HostPath $link -StreamName $linkStream -ExactPattern $pattern)
    $linkStreamsAfter=@(Get-UniNamedDataStreams -Path $link)
    Assert-UniReparseStreamTest (@($linkStreamsAfter | Where-Object {$_.StreamName -ceq $linkStream}).Count -eq 0) 'Target stream remained on the reparse-point object.'
    $targetStreamsAfter=@(Get-UniNamedDataStreams -Path $target)
    Assert-UniReparseStreamTest (@($targetStreamsAfter | Where-Object {$_.StreamName -ceq $targetStream}).Count -eq 1) 'Deleting the link-object stream damaged the target stream.'
} finally {
    if(Test-Path -LiteralPath $link -ErrorAction SilentlyContinue){[IO.Directory]::Delete($link,$false)}
    if(Test-Path -LiteralPath $root -ErrorAction SilentlyContinue){Remove-Item -LiteralPath $root -Recurse -Force}
}

'UNI_REPARSE_POINT_STREAM_TEST_OK'
