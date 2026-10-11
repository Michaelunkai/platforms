[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$enginePath = Join-Path $PSScriptRoot 'Reass.ps1'
if (-not [IO.File]::Exists($enginePath)) { throw "reass self-test cannot find the engine: $enginePath" }

$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$sandbox = Join-Path $tempRoot ("ReassRestoreSelfTest_{0}" -f [guid]::NewGuid().ToString('N'))
$resolvedSandbox = [IO.Path]::GetFullPath($sandbox).TrimEnd('\')
$tempPrefix = $tempRoot + '\'
if (-not $resolvedSandbox.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase) -or
    -not ([IO.Path]::GetFileName($resolvedSandbox).StartsWith('ReassRestoreSelfTest_',[StringComparison]::OrdinalIgnoreCase))) {
    throw "reass self-test refused an unsafe sandbox path: $resolvedSandbox"
}

function Assert-ReassSelfTest([bool]$Condition,[string]$Message) {
    if (-not $Condition) { throw "reass self-test failed: $Message" }
}

function New-ReassSelfTestBackup([string]$BackupRoot,[string]$Name,[string]$Game,[string]$Target,[DateTimeOffset]$CreatedUtc,[switch]$CorruptHash) {
    $backupPath = Join-Path $BackupRoot $Name
    $saveRoot = Join-Path $backupPath 'SaveGames'
    [IO.Directory]::CreateDirectory((Join-Path $saveRoot 'EmptyAtRoot')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $saveRoot 'Slot\EmptyChild')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $saveRoot 'Slot\Nested')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $saveRoot 'profile.sav'),'snapshot-profile',[Text.Encoding]::UTF8)
    [IO.File]::WriteAllText((Join-Path $saveRoot 'Slot\Nested\state.dat'),'snapshot-state',[Text.Encoding]::UTF8)

    $files = @(Microsoft.PowerShell.Management\Get-ChildItem -LiteralPath $saveRoot -Recurse -Force -File -ErrorAction Stop)
    $fileEntries = @(
        foreach ($file in $files) {
            $relative = $file.FullName.Substring($saveRoot.Length).TrimStart('\')
            $sha = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
            if ($CorruptHash) { $sha = '0' * 64 }
            [pscustomobject]@{path=('SaveGames\' + $relative);source=$Target;bytes=[int64]$file.Length;sha256=$sha}
        }
    )
    $bytes = [int64](($files | Measure-Object Length -Sum).Sum)
    $audit = [ordered]@{
        version = 3
        status = 'complete'
        game = $Game
        createdUtc = $CreatedUtc
        detectedUtc = $CreatedUtc
        saveSources = @($Target)
        storedUnder = @('')
        files = $files.Count
        bytes = $bytes
        fileEntries = $fileEntries
        registryKeys = @()
        registryFiles = @()
        registryEntries = @()
    }
    [IO.File]::WriteAllText((Join-Path $backupPath 'backup.json'),($audit | ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($true))
    $backupPath
}

try {
    [IO.Directory]::CreateDirectory($sandbox) | Out-Null
    $backupRoot = Join-Path $sandbox 'backups'
    [IO.Directory]::CreateDirectory($backupRoot) | Out-Null

    $tokens = $null
    $parseErrors = $null
    $engineAst = [System.Management.Automation.Language.Parser]::ParseFile($enginePath,[ref]$tokens,[ref]$parseErrors)
    Assert-ReassSelfTest ($parseErrors.Count -eq 0) 'The engine does not parse cleanly.'
    $registryFunctionAst = $engineAst.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-ReassRegistryEqual'},$true)
    Assert-ReassSelfTest ($null -ne $registryFunctionAst) 'The registry snapshot comparison function is missing.'
    . ([scriptblock]::Create($registryFunctionAst.Extent.Text))
    $expectedRegistry = Join-Path $sandbox 'registry-expected.reg'
    $actualRegistry = Join-Path $sandbox 'registry-actual.reg'
    $registrySnapshot = @('Windows Registry Editor Version 5.00','','[HKEY_CURRENT_USER\Software\ReassFixture]','"name"="value"') -join "`r`n"
    [IO.File]::WriteAllText($expectedRegistry,$registrySnapshot,[Text.Encoding]::Unicode)
    [IO.File]::WriteAllText($actualRegistry,($registrySnapshot -replace 'Windows Registry Editor Version 5.00','REGEDIT4'),[Text.Encoding]::Unicode)
    Assert-ReassSelfTest (Test-ReassRegistryEqual $expectedRegistry $actualRegistry) 'Equivalent exported registry snapshots were not accepted.'
    [IO.File]::WriteAllText($actualRegistry,($registrySnapshot + "`r`n`"stale`"=`"extra`""),[Text.Encoding]::Unicode)
    Assert-ReassSelfTest (-not (Test-ReassRegistryEqual $expectedRegistry $actualRegistry)) 'A registry snapshot with stale values was accepted.'

    $game = 'Reass Restore Regression'
    $target = Join-Path $sandbox 'live\state'
    [IO.Directory]::CreateDirectory($target) | Out-Null
    [IO.File]::WriteAllText((Join-Path $target 'old-state.txt'),'must-be-preserved',[Text.Encoding]::UTF8)

    $createdUtc = [DateTimeOffset]::UtcNow
    $validBackup = New-ReassSelfTestBackup $backupRoot 'Regression_valid' $game $target $createdUtc
    $exactExe = Join-Path $sandbox 'games\selected.exe'
    $otherExe = Join-Path $sandbox 'games\other.exe'
    $validAuditPath = Join-Path $validBackup 'backup.json'
    $validAudit = Get-Content -LiteralPath $validAuditPath -Raw | ConvertFrom-Json
    $validAudit | Add-Member -NotePropertyName executable -NotePropertyValue $exactExe
    $validAudit | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $validAuditPath -Encoding UTF8
    $exactOutput = @(& $enginePath -GameExecutable $exactExe -BackupRoot $backupRoot -VerifyOnly) -join "`n"
    Assert-ReassSelfTest ($exactOutput -match 'REASS_VERIFY_OK') 'Exact executable did not select its own verified backup.'
    $wrongRejected = $false
    try { & $enginePath -GameExecutable $otherExe -BackupRoot $backupRoot -VerifyOnly }
    catch { $wrongRejected = $true }
    Assert-ReassSelfTest $wrongRejected 'An unmatched executable fell back to another game.'

    $otherInvalid = New-ReassSelfTestBackup $backupRoot 'Other_invalid_mapping' 'Other Game' $target $createdUtc.AddMinutes(30)
    $otherAuditPath = Join-Path $otherInvalid 'backup.json'
    $otherAudit = Get-Content -LiteralPath $otherAuditPath -Raw | ConvertFrom-Json
    $otherAudit | Add-Member -NotePropertyName executable -NotePropertyValue $otherExe
    $otherAudit.saveSources = @(); $otherAudit.storedUnder = @()
    $otherAudit | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $otherAuditPath -Encoding UTF8
    $exactOutput = @(& $enginePath -GameExecutable $exactExe -BackupRoot $backupRoot -VerifyOnly) -join "`n"
    Assert-ReassSelfTest ($exactOutput -match 'REASS_VERIFY_OK') 'An invalid backup identified as another executable blocked the selected game.'
    $nameOutput = @(& $enginePath -Game $game -BackupRoot $backupRoot -VerifyOnly) -join "`n"
    Assert-ReassSelfTest ($nameOutput -match 'REASS_VERIFY_OK') 'An invalid backup identified as another title blocked the selected game.'
    $otherAudit.executable = $exactExe; $otherAudit.game = $game
    $otherAudit | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $otherAuditPath -Encoding UTF8
    $invalidSelectedRejected = $false
    try { & $enginePath -GameExecutable $exactExe -BackupRoot $backupRoot -VerifyOnly }
    catch { $invalidSelectedRejected = $_.Exception.Message -match 'newest backup' }
    Assert-ReassSelfTest $invalidSelectedRejected 'Invalid newest selected-game metadata fell back to an older backup.'
    $otherAudit.executable = ''; $otherAudit.game = ''
    $otherAudit | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $otherAuditPath -Encoding UTF8
    $unidentifiedRejected = $false
    try { & $enginePath -GameExecutable $exactExe -BackupRoot $backupRoot -VerifyOnly }
    catch { $unidentifiedRejected = $_.Exception.Message -match 'newest backup' }
    Assert-ReassSelfTest $unidentifiedRejected 'Unidentifiable corrupt newest metadata fell back to an older backup.'
    $otherAudit.executable = $otherExe; $otherAudit.game = 'Other Game'
    $otherAudit | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $otherAuditPath -Encoding UTF8

    # A 'no-saves' backup is the detector's record of a play session that
    # produced no save payload. It carries no progress, so it must be skipped
    # rather than block selection of the latest real backup.
    $noSavesBackup = Join-Path $backupRoot 'Regression_no_saves'
    [IO.Directory]::CreateDirectory((Join-Path $noSavesBackup 'SaveGames')) | Out-Null
    $noSavesAudit = [ordered]@{
        version = 3
        status = 'no-saves'
        game = $game
        createdUtc = $createdUtc.AddMinutes(40)
        detectedUtc = $createdUtc.AddMinutes(40)
        saveSources = @()
        storedUnder = @()
        files = 0
        bytes = 0
        fileEntries = @()
        registryKeys = @()
        registryFiles = @()
        registryEntries = @()
    }
    [IO.File]::WriteAllText((Join-Path $noSavesBackup 'backup.json'),($noSavesAudit | ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($true))
    $noSavesOutput = @(& $enginePath -GameExecutable $exactExe -BackupRoot $backupRoot -VerifyOnly 6>&1) -join "`n"
    Assert-ReassSelfTest ($noSavesOutput -match 'REASS_VERIFY_OK') 'A newest no-saves backup blocked selection of the latest real backup.'
    Assert-ReassSelfTest ($noSavesOutput -match 'skipping-no-saves-backup') 'The no-saves backup was not reported as skipped.'
    $noSavesOutput = @(& $enginePath -Game $game -BackupRoot $backupRoot -VerifyOnly 6>&1) -join "`n"
    Assert-ReassSelfTest ($noSavesOutput -match 'REASS_VERIFY_OK') 'A newest no-saves backup blocked selection of the latest real backup by game name.'

    $global:LASTEXITCODE = 0
    $verifyResultPath = Join-Path $sandbox 'verify-result.json'
    & $enginePath -Game $game -BackupRoot $backupRoot -VerifyOnly -ResultPath $verifyResultPath
    Assert-ReassSelfTest ($global:LASTEXITCODE -eq 0) 'VerifyOnly did not accept the valid newest fixture.'
    Assert-ReassSelfTest ([IO.File]::Exists($verifyResultPath)) 'VerifyOnly did not write a result receipt.'
    $verifyResult = [IO.File]::ReadAllText($verifyResultPath) | ConvertFrom-Json
    Assert-ReassSelfTest ($verifyResult.schemaVersion -eq 1 -and $verifyResult.outcome -eq 'verified' -and $verifyResult.integrity -eq 'verified') 'VerifyOnly result receipt is inconsistent.'
    Assert-ReassSelfTest ([IO.File]::Exists([string]$verifyResult.backupManifest)) 'VerifyOnly receipt does not identify a physical manifest.'
    Assert-ReassSelfTest ($verifyResult.fileCount -eq $validAudit.files -and $verifyResult.registryCount -eq @($validAudit.registryEntries).Count -and $verifyResult.verifiedBytes -eq $validAudit.bytes) 'VerifyOnly sidecar counts disagree with the physical backup manifest.'
    Assert-ReassSelfTest ($verifyResult.backupManifestSha256 -eq (Get-FileHash -LiteralPath $verifyResult.backupManifest -Algorithm SHA256).Hash) 'VerifyOnly sidecar does not pin the physical manifest hash.'

    $pinnedManifest = [IO.Path]::GetFullPath([string]$verifyResult.backupManifest)
    $pinnedHash = [string]$verifyResult.backupManifestSha256
    $newerValid = New-ReassSelfTestBackup $backupRoot 'Regression_newer_valid' $game $target $createdUtc.AddMinutes(1)
    $newerValidManifest = Join-Path $newerValid 'backup.json'
    $newerValidAudit = Get-Content -LiteralPath $newerValidManifest -Raw | ConvertFrom-Json
    $newerValidAudit | Add-Member -NotePropertyName executable -NotePropertyValue $exactExe
    $newerValidAudit | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $newerValidManifest -Encoding UTF8
    $preRestoreCountBeforeMismatch = @(Microsoft.PowerShell.Management\Get-ChildItem -LiteralPath $backupRoot -Directory -Force | Where-Object {$_.Name -like 'pre-restore_*'}).Count
    $global:LASTEXITCODE = 0
    $mismatchMessage = ''
    $mismatchResultPath = Join-Path $sandbox 'mismatched-pin-result.json'
    try {
        $null = @(& $enginePath -GameExecutable $exactExe -BackupRoot $backupRoot -ExpectedBackupManifest $pinnedManifest -ExpectedBackupManifestSha256 $pinnedHash -Confirm:$false -ResultPath $mismatchResultPath 2>&1)
    } catch { $mismatchMessage = $_.Exception.Message }
    Assert-ReassSelfTest ($global:LASTEXITCODE -eq 1 -and $mismatchMessage -match 'selected latest backup does not match the expected manifest') 'A newly selected backup was not rejected against the verify-only manifest.'
    Assert-ReassSelfTest ([IO.File]::ReadAllText((Join-Path $target 'old-state.txt')) -eq 'must-be-preserved') 'A mismatched pinned restore changed the live target.'
    $preRestoreCountAfterMismatch = @(Microsoft.PowerShell.Management\Get-ChildItem -LiteralPath $backupRoot -Directory -Force | Where-Object {$_.Name -like 'pre-restore_*'}).Count
    Assert-ReassSelfTest ($preRestoreCountAfterMismatch -eq $preRestoreCountBeforeMismatch) 'A mismatched pinned restore created pre-restore state before rejecting the backup.'

    $latestVerifyResultPath = Join-Path $sandbox 'latest-verify-result.json'
    & $enginePath -GameExecutable $exactExe -BackupRoot $backupRoot -VerifyOnly -ResultPath $latestVerifyResultPath
    Assert-ReassSelfTest ($global:LASTEXITCODE -eq 0) 'VerifyOnly did not verify the newer selected-game backup.'
    $latestVerifyResult = [IO.File]::ReadAllText($latestVerifyResultPath) | ConvertFrom-Json
    Assert-ReassSelfTest ([IO.Path]::GetFullPath([string]$latestVerifyResult.backupManifest) -eq [IO.Path]::GetFullPath($newerValidManifest)) 'VerifyOnly did not identify the newest exact-game manifest.'
    Assert-ReassSelfTest ($latestVerifyResult.backupManifestSha256 -eq (Get-FileHash -LiteralPath $newerValidManifest -Algorithm SHA256).Hash) 'VerifyOnly did not pin the newest manifest hash.'

    $preRestoreCountBeforeHashMismatch = @(Microsoft.PowerShell.Management\Get-ChildItem -LiteralPath $backupRoot -Directory -Force | Where-Object {$_.Name -like 'pre-restore_*'}).Count
    $global:LASTEXITCODE = 0
    $hashMismatchMessage = ''
    $hashMismatchResultPath = Join-Path $sandbox 'mismatched-hash-result.json'
    try {
        $null = @(& $enginePath -GameExecutable $exactExe -BackupRoot $backupRoot -ExpectedBackupManifest ([string]$latestVerifyResult.backupManifest) -ExpectedBackupManifestSha256 ('0' * 64) -Confirm:$false -ResultPath $hashMismatchResultPath 2>&1)
    } catch { $hashMismatchMessage = $_.Exception.Message }
    Assert-ReassSelfTest ($global:LASTEXITCODE -eq 1 -and $hashMismatchMessage -match 'manifest changed since verify-only') 'A changed pinned manifest hash was not rejected.'
    Assert-ReassSelfTest ([IO.File]::ReadAllText((Join-Path $target 'old-state.txt')) -eq 'must-be-preserved') 'A mismatched pinned manifest hash changed the live target.'
    $preRestoreCountAfterHashMismatch = @(Microsoft.PowerShell.Management\Get-ChildItem -LiteralPath $backupRoot -Directory -Force | Where-Object {$_.Name -like 'pre-restore_*'}).Count
    Assert-ReassSelfTest ($preRestoreCountAfterHashMismatch -eq $preRestoreCountBeforeHashMismatch) 'A mismatched pinned manifest hash created pre-restore state before rejecting the backup.'

    $global:LASTEXITCODE = 0
    $restoreResultPath = Join-Path $sandbox 'restore-result.json'
    & $enginePath -GameExecutable $exactExe -BackupRoot $backupRoot -ExpectedBackupManifest ([string]$latestVerifyResult.backupManifest) -ExpectedBackupManifestSha256 ([string]$latestVerifyResult.backupManifestSha256) -Confirm:$false -ResultPath $restoreResultPath
    Assert-ReassSelfTest ($global:LASTEXITCODE -eq 0) 'The isolated restore returned a failure code.'
    Assert-ReassSelfTest ([IO.File]::Exists($restoreResultPath)) 'Restore did not write a result receipt.'
    $restoreResult = [IO.File]::ReadAllText($restoreResultPath) | ConvertFrom-Json
    Assert-ReassSelfTest ($restoreResult.schemaVersion -eq 1 -and $restoreResult.outcome -eq 'restored' -and $restoreResult.integrity -eq 'verified') 'Restore result receipt is inconsistent.'
    Assert-ReassSelfTest ($restoreResult.backupManifest -eq $latestVerifyResult.backupManifest -and $restoreResult.backupManifestSha256 -eq $latestVerifyResult.backupManifestSha256) 'Restore result did not preserve the verify-only manifest identity.'
    Assert-ReassSelfTest ($restoreResult.fileCount -eq $validAudit.files -and $restoreResult.registryCount -eq @($validAudit.registryEntries).Count -and $restoreResult.verifiedBytes -eq $validAudit.bytes) 'Restore sidecar counts disagree with the physical backup manifest.'
    Assert-ReassSelfTest ([IO.Directory]::Exists([string]$restoreResult.preRestoreRollback)) 'Restore result does not identify its physical rollback receipt.'
    Assert-ReassSelfTest ([IO.File]::ReadAllText((Join-Path $target 'profile.sav')) -eq 'snapshot-profile') 'A root save file was not restored.'
    Assert-ReassSelfTest ([IO.File]::ReadAllText((Join-Path $target 'Slot\Nested\state.dat')) -eq 'snapshot-state') 'A nested save file was not restored.'
    Assert-ReassSelfTest ([IO.Directory]::Exists((Join-Path $target 'EmptyAtRoot'))) 'An empty root directory was not restored.'
    Assert-ReassSelfTest ([IO.Directory]::Exists((Join-Path $target 'Slot\EmptyChild'))) 'An empty nested directory was not restored.'
    Assert-ReassSelfTest (-not [IO.File]::Exists((Join-Path $target 'old-state.txt'))) 'The restore did not replace the previous target tree.'
    $receiptFolder = @(Microsoft.PowerShell.Management\Get-ChildItem -LiteralPath $backupRoot -Directory -Force | Where-Object {$_.Name -like 'pre-restore_*'} | Select-Object -First 1)[0]
    Assert-ReassSelfTest ($null -ne $receiptFolder -and [IO.File]::Exists((Join-Path $receiptFolder.FullName '01_state\old-state.txt'))) 'The pre-restore snapshot did not preserve the prior target.'

    $newerCorrupt = New-ReassSelfTestBackup $backupRoot 'Regression_newer_corrupt' $game $target $createdUtc.AddHours(1) -CorruptHash
    $targetBeforeFailure = @(
        Microsoft.PowerShell.Management\Get-ChildItem -LiteralPath $target -Recurse -Force -File |
            Sort-Object FullName |
            ForEach-Object { '{0}|{1}' -f $_.FullName.Substring($target.Length), (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    ) -join "`n"

    $global:LASTEXITCODE = 0
    $failureText = $null
    $failureOutput = @()
    try {
        $failureOutput = @(& $enginePath -Game $game -BackupRoot $backupRoot -Confirm:$false 2>&1)
    } catch {
        $failureText = $_.Exception.Message
    }
    Assert-ReassSelfTest ($global:LASTEXITCODE -eq 1 -or $failureText) 'A corrupt newest candidate did not fail closed.'
    $failureText = @($failureText) + @($failureOutput | ForEach-Object {[string]$_}) -join "`n"
    Assert-ReassSelfTest ($failureText -match 'newest backup') 'The failure did not identify the newest candidate.'
    $targetAfterFailure = @(
        Microsoft.PowerShell.Management\Get-ChildItem -LiteralPath $target -Recurse -Force -File |
            Sort-Object FullName |
            ForEach-Object { '{0}|{1}' -f $_.FullName.Substring($target.Length), (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    ) -join "`n"
    Assert-ReassSelfTest ($targetBeforeFailure -ceq $targetAfterFailure) 'A failed newest candidate changed the existing restore target.'

    $missingManifest = Join-Path $backupRoot 'Reass_Restore_Regression_2026-09-17_03-00-00-000_deadbeef'
    [IO.Directory]::CreateDirectory($missingManifest) | Out-Null
    [IO.Directory]::SetLastWriteTimeUtc($missingManifest,$createdUtc.AddHours(2).UtcDateTime)
    $global:LASTEXITCODE = 0
    $failureText = $null
    $failureOutput = @()
    try {
        $failureOutput = @(& $enginePath -Game $game -BackupRoot $backupRoot -Confirm:$false 2>&1)
    } catch {
        $failureText = $_.Exception.Message
    }
    $failureText = @($failureText) + @($failureOutput | ForEach-Object {[string]$_}) -join "`n"
    Assert-ReassSelfTest ($global:LASTEXITCODE -eq 1 -or $failureText) 'A newest final folder without a manifest was not rejected.'
    Assert-ReassSelfTest ($failureText -match 'backup.json is missing') 'A missing final manifest was not identified in the failure.'
    $targetAfterMissingManifest = @(
        Microsoft.PowerShell.Management\Get-ChildItem -LiteralPath $target -Recurse -Force -File |
            Sort-Object FullName |
            ForEach-Object { '{0}|{1}' -f $_.FullName.Substring($target.Length), (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    ) -join "`n"
    Assert-ReassSelfTest ($targetBeforeFailure -ceq $targetAfterMissingManifest) 'A missing newest backup changed the existing restore target.'

    Write-Output 'REASS_SELFTEST_OK isolated_restore=verified pinned_manifest=verified mismatch_before_mutation=verified empty_directories=preserved prior_state=preserved corrupt_newest=refused missing_manifest_newest=refused'
} finally {
    if ([IO.Directory]::Exists($resolvedSandbox)) {
        if (-not $resolvedSandbox.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase) -or
            -not ([IO.Path]::GetFileName($resolvedSandbox).StartsWith('ReassRestoreSelfTest_',[StringComparison]::OrdinalIgnoreCase))) {
            throw "reass self-test refused to remove an unsafe sandbox path: $resolvedSandbox"
        }
        [IO.Directory]::Delete($resolvedSandbox,$true)
    }
}
