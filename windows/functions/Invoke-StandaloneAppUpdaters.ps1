# Standalone app updaters for apps that package managers do not track.
# Called by `upup` after upgrader/wingup. Each updater compares the
# installed version against the vendor's official source and force-updates
# with the vendor's own silent installer. Real-time progress on every stage.

$ErrorActionPreference = 'Continue'

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
# Ollama — winget does not track it; check GitHub releases directly
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
    if ($ollamaCurrent -and $ollamaLatest -and -not (Test-VersionOlder $ollamaCurrent $ollamaLatest)) { $needsUpdate = $false }
    if ($needsUpdate) {
        Write-Host '[standalone] Ollama: downloading official installer...' -ForegroundColor Cyan
        $installer = Join-Path $env:TEMP 'OllamaSetup-latest.exe'
        try {
            Invoke-WebRequest -Uri 'https://ollama.com/download/OllamaSetup.exe' -OutFile $installer -UseBasicParsing -TimeoutSec 600
            $size = (Get-Item $installer).Length
            if ($size -lt 10MB) { throw ("downloaded file too small ({0} bytes) - aborting install" -f $size) }
            Write-Host ("[standalone] Ollama: installing silently ({0:N0} bytes)..." -f $size) -ForegroundColor Cyan
            $proc = Start-Process -FilePath $installer -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait -PassThru -WindowStyle Hidden
            Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
            $after = $null
            try { if ((& ollama --version 2>&1 | Out-String) -match '(\d+\.\d+\.\d+)') { $after = $Matches[1] } } catch { }
            if ($proc.ExitCode -eq 0 -and $after -and -not (Test-VersionOlder $after $ollamaLatest)) {
                Write-Host ("[standalone] Ollama: updated {0} -> {1}" -f $ollamaCurrent, $after) -ForegroundColor Green
            } elseif ($after -and $ollamaCurrent -and $after -ne $ollamaCurrent) {
                Write-Host ("[standalone] Ollama: updated {0} -> {1} (installer exit {2})" -f $ollamaCurrent, $after, $proc.ExitCode) -ForegroundColor Green
            } else {
                Write-Warning ("[standalone] Ollama: update did not verify (exit {0}, version now {1})." -f $proc.ExitCode, $(if ($after) { $after } else { 'unknown' }))
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
