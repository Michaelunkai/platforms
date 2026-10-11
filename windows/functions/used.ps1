$ErrorActionPreference = 'Continue'

# === Real-time ZAI individual coding plan usage ===
# Primary source: the live backend quota endpoint the ZCode app itself uses
# (https://api.z.ai/api/monitor/usage/quota/limit) with the OAuth access token
# decrypted from ~/.zcode/v2/credentials.json (ZCode's enc:v1: AES-256-GCM
# scheme, key = SHA256 of a deterministic machine-specific secret).
# Fallback: the app's Local Storage LevelDB cache (same snapshot schema).
# Window identity comes from the row's unit field, NOT row order:
#   unit 3 (number 5)  = rolling 5-hour prompts window
#   unit 6 (number 1)  = rolling weekly prompts window
# When a window is freshly reset the API returns only ONE row, so unit-based
# labeling is required; a missing window simply means 100% remaining.
# Free "Start" plan entries (limits carrying planId) are always excluded.

$h5Rem = -1; $wkRem = -1
$h5ResetMs = 0; $wkResetMs = 0

# The API's percentage field is the USED percent (verified: currentValue 423 of
# usage 2000 reports percentage 21). Remaining is derived from remaining/usage
# when present, otherwise 100 - percentage.
function Get-RemainingPct($limit) {
    $usage = [double]$limit.usage
    if ($usage -gt 0 -and $null -ne $limit.remaining) {
        $r = [double]$limit.remaining / $usage * 100
        if ($r -lt 0) { $r = 0 }; if ($r -gt 100) { $r = 100 }
        return [math]::Round($r)
    }
    $r = 100 - [double]$limit.percentage
    if ($r -lt 0) { $r = 0 }; if ($r -gt 100) { $r = 100 }
    return [math]::Round($r)
}

# Classify a quota row into its rolling window.
function Get-WindowKind($limit) {
    $unit = -1; $number = -1
    [void][int]::TryParse([string]$limit.unit, [ref]$unit)
    [void][int]::TryParse([string]$limit.number, [ref]$number)
    if ($unit -eq 3 -or $number -eq 5) { return '5h' }
    if ($unit -eq 6 -or $number -eq 1) { return 'week' }
    return 'unknown'
}

# Assign rows to the two windows. A window with no row stays at 100%
# (freshly reset / nothing used yet in that rolling window).
function Add-LimitsToWindows($rows) {
    foreach ($row in $rows) {
        if ($row.planId -or -not $row.nextResetTime) { continue }
        switch (Get-WindowKind $row) {
            '5h' {
                if ($script:h5Rem -lt 0) {
                    $script:h5Rem = Get-RemainingPct $row
                    $script:h5ResetMs = [double]$row.nextResetTime
                }
            }
            'week' {
                if ($script:wkRem -lt 0) {
                    $script:wkRem = Get-RemainingPct $row
                    $script:wkResetMs = [double]$row.nextResetTime
                }
            }
        }
    }
    if ($script:h5Rem -lt 0) { $script:h5Rem = 100 }
    if ($script:wkRem -lt 0) { $script:wkRem = 100 }
}

# --- 1) live API ---
$credsFile = Join-Path $env:USERPROFILE '.zcode\v2\credentials.json'
$nodeExe = (Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $nodeExe) {
    foreach ($cand in @("$env:LOCALAPPDATA\Programs\nodejs\node.exe", 'C:\Program Files\nodejs\node.exe')) {
        if (Test-Path $cand) { $nodeExe = $cand; break }
    }
}
if ((Test-Path $credsFile) -and $nodeExe) {
    try {
        $token = & $nodeExe -e "
const crypto=require('crypto'),fs=require('fs'),os=require('os');
const c=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));
const s='zcode-credential-fallback:'+process.platform+':'+os.homedir()+':'+os.userInfo().username;
const k=crypto.createHash('sha256').update(s).digest();
function d(v){if(!v.startsWith('enc:v1:'))return v;const p=v.slice(7).split('.');if(p.length!==3)return '';
const d2=crypto.createDecipheriv('aes-256-gcm',k,Buffer.from(p[0],'base64url'));d2.setAuthTag(Buffer.from(p[1],'base64url'));
return Buffer.concat([d2.update(Buffer.from(p[2],'base64url')),d2.final()]).toString('utf8');}
const t=d(c['oauth:zai:access_token']||'');if(!t)process.exit(1);process.stdout.write(t);
" $credsFile 2>$null
    } catch { $token = $null }
    if ($token) {
        try {
            $resp = Invoke-RestMethod -Uri 'https://api.z.ai/api/monitor/usage/quota/limit' -Headers @{ authorization = $token } -TimeoutSec 10
            if ($resp.data -and $resp.data.limits) {
                Add-LimitsToWindows @($resp.data.limits)
                $script:usedSource = 'live'
            }
        } catch { }
    }
}

