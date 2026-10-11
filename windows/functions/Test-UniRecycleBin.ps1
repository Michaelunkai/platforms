param()

$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'uni.ps1')

function Assert-UniRecycleBinTest {
    param([bool]$Condition,[string]$Message)
    if(-not $Condition){throw $Message}
}

$root='C:\Windows\Temp\UniRecycleBin-'+[Guid]::NewGuid().ToString('N')
$sid=Join-Path $root 'S-1-5-21-100-200-300-1001'
$suffix='A1B2C3D4'
$info=Join-Path $sid ('$I'+$suffix+'.exe')
$payload=Join-Path $sid ('$R'+$suffix+'.exe')
$v1Info=Join-Path $sid '$IV1.bin'
$v1Payload=Join-Path $sid '$RV1.bin'
$original='C:\Users\Admin\AppData\Local\UniRecycleFixture\Target.exe'
$v1Original='C:\Users\Admin\AppData\Roaming\UniRecycleFixture\Target.dll'
$ownedRoot='C:\Windows\Temp\UniRecycleBin-'+[Guid]::NewGuid().ToString('N')+'\OwnedApp'
$ownedOriginal=$ownedRoot+'\Target.exe'
$ownedInfo=Join-Path $sid ('$IOWNED.bin')
$ownedPayload=Join-Path $sid ('$ROWNED.bin')
$ownedDirInfo=Join-Path $sid ('$IDIR.bin')
$ownedDirPayload=Join-Path $sid ('$RDIR.bin')
$ownedDirFile=Join-Path $ownedDirPayload 'shared.bin'
$ownedDirAlias=Join-Path $root 'outside-shared.bin'
$ownedDirOriginal=$ownedRoot+'\Target'
$unownedInfo=Join-Path $sid ('$IUNOWNED.bin')
$unownedPayload=Join-Path $sid ('$RUNOWNED.bin')
$orphanPayload=Join-Path $sid ('$RORPHAN.bin')
$rootLevelPayload=Join-Path $root '$RROOTLEVEL.bin'

