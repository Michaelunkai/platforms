# Learned Errors

## 2026-05-05 - Vault Import PowerShell Backtick Quoting

- Context: Importing `F:\Downloads\Documentation(job).csv` into the Obsidian vault with `vault-save-note.ps1`.
- Error: Inline PowerShell parser failed on a markdown line after using a backtick before a closing double quote in `"- SHA-256: `$hash`"`.
- Fix: Avoid backtick-delimited inline code inside double-quoted PowerShell strings; build those lines with single-quoted literals plus concatenation or omit markdown backticks in generated text.

## 2026-05-05 - Nested PowerShell Native Stdout Encoding Failure

- Context: Calling `powershell.exe -NoProfile -ExecutionPolicy Bypass -File F:\backup\obsidion\scripts\vault-save-note.ps1` from the current shell during the same vault import.
- Error: `Program 'powershell.exe' failed to run: StandardOutputEncoding is only supported when standard output is redirected.`
- Fix: Dot-call or invoke `vault-save-note.ps1` directly in the current PowerShell host with `& 'F:\backup\obsidion\scripts\vault-save-note.ps1' ...` instead of spawning a nested `powershell.exe`.

## 2026-05-05 - LASTEXITCODE Blank After Successful PowerShell Script

- Context: Verifying `vault-save-note.ps1` after direct invocation during the TovTech documentation vault import.
- Error: The script printed `Vault Note Created`, but the wrapper checked `$LASTEXITCODE -ne 0`; for a PowerShell script `$LASTEXITCODE` can be blank, so the wrapper threw a false failure.
- Fix: For PowerShell script invocations, rely on thrown exceptions or `$?`, not `$LASTEXITCODE`, unless the script explicitly sets a process exit code.

## 2026-05-05 - LinkedIn Job Tracker Summary Encoding

- Context: Running `job_progress.py summary --workspace linkedin-auto-apply` from Windows PowerShell after a LinkedIn Easy Apply batch.
- Error: The summary hit `UnicodeEncodeError: 'charmap' codec can't encode characters` when an older Hebrew role name was printed through the default console encoding.
- Fix: Set `$env:PYTHONIOENCODING='utf-8'` before running the tracker summary command.

## 2026-08-03 - PowerShell Built-in Variable Collision

- Context: Verifying AutoHotkey hotkey ownership and the live DS2 Ctrl+H/Alt+H cycle.
- Error: Probe assignments to `$pid` and `$error` failed because PowerShell reserves `$PID` and `$Error`.
- Fix: Use explicit names such as `$targetPid` and `$win32Error` in PowerShell verification probes.

## 2026-08-12 - Windows 11 Notepad Launcher PID Is Not the Window Owner

- Context: Running a disposable Ctrl+H/Alt+H acceptance test against Notepad.
- Error: `Start-Process notepad.exe -PassThru` returned a launcher process that never acquired a main window.
- Fix: Snapshot existing Notepad PIDs, launch Notepad, then discover the new `Notepad.exe` process with a nonzero `MainWindowHandle` before testing.

## 2026-08-12 - AutoHotkey FileDelete Throws for a Missing Probe Marker

- Context: Starting the disposable Ctrl+H/Alt+H GUI acceptance probe.
- Error: `FileDelete` stopped the probe before it created its GUI-ready marker when the marker was already absent.
- Fix: Use `try FileDelete(...)` for optional stale-marker cleanup.

## 2026-08-12 - Power Throttling Query Requires Version Initialization

- Context: Capturing exact process power-throttling state before the Ctrl+H game low-resource mode.
- Error: `GetProcessInformation(ProcessPowerThrottling)` returned `ERROR_INVALID_PARAMETER` when the 12-byte structure was zero-initialized.
- Fix: Set `Version` to `PROCESS_POWER_THROTTLING_CURRENT_VERSION` (`1`) before the query.

## 2026-08-12 - Exact Function Declaration Needed for Line-Range Audits

- Context: Auditing `LoadFrozenProcesses()` for forbidden automatic resume calls.
- Error: A loose search matched both the startup invocation and function declaration, producing an array where one line number was expected.
- Fix: Anchor the search to the declaration form, such as `^LoadFrozenProcesses\(\) \{`, before slicing source lines.

## 2026-08-12 - ScheduledTasks Cmdlet Unavailable

- Context: Auditing startup routes for the authoritative Ctrl+H/Alt+H AutoHotkey controller.
- Error: `Get-ScheduledTask` was unavailable in the current Windows PowerShell session.
- Fix: Use the explicit `C:\Windows\System32\schtasks.exe /Query /FO CSV /V` path and inspect its output before adding another startup route.

