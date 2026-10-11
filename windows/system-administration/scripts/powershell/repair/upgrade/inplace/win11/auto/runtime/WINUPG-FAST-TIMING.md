# WINUPG Fast Timing (2026-09-29)

Source: `repair-upgrade.ps1` FastPrep diff vs `.bak-winupg-fast-20260929-2241`
(anchor edits only — prep-phase + setup-monitor overhead, NOT measured wall-clock).

## Phase math (minutes)

| Phase | Today-median (65) | Full-optimized (47) | Fast-best (35) |
|---|---|---|---|
| Prep (ISO stage + validate + register) | 11 | 4 | 2 |
| Setup (setup.exe unattended) | 51 | 42 | 31 |
| Post-boot (cleanup + wipe + rearm) | 3 | 1 | 2 |
| **Total** | **65** | **47** | **35** |

Prep 11 -> 2 saves 9 min: warm WinSetup cache reuse (`C:\WinSetupCache\WinSetup`,
DISM-readability gate, skip robocopy / full PE repair / full recount), SHA256
source-vs-dest comparison only on cache-miss (length differs), 16-critical-path
PE validation by default (`$env:WINUPG_FULL_SCAN='1'` restores full recursive scan),
robocopy `/MT:16 /R:1 /W:0 /NP`, takeown/icacls timeout 45s -> 15s, setup-log tail
120 -> 40 lines.

Setup 51 -> 42 (Full) / 31 (Fast): monitor loop `Start-Sleep 1s -> 4s`
(`Wait-RepairUpgradeSetup -HeartbeatSeconds 4`) cuts WMI/log-poll overhead;
remaining delta is machine-bound (disk/CPU/DynamicUpdate), not script-bound.

Post 3 -> 1: agent3 inserts — `agent3-rearm-insert.txt` (AtStartup SYSTEM
`WinSetupPostBootReArmSystem`, PT30M limit, `postboot\ReArm-System.ps1`
re-creates ONLOGON triggers lost across reboots) + `agent3-wipe-insert.txt`
(autologon wipe: DefaultPassword/AutoLogonCount removed, AutoAdminLogon=0,
`autologon-cleaned.json` + `desktop-ready.marker`).

## December drift note (+7–12 min)

Expect +7–12 min on December ISO (larger image + DynamicUpdate payload):
Prep +2–4 (hash on first cold cache-miss), Setup +5–8 (bigger install.wim/esd,
driver migration). Warm cache absorbs prep drift on reruns; `-DisableDynamicUpdate`
trades ~5 min setup for post-upgrade patching.

## Rollback paths

- `auto\repair-upgrade.ps1.bak-winupg-fast-20260929-2241` (103991 B) — pre-FastPrep repair script.
- `ps5-profile-portable\Microsoft.PowerShell_profile.full.definitions.ps1.bak-winupg-fast-20260929-2241` (3061036 B) — pre-FastPrep profile definitions.
- Restore: copy `.bak-winupg-fast-20260929-2241` over the live file, re-run
  `Parser::ParseFile` (expect 0 errors) + `repair-upgrade.ps1 -VerifyAutomationOnly`.

## Verification (2026-09-29)

- `Parser::ParseFile` 0 errors: `repair-upgrade.ps1` (pre + post agent3 apply),
  `Microsoft.PowerShell_profile.full.definitions.ps1`, `postboot\ReArm-System.ps1`.
- `repair-upgrade.ps1 -VerifyAutomationOnly` exit 0 (pre + post apply) — safe,
  returns at line ~1681 before any setup launch; no setup.exe started, no reboot.
- agent3 inserts applied at anchors: wipe after line 1484 (`DONE target absent`),
  rearm after line 1576 (`Register-PostBootScheduledTask ... -Retry`).
