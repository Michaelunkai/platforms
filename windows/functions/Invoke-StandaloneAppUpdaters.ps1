# Standalone app updaters for apps that package managers do not track.
# Called by `upup` after upgrader/wingup. Each updater compares the
# installed version against the vendor's official source and force-updates
# with the vendor's own silent installer. Real-time progress on every stage.

$ErrorActionPreference = 'Continue'

# PS 5.1's progress-bar rendering slows Invoke-WebRequest downloads to a
# crawl; real-time status comes from our own Write-Host lines instead.
$ProgressPreference = 'SilentlyContinue'

function Test-CommandExists([string]$name) {
    return $null -ne (Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Get-SemVerComparable([string]$v) {
    if (-not $v) { return $null }
    $v = $v.Trim().TrimStart('vV')
    $v = ($v -split '[-+ ]')[0]
    return $v
}

function Test-VersionOlder([string]$current, [string]$latest) {
    $c = Get-SemVerComparable $current
    $l = Get-SemVerComparable $latest
    if (-not $c -or -not $l) { return $true }   # cannot verify -> force update
    $cp = $c -split '\.' | ForEach-Object { [int]($_ -replace '\D', '') }
    $lp = $l -split '\.' | ForEach-Object { [int]($_ -replace '\D', '') }
    $width = [Math]::Max($cp.Count, $lp.Count)
    for ($i = 0; $i -lt $width; $i++) {
        $a = if ($i -lt $cp.Count) { $cp[$i] } else { 0 }
        $b = if ($i -lt $lp.Count) { $lp[$i] } else { 0 }
        if ($a -lt $b) { return $true }
        if ($a -gt $b) { return $false }
    }
    return $false
}

# ---------------------------------------------------------------------------
# Ollama — winget does not track it; check GitHub releases directly.
# The official silent installer NO-OPS (exit 0, nothing changed) while any
# Ollama process is running, so all Ollama processes are stopped first and
# the tray app is restored afterwards. Portable copies (e.g. F:\ dirs put on
# PATH) get the updated binaries mirrored from the official install.
# ---------------------------------------------------------------------------
if (Test-CommandExists 'ollama') {
    Write-Host '[standalone] Ollama: checking version against official releases...' -ForegroundColor Cyan
    $ollamaCurrent = $null
    try {
        $raw = (& ollama --version 2>&1 | Out-String)
        if ($raw -match '(\d+\.\d+\.\d+)') { $ollamaCurrent = $Matches[1] }
    } catch { }
    $ollamaLatest = $null
    try {
        $tag = (Invoke-RestMethod -Uri 'https://api.github.com/repos/ollama/ollama/releases/latest' -TimeoutSec 20 -UseBasicParsing).tag_name
        if ($tag) { $ollamaLatest = $tag.TrimStart('vV') }
    } catch { }
    Write-Host ("[standalone] Ollama: installed {0}, latest {1}" -f ($(if ($ollamaCurrent) { $ollamaCurrent } else { 'unknown' })), ($(if ($ollamaLatest) { $ollamaLatest } else { 'unknown' }))) -ForegroundColor Gray

    $needsUpdate = $true
    $officialInstall = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'
    $pathOllama = (Get-Command ollama -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    # `ollama --version` reports the SERVER version whenever a server is
    # reachable, which can hide an outdated client exe. The client is only
    # "already latest" when the reported version is current AND the PATH
    # binary is byte-identical to the official install (when one exists).
    $clientMatchesOfficial = $true
    if ((Test-Path -LiteralPath $officialInstall -PathType Leaf) -and $pathOllama) {
        $officialFull = (Resolve-Path -LiteralPath $officialInstall).Path
        $pathFull = (Resolve-Path -LiteralPath $pathOllama).Path
        if ($pathFull -ne $officialFull) {
            $clientMatchesOfficial = ((Get-FileHash -LiteralPath $pathFull -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $officialFull -Algorithm SHA256).Hash)
        }
    }
    if (-not (Test-VersionOlder $ollamaCurrent $ollamaLatest) -and $clientMatchesOfficial) { $needsUpdate = $false }
    if ($needsUpdate) {

        # remember the tray app so it can be restored after the update
        $trayProcesses = @(Get-Process -Name 'ollama app' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path -Unique)

        Write-Host '[standalone] Ollama: stopping running Ollama processes (installer no-ops while running)...' -ForegroundColor Cyan
        foreach ($proc in @(Get-Process -Name 'ollama', 'ollama app' -ErrorAction SilentlyContinue)) {
            try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch { }
        }
        Start-Sleep -Seconds 3

        Write-Host '[standalone] Ollama: downloading official installer...' -ForegroundColor Cyan
        $installer = Join-Path $env:TEMP 'OllamaSetup-latest.exe'
        try {
            Invoke-WebRequest -Uri 'https://ollama.com/download/OllamaSetup.exe' -OutFile $installer -UseBasicParsing -TimeoutSec 900
            $size = (Get-Item $installer).Length
            if ($size -lt 10MB) { throw ("downloaded file too small ({0} bytes) - aborting install" -f $size) }
            Write-Host ("[standalone] Ollama: installing silently ({0:N0} bytes)..." -f $size) -ForegroundColor Cyan
            $proc = Start-Process -FilePath $installer -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait -PassThru -WindowStyle Hidden
            Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
            if ($proc.ExitCode -ne 0) {
                Write-Warning ("[standalone] Ollama: official installer exit code {0}." -f $proc.ExitCode)
            }

            $afterOfficial = $null
            if (Test-Path -LiteralPath $officialInstall -PathType Leaf) {
                try { if ((& $officialInstall --version 2>&1 | Out-String) -match '(\d+\.\d+\.\d+)') { $afterOfficial = $Matches[1] } } catch { }
            }
            if ($afterOfficial) {
                Write-Host ("[standalone] Ollama: official install now {0}" -f $afterOfficial) -ForegroundColor Green
            } else {
                Write-Warning '[standalone] Ollama: official installer did not produce a usable version.'
            }

            # portable copies (any ollama.exe on PATH outside the official
            # install dir) get the updated binaries mirrored over
            if ($afterOfficial -and $pathOllama -and
                ($pathOllama -ne $officialInstall) -and
                ((Split-Path -Parent $pathOllama -ErrorAction SilentlyContinue) -ne (Split-Path -Parent $officialInstall))) {
                $portableDir = Split-Path -Parent $pathOllama
                Write-Host ("[standalone] Ollama: mirroring update into portable copy at {0}..." -f $portableDir) -ForegroundColor Cyan
                try {
                    $srcRoot = Split-Path -Parent $officialInstall
                    foreach ($rel in @('ollama.exe', 'lib')) {
                        $src = Join-Path $srcRoot $rel
                        $dst = Join-Path $portableDir $rel
                        if (Test-Path -LiteralPath $src -PathType Container) {
                            New-Item -ItemType Directory -Path $dst -Force -ErrorAction SilentlyContinue | Out-Null
                            Copy-Item -LiteralPath (Join-Path $src '*') -Destination $dst -Recurse -Force -ErrorAction SilentlyContinue
                        } elseif (Test-Path -LiteralPath $src -PathType Leaf) {
                            Copy-Item -LiteralPath $src -Destination $dst -Force -ErrorAction SilentlyContinue
                        }
                    }
                    $afterPortable = $null
                    try { if ((& $pathOllama --version 2>&1 | Out-String) -match '(\d+\.\d+\.\d+)') { $afterPortable = $Matches[1] } } catch { }
                    Write-Host ("[standalone] Ollama: portable copy now {0}" -f $(if ($afterPortable) { $afterPortable } else { 'unknown' })) -ForegroundColor Green
                } catch {
                    Write-Warning ("[standalone] Ollama: portable mirror failed: {0}" -f $_.Exception.Message)
                }
            }

            # restore the tray app that was running before the update
            foreach ($tray in $trayProcesses) {
                if (Test-Path -LiteralPath $tray -PathType Leaf) {
                    Write-Host ("[standalone] Ollama: restarting tray app {0}" -f $tray) -ForegroundColor Cyan
                    Start-Process -FilePath $tray -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null
                }
            }
        } catch {
            Write-Warning ("[standalone] Ollama: update failed: {0}" -f $_.Exception.Message)
        }
    } else {
        Write-Host ("[standalone] Ollama: already latest ({0})" -f $ollamaCurrent) -ForegroundColor Green
    }
}

# ---------------------------------------------------------------------------
# Scoop — command-line app manager (only if present)
# ---------------------------------------------------------------------------
if (Test-CommandExists 'scoop') {
    Write-Host '[standalone] Scoop: updating all apps...' -ForegroundColor Cyan
    try {
        & scoop update 2>&1 | ForEach-Object { Write-Host ("[standalone] scoop: {0}" -f $_) -ForegroundColor DarkGray }
        & scoop update all 2>&1 | ForEach-Object { Write-Host ("[standalone] scoop: {0}" -f $_) -ForegroundColor DarkGray }
    } catch {
        Write-Warning ("[standalone] scoop update failed: {0}" -f $_.Exception.Message)
    }
}

# ---------------------------------------------------------------------------
# Rustup — Rust toolchain (only if present)
# ---------------------------------------------------------------------------
if (Test-CommandExists 'rustup') {
    Write-Host '[standalone] Rustup: updating toolchains...' -ForegroundColor Cyan
    try {
        & rustup update 2>&1 | ForEach-Object { Write-Host ("[standalone] rustup: {0}" -f $_) -ForegroundColor DarkGray }
    } catch {
        Write-Warning ("[standalone] rustup update failed: {0}" -f $_.Exception.Message)
    }
}

Write-Host '[standalone] Standalone app updater pass complete.' -ForegroundColor Cyan
