# WINUPG Default-Fast — Change Review

**Date:** 2026-09-29
**Author:** opencode (ps5 skill run)

## What changed

`winupg` now runs the **fastest path by default** with **zero flags** — plain `winupg`
needs no extra dashes or slashes. `-Full` is the opt-in slow path (Dynamic Update
enabled, lands fully patched, +10-14 min).

Behavior table:

| Invocation | Dynamic Update | Stage root | Est. wall-clock to desktop | Patch state |
|-----------|---------------|-----------|-----------------------------|-------------|
| `winupg` (default) | **Disable** (fast) | `C:\WinSetupCache\WinSetup` | ~35 best / ~44-47 typical | Windows Update catches up in background after desktop |
| `winupg -Full` | Enable | `C:\WinSetupCache\WinSetup` | ~47-60 | Fully patched immediately |
| `winupg -EnableAutoLogon` | Disable (fast) | `C:\WinSetupCache\WinSetup` | ~35-40 | Background catch-up, zero clicks to desktop |
| `winupg -EnableAutoLogon -Full` | Enable | `C:\WinSetupCache\WinSetup` | ~47-60 | Fully patched, zero clicks |

Legacy `-Fast` switch is preserved and behaves as default (DisableDynamicUpdate).

## Files changed (via ps5 mutation engine)

- Persistent function sources (all 4, atomic `mvfunc`):
  - `ProfileSources\ps5-profile-portable\Microsoft.PowerShell_profile.runtime.ps1`
  - `ProfileSources\ps5-profile-portable\Microsoft.PowerShell_profile.full.definitions.ps1`
  - `ProfileSources\ps5-profile-portable\Microsoft.PowerShell_profile.full.ps1`
  - `ProfileSources\ps5-profile-portable\legacy-safe-functions\profile-wrappers.ps1`
- Engine also re-verified `ProfileSources\ps5-profile-portable\Microsoft.PowerShell_profile.ps1` (loader, no winupg body).
- Test added: `F:\study\...\auto\Test-WinupgFastZeroTouch.ps1` check (i) — fastest-by-default assertion.
- Engine: `F:\study\...\auto\repair-upgrade.ps1` (ExtractDir=C:, /MT:16, warm cache, 15s timeouts, 4s poll) — unchanged this run, already applied previously.

### Repair of a prior defect

An earlier `mvfunc` produced a **double-braced** body (`function winupg { { ... } }`),
which made the lazy resolver emit a parameterless wrapper. This run reconstructed
the clean body from the AST (`PipelineAst -> CommandExpressionAst ->
ScriptBlockExpressionAst`) and re-applied it through the mutation engine.

## Backups

- `...\ProfileSources\ps5-profile-portable\*.bak-funcmutation-20260929-230905-913` (engine backup, post-fix)
- `...\ProfileSources\ps5-profile-portable\*.bak-funcmutation-20260929-225741-817` (pre-fix, double-braced state)
- `...\auto\repair-upgrade.ps1.bak-winupg-fast-20260929-2241` + `...full.definitions.ps1.bak-winupg-fast-20260929-2241`

## Verification (all green)

- All 4 sources + 2 bootstrap profiles: **Parser::ParseFile zero errors**.
- `winupg` exists exactly once per source; body has `[CmdletBinding()]`, params
  `IsoSource, StageRoot, EnableAutoLogon, Fast, Full, NoAutoLogon`, and the
  default-fast line `if (-not $Full) { $defaultArgs += '-DisableDynamicUpdate' }`.
- Fresh PS5 (primary bootstrap): `CommandType=Function`, all 6 params resolve.
- Fresh PS5 (second bootstrap `Documents\PowerShell\...`): same, all 6 params.
- `Test-RepairUpgradeLaunch.ps1`: PASS (exit 0).
- `Test-WinupgFastZeroTouch.ps1`: 9/9 PASS (added check i: fastest-by-default).
- Engine dry-run `repair-upgrade.ps1 -VerifyAutomationOnly`: EXIT 0, no `setup.exe`/`SetupHost` running.

Function-count note: each source gained one name — the nested
`Enable-WinupgAutoLogon` helper (intended part of the auto-logon feature), which is
indented and therefore counted by the top-level regex. No unrelated function
added, removed, or renamed.

## Images

- `runtime\img\winupg-default-fast-flow.svg` — flow: default fast path vs `-Full` branch, zero flags to desktop-ready.
- `runtime\img\winupg-time-bars.svg` — estimated wall-clock bars: as-is ~65 / Full ~47 / Fast ~35.

## Deployed URL

None. This is a local Windows PowerShell 5.1 profile function on this host; there
is genuinely no URL.

## Rollback

Restore any `.bak-funcmutation-20260929-*` backup for the four sources, or the
earlier `.bak-winupg-fast-20260929-2241` pair, then run
`Initialize-CodexProfileFunctions` in a fresh PS5.

## 2026-09-29 hotfix (user reported breakage)

Three bugs found and fixed in `repair-upgrade.ps1` (all introduced by the fast/zero-touch edits):

1. **PE validation mis-flagged non-executables** (Step 3): fast-path
   `Repair-InvalidExtractedPortableExecutables` ran `Test-PortableExecutableFile` on
   ALL critical paths including `sources\SetupPlatform.cfg` and `install.esd/.wim`
   (never PE files) -> recopy -> `Write-Fail`. Fix: only PE-validate `\.(dll|exe)$`.
2. **Warm-cache Join-Path got an array** (Step 3): `$warmImage = @(... | Select -First 1)`
   is always an array; `Join-Path $ExtractDir $warmImage` threw
   `Cannot convert Object[] to String (ChildPath)`. Fix: use `$warmImage[0]`.
3. **ReArm schtasks /Delete threw under EAP=Stop** (Step 0B): deleting a
   not-yet-existing task writes stderr, and EAP=Stop promoted it to a terminating
   error. Fix: wrap in EAP=Continue (matching existing pattern).

Verification: `-VerifyIsoPreparationOnly` EXIT 0, `-VerifyCleanupOnly` EXIT 0,
`Test-RepairUpgradeLaunch` PASS, `Test-WinupgFastZeroTouch` 12/12 PASS, fresh-PS5
`winupg` dispatch OK, no setup.exe spawned, test-run scheduled tasks removed.
Regression checks (j), (k), (l) added to the test.