try {
    [void][IO.Directory]::CreateDirectory($sid)
    [IO.File]::WriteAllBytes($payload,[Text.Encoding]::UTF8.GetBytes('recycle payload'))
    $pathBytes=[Text.Encoding]::Unicode.GetBytes($original+[char]0)
    $data=New-Object byte[] (28+$pathBytes.Length)
    [Array]::Copy([BitConverter]::GetBytes([Int64]2),0,$data,0,8)
    [Array]::Copy([BitConverter]::GetBytes([Int64]15),0,$data,8,8)
    [Array]::Copy([BitConverter]::GetBytes([DateTime]::UtcNow.ToFileTimeUtc()),0,$data,16,8)
    [Array]::Copy([BitConverter]::GetBytes([Int32]($original.Length+1)),0,$data,24,4)
    [Array]::Copy($pathBytes,0,$data,28,$pathBytes.Length)
    [IO.File]::WriteAllBytes($info,$data)

    Assert-UniRecycleBinTest ([bool](Get-Command Get-UniRecycleBinMetadata -CommandType Function -ErrorAction SilentlyContinue)) 'Missing Recycle Bin metadata parser.'
    $record=Get-UniRecycleBinMetadata -InfoPath $info
    Assert-UniRecycleBinTest ($record.Version -eq 2) 'Recycle Bin v2 metadata version was not parsed.'
    Assert-UniRecycleBinTest ($record.OriginalPath -ceq $original) 'Recycle Bin original path was not parsed exactly.'
    Assert-UniRecycleBinTest ($record.PayloadPath -ceq $payload) 'Recycle Bin $R companion path was not derived exactly.'
    Assert-UniRecycleBinTest ($record.OriginalSize -eq 15) 'Recycle Bin original size was not parsed.'
    [IO.File]::Delete($payload)
    Assert-UniRecycleBinTest (-not (Get-UniRecycleBinMetadata -InfoPath $info -RequirePayload:$false).PayloadExists) 'Missing payload state was not reported.'

    [IO.File]::WriteAllBytes($v1Payload,[Text.Encoding]::UTF8.GetBytes('recycle v1 payload'))
    $v1PathBytes=[Text.Encoding]::Unicode.GetBytes($v1Original+[char]0)
    $v1Data=New-Object byte[] (24+$v1PathBytes.Length)
    [Array]::Copy([BitConverter]::GetBytes([Int64]1),0,$v1Data,0,8)
    [Array]::Copy([BitConverter]::GetBytes([Int64]18),0,$v1Data,8,8)
    [Array]::Copy([BitConverter]::GetBytes([DateTime]::UtcNow.ToFileTimeUtc()),0,$v1Data,16,8)
    [Array]::Copy($v1PathBytes,0,$v1Data,24,$v1PathBytes.Length)
    [IO.File]::WriteAllBytes($v1Info,$v1Data)
    $v1Record=Get-UniRecycleBinMetadata -InfoPath $v1Info
    Assert-UniRecycleBinTest ($v1Record.Version -eq 1) 'Recycle Bin v1 metadata version was not parsed.'
    Assert-UniRecycleBinTest ($v1Record.OriginalPath -ceq $v1Original) 'Recycle Bin v1 original path was not parsed exactly.'
    Assert-UniRecycleBinTest ($v1Record.PayloadPath -ceq $v1Payload) 'Recycle Bin v1 $R companion path was not derived exactly.'

    function New-TestRecycleRecord {
        param([string]$InfoPath,[string]$PayloadPath,[string]$OriginalPath)
        [IO.File]::WriteAllBytes($PayloadPath,[Text.Encoding]::UTF8.GetBytes('recycle payload'))
        $pathBytes=[Text.Encoding]::Unicode.GetBytes($OriginalPath+[char]0)
        $record=New-Object byte[] (28+$pathBytes.Length)
        [Array]::Copy([BitConverter]::GetBytes([Int64]2),0,$record,0,8)
        [Array]::Copy([BitConverter]::GetBytes([Int64]15),0,$record,8,8)
        [Array]::Copy([BitConverter]::GetBytes([DateTime]::UtcNow.ToFileTimeUtc()),0,$record,16,8)
        [Array]::Copy([BitConverter]::GetBytes([Int32]($OriginalPath.Length+1)),0,$record,24,4)
        [Array]::Copy($pathBytes,0,$record,28,$pathBytes.Length)
        [IO.File]::WriteAllBytes($InfoPath,$record)
    }
    New-TestRecycleRecord -InfoPath $ownedInfo -PayloadPath $ownedPayload -OriginalPath $ownedOriginal
    New-TestRecycleRecord -InfoPath $ownedDirInfo -PayloadPath $ownedDirPayload -OriginalPath $ownedDirOriginal
    [IO.File]::Delete($ownedDirPayload)
    [IO.Directory]::CreateDirectory($ownedDirPayload) | Out-Null
    [IO.File]::WriteAllBytes($ownedDirFile,[Text.Encoding]::UTF8.GetBytes('shared recycle payload'))
    New-Item -ItemType HardLink -Path $ownedDirAlias -Target $ownedDirFile -Force | Out-Null
    New-TestRecycleRecord -InfoPath $unownedInfo -PayloadPath $unownedPayload -OriginalPath 'C:\Users\Admin\Documents\Target.exe'
    [IO.File]::WriteAllBytes($orphanPayload,[Text.Encoding]::UTF8.GetBytes('orphan recycle payload'))
    [IO.File]::WriteAllBytes($rootLevelPayload,[Text.Encoding]::UTF8.GetBytes('root-level recycle payload'))
    Assert-UniRecycleBinTest ([bool](Get-Command Invoke-UniRecycleBinSweep -CommandType Function -ErrorAction SilentlyContinue)) 'Missing Recycle Bin cleanup sweep.'
    $script:UniOwnedRoots=@($ownedRoot)
    $script:UniOtherRoots=@()
    $script:UniProtectedArtifacts=New-Object 'System.Collections.Generic.List[string]'
    $script:UniFailed=New-Object 'System.Collections.Generic.List[string]'
    $script:UniStats=@{Files=0;Dirs=0}
    $script:UniAggressiveSweep=$true
    Invoke-UniRecycleBinSweep -ReExact ([regex]'(?i)(?<![A-Za-z0-9])Target(?![A-Za-z0-9])') -OrphanPat '(?i)target' -RecycleRoot $root
    Assert-UniRecycleBinTest (-not (Test-Path -LiteralPath $ownedInfo)) 'Owned Recycle Bin metadata remained.'
    Assert-UniRecycleBinTest (-not (Test-Path -LiteralPath $ownedPayload)) 'Owned Recycle Bin payload remained.'
    Assert-UniRecycleBinTest (Test-Path -LiteralPath $ownedDirInfo) 'Hard-linked directory payload metadata was deleted.'
    Assert-UniRecycleBinTest (Test-Path -LiteralPath $ownedDirFile) 'Hard-linked directory payload file was deleted.'
    Assert-UniRecycleBinTest (@($script:UniFailed | Where-Object {$_ -match 'Hard-linked target file'}).Count -gt 0) 'Hard-linked directory payload was not refused and reported.'
    Assert-UniRecycleBinTest (Test-Path -LiteralPath $unownedInfo) 'Ambiguous Recycle Bin metadata was deleted.'
    Assert-UniRecycleBinTest (Test-Path -LiteralPath $unownedPayload) 'Ambiguous Recycle Bin payload was deleted.'
    Assert-UniRecycleBinTest (@($script:UniProtectedArtifacts | Where-Object {$_ -match [regex]::Escape($unownedInfo)}).Count -eq 1) 'Ambiguous target-looking Recycle Bin record was not reported.'
    Assert-UniRecycleBinTest (Test-Path -LiteralPath $orphanPayload) 'Orphan Recycle Bin payload was deleted.'
    Assert-UniRecycleBinTest (@($script:UniProtectedArtifacts | Where-Object {$_ -match [regex]::Escape($orphanPayload) -and $_ -match 'unknowable'}).Count -eq 1) 'Orphan Recycle Bin payload was not reported as an ambiguity.'
    Assert-UniRecycleBinTest (Test-Path -LiteralPath $rootLevelPayload) 'Root-level Recycle Bin payload was deleted.'
    Assert-UniRecycleBinTest (@($script:UniProtectedArtifacts | Where-Object {$_ -match [regex]::Escape($rootLevelPayload) -and $_ -match 'SID ownership'}).Count -eq 1) 'Root-level Recycle Bin payload was not reported as an ambiguity.'
} finally {
    if(Test-Path -LiteralPath $root -ErrorAction SilentlyContinue){Remove-Item -LiteralPath $root -Recurse -Force}
}

'UNI_RECYCLE_BIN_TEST_OK'
