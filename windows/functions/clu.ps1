#Requires -Version 5
# Standalone F:-resident entry point for the real-time usage report.
# Shows opencode go usage and ChatGPT/Codex subscription status. Never throws.

[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$Quiet,
    [switch]$Refresh
)

$ErrorActionPreference = 'Stop'
$ocAuth = $null
$ocUsage = $null
$cxAuth = $null

# ---- opencode go (real-time subscription usage) ----
$opencodeLines = New-Object System.Collections.Generic.List[string]
$opencodeAuth = Join-Path $env:USERPROFILE '.local\share\opencode\auth.json'
try {
    if (Test-Path -LiteralPath $opencodeAuth -PathType Leaf) {
        $ocAuth = Get-Content -LiteralPath $opencodeAuth -Raw | ConvertFrom-Json
        $goKey = $ocAuth.'opencode-go'.key
        if ($goKey) {
            $ocUsage = Invoke-RestMethod -Uri 'https://opencode.ai/zen/go/v1/usage' -Headers @{Authorization = "Bearer $goKey"; Accept = 'application/json'} -TimeoutSec 25
            if ($ocUsage.usage) {
                $opencodeLines.Add('opencode go (real-time):')
                foreach ($k in @('rolling', 'weekly', 'monthly')) {
                    $u = $ocUsage.usage.$k
                    if ($null -ne $u -and $null -ne $u.percent) {
                        $pct = [double]$u.percent
                        $filled = [Math]::Floor($pct / 5)
                        if ($filled -lt 0) { $filled = 0 }
                        if ($filled -gt 20) { $filled = 20 }
                        $bar = ('#' * $filled) + ('-' * (20 - $filled))
                        $reset = ''
                        if ($u.resetsAt) {
                            try {
                                $resetDt = [DateTimeOffset]::Parse($u.resetsAt).ToLocalTime()
                                $diff = $resetDt - [DateTimeOffset]::Now
                                if ($diff.TotalMinutes -gt 0) {
                                    if ($k -eq 'rolling') { $reset = ' (resets in ' + [int]$diff.TotalHours + 'h ' + $diff.Minutes + 'm)' }
                                    else { $reset = ' (resets in ' + [int]$diff.TotalDays + 'd ' + $diff.Hours + 'h)' }
                                } else { $reset = ' (resets now)' }
                            } catch {}
                        }
                        $flag = if ($pct -ge 100 -or $u.status -eq 'rate-limited') { ' [RATE-LIMITED]' } else { '' }
                        $opencodeLines.Add('  ' + $k.PadRight(8) + ' [' + $bar + '] ' + $pct + '%' + $reset + $flag)
                    }
                }
            }
        } else {
            $opencodeLines.Add('opencode go: not authenticated (no key in auth.json)')
        }
    } else {
        $opencodeLines.Add('opencode go: not logged in (no auth.json at ' + $opencodeAuth + ')')
    }
} catch {
    $opencodeLines.Add('opencode go: unavailable - ' + $_.Exception.Message + ' @ ' + $_.InvocationInfo.Line.Trim())
}