# --- 2) fallback: LevelDB cache ---
if ($script:usedSource -ne 'live') {
    $lsDir = 'C:\Users\Admin\AppData\Roaming\zcode\session\Local Storage\leveldb'
    $files = @()
    if (Test-Path $lsDir) {
        $files = Get-ChildItem $lsDir -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending
    }
    $best = $null
    $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
    foreach ($file in $files) {
        $text = $null
        try {
            $fs = [System.IO.File]::Open($file.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share)
            $ms = New-Object System.IO.MemoryStream
            try { $fs.CopyTo($ms) } catch { }
            $fs.Dispose()
            $text = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
        } catch { continue }
        if (-not $text) { continue }

        $pos = 0
        while ($true) {
            $start = $text.IndexOf('{"cachedAt":', $pos)
            if ($start -lt 0) { break }
            $depth = 0; $end = -1
            $scanMax = [Math]::Min($start + 80000, $text.Length)
            for ($i = $start; $i -lt $scanMax; $i++) {
                $ch = $text[$i]
                if ($ch -eq '{') { $depth++ }
                elseif ($ch -eq '}') { $depth--; if ($depth -eq 0) { $end = $i + 1; break } }
            }
            if ($end -lt 0) { break }
            $pos = $end
            $json = $text.Substring($start, $end - $start)
            try { $obj = ConvertFrom-Json -InputObject $json } catch { continue }
            if (-not $obj.snapshot -or -not $obj.snapshot.quota) { continue }
            $limits = @($obj.snapshot.quota.limits | Where-Object { -not $_.planId -and $_.nextResetTime })
            if ($limits.Count -lt 1) { continue }
            if (-not $best -or [double]$obj.cachedAt -gt [double]$best.cachedAt) { $best = $obj }
        }
    }
    if ($best) {
        Add-LimitsToWindows @($best.snapshot.quota.limits)
        $script:usedSource = 'cache'
    }
}

function Format-Reset([double]$resetMs) {
    if ($resetMs -le 0) { return '' }
    $resetLocal = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$resetMs).ToLocalTime()
    $left = $resetLocal - [DateTimeOffset]::Now
    if ($left.TotalSeconds -lt 0) { $left = [TimeSpan]::Zero }
    $hm = ''
    if ($left.Days -gt 0) {
        $hm = '{0}d {1}h {2}m' -f $left.Days, $left.Hours, $left.Minutes
    } elseif ($left.Hours -gt 0) {
        $hm = '{0}h {1}m' -f $left.Hours, $left.Minutes
    } else {
        $hm = '{0}m {1}s' -f $left.Minutes, $left.Seconds
    }
    return ('resets {0}  (in {1})' -f $resetLocal.ToString('MMM dd HH:mm'), $hm)
}

$h5Reset = Format-Reset $h5ResetMs
$wkReset = Format-Reset $wkResetMs

Write-Output ("5-hour remaining: {0}%  {1}" -f $h5Rem, $h5Reset)
Write-Output ("Weekly remaining: {0}%  {1}" -f $wkRem, $wkReset)

# query local DB for prompt/token counts
$sq3 = 'C:\Users\Admin\AppData\Local\Android\platform-tools\sqlite3.exe'
$db = 'C:\Users\Admin\.zcode\cli\db\db.sqlite'
$nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$h5Ms = $nowMs - (5 * 3600 * 1000)
$w7Ms = $nowMs - (7 * 7 * 24 * 3600 * 1000)
$h5Prompts = 0; $w7Prompts = 0; $h5Tokens = 0; $w7Tokens = 0
if (Test-Path $sq3) {
    $h5Prompts = [int](& $sq3 $db "SELECT COUNT(*) FROM turn_usage WHERE started_at >= $h5Ms;" 2>$null)
    $w7Prompts = [int](& $sq3 $db "SELECT COUNT(*) FROM turn_usage WHERE started_at >= $w7Ms;" 2>$null)
    $h5Tokens = [long](& $sq3 $db "SELECT IFNULL(SUM(computed_total_tokens),0) FROM model_usage WHERE started_at >= $h5Ms;" 2>$null)
    $w7Tokens = [long](& $sq3 $db "SELECT IFNULL(SUM(computed_total_tokens),0) FROM model_usage WHERE started_at >= $w7Ms;" 2>$null)
}

# display
function Get-Bar([double]$pctRem, [int]$w) {
    $pctUsed = 100 - $pctRem
    $f = [math]::Floor(($pctUsed / 100) * $w); if ($f -lt 0) { $f = 0 }; if ($f -gt $w) { $f = $w }
    $c = if ($pctRem -le 10) { 'Red' } elseif ($pctRem -le 30) { 'Yellow' } else { 'Green' }
    @{ Bar = ([string][char]0x2588) * $f + ([string][char]0x2591) * ($w - $f); Color = $c }
}

Write-Host ''
Write-Host ('  ZCode Usage (live subscription)' + $(if ($script:usedSource -eq 'cache') { ' [cached]' })) -ForegroundColor White
Write-Host ('  ' + ([string][char]0x2500) * 55) -ForegroundColor DarkGray

$h5b = Get-Bar $h5Rem 30
Write-Host ('  5-hour remaining  ') -NoNewline
Write-Host $h5b.Bar -ForegroundColor $h5b.Color -NoNewline
Write-Host ('  {0}%' -f $h5Rem) -ForegroundColor $h5b.Color
Write-Host ('  {0}' -f $h5Reset) -ForegroundColor DarkGray

$w7b = Get-Bar $wkRem 30
Write-Host ('  Weekly remaining  ') -NoNewline
Write-Host $w7b.Bar -ForegroundColor $w7b.Color -NoNewline
Write-Host ('  {0}%' -f $wkRem) -ForegroundColor $w7b.Color
Write-Host ('  {0}' -f $wkReset) -ForegroundColor DarkGray

Write-Host ('  ' + ([string][char]0x2500) * 55) -ForegroundColor DarkGray
Write-Host ('  prompts (5h): {0}  |  (7w): {1}' -f $h5Prompts, $w7Prompts) -ForegroundColor DarkGray
Write-Host ('  tokens  (5h): {0:N0}  |  (7w): {1:N0}' -f $h5Tokens, $w7Tokens) -ForegroundColor DarkGray
Write-Host ''
