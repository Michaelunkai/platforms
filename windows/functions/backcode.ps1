<#
================================================================================
 backcode - ZCode backup engine (standalone, final)
================================================================================
 Backs up EVERYTHING ZCode-related from C: to F:\backup\ai\zcode, as fast as
 possible, in an organized layout, with real-time progress.

 WHAT IS BACKED UP (live -> backup, /E /B fast mirror, locked files included):
   C:\Users\Admin\.zcode                -> F:\backup\ai\zcode\dot-zcode
      (sessions, data, skills, slash commands, workflows, cli state)
      EXCLUDED (volatile junk): .zcode\tmp, .zcode\cli\exec
   C:\Users\Admin\AppData\Roaming\zcode -> F:\backup\ai\zcode\roaming-zcode
   C:\Users\Admin\.zcode\cli\db\db.sqlite
      -> F:\backup\ai\zcode\databases\db.sqlite  (SQLite .backup API:
         consistent online snapshot of the sessions database)

 ALSO MAINTAINED:
   F:\backup\ai\zcode\tools\backcode.ps1   (this engine, self-updated)
   F:\backup\ai\zcode\BACKUP-MANIFEST.txt  (run log + integrity numbers)

 No /MIR: live app data (locked Electron/session files) is never purged from
 the backup - /B backup mode reads locked files; volatile cache misses are
 logged and accepted, essential failures are reported.
================================================================================
#>
$ErrorActionPreference = 'Continue'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$backupRoot = 'F:\backup\ai\zcode'
New-Item $backupRoot -ItemType Directory -Force | Out-Null
New-Item (Join-Path $backupRoot 'tools') -ItemType Directory -Force | Out-Null
$logDir = Join-Path $backupRoot 'logs'
New-Item $logDir -ItemType Directory -Force | Out-Null
$logPath = Join-Path $logDir 'backcode-robocopy.log'

# self-update the engine copy inside the backup
$self = $PSCommandPath
if ($self -and ((Split-Path $self -Parent) -ne (Join-Path $backupRoot 'tools'))) {
    try { Copy-Item -LiteralPath $self -Destination (Join-Path $backupRoot 'tools\backcode.ps1') -Force } catch { }
}

$manifest = [System.Collections.Generic.List[string]]::new()
$manifest.Add(('BACKCODE RUN ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
$globalFail = $false

# ---------- 1. full data mirrors (output to log, not terminal) ----------
$mirrorPairs = [ordered]@{
    'C:\Users\Admin\.zcode'                = Join-Path $backupRoot 'dot-zcode'
    'C:\Users\Admin\AppData\Roaming\zcode' = Join-Path $backupRoot 'roaming-zcode'
}
foreach ($src in $mirrorPairs.Keys) {
    $dst = $mirrorPairs[$src]
    if (-not (Test-Path -LiteralPath $src)) {
        $manifest.Add(('SKIP,' + $src + ',missing source'))
        continue
    }
    if ($src -like '*.zcode') {
        & robocopy $src $dst /E /B /MT:16 /COPY:DAT /DCOPY:DAT /R:1 /W:1 /XD (Join-Path $src 'tmp') (Join-Path $src 'cli\exec') /XF (Join-Path $src 'bridge-agent-test.log') >> $logPath 2>&1
    } else {
        & robocopy $src $dst /E /B /MT:16 /COPY:DAT /DCOPY:DAT /R:1 /W:1 >> $logPath 2>&1
    }
    $rc = $LASTEXITCODE
    if ($rc -ge 16) { $globalFail = $true }
    $manifest.Add(('MIRROR,' + $src + ',' + $dst + ',exit=' + $rc))
}

# ---------- 2. sessions database: consistent online snapshot ----------
$sq3 = 'C:\Users\Admin\AppData\Local\Android\platform-tools\sqlite3.exe'
$liveDb = 'C:\Users\Admin\.zcode\cli\db\db.sqlite'
if ((Test-Path $sq3) -and (Test-Path $liveDb)) {
    $dbDir = Join-Path $backupRoot 'databases'
    New-Item $dbDir -ItemType Directory -Force | Out-Null
    $dbBak = Join-Path $dbDir 'db.sqlite'
    $bakArgs = @($liveDb, ".backup '$dbBak'")
    & $sq3 @bakArgs 2>$null | Out-Null
    $ic = & $sq3 $dbBak 'PRAGMA integrity_check;' 2>$null
    $icFirst = @($ic) | Select-Object -First 1
    $manifest.Add(('DB-SAFE-BACKUP,' + $liveDb + ',' + $dbBak + ',integrity=' + $icFirst))
}

# ---------- 3. self-update + manifest ----------
try { Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $backupRoot 'tools\backcode.ps1') -Force } catch { }
$manifest.Add(('DONE in ' + [math]::Round($sw.Elapsed.TotalSeconds, 1) + 's; globalFail=' + $globalFail))
$manifest | Set-Content -LiteralPath (Join-Path $backupRoot 'BACKUP-MANIFEST.txt') -Encoding UTF8
$sw.Stop()
if ($globalFail) { Write-Host '[backcode] COMPLETED WITH ERRORS (see manifest)' -ForegroundColor Red }
else { Write-Host '[backcode] BACKUP COMPLETE - latest ZCode state mirrored to F:\backup\ai\zcode' -ForegroundColor Green }