# ---- ChatGPT / Codex subscription ----
$codexLines = New-Object System.Collections.Generic.List[string]
$codexAuth = Join-Path $env:USERPROFILE '.codex\auth.json'
try {
    if (Test-Path -LiteralPath $codexAuth -PathType Leaf) {
        $cxAuth = Get-Content -LiteralPath $codexAuth -Raw | ConvertFrom-Json
        $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
        if (-not (Test-Path -LiteralPath $curl -PathType Leaf)) { $curl = 'curl' }
        $usage = $null
        for ($attempt = 0; $attempt -lt 2 -and -not ($usage -and $usage.rate_limit); $attempt++) {
            $at = $cxAuth.tokens.access_token
            $acct = $cxAuth.tokens.account_id
            $usageJson = & $curl -sS -m 25 -H "Authorization: Bearer $at" -H "Accept: application/json" -H "User-Agent: codex-cli/0.156.1" -H "chatgpt-account-id: $acct" -H "oai-language: en-US" "https://chatgpt.com/backend-api/codex/usage" 2>&1
            $usage = $null
            try { $usage = $usageJson | ConvertFrom-Json } catch {}
            if ($usage -and $usage.rate_limit) { break }
            $rt = $cxAuth.tokens.refresh_token
            if (-not $rt) { break }
            $body = 'grant_type=refresh_token&refresh_token=' + [uri]::EscapeDataString($rt) + '&client_id=app_EMoamEEZ73f0CkXaXp7hrann'
            $newTok = & $curl -sS -m 25 -X POST -H "Content-Type: application/x-www-form-urlencoded" -d $body "https://auth.openai.com/oauth/token" 2>&1
            $newTokObj = $null
            try { $newTokObj = $newTok | ConvertFrom-Json } catch {}
            if ($newTokObj -and $newTokObj.access_token) {
                $cxAuth.tokens.access_token = $newTokObj.access_token
                if ($newTokObj.id_token) { $cxAuth.tokens.id_token = $newTokObj.id_token }
                if ($newTokObj.refresh_token) { $cxAuth.tokens.refresh_token = $newTokObj.refresh_token }
                $cxAuth.last_refresh = (Get-Date).ToUniversalTime().ToString('o')
                try { $cxAuth | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $codexAuth -Encoding UTF8 } catch {}
            }
        }
        if ($usage -and $usage.rate_limit) {
            $codexLines.Add('ChatGPT / Codex (' + $usage.plan_type + '):')
            $pw = $usage.rate_limit.primary_window
            $pct = [double]$pw.used_percent
            $filled = [Math]::Floor($pct / 5)
            if ($filled -lt 0) { $filled = 0 }
            if ($filled -gt 20) { $filled = 20 }
            $bar = ('#' * $filled) + ('-' * (20 - $filled))
            $reset = ''
            if ($pw.reset_at) {
                try {
                    $resetDt = [DateTimeOffset]::FromUnixTimeSeconds([int64]$pw.reset_at).ToLocalTime()
                    $diff = $resetDt - [DateTimeOffset]::Now
                    if ($diff.TotalMinutes -gt 0) { $reset = ' (resets in ' + [int]$diff.TotalDays + 'd ' + $diff.Hours + 'h)' }
                    else { $reset = ' (resets now)' }
                } catch {}
            }
            $flag = if ($usage.rate_limit.limit_reached) { ' [LIMIT REACHED]' } else { '' }
            $codexLines.Add('  Weekly:  [' + $bar + '] ' + $pct + '%' + $reset + $flag)
            foreach ($al in $usage.additional_rate_limits) {
                $u = $al.rate_limit.primary_window
                $p2 = [double]$u.used_percent
                $f2 = [Math]::Floor($p2 / 5)
                if ($f2 -lt 0) { $f2 = 0 }
                if ($f2 -gt 20) { $f2 = 20 }
                $b2 = ('#' * $f2) + ('-' * (20 - $f2))
                $codexLines.Add('  ' + $al.limit_name + ': [' + $b2 + '] ' + $p2 + '%')
            }
            if ($usage.rate_limit_reset_credits -and $usage.rate_limit_reset_credits.available_count -gt 0) {
                $codexLines.Add('  reset credits available: ' + $usage.rate_limit_reset_credits.available_count)
            }
        } else {
            $codexLines.Add('ChatGPT / Codex: unable to fetch usage (token may need re-login via `codex login`)')
        }
    } else {
        $codexLines.Add('ChatGPT / Codex: not logged in (no auth.json at ' + $codexAuth + ')')
    }
} catch {
    $codexLines.Add('ChatGPT / Codex: ' + $_.Exception.Message)
}

if ($Json) {
    [pscustomobject]@{
        opencodeGo = if ($ocUsage) { $ocUsage.usage } else { $null }
        chatgptCodex = if ($usage) { $usage } else { $null }
    } | ConvertTo-Json -Depth 6
} else {
    Write-Host ''
    Write-Host '========================================'
    Write-Host '      REAL-TIME USAGE REPORT'
    Write-Host '========================================'
    Write-Host ''
    $opencodeLines | ForEach-Object { Write-Host $_ }
    Write-Host ''
    $codexLines | ForEach-Object { Write-Host $_ }
    Write-Host ''
    Write-Host '========================================'
}