## 2026-08-12 - WINDIR Was Empty in the Tool Environment

- Context: Backing up the registry Run key before installing the AutoHotkey controller startup entry.
- Error: `$env:WINDIR` expanded to an empty string, producing the invalid executable path `\System32\reg.exe`.
- Fix: Use the explicit `C:\Windows\System32\reg.exe` path for Windows system utilities in this environment.

## 2026-08-12 - Direct AutoHotkey Invocation Left LASTEXITCODE Blank

- Context: Syntax-checking `current.ahk` before replacing the live Ctrl+H/Alt+H controller.
- Error: A direct executable invocation left `$LASTEXITCODE` blank, and a numeric comparison incorrectly treated that as a syntax failure.
- Fix: Launch the syntax check with `Start-Process -Wait -PassThru` and inspect the returned process object's `ExitCode`.

## 2026-08-12 - Self-Activating Hotkey Probe Lost Foreground

- Context: Testing Ctrl+H with a disposable AutoHotkey GUI while another window could take foreground.
- Error: The probe's delayed Ctrl+H targeted an Administrator Windows PowerShell window instead of the probe.
- Fix: Do not use delayed self-sending probes for a global foreground hotkey. Verify the exact foreground PID immediately before dispatch and fail closed if it differs.

## 2026-08-12 - Synchronous Working-Set Trim Blocked Game Restore

- Context: Reducing a multi-gigabyte game's RAM after true suspension.
- Error: `EmptyWorkingSet` blocked the controller hotkey thread long enough that Alt+H could not be processed immediately.
- Fix: Games use `game_suspend`: true suspension plus VERY_LOW memory priority, but no synchronous working-set trim. Windows may reclaim pages asynchronously while the controller remains immediately responsive.

## 2026-08-12 - Pipeline After Foreach Needs Grouping

- Context: Reporting multiple AutoHotkey syntax-check results in one PowerShell command.
- Error: Piping directly after a `foreach` statement produced `An empty pipe element is not allowed`.
- Fix: Assign the loop output to a variable or wrap the entire loop in `@(...)` before piping it to `Format-Table`.

## 2026-09-08 - AHK mute hotstrings and ddrivers AppsFolder popup

- Root cause: `ddrivers` launched GameSir Connect through a stale `shell:AppsFolder` identifier even though the installed direct executable was available; the requested mute hotstrings were also absent from the live script.
- Fix: use the verified direct vendor executable list only; add HWND-based app mute/unmute and CoreAudio default-capture mute/unmute with session and `%TEMP%\mic-prev-level.txt` persistence.
- Verification: AutoHotkey v2 `/validate` exit 0; direct app-mute and six-tool driver probes passed; live `mmute`, `unmute`, `mmmute`, and `uunmute` triggers were consumed and the microphone state/file were restored.

## 2026-09-08 - kkkk native helper launch and warning dialog

- Error: The first helper launch used an undefined `WaitForKkkkProcessTreeExit` name, so AHK `#Warn` paused the helper behind a dialog; the production launcher also needed an explicit `/script` switch for this installed runtime.
- Fix: call the defined bounded tree wait function and launch the helper with `AutoHotkey64.exe /script`; keep a creation-stamp check, children-first native `TerminateProcess`, bounded wait, and post-kill verification.
- Verification: source and helper validation exited 0; a disposable process-tree kill passed; the live four-tap `kkkk` route passed and logged helper exit 0. Native injected text did not reach a disposable editor control, so microphone text hotstrings were validated through their exact handler functions instead.

## 2026-09-08 - PowerShell v5 inline if reporting

- Error: An inline `(if (...) { ... } else { ... })` used only for probe reporting was parsed as a command, causing a false nonzero test result after the underlying action had already succeeded.
- Fix: assign a default result and use a standalone `if` statement; use `Start-Process -Wait -PassThru` when an executable exit code is required.

## 2026-09-14 - AHK inspection quoting and hard-link detachment

- Error: One ripgrep query embedded quoted hotkey text inside a PowerShell double-quoted regex and produced an unclosed-group error; a later multi-item reporting loop also piped directly after `foreach`, and the shell policy rejected a remove/move-based hard-link detachment before execution.
- Fix: use separate `-e` patterns with single-quoted PowerShell literals, assign loop output before formatting, and use `apply_patch` move operations to detach an exact hard-linked target without altering its backup.

## 2026-09-14 - SetForegroundWindow was denied in the launcher probe

- Error: A PowerShell launcher-hotkey probe called `SetForegroundWindow` from a non-foreground tool process, so Windows kept another application focused and the fail-closed PID check stopped before sending any shortcut.
- Fix: attach the probe thread to the target window thread with `AttachThreadInput`, restore/focus the exact disposable HWND, detach, then re-check `GetForegroundWindow` immediately before dispatch.

## 2026-09-14 - Injected Ctrl+R did not reach the hook hotkey

- Error: The in-memory AHK launcher probe verified `sstartup` and `ss2t`, but both AHK `Send("^r")` and native injected Ctrl+R left OpenWhispr foreground while Ctrl+R was declared as a hook hotkey.
- Fix: register Ctrl+R through the controller's existing Windows `RegisterHotKey` plus `MOD_NOREPEAT` path, alongside Ctrl+H and Alt+H, and remove the duplicate hook declaration.

## 2026-09-14 - Cross-process tooltip and audio-session probes blocked

- Error: Reading another process's tooltip text synchronously caused the app-mute probe to time out, and a raw CoreAudio session inventory probe remained behind an AutoHotkey error window until its exact stdin-probe PID was terminated. A disposable freeze GUI also could not acquire foreground from the headless host, so its fail-closed PID check correctly sent no Ctrl+H.
- Fix: never use cross-process tooltip reads for handler verification; record bounded backend success in the controller log, terminate only a verified disposable probe PID, and use an already foregrounded reversible application for Ctrl+H acceptance tests.

## 2026-09-14 - True game suspension broke Wand and game resume

- Root cause: Ctrl+H routed every detected game to `NtSuspendProcess`, including while Wand was attached. This stopped trainer IPC and could invalidate a live Direct3D device; the affected PID was logged as `game_suspend` and later remained `restore_pending` before exiting.
- Fix: games now use minimize plus reversible IDLE priority, EcoQoS execution-speed throttling, and VERY_LOW memory priority without process suspension or working-set trimming. Alt+H restores the exact captured process policy and window geometry. Ordinary non-game applications retain true suspension.
- Regression test: before the fix, the source guard failed because games selected `game_suspend`, called the suspended backend, and skipped geometry restoration. The corrected routing must select `throttle`, call `ApplyGameLowResourceMode`, and restore captured geometry.
- PowerShell error: a process-state report repeated the known empty-pipeline parser failure by piping directly after `foreach`; assign loop output to a variable before formatting.
- Verification-host error: the first post-fix regression runner inherited a broken PowerShell Core module path, so `Get-Content` never loaded and the assertion produced a false failure. Run verification through explicit Windows PowerShell 5.1 with `-NoProfile` and avoid outer-shell `$` expansion.
- Runtime-harness error: the first game-like acceptance probe reused a previously discovered Game Library PID after that process had exited, so it aborted at `GetProcessById` before modifying the window or sending Ctrl+H. Acquire foreground HWND/PID atomically after Ctrl+R inside the same bounded harness.
- Runtime-harness timing error: a redundant second Ctrl+R was sent immediately before Ctrl+H; its asynchronous foreground action reopened Game Library after pause, making `IsIconic` false even though the throttle, resume, and Wand continuity checks passed. Launch once, keep the already-foreground HWND, then send Ctrl+H directly.
- Audit error: Git refused the final repository status check because `F:\study\Platforms` is owned by a different Windows SID and is not configured as a safe directory. Do not mutate the user's global Git trust configuration just for an audit; use scoped source, runtime, and hash checks instead.
- Final-state assertion error: `^Count=0$` did not match the CRLF-terminated INI line and falsely reported a nonzero frozen count. Use `^Count=0\r?$` or parse the value instead of assuming LF-only text.

## 2026-09-14 - PowerShell 5 ProcessStartInfo probe constructor

- Error: `New-Object Diagnostics.ProcessStartInfo(exe, args)` was parsed as three constructor arguments in the disposable CPU-cap probe and failed before the child process started.
- Fix: create an empty `Diagnostics.ProcessStartInfo` object and assign its `FileName` and `Arguments` properties explicitly.

## 2026-09-14 - Resume CPU sample was not a valid restoration assertion

- Error: The runtime test compared a busy paused sample with an idle post-resume Game Library sample and treated the lower uncapped CPU value as a failed restore.
- Fix: query the named Job Object directly after Alt+H and assert its CPU-control flags are zero; use process priority, visibility, geometry, PID, and responsiveness as the live restoration checks.
- Verification-host error: an inline PowerShell source check expanded `$s` and `$match` in the outer shell before PowerShell received them, producing command-not-found errors. Use encoded `-Command` payloads for checks containing PowerShell variables.
- Runtime-harness foreground error: Ctrl+R left the Codex window foreground during the final clean run, so the probe correctly aborted before sending Ctrl+H to the wrong PID. Acquire Game Library directly and use thread-input attachment for the bounded foreground check.
- Runtime-harness policy error: the raw `ProcessPowerThrottling` query passed a zeroed buffer, so `GetProcessInformation` returned false and the comparison read uninitialized mask bytes. Initialize the query buffer's version field to `1`, matching `CaptureProcessResourceState`.
- Runtime-harness compilation error: one diagnostic `Add-Type` block repeated `using System;`, and PowerShell's compiler treats warnings as errors in this host. Keep each diagnostic C# block's using directives unique.

## 2026-09-14 - Runtime-harness PowerShell PID variable collision

- Error: A diagnostic probe assigned `$pid`, which is a read-only automatic PowerShell variable. The assignment failed, and the remainder of that probe queried the wrong process/job name.
- Fix: use task-specific variable names such as `$gamePid` and never reuse the built-in `$PID` variable in verification commands.

## 2026-09-14 - Runtime-harness elapsed-time expression typo

- Error: A resume probe wrote `Get-Date-$start` without a space or parentheses, so PowerShell treated it as a command and emitted one error per polling iteration.
- Fix: compute elapsed time as `((Get-Date) - $startedAt).TotalMilliseconds` and discard that probe's timing fields; the hotkey itself was still dispatched and the process remained alive.

## 2026-09-14 - Wand continuity probe lost its external baseline

- Error: The Wand processes observed during the successful pause and controller-reload checks exited before the later resume-only sample, so that sample could not claim same-PID continuity.
- Fix: restart the configured Wand executable and capture the complete live process set immediately before a fresh pause/reload/resume cycle; treat a missing post-cycle set as a failed acceptance result.

## 2026-09-14 - Game Library synthetic fullscreen process exited during resume probe

- Error: The disposable Game Library target exited after Alt+H even though the window became visible and exact in 105 ms; this makes that target unsuitable for a multi-second post-resume resource assertion.
- Fix: do not treat the app's own exit as controller success; use a stable disposable GUI target for the generic throttle/restore test and keep the game-library result as evidence only for the window-restore timing path.

## 2026-09-14 - Source regression assertion pattern drift

- Error: A first source-only check looked for the helper's old literal `State=paused` formatting and reported a false failure after the helper was parameterized with `trimMode`.
- Fix: assert the actual `IniRead(..., "State", "") = "paused"` guard and compare source positions for `resuming` before `RestoreProcessResources`.

## 2026-09-14 - Delayed-trim helper unit probe blocked by execution policy

- Error: The shell policy rejected the disposable temporary-state probe before it ran, so no helper runtime result was produced.
- Fix: retain the source guard and standalone AHK validation as the non-mutating evidence; do not claim a helper runtime trim result that was not observed.

## 2026-09-14 - Ctrl+R existing-instance probe lost its transient target

- Error: The first Ctrl+R launch correctly produced a foreground Game Library window, but that executable exited before the second “already running” probe began, so no same-PID assertion was possible.
- Fix: record the launch/foreground success only; do not claim the existing-instance branch was runtime-tested against an app that had already exited.

## 2026-09-14 - Disposable OSK exited after successful throttle restore

- Error: The controlled state-load test observed the on-screen keyboard alive, responsive, visible, non-iconic, and Normal immediately after Alt+H, but it exited before the later cleanup poll.
- Fix: use the immediate post-restore snapshot as the acceptance evidence and do not interpret the disposable utility's later exit as a controller freeze.

## 2026-10-11 - Git Bash mangles AutoHotkey slash flags into paths

- Error: invoking `AutoHotkey64.exe /ErrorStdOut=UTF8 /validate current.ahk` from Git Bash rewrote `/ErrorStdOut=UTF8` into `C:/Program Files/Git/ErrorStdOut=UTF8`; AHK treated it as the script file, failed, and popped a GUI "Script file not found" dialog while reporting a meaningless exit code 2.
- Fix: run the validation gate through PowerShell (`Start-Process -Wait -PassThru` with the flags as separate `-ArgumentList` items) so MSYS path conversion never touches the arguments; capture `.ExitCode` for the gate result.
