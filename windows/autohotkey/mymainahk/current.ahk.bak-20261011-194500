#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook

; Keep the shortcut runtime responsive even when the system is busy.
InstallKeybdHook()
InstallMouseHook()
SetWinDelay(-1)
SetControlDelay(-1)
SetKeyDelay(-1, -1)
SetMouseDelay(-1)
SendMode("Input")
; Thread("Interrupt", 0) let ONE long-running hotkey thread (bulk window moves,
; fullscreen recovery, Paragon waits) block every other shortcut and stall the
; #SingleInstance-exit message, so reloads left zombie instances that
; double-fired hotkeys and held Ctrl+H/Alt+H hostage. A short interrupt delay
; keeps every shortcut responsive while freeze/resume stays atomic via
; Critical("On") inside FreezeForegroundApp/RestoreFrozenApps.
Thread("Interrupt", 50)
try DllCall("SetPriorityClass", "Ptr", DllCall("GetCurrentProcess", "Ptr"), "UInt", 0x80) ; HIGH_PRIORITY_CLASS
A_TrayMenu.Delete()
A_TrayMenu.Add("Reload", (*) => Reload())
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_TrayMenu.Default := "Reload"
A_IconTip := "MyMainAHK"

; Own Ctrl+H, Alt+H, and Ctrl+R through one explicit Windows registration path. The
; MOD_NOREPEAT flag is essential: without it, holding the chord long enough for
; the game to minimize can send another activation to the newly exposed app.
global PROCESS_PAUSE_HOTKEY_ID := 0x4A01
global PROCESS_RESUME_HOTKEY_ID := 0x4A02
global GAME_LIBRARY_HOTKEY_ID := 0x4A03
global processControlHotkeysRegistered := false
global lastPauseHotkeyMessageTime := 0
global lastResumeHotkeyMessageTime := 0
global processHotkeyRegistrationFailures := 0
OnMessage(0x0312, ProcessControlHotkeyMessage) ; WM_HOTKEY
OnExit(UnregisterProcessControlHotkeys)
OnExit(CloseGameControlPipe)
RegisterProcessControlHotkeys()
SetTimer(CheckMcsPostRestoreMarker, -1)
SetTimer(CheckMcsPostRestoreMarker, 500)
SetTimer(EnsureWhisperKeyRunning, -2000)
SetTimer(EnsureWhisperKeyRunning, 10000)
; Keep the OpenWhispr Ctrl+Win dictation trigger exact (functions at file end).
global sttGuardArmed := false
global sttGuardForeign := false
global sttGuardSuspended := false
global sttGuardResumeAt := 0
SetTimer(SttGuardTick, 25)
OnExit(SttGuardOnExit)
SetTimer(InitializeGameLaunchMonitorEnforcer, -1)

global knownGameLaunchWindows := Map()
global pendingGameMonitorEnforcement := Map()
global lastUserLaunchMonitor := MonitorGetPrimary()

InitializeGameLaunchMonitorEnforcer() {
    global knownGameLaunchWindows
    for hwnd in WinGetList() {
        knownGameLaunchWindows[hwnd] := true
    }
    SampleUserLaunchMonitor()
    SetTimer(SampleUserLaunchMonitor, 100)
    SetTimer(EnforceNewGameLaunchMonitor, 250)
}

SampleUserLaunchMonitor() {
    global lastUserLaunchMonitor
    try {
        hwnd := WinGetID("A")
        if (hwnd && !IsLikelyGameWindow(hwnd)) {
            lastUserLaunchMonitor := GetWindowMonitor(hwnd)
        }
    }
}

GetMonitorAtPoint(x, y) {
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &left, &top, &right, &bottom)
        if (x >= left && x < right && y >= top && y < bottom) {
            return A_Index
        }
    }
    return MonitorGetPrimary()
}

PlaceGameWindowOnMonitor(hwnd, monitorNum) {
    ; A hung game window (e.g. suspended by Ctrl+H) cannot be repositioned and
    ; would block the synchronous Win* calls; skip it instead.
    if (!DllCall("IsWindow", "Ptr", hwnd, "Int") || IsWindowHung(hwnd)) {
        return false
    }

    try {
        MonitorGet(monitorNum, &left, &top, &right, &bottom)
        width := right - left
        height := bottom - top
        isFullscreen := IsWindowFullscreenLike(hwnd)
        isMaximized := DllCall("IsZoomed", "Ptr", hwnd, "Int")

        if (isFullscreen) {
            DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0, "Int", left, "Int", top
                , "Int", width, "Int", height, "UInt", 0x0014 | 0x4000) ; NOZORDER | NOACTIVATE | ASYNCWINDOWPOS
        } else {
            if (isMaximized) {
                AsyncWinRestore(hwnd)
                Sleep(40)
            }
            WinGetPos(, , &windowWidth, &windowHeight, "ahk_id " hwnd)
            windowWidth := Min(windowWidth, width)
            windowHeight := Min(windowHeight, height)
            targetX := left + Max(0, (width - windowWidth) // 2)
            targetY := top + Max(0, (height - windowHeight) // 2)
            AsyncWinMove(hwnd, targetX, targetY, windowWidth, windowHeight)
            if (isMaximized) {
                Sleep(40)
                AsyncWinMaximize(hwnd)
            }
        }
        return GetWindowMonitor(hwnd) = monitorNum
    } catch {
        return false
    }
}

EnforceNewGameLaunchMonitor() {
    global knownGameLaunchWindows, pendingGameMonitorEnforcement, lastUserLaunchMonitor
    now := A_TickCount

    for hwnd in WinGetList() {
        if (knownGameLaunchWindows.Has(hwnd)) {
            continue
        }
        knownGameLaunchWindows[hwnd] := true

        if (!IsLikelyGameWindow(hwnd)) {
            continue
        }

        targetMonitor := lastUserLaunchMonitor
        pendingGameMonitorEnforcement[hwnd] := Map(
            "monitor", targetMonitor,
            "deadline", now + 15000
        )
        LogFreezeAction("Game launch monitor target HWND " hwnd " monitor " targetMonitor)
    }

    expired := []
    for hwnd, state in pendingGameMonitorEnforcement {
        if (!DllCall("IsWindow", "Ptr", hwnd, "Int") || now >= state["deadline"]) {
            expired.Push(hwnd)
            continue
        }
        PlaceGameWindowOnMonitor(hwnd, state["monitor"])
    }
    for hwnd in expired {
        pendingGameMonitorEnforcement.Delete(hwnd)
    }
}

EnsureWhisperKeyRunning()
{
    heartbeat := "F:\backup\windowsapps\installed\WhisperKeyLocal\Data\runtime-heartbeat.txt"
    launcher := A_AppData "\Microsoft\Windows\Start Menu\Programs\Startup\WhisperKeyLocal.vbs"
    ; The optional WhisperKey helper was removed from Startup.  Never let a
    ; missing helper interrupt the shortcut controller's timer thread.
    if !FileExist(launcher)
        return
    if !FileExist(heartbeat) || DateDiff(A_Now, FileGetTime(heartbeat, "M"), "Seconds") > 15 {
        try Run('wscript.exe //B //Nologo "' launcher '"', , "Hide")
    }
}

RegisterProcessControlHotkeys() {
    global PROCESS_PAUSE_HOTKEY_ID, PROCESS_RESUME_HOTKEY_ID, GAME_LIBRARY_HOTKEY_ID
        , processControlHotkeysRegistered, processHotkeyRegistrationFailures
    if (processControlHotkeysRegistered) {
        return true
    }

    ctrlOk := DllCall("RegisterHotKey", "Ptr", A_ScriptHwnd
        , "Int", PROCESS_PAUSE_HOTKEY_ID, "UInt", 0x4002, "UInt", 0x48, "Int") ; CTRL | NOREPEAT, H
    ctrlError := A_LastError
    altOk := DllCall("RegisterHotKey", "Ptr", A_ScriptHwnd
        , "Int", PROCESS_RESUME_HOTKEY_ID, "UInt", 0x4001, "UInt", 0x48, "Int") ; ALT | NOREPEAT, H
    altError := A_LastError
    libraryOk := DllCall("RegisterHotKey", "Ptr", A_ScriptHwnd
        , "Int", GAME_LIBRARY_HOTKEY_ID, "UInt", 0x4002, "UInt", 0x52, "Int") ; CTRL | NOREPEAT, R
    libraryError := A_LastError
    if (ctrlOk && altOk && libraryOk) {
        processControlHotkeysRegistered := true
        processHotkeyRegistrationFailures := 0
        LogFreezeAction("Registered Ctrl+H, Alt+H, and Ctrl+R with MOD_NOREPEAT")
        return true
    }

    ; Treat the pair atomically so there is never a half-working state.  Retry
    ; after a short delay in case a replaced script instance is still exiting.
    if (ctrlOk) {
        DllCall("UnregisterHotKey", "Ptr", A_ScriptHwnd, "Int", PROCESS_PAUSE_HOTKEY_ID)
    }
    if (altOk) {
        DllCall("UnregisterHotKey", "Ptr", A_ScriptHwnd, "Int", PROCESS_RESUME_HOTKEY_ID)
    }
    if (libraryOk) {
        DllCall("UnregisterHotKey", "Ptr", A_ScriptHwnd, "Int", GAME_LIBRARY_HOTKEY_ID)
    }
    ; Failure almost always means a previous instance of this script still owns
    ; the hotkeys and is not exiting. Log once, then after a few seconds force-
    ; remove the duplicate so Ctrl+H/Alt+H and every other hotkey work again.
    processHotkeyRegistrationFailures += 1
    if (processHotkeyRegistrationFailures = 1) {
        LogFreezeAction("Hotkey registration retry CtrlError=" ctrlError " AltError=" altError " LibraryError=" libraryError)
    }
    if (processHotkeyRegistrationFailures >= 12) {
        LogFreezeAction("Force-removing duplicate instances holding Ctrl+H/Alt+H")
        RemoveDuplicateInstances()
        processHotkeyRegistrationFailures := 0
    }
    SetTimer(RegisterProcessControlHotkeys, -250)
    return false
}

; Terminate every other running instance of this script. AHK script windows are
; hidden top-level windows titled "<script name> - AutoHotkey vX.Y.Z", so the
; title prefix identifies sibling instances without touching other AHK scripts
; (e.g. the UX launcher) or unrelated programs.
RemoveDuplicateInstances() {
    scriptPrefix := A_ScriptName " - AutoHotkey"
    for hwnd in WinGetList() {
        try title := WinGetTitle("ahk_id " hwnd)
        catch
            continue
        if !InStr(title, scriptPrefix)
            continue
        try pid := WinGetPID("ahk_id " hwnd)
        catch
            continue
        if (pid && pid != DllCall("GetCurrentProcessId", "UInt")) {
            Run('taskkill.exe /F /PID ' pid, , "Hide")
        }
    }
}

UnregisterProcessControlHotkeys(*) {
    global PROCESS_PAUSE_HOTKEY_ID, PROCESS_RESUME_HOTKEY_ID, GAME_LIBRARY_HOTKEY_ID
        , processControlHotkeysRegistered
    DllCall("UnregisterHotKey", "Ptr", A_ScriptHwnd, "Int", PROCESS_PAUSE_HOTKEY_ID)
    DllCall("UnregisterHotKey", "Ptr", A_ScriptHwnd, "Int", PROCESS_RESUME_HOTKEY_ID)
    DllCall("UnregisterHotKey", "Ptr", A_ScriptHwnd, "Int", GAME_LIBRARY_HOTKEY_ID)
    processControlHotkeysRegistered := false
}

ProcessControlHotkeyMessage(wParam, lParam, msg, hwnd) {
    global PROCESS_PAUSE_HOTKEY_ID, PROCESS_RESUME_HOTKEY_ID, GAME_LIBRARY_HOTKEY_ID
        , lastPauseHotkeyMessageTime, lastResumeHotkeyMessageTime
    messageTime := DllCall("GetMessageTime", "UInt")
    if (wParam = PROCESS_PAUSE_HOTKEY_ID) {
        elapsed := (messageTime - lastPauseHotkeyMessageTime) & 0xFFFFFFFF
        if (lastPauseHotkeyMessageTime && elapsed < 500) {
            return 0
        }
        lastPauseHotkeyMessageTime := messageTime
        FreezeForegroundApp()
    } else if (wParam = PROCESS_RESUME_HOTKEY_ID) {
        elapsed := (messageTime - lastResumeHotkeyMessageTime) & 0xFFFFFFFF
        if (lastResumeHotkeyMessageTime && elapsed < 500) {
            return 0
        }
        lastResumeHotkeyMessageTime := messageTime
        RestoreFrozenApps()
    } else if (wParam = GAME_LIBRARY_HOTKEY_ID) {
        OpenGameLibraryManager()
    }
    return 0
}

StartGameControlPipe() {
    global gameControlPipeHandle, gameControlPipeName
    if (gameControlPipeHandle)
        return true

    sid := GetCurrentUserSidString()
    if (sid = "")
        return false
    sessionId := 0
    if !DllCall("ProcessIdToSessionId", "UInt", DllCall("GetCurrentProcessId", "UInt"), "UInt*", &sessionId, "Int")
        return false

    gameControlPipeName := "\\.\pipe\GameLibrary-AHK-Control-" sid "-" sessionId
    descriptorText := "D:P(A;;GA;;;" sid ")"
    securityDescriptor := 0
    if !DllCall("Advapi32\ConvertStringSecurityDescriptorToSecurityDescriptorW"
        , "WStr", descriptorText, "UInt", 1, "Ptr*", &securityDescriptor, "Ptr", 0, "Int")
        return false

    securityAttributes := Buffer(A_PtrSize = 8 ? 24 : 12, 0)
    NumPut("UInt", securityAttributes.Size, securityAttributes, 0)
    NumPut("Ptr", securityDescriptor, securityAttributes, A_PtrSize = 8 ? 8 : 4)
    NumPut("Int", 0, securityAttributes, A_PtrSize * 2)
    pipe := DllCall("CreateNamedPipeW", "WStr", gameControlPipeName
        , "UInt", 0x00000003 ; PIPE_ACCESS_DUPLEX
        , "UInt", 0x0000000F ; message mode, nonblocking, reject remote clients
        , "UInt", 1, "UInt", 4096, "UInt", 4096, "UInt", 0
        , "Ptr", securityAttributes.Ptr, "Ptr")
    DllCall("LocalFree", "Ptr", securityDescriptor, "Ptr")
    if (!pipe || pipe = -1)
        return false
    gameControlPipeHandle := pipe
    return true
}

CloseGameControlPipe(*) {
    global gameControlPipeHandle, gameControlPipeConnected, gameControlPipeReplySent, gameControlPipeConnectedTick
    SetTimer(PollGameControlPipe, 0)
    if (!gameControlPipeHandle)
        return
    if (gameControlPipeConnected)
        DllCall("DisconnectNamedPipe", "Ptr", gameControlPipeHandle)
    DllCall("CloseHandle", "Ptr", gameControlPipeHandle)
    gameControlPipeHandle := 0
    gameControlPipeConnected := false
    gameControlPipeReplySent := false
    gameControlPipeConnectedTick := 0
}

PollGameControlPipe() {
    global gameControlPipeHandle, gameControlPipeConnected, gameControlPipeReplySent, gameControlPipeReplyTick, gameControlPipeLastStartTick, gameControlPipeConnectedTick
    if (!gameControlPipeHandle) {
        if (!gameControlPipeLastStartTick || A_TickCount - gameControlPipeLastStartTick >= 5000) {
            gameControlPipeLastStartTick := A_TickCount
            StartGameControlPipe()
        }
        return
    }

    if (!gameControlPipeConnected) {
        connected := DllCall("ConnectNamedPipe", "Ptr", gameControlPipeHandle, "Ptr", 0, "Int")
        connectError := connected ? 0 : DllCall("GetLastError", "UInt")
        if (!connected && connectError != 535) { ; ERROR_PIPE_CONNECTED
            return
        }
        gameControlPipeConnected := true
        gameControlPipeConnectedTick := A_TickCount
        gameControlPipeReplySent := false
    }

    requestBuffer := Buffer(2048, 0)
    bytesRead := 0
    readOk := DllCall("ReadFile", "Ptr", gameControlPipeHandle, "Ptr", requestBuffer.Ptr
        , "UInt", requestBuffer.Size - 1, "UInt*", &bytesRead, "Ptr", 0, "Int")
    if (!readOk) {
        readError := DllCall("GetLastError", "UInt")
        if (readError = 232) ; ERROR_NO_DATA: client connected, request not written yet
        {
            if ((gameControlPipeReplySent && A_TickCount - gameControlPipeReplyTick > 5000)
                || (!gameControlPipeReplySent && A_TickCount - gameControlPipeConnectedTick > 2000))
                DisconnectGameControlPipeClient()
            return
        }
        if (readError = 234) { ; ERROR_MORE_DATA: reject oversized request
            if (WriteGameControlPipeResponse("", "failed", "Request exceeded the protocol limit.")) {
                gameControlPipeReplySent := true
                gameControlPipeReplyTick := A_TickCount
            } else {
                DisconnectGameControlPipeClient()
            }
            return
        }
        DisconnectGameControlPipeClient()
        return
    }
    if (bytesRead = 0) {
        if (gameControlPipeReplySent)
            DisconnectGameControlPipeClient()
        return
    }

    request := StrGet(requestBuffer, bytesRead, "UTF-8")
    try response := HandleGameControlPipeRequest(request)
    catch as ex {
        response := {RequestId: "", State: "failed", Detail: "AHK handler failed."}
    }
    if (WriteGameControlPipeResponse(response.RequestId, response.State, response.Detail)) {
        gameControlPipeReplySent := true
        gameControlPipeReplyTick := A_TickCount
    } else {
        DisconnectGameControlPipeClient()
    }
}

DisconnectGameControlPipeClient() {
    global gameControlPipeHandle, gameControlPipeConnected, gameControlPipeReplySent, gameControlPipeConnectedTick
    if (gameControlPipeHandle && gameControlPipeConnected)
        DllCall("DisconnectNamedPipe", "Ptr", gameControlPipeHandle)
    gameControlPipeConnected := false
    gameControlPipeReplySent := false
    gameControlPipeConnectedTick := 0
}

HandleGameControlPipeRequest(request) {
    global gameControlRequests, gameControlRequestOrder, gameControlPipeHandle
    fields := StrSplit(Trim(request, "`r`n"), "`t")
    requestId := fields.Length >= 2 ? fields[2] : ""
    operation := fields.Length >= 3 ? fields[3] : ""
    if (fields.Length != 6 || fields[1] != "v1" || !RegExMatch(requestId, "^[0-9A-Fa-f]{32}$"))
        return {RequestId: requestId, State: "failed", Detail: "Malformed request."}

    if (!RegExMatch(fields[4], "^[0-9]{1,10}$") || !RegExMatch(fields[5], "^[0-9A-Fa-f]{16}$")
        || !RegExMatch(fields[6], "^[0-9]{1,20}$"))
        return {RequestId: requestId, State: "failed", Detail: "Malformed process identity."}

    pid := Integer(fields[4])
    created := StrUpper(fields[5])
    hwnd := Integer(fields[6])
    clientPid := 0
    if (!DllCall("GetNamedPipeClientProcessId", "Ptr", gameControlPipeHandle, "UInt*", &clientPid, "Int")
        || !IsAuthorizedGameLibraryClient(clientPid))
        return {RequestId: requestId, State: "failed", Detail: "The requesting process is not the Game Library in this session."}

    if (gameControlRequests.Has(requestId)) {
        previous := gameControlRequests[requestId]
        if (previous.Operation != operation || previous.Pid != pid || previous.Created != created || previous.Hwnd != hwnd)
            return {RequestId: requestId, State: "failed", Detail: "A request ID was reused with a different operation or target."}
        return {RequestId: requestId, State: previous.State, Detail: previous.Detail}
    }

    if (operation != "Pause" && operation != "Resume" && operation != "Status")
        return RememberGameControlRequest(requestId, operation, pid, created, hwnd, "failed", "Unsupported operation.")
    if (!ValidateGameControlTarget(pid, created, hwnd, clientPid))
        return RememberGameControlRequest(requestId, operation, pid, created, hwnd, "failed", "The process, creation stamp, window, or session did not match.")

    if (operation = "Status") {
        state := GetGameControlState(pid, created, hwnd)
        detail := state = "failed" ? "The target has a pending recovery error." : "Current state read from the AHK frozen-process registry."
        return RememberGameControlRequest(requestId, operation, pid, created, hwnd, state, detail)
    }

    currentState := GetGameControlState(pid, created, hwnd)
    if ((operation = "Pause" && currentState = "paused") || (operation = "Resume" && currentState = "running"))
        return RememberGameControlRequest(requestId, operation, pid, created, hwnd, currentState, "The target is already in the requested state.")

    pendingState := operation = "Pause" ? "pausing" : "resuming"
    RememberGameControlRequest(requestId, operation, pid, created, hwnd, pendingState, "The target operation was queued.")
    SetTimer(() => RunGameControlPipeOperation(requestId, operation, pid, created, hwnd), -1)
    return gameControlRequests[requestId]
}

RunGameControlPipeOperation(requestId, operation, pid, created, hwnd) {
    global gameControlRequests
    if (!gameControlRequests.Has(requestId))
        return
    try {
        state := operation = "Pause" ? PauseTargetWindow(hwnd, pid, created) : ResumeTargetProcess(pid, created, hwnd)
        detail := state = "failed" ? "AHK could not safely complete the operation." : "The target operation completed or is restoring its window."
    } catch as ex {
        state := "failed"
        detail := ex.Message
    }
    if (gameControlRequests.Has(requestId))
        SetGameControlRequestState(requestId, state, detail)
}

RememberGameControlRequest(requestId, operation, pid, created, hwnd, state, detail) {
    global gameControlRequests, gameControlRequestOrder
    gameControlRequests[requestId] := {RequestId: requestId, Operation: operation, Pid: pid, Created: created, Hwnd: hwnd, State: state, Detail: SanitizeGameControlText(detail)}
    gameControlRequestOrder.Push(requestId)
    while (gameControlRequestOrder.Length > 256) {
        oldId := gameControlRequestOrder.RemoveAt(1)
        if (gameControlRequests.Has(oldId))
            gameControlRequests.Delete(oldId)
    }
    return gameControlRequests[requestId]
}

SetGameControlRequestState(requestId, state, detail) {
    global gameControlRequests
    if (!gameControlRequests.Has(requestId))
        return
    entry := gameControlRequests[requestId]
    entry.State := state
    entry.Detail := SanitizeGameControlText(detail)
}

WriteGameControlPipeResponse(requestId, state, detail) {
    global gameControlPipeHandle
    if (!gameControlPipeHandle)
        return false
    response := "v1`t" requestId "`t" state "`t" SanitizeGameControlText(detail) "`n"
    responseBuffer := Buffer(StrPut(response, "UTF-8"), 0)
    responseBytes := StrPut(response, responseBuffer, "UTF-8") - 1
    bytesWritten := 0
    return DllCall("WriteFile", "Ptr", gameControlPipeHandle, "Ptr", responseBuffer.Ptr
        , "UInt", responseBytes, "UInt*", &bytesWritten, "Ptr", 0, "Int") && bytesWritten = responseBytes
}

SanitizeGameControlText(value) {
    value := StrReplace(value, "`t", " ")
    value := StrReplace(value, "`r", " ")
    value := StrReplace(value, "`n", " ")
    return SubStr(value, 1, 300)
}

GetGameControlState(pid, created, hwnd) {
    global frozenProcesses
    if (!ProcessExist(pid) || GetProcessCreationStamp(pid) != created)
        return "failed"
    for _, processInfo in frozenProcesses {
        if (processInfo.pid != pid || !processInfo.HasProp("created") || processInfo.created != created)
            continue
        if (processInfo.state = "paused")
            return "paused"
        if (processInfo.state = "pausing")
            return "pausing"
        if (processInfo.state = "resuming")
            return "resuming"
        if (processInfo.state = "restoring")
            return "restoring"
        if (processInfo.state = "restore_pending")
            return "failed"
    }
    return "running"
}

ValidateGameControlTarget(pid, created, hwnd, clientPid := 0) {
    if (!pid || !hwnd || pid = DllCall("GetCurrentProcessId", "UInt") || pid = clientPid
        || !RegExMatch(created, "^[0-9A-F]{16}$") || !ProcessExist(pid)
        || !DllCall("IsWindow", "Ptr", hwnd, "Int"))
        return false
    if (GetProcessSessionId(pid) != GetCurrentSessionId() || GetProcessCreationStamp(pid) != created)
        return false
    windowPid := 0
    if (!DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &windowPid) || windowPid != pid)
        return false
    imagePath := GetProcessImagePath(pid)
    imageName := StrLower(RegExReplace(imagePath, ".*\\", ""))
    return imagePath != "" && imageName != "gamelibrary.exe"
        && imageName != "autohotkey64.exe" && imageName != "autohotkey.exe"
}

IsAuthorizedGameLibraryClient(pid) {
    if (!pid || GetProcessSessionId(pid) != GetCurrentSessionId())
        return false
    imagePath := GetProcessImagePath(pid)
    imageName := StrLower(RegExReplace(imagePath, ".*\\", ""))
    return imageName = "gamelibrary.exe"
}

GetCurrentSessionId() {
    sessionId := 0
    if DllCall("ProcessIdToSessionId", "UInt", DllCall("GetCurrentProcessId", "UInt"), "UInt*", &sessionId, "Int")
        return sessionId
    return -1
}

GetProcessSessionId(pid) {
    sessionId := 0
    return DllCall("ProcessIdToSessionId", "UInt", pid, "UInt*", &sessionId, "Int") ? sessionId : -1
}

GetProcessImagePath(pid) {
    process := DllCall("OpenProcess", "UInt", 0x1000, "Int", 0, "UInt", pid, "Ptr")
    if (!process)
        return ""
    imageBuffer := Buffer(32768 * 2, 0)
    length := 32768
    ok := DllCall("QueryFullProcessImageNameW", "Ptr", process, "UInt", 0
        , "Ptr", imageBuffer.Ptr, "UInt*", &length, "Int")
    DllCall("CloseHandle", "Ptr", process)
    return ok ? StrGet(imageBuffer, length, "UTF-16") : ""
}

GetCurrentUserSidString() {
    token := 0
    if !DllCall("Advapi32\OpenProcessToken", "Ptr", DllCall("GetCurrentProcess", "Ptr"), "UInt", 0x0008, "Ptr*", &token, "Int")
        return ""
    required := 0
    DllCall("Advapi32\GetTokenInformation", "Ptr", token, "Int", 1, "Ptr", 0, "UInt", 0, "UInt*", &required)
    if (!required) {
        DllCall("CloseHandle", "Ptr", token)
        return ""
    }
    tokenUser := Buffer(required, 0)
    if !DllCall("Advapi32\GetTokenInformation", "Ptr", token, "Int", 1, "Ptr", tokenUser.Ptr, "UInt", required, "UInt*", &required, "Int") {
        DllCall("CloseHandle", "Ptr", token)
        return ""
    }
    sidStringPointer := 0
    sidPointer := NumGet(tokenUser, 0, "Ptr")
    ok := DllCall("Advapi32\ConvertSidToStringSidW", "Ptr", sidPointer, "Ptr*", &sidStringPointer, "Int")
    sid := ok ? StrGet(sidStringPointer, "UTF-16") : ""
    if (sidStringPointer)
        DllCall("LocalFree", "Ptr", sidStringPointer, "Ptr")
    DllCall("CloseHandle", "Ptr", token)
    return sid
}

; ============================================================================
; MONITOR MANAGEMENT FUNCTIONS
; ============================================================================
; This section provides robust multi-monitor management functionality including:
; - Monitor detection and enumeration
; - Window-to-monitor mapping and detection
; - Window movement between monitors with edge case handling
; - Monitor focus switching with cursor positioning
; - Fullscreen, maximized, and spanning window support
; ============================================================================

GetDisplayDeviceEntry(deviceName, index) {
    ; DISPLAY_DEVICEW contains fixed-width fields and has no pointer-sized members.
    device := Buffer(840, 0)
    NumPut("UInt", device.Size, device, 0)

    if (deviceName = "") {
        ok := DllCall("User32\EnumDisplayDevicesW", "Ptr", 0, "UInt", index
            , "Ptr", device.Ptr, "UInt", 1, "Int")
    } else {
        ok := DllCall("User32\EnumDisplayDevicesW", "Str", deviceName, "UInt", index
            , "Ptr", device.Ptr, "UInt", 1, "Int")
    }

    if !ok
        return 0

    return Map(
        "name", StrGet(device.Ptr + 4, 32, "UTF-16"),
        "string", StrGet(device.Ptr + 68, 128, "UTF-16"),
        "flags", NumGet(device, 324, "UInt"),
        "id", StrGet(device.Ptr + 328, 128, "UTF-16")
    )
}

GetMonitorDeviceInfo(monitorNum) {
    gdiName := MonitorGetName(monitorNum)
    adapterName := ""

    Loop 32 {
        adapter := GetDisplayDeviceEntry("", A_Index - 1)
        if !IsObject(adapter)
            break
        if (adapter["name"] = gdiName) {
            adapterName := adapter["string"]
            break
        }
    }

    monitor := GetDisplayDeviceEntry(gdiName, 0)
    monitorId := IsObject(monitor) ? monitor["id"] : ""
    return Map("name", gdiName, "adapter", adapterName, "id", monitorId)
}

IsVirtualMonitor(monitorNum) {
    try info := GetMonitorDeviceInfo(monitorNum)
    catch {
        return false
    }

    identity := StrLower(info["adapter"] "|" info["id"])
    return InStr(identity, "virtual")
        || InStr(identity, "indirect display")
        || InStr(identity, "iddsample")
        || InStr(identity, "mtt1337")
        || (identity = "|" && InStr(StrLower(info["name"]), "display10"))
}

IsTvMonitor(monitorNum) {
    try info := GetMonitorDeviceInfo(monitorNum)
    catch {
        return false
    }

    adapter := StrLower(info["adapter"])
    deviceId := StrLower(info["id"])
    return InStr(deviceId, "mtt1337")
        || InStr(adapter, "virtual display driver")
        || InStr(adapter, "sunshine")
        || InStr(adapter, "moonlight")
}

BuildPhysicalMonitorOrder(records, primaryMonitor) {
    primaryPhysical := 0
    otherPhysical := []

    for record in records {
        if record["isVirtual"]
            continue
        if (record["index"] = primaryMonitor)
            primaryPhysical := record["index"]
        else
            otherPhysical.Push(record["index"])
    }

    ordered := []
    if primaryPhysical
        ordered.Push(primaryPhysical)
    for monitorNum in otherPhysical
        ordered.Push(monitorNum)
    return ordered
}

GetPhysicalMonitorIndexes() {
    records := []
    Loop MonitorGetCount() {
        records.Push(Map("index", A_Index, "isVirtual", IsVirtualMonitor(A_Index)))
    }
    return BuildPhysicalMonitorOrder(records, MonitorGetPrimary())
}

GetPhysicalMonitorPair() {
    physical := GetPhysicalMonitorIndexes()
    return Map(
        "count", physical.Length,
        "primary", physical.Length >= 1 ? physical[1] : 0,
        "secondary", physical.Length >= 2 ? physical[2] : 0,
        "all", physical
    )
}

GetOtherPhysicalMonitor(currentMonitor) {
    pair := GetPhysicalMonitorPair()
    if !pair["primary"] || !pair["secondary"]
        return 0
    return (currentMonitor = pair["primary"]) ? pair["secondary"] : pair["primary"]
}

; Get detailed information about all monitors
; This function enumerates all connected monitors and retrieves their properties
; Returns: Map where key is monitor index (1-based), value is Map of monitor properties
;   Properties include: left, top, right, bottom, width, height,
;                      workLeft, workTop, workRight, workBottom, workWidth, workHeight,
;                      name, isPrimary
GetMonitorInfo() {
    monitors := Map()
    monitorCount := MonitorGetCount()

    Loop monitorCount {
        monIndex := A_Index
        monitors[monIndex] := Map()

        ; Get full monitor bounds
        MonitorGet(monIndex, &mLeft, &mTop, &mRight, &mBottom)
        monitors[monIndex]["left"] := mLeft
        monitors[monIndex]["top"] := mTop
        monitors[monIndex]["right"] := mRight
        monitors[monIndex]["bottom"] := mBottom
        monitors[monIndex]["width"] := mRight - mLeft
        monitors[monIndex]["height"] := mBottom - mTop

        ; Get work area (excluding taskbar)
        MonitorGetWorkArea(monIndex, &wLeft, &wTop, &wRight, &wBottom)
        monitors[monIndex]["workLeft"] := wLeft
        monitors[monIndex]["workTop"] := wTop
        monitors[monIndex]["workRight"] := wRight
        monitors[monIndex]["workBottom"] := wBottom
        monitors[monIndex]["workWidth"] := wRight - wLeft
        monitors[monIndex]["workHeight"] := wBottom - wTop

        ; Get monitor name
        monitors[monIndex]["name"] := MonitorGetName(monIndex)
        deviceInfo := GetMonitorDeviceInfo(monIndex)
        monitors[monIndex]["adapter"] := deviceInfo["adapter"]
        monitors[monIndex]["deviceId"] := deviceInfo["id"]
        monitors[monIndex]["isVirtual"] := IsVirtualMonitor(monIndex)
        monitors[monIndex]["isPhysical"] := !monitors[monIndex]["isVirtual"]

        ; Check if primary monitor
        monitors[monIndex]["isPrimary"] := MonitorGetPrimary() = monIndex
    }

    return monitors
}

; Get which monitor a window is currently on
; Parameters:
;   hwnd - Window handle to check
; Returns: Monitor number (1-based), defaults to the primary monitor if detection fails
GetWindowMonitor(hwnd) {
    ; Validate window handle
    if (!hwnd || !WinExist("ahk_id " hwnd)) {
        return MonitorGetPrimary()
    }

    try {
        monitorCount := MonitorGetCount()
        if (monitorCount < 1) {
            return MonitorGetPrimary()
        }

        ; MonitorFromWindow preserves the real monitor association for minimized
        ; windows, whose reported coordinates are often the off-screen -32000 sentinel.
        windowMonitorHandle := DllCall("User32\MonitorFromWindow", "Ptr", hwnd, "UInt", 2, "Ptr")
        if windowMonitorHandle {
            Loop monitorCount {
                MonitorGet(A_Index, &mLeft, &mTop, &mRight, &mBottom)
                centerX := mLeft + ((mRight - mLeft) // 2)
                centerY := mTop + ((mBottom - mTop) // 2)
                point := (centerX & 0xFFFFFFFF) | (centerY << 32)
                candidateHandle := DllCall("User32\MonitorFromPoint", "Int64", point, "UInt", 0, "Ptr")
                if (candidateHandle = windowMonitorHandle)
                    return A_Index
            }
        }

        ; Fall back to center-point detection for unusual windows without a
        ; monitor handle.
        WinGetPos(&winX, &winY, &winW, &winH, "ahk_id " hwnd)
        if (winW <= 0 || winH <= 0)
            return MonitorGetPrimary()
        winCenterX := winX + (winW // 2)
        winCenterY := winY + (winH // 2)

        Loop monitorCount {
            MonitorGet(A_Index, &mLeft, &mTop, &mRight, &mBottom)
            if (winCenterX >= mLeft && winCenterX < mRight &&
                winCenterY >= mTop && winCenterY < mBottom) {
                return A_Index
            }
        }
    } catch {
        ; Any error defaults to the primary monitor.
    }

    return MonitorGetPrimary()
}

; Enumerate all windows grouped by monitor
; This function scans all visible windows and groups them by which monitor they're on
; It filters out system windows, invisible windows, tool windows, and tiny windows
; The grouping is based on window center point location
; Returns: Map where key is monitor number (1-based), value is array of window handles (hwnd)
;   - Only includes visible application windows with titles
;   - Excludes: Shell_TrayWnd, Progman, WorkerW, tool windows, windows < 50x50px
EnumerateWindowsByMonitor() {
    monitorCount := MonitorGetCount()
    windowsByMonitor := Map()

    ; Initialize map with empty arrays for each monitor
    Loop monitorCount {
        windowsByMonitor[A_Index] := []
    }

    ; Enumerate all windows
    for hwnd in WinGetList() {
        try {
            ; Get window title
            title := WinGetTitle("ahk_id " hwnd)
            if (!title || title = "")
                continue

            ; Get window style to check visibility
            style := WinGetStyle("ahk_id " hwnd)
            if !(style & 0x10000000)  ; WS_VISIBLE
                continue

            ; Get window class
            winClass := WinGetClass("ahk_id " hwnd)

            ; Skip system windows
            if (winClass = "Shell_TrayWnd" || winClass = "Shell_SecondaryTrayWnd" ||
                winClass = "Progman" || winClass = "WorkerW" || winClass = "Windows.UI.Core.CoreWindow" ||
                winClass = "DV2ControlHost" || winClass = "TopLevelWindowForOverflowXamlIsland" ||
                winClass = "Xaml_WindowedPopupClass")
                continue

            ; Get extended style
            exStyle := WinGetExStyle("ahk_id " hwnd)

            ; Skip tool windows (like floating toolbars)
            if (exStyle & 0x80)  ; WS_EX_TOOLWINDOW
                continue

            ; Minimized windows often report a tiny taskbar-button rectangle.
            ; Keep them so bulk moves can update their restore monitor.
            minMaxState := WinGetMinMax("ahk_id " hwnd)
            if (minMaxState != -1) {
                WinGetPos(, , &wW, &wH, "ahk_id " hwnd)
                if (wW < 50 || wH < 50)
                    continue
            }

            ; A hung window (e.g. a game suspended by Ctrl+H) cannot be moved;
            ; skip it so bulk swaps never block on synchronous Win* calls.
            if IsWindowHung(hwnd)
                continue

            monitorNum := GetWindowMonitor(hwnd)
            if windowsByMonitor.Has(monitorNum)
                windowsByMonitor[monitorNum].Push(hwnd)
        } catch {
            ; Skip problematic windows
            continue
        }
    }

    return windowsByMonitor
}

; Check if window is in fullscreen mode (covers entire screen)
; Parameters:
;   hwnd - Window handle to check
; Returns: true if fullscreen, false otherwise
IsWindowFullscreen(hwnd) {
    ; Validate window handle
    if (!hwnd || !WinExist("ahk_id " hwnd)) {
        return false
    }

    try {
        ; Get window position and size
        WinGetPos(&winX, &winY, &winW, &winH, "ahk_id " hwnd)

        ; Validate window dimensions
        if (winW <= 0 || winH <= 0) {
            return false
        }

        ; Get the monitor the window is on
        monitorNum := GetWindowMonitor(hwnd)
        if (monitorNum < 1 || monitorNum > MonitorGetCount()) {
            return false
        }

        MonitorGet(monitorNum, &mLeft, &mTop, &mRight, &mBottom)

        ; Check if window covers the entire monitor (fullscreen)
        ; Allow small margin of error (5 pixels) for window borders
        if (Abs(winX - mLeft) <= 5 && Abs(winY - mTop) <= 5 &&
            Abs(winW - (mRight - mLeft)) <= 10 && Abs(winH - (mBottom - mTop)) <= 10) {
            return true
        }
    } catch {
        ; Any error means not fullscreen
        return false
    }

    return false
}

; Check if window spans multiple monitors
; Parameters:
;   hwnd - Window handle to check
; Returns: true if spanning multiple monitors, false otherwise
IsWindowSpanningMonitors(hwnd) {
    ; Validate window handle
    if (!hwnd || !WinExist("ahk_id " hwnd)) {
        return false
    }

    try {
        WinGetPos(&winX, &winY, &winW, &winH, "ahk_id " hwnd)

        ; Validate window dimensions
        if (winW <= 0 || winH <= 0) {
            return false
        }

        ; Count how many monitors this window intersects
        monitorCount := MonitorGetCount()
        if (monitorCount < 2) {
            return false  ; Can't span if less than 2 monitors
        }

        intersectionCount := 0

        Loop monitorCount {
            try {
                MonitorGet(A_Index, &mLeft, &mTop, &mRight, &mBottom)

                ; Check for intersection between window and monitor
                if (winX < mRight && winX + winW > mLeft &&
                    winY < mBottom && winY + winH > mTop) {
                    intersectionCount++
                }
            } catch {
                continue
            }
        }

        return intersectionCount > 1
    } catch {
        ; Any error means not spanning
        return false
    }

    return false
}

; Move all windows from one monitor to another
; This is the core function for bulk window movement between monitors
; It handles various window states intelligently:
;   - Fullscreen windows: Restore -> Move -> Re-fullscreen on target monitor
;   - Maximized windows: Restore -> Move -> Re-maximize on target monitor
;   - Spanning windows: Restore -> Center on target monitor
;   - Normal windows: Preserve relative position from source to target monitor
; Parameters:
;   sourceMonitor - Monitor number to move windows FROM (1-based index)
;   targetMonitor - Monitor number to move windows TO (1-based index)
; Returns: Map with success status and detailed results
;   - success: true if at least one window moved successfully
;   - movedCount: Number of windows successfully moved
;   - failedCount: Number of windows that failed to move
;   - message: Description of operation result
; Note: Preserves minimized and maximized state while relocating windows
MoveAllWindowsBetweenMonitors(sourceMonitor, targetMonitor) {
    result := Map(
        "success", false,
        "movedCount", 0,
        "failedCount", 0,
        "message", ""
    )

    ; Validate monitor numbers
    monitorCount := MonitorGetCount()
    if (sourceMonitor < 1 || sourceMonitor > monitorCount) {
        result["message"] := "Invalid source monitor: " sourceMonitor " (only " monitorCount " monitor(s) available)"
        return result
    }
    if (targetMonitor < 1 || targetMonitor > monitorCount) {
        result["message"] := "Invalid target monitor: " targetMonitor " (only " monitorCount " monitor(s) available)"
        return result
    }
    if (sourceMonitor = targetMonitor) {
        result["message"] := "Source and target monitors are the same (" sourceMonitor ")"
        return result
    }

    ; Get windows grouped by monitor
    try {
        windowsByMonitor := EnumerateWindowsByMonitor()
    } catch as err {
        result["message"] := "Failed to enumerate windows: " err.Message
        return result
    }

    ; Get source monitor windows
    sourceWindows := windowsByMonitor[sourceMonitor]
    if (sourceWindows.Length = 0) {
        result["message"] := "No windows found on source monitor " sourceMonitor
        return result
    }

    ; Get monitor info for both monitors
    try {
        MonitorGetWorkArea(sourceMonitor, &sLeft, &sTop, &sRight, &sBottom)
        MonitorGetWorkArea(targetMonitor, &tLeft, &tTop, &tRight, &tBottom)
        MonitorGet(targetMonitor, &tFullLeft, &tFullTop, &tFullRight, &tFullBottom)
    } catch as err {
        result["message"] := "Failed to get monitor information: " err.Message
        return result
    }

    sWidth := sRight - sLeft
    sHeight := sBottom - sTop
    tWidth := tRight - tLeft
    tHeight := tBottom - tTop

    movedCount := 0
    failedCount := 0

    ; Move each window from source to target monitor
    ; Iterates through all windows found on the source monitor and moves them individually
    for hwnd in sourceWindows {
        try {
            ; Verify window still exists (user may have closed it since enumeration)
            if (!WinExist("ahk_id " hwnd)) {
                failedCount++
                continue
            }

            ; Restore minimized windows long enough to move their normal placement,
            ; then minimize them again after the move.
            wasMinimized := false
            wasMaximized := false
            try {
                minMaxState := WinGetMinMax("ahk_id " hwnd)
                wasMinimized := minMaxState = -1
                if wasMinimized {
                    WinRestore("ahk_id " hwnd)
                    Sleep(50)
                    minMaxState := WinGetMinMax("ahk_id " hwnd)
                }
                wasMaximized := minMaxState = 1
            } catch as err {
                failedCount++
                continue
            }

            ; Check if window spans multiple monitors
            try {
                isSpanning := IsWindowSpanningMonitors(hwnd)
            } catch {
                isSpanning := false
            }

            ; Check if window is in fullscreen mode
            try {
                isFullscreen := IsWindowFullscreen(hwnd)
            } catch {
                isFullscreen := false
            }

            ; Handle fullscreen apps (games, video players)
            ; Fullscreen is different from maximized - it covers entire screen including taskbar
            ; Common in games and video players
            if (isFullscreen && !wasMaximized) {
                try {
                    ; Fullscreen apps need special handling to prevent visual glitches
                    ; First restore to windowed mode to allow repositioning
                    WinRestore("ahk_id " hwnd)
                    Sleep(100)  ; Longer delay for fullscreen transitions (some apps are slow)

                    ; Move to target monitor and make fullscreen again
                    ; Use full monitor bounds (not work area) to cover entire screen
                    WinMove(tFullLeft, tFullTop, tFullRight - tFullLeft, tFullBottom - tFullTop, "ahk_id " hwnd)
                    Sleep(50)

                    if wasMinimized
                        WinMinimize("ahk_id " hwnd)
                    movedCount++
                    continue  ; Skip normal window movement logic
                } catch as err {
                    failedCount++
                    continue
                }
            }

            ; Handle spanning windows - move to center of target monitor
            if (isSpanning) {
                try {
                    WinRestore("ahk_id " hwnd)
                    Sleep(50)

                    WinGetPos(, , &winW, &winH, "ahk_id " hwnd)

                    ; Center on target monitor
                    centerX := tLeft + ((tWidth - winW) // 2)
                    centerY := tTop + ((tHeight - winH) // 2)

                    ; Ensure it fits
                    centerX := Max(tLeft, Min(centerX, tRight - winW))
                    centerY := Max(tTop, Min(centerY, tBottom - winH))

                    WinMove(centerX, centerY, , , "ahk_id " hwnd)
                    if wasMinimized
                        WinMinimize("ahk_id " hwnd)
                    movedCount++
                    continue
                } catch as err {
                    failedCount++
                    continue
                }
            }

            ; Handle maximized windows
            if (wasMaximized) {
                try {
                    WinRestore("ahk_id " hwnd)
                    Sleep(30)
                } catch as err {
                    failedCount++
                    continue
                }
            }

            ; Get current window position
            try {
                WinGetPos(&winX, &winY, &winW, &winH, "ahk_id " hwnd)
            } catch as err {
                failedCount++
                continue
            }

            ; Calculate relative position on source monitor
            ; This preserves window placement (e.g., top-left corner stays top-left)
            ; relX and relY are values between 0.0 and 1.0 representing position ratio
            relX := (winX - sLeft) / sWidth
            relY := (winY - sTop) / sHeight

            ; Apply same relative position on target monitor
            ; This maintains visual consistency when moving windows between monitors
            newX := tLeft + (relX * tWidth)
            newY := tTop + (relY * tHeight)

            ; Ensure window fits on target monitor (clamp to work area boundaries)
            ; This prevents windows from being positioned off-screen or partially hidden
            newX := Max(tLeft, Min(newX, tRight - winW))
            newY := Max(tTop, Min(newY, tBottom - winH))

            ; Move the window
            try {
                WinMove(newX, newY, , , "ahk_id " hwnd)
                Sleep(30)

                ; If window was maximized, re-maximize it on the new monitor
                if (wasMaximized) {
                    Sleep(30)
                    WinMaximize("ahk_id " hwnd)
                }
                if wasMinimized {
                    Sleep(30)
                    WinMinimize("ahk_id " hwnd)
                }

                movedCount++
            } catch as err {
                failedCount++
                continue
            }
        } catch as err {
            ; Catch-all for any unexpected errors
            failedCount++
            continue
        }
    }

    ; Update result object
    result["movedCount"] := movedCount
    result["failedCount"] := failedCount
    result["success"] := movedCount > 0

    if (movedCount > 0) {
        if (failedCount > 0) {
            result["message"] := "Moved " movedCount " window(s), " failedCount " failed"
        } else {
            result["message"] := "Successfully moved " movedCount " window(s)"
        }
    } else {
        result["message"] := "Failed to move any windows (" failedCount " errors)"
    }

    return result
}

MoveAllWindowsToMonitor(targetMonitor) {
    result := Map("success", false, "movedCount", 0, "failedCount", 0, "message", "")
    monitorCount := MonitorGetCount()
    if (targetMonitor < 1 || targetMonitor > monitorCount) {
        result["message"] := "Target monitor is not available"
        return result
    }

    Loop monitorCount {
        sourceMonitor := A_Index
        if (sourceMonitor = targetMonitor)
            continue
        moveResult := MoveAllWindowsBetweenMonitors(sourceMonitor, targetMonitor)
        result["movedCount"] += moveResult["movedCount"]
        result["failedCount"] += moveResult["failedCount"]
    }

    result["success"] := result["movedCount"] > 0
    if result["movedCount"] > 0 {
        result["message"] := "Moved " result["movedCount"] " window(s) to the main monitor"
        if result["failedCount"] > 0
            result["message"] .= " (" result["failedCount"] " failed)"
    } else if result["failedCount"] > 0 {
        result["message"] := "Could not move " result["failedCount"] " window(s)"
    } else {
        result["message"] := "All app windows are already on the main monitor"
    }
    return result
}

MoveWindowScaledBetweenMonitors(hwnd, sourceMonitor, targetMonitor) {
    ; Hung windows (frozen games, suspended processes) cannot be moved and
    ; block synchronous Win* commands; skip them instead of stalling the script.
    if (!hwnd || !WinExist("ahk_id " hwnd) || IsWindowHung(hwnd))
        return false

    try {
        MonitorGetWorkArea(sourceMonitor, &sLeft, &sTop, &sRight, &sBottom)
        MonitorGetWorkArea(targetMonitor, &tLeft, &tTop, &tRight, &tBottom)
        MonitorGet(targetMonitor, &tFullLeft, &tFullTop, &tFullRight, &tFullBottom)

        minMaxState := WinGetMinMax("ahk_id " hwnd)
        wasMinimized := minMaxState = -1
        if wasMinimized {
            AsyncWinRestore(hwnd)
            Sleep(50)
            minMaxState := WinGetMinMax("ahk_id " hwnd)
        }
        wasMaximized := minMaxState = 1
        wasFullscreen := IsWindowFullscreen(hwnd) && !wasMaximized

        if wasFullscreen {
            AsyncWinRestore(hwnd)
            Sleep(80)
            AsyncWinMove(hwnd, tFullLeft, tFullTop, tFullRight - tFullLeft, tFullBottom - tFullTop)
        } else {
            if wasMaximized {
                AsyncWinRestore(hwnd)
                Sleep(40)
            }

            WinGetPos(&winX, &winY, &winW, &winH, "ahk_id " hwnd)
            sourceWidth := sRight - sLeft
            sourceHeight := sBottom - sTop
            targetWidth := tRight - tLeft
            targetHeight := tBottom - tTop
            newWidth := Min(Round(winW * (targetWidth / sourceWidth)), targetWidth)
            newHeight := Min(Round(winH * (targetHeight / sourceHeight)), targetHeight)
            newX := tLeft + Round((winX - sLeft) * (targetWidth / sourceWidth))
            newY := tTop + Round((winY - sTop) * (targetHeight / sourceHeight))
            newX := Max(tLeft, Min(newX, tRight - newWidth))
            newY := Max(tTop, Min(newY, tBottom - newHeight))
            AsyncWinMove(hwnd, newX, newY, newWidth, newHeight)

            if wasMaximized {
                Sleep(40)
                AsyncWinMaximize(hwnd)
            }
        }

        if wasMinimized {
            Sleep(40)
            AsyncWinMinimize(hwnd)
        }
        return GetWindowMonitor(hwnd) = targetMonitor
    } catch {
        return false
    }
}

; Switch focus to a window on the target monitor
; This function activates a window on the target monitor and moves the mouse cursor
; It finds the topmost visible window on the target monitor (first in Z-order)
; and activates it, then moves the mouse to the center of that window
; If no window exists on the target monitor, moves mouse to monitor center
; Parameters:
;   targetMonitor - Monitor number to switch focus TO (1-based index)
; Returns: Map with success status and optional message
;   - success: true if a window was activated, false if only mouse moved
;   - message: Description of what happened (includes window title if activated)
;   - hwnd: Window handle that was activated (0 if no window activated)
; Used by: Ctrl+2 hotkey for monitor switching
SwitchFocusBetweenMonitors(targetMonitor) {
    result := Map(
        "success", false,
        "message", "",
        "hwnd", 0
    )

    ; Validate monitor exists
    monitorCount := MonitorGetCount()
    if (targetMonitor < 1 || targetMonitor > monitorCount) {
        result["message"] := "Invalid monitor number: " targetMonitor
        return result
    }

    ; Get current active window to exclude it
    activeHwnd := WinGetID("A")

    ; Get target monitor bounds
    MonitorGet(targetMonitor, &tLeft, &tTop, &tRight, &tBottom)

    ; Build list of candidate windows on target monitor
    candidateWindows := []
    for hwnd in WinGetList() {
        try {
            ; Skip the current active window
            if (hwnd = activeHwnd)
                continue

            ; Skip windows without title
            title := WinGetTitle("ahk_id " hwnd)
            if (!title || title = "")
                continue

            ; Get window style to check visibility
            style := WinGetStyle("ahk_id " hwnd)
            if !(style & 0x10000000)  ; WS_VISIBLE
                continue

            ; Get window class
            winClass := WinGetClass("ahk_id " hwnd)

            ; Skip system windows
            if (winClass = "Shell_TrayWnd" || winClass = "Shell_SecondaryTrayWnd" ||
                winClass = "Progman" || winClass = "WorkerW" || winClass = "Windows.UI.Core.CoreWindow" ||
                winClass = "DV2ControlHost" || winClass = "TopLevelWindowForOverflowXamlIsland" ||
                winClass = "Xaml_WindowedPopupClass")
                continue

            ; Get extended style
            exStyle := WinGetExStyle("ahk_id " hwnd)

            ; Skip tool windows (like floating toolbars)
            if (exStyle & 0x80)  ; WS_EX_TOOLWINDOW
                continue

            ; Get window position
            WinGetPos(&wX, &wY, &wW, &wH, "ahk_id " hwnd)

            ; Skip tiny windows (likely tooltips or hidden windows)
            if (wW < 50 || wH < 50)
                continue

            ; Calculate window center
            wCenterX := wX + (wW // 2)
            wCenterY := wY + (wH // 2)

            ; Check if window center is on target monitor
            if (wCenterX >= tLeft && wCenterX < tRight &&
                wCenterY >= tTop && wCenterY < tBottom) {
                candidateWindows.Push(Map("hwnd", hwnd, "title", title))
            }
        } catch {
            ; Skip problematic windows
            continue
        }
    }

    ; If we found windows on target monitor, activate the first one (topmost in Z-order)
    ; WinGetList() returns windows in Z-order, so candidateWindows[1] is the topmost visible window
    if (candidateWindows.Length > 0) {
        targetHwnd := candidateWindows[1]["hwnd"]
        targetTitle := candidateWindows[1]["title"]

        try {
            ; Activate the target window (brings it to foreground)
            WinActivate("ahk_id " targetHwnd)
            Sleep(50)  ; Allow time for activation to complete

            ; Verify activation worked (some windows may resist activation)
            if (WinActive("ahk_id " targetHwnd)) {
                ; Move mouse cursor to the center of the activated window
                ; This provides visual feedback and allows immediate interaction
                try {
                    WinGetPos(&wX, &wY, &wW, &wH, "ahk_id " targetHwnd)
                    cursorX := wX + (wW // 2)  ; Calculate horizontal center
                    cursorY := wY + (wH // 2)  ; Calculate vertical center
                    MouseMove(cursorX, cursorY, 0)  ; 0 = instant move, no animation
                } catch {
                    ; If cursor move fails, don't fail the entire operation
                    ; Window activation is still successful
                }

                result["success"] := true
                result["message"] := "Switched to Monitor " targetMonitor " - " targetTitle
                result["hwnd"] := targetHwnd
                return result
            } else {
                result["message"] := "Failed to activate window on Monitor " targetMonitor
                return result
            }
        } catch as err {
            result["message"] := "Error activating window: " err.Message
            return result
        }
    }

    ; If no window found, move mouse to target monitor center
    centerX := tLeft + ((tRight - tLeft) // 2)
    centerY := tTop + ((tBottom - tTop) // 2)

    try {
        MouseMove(centerX, centerY, 0)
        result["success"] := false  ; Success is false because no window was activated
        result["message"] := "No window on Monitor " targetMonitor " - moved mouse to center"
        return result
    } catch as err {
        result["message"] := "Error moving mouse: " err.Message
        return result
    }
}

; ============================================================================
; PROCESS SUSPENSION FUNCTIONS
; ============================================================================
; These functions use Windows API to suspend/resume processes for resource management

global lastProcessActionError := ""

LogFreezeAction(message) {
    try FileAppend(A_Now " | " message "`n", A_Temp "\\current-ahk-freeze.log")
}

; Suspend a process to stop CPU/GPU work while retaining RAM for reliable resume.
; Parameters:
;   pid - Process ID to suspend
; Returns: true if successful, false otherwise
SuspendProcess(pid) {
    global lastProcessActionError
    lastProcessActionError := ""
    ; Request only the access this operation needs.  PROCESS_ALL_ACCESS is more
    ; likely to be denied and was the cause of avoidable Ctrl+H failures.
    hProcess := DllCall("OpenProcess", "UInt", 0x0800, "Int", 0, "UInt", pid, "Ptr")
    if (!hProcess) {
        lastProcessActionError := "OpenProcess failed for PID " pid " (Win32 " A_LastError ")"
        LogFreezeAction(lastProcessActionError)
        return false
    }

    ; NTSTATUS is signed.  Returning it as UInt made every failure look successful.
    result := DllCall("ntdll\NtSuspendProcess", "Ptr", hProcess, "Int")
    DllCall("CloseHandle", "Ptr", hProcess)
    if (result < 0) {
        lastProcessActionError := "NtSuspendProcess failed for PID " pid " (NTSTATUS " Format("0x{:08X}", result & 0xFFFFFFFF) ")"
        LogFreezeAction(lastProcessActionError)
    } else {
        LogFreezeAction("Suspended PID " pid)
    }
    return (result >= 0)
}

; Resume a suspended process without forcing a fake RAM cap
; Parameters:
;   pid - Process ID to resume
; Returns: true if successful, false otherwise
ResumeProcess(pid) {
    global lastProcessActionError
    lastProcessActionError := ""
    hProcess := DllCall("OpenProcess", "UInt", 0x0800, "Int", 0, "UInt", pid, "Ptr")
    if (!hProcess) {
        lastProcessActionError := "OpenProcess resume failed for PID " pid " (Win32 " A_LastError ")"
        LogFreezeAction(lastProcessActionError)
        return false
    }

    result := DllCall("ntdll\NtResumeProcess", "Ptr", hProcess, "Int")
    DllCall("CloseHandle", "Ptr", hProcess)
    if (result < 0) {
        lastProcessActionError := "NtResumeProcess failed for PID " pid " (NTSTATUS " Format("0x{:08X}", result & 0xFFFFFFFF) ")"
        LogFreezeAction(lastProcessActionError)
    } else {
        LogFreezeAction("Resumed PID " pid)
    }
    return (result >= 0)
}

; Wait until a window reaches or leaves minimized state before changing process state
WaitForMinimizedState(hwnd, shouldBeMinimized, timeoutMs := 350) {
    deadline := A_TickCount + timeoutMs
    Loop {
        if (!hwnd || !DllCall("IsWindow", "Ptr", hwnd, "Int")) {
            return false
        }

        isMinimized := DllCall("IsIconic", "Ptr", hwnd, "Int")
        if (!!isMinimized = !!shouldBeMinimized) {
            return true
        }

        if (A_TickCount >= deadline) {
            return false
        }

        Sleep(10)
    }
}

; ============================================================================
; ASYNC WINDOW OPERATIONS
; ============================================================================
; A window owned by a frozen or hung process (e.g. a game suspended by Ctrl+H)
; cannot process synchronous messages.  AHK's WinMove/WinMaximize/WinRestore
; send those synchronously and BLOCK the entire script - every hotkey, timer
; and the reload/exit message stops until the target responds, which for a
; suspended game is forever.  These helpers deliver the same window-state
; changes asynchronously (PostMessage / ShowWindowAsync / SWP_ASYNCWINDOWPOS),
; so a hung window can never stall the shortcut runtime again.

IsWindowHung(hwnd) {
    return hwnd && DllCall("IsWindow", "Ptr", hwnd, "Int") && DllCall("IsHungAppWindow", "Ptr", hwnd, "Int")
}

AsyncWinRestore(hwnd) {
    if (!hwnd || !DllCall("IsWindow", "Ptr", hwnd, "Int"))
        return
    DllCall("ShowWindowAsync", "Ptr", hwnd, "Int", 9) ; SW_RESTORE
    PostMessage(0x0112, 0xF120, 0, , "ahk_id " hwnd)   ; WM_SYSCOMMAND, SC_RESTORE
}

AsyncWinMinimize(hwnd) {
    if (!hwnd || !DllCall("IsWindow", "Ptr", hwnd, "Int"))
        return
    DllCall("ShowWindowAsync", "Ptr", hwnd, "Int", 6) ; SW_MINIMIZE
    PostMessage(0x0112, 0xF020, 0, , "ahk_id " hwnd)   ; WM_SYSCOMMAND, SC_MINIMIZE
}

AsyncWinMaximize(hwnd) {
    if (!hwnd || !DllCall("IsWindow", "Ptr", hwnd, "Int"))
        return
    DllCall("ShowWindowAsync", "Ptr", hwnd, "Int", 3) ; SW_MAXIMIZE
    PostMessage(0x0112, 0xF030, 0, , "ahk_id " hwnd)   ; WM_SYSCOMMAND, SC_MAXIMIZE
}

AsyncWinMove(hwnd, x, y, w, h) {
    if (!hwnd || !DllCall("IsWindow", "Ptr", hwnd, "Int"))
        return
    ; SWP_NOZORDER | SWP_NOACTIVATE | SWP_ASYNCWINDOWPOS: never blocks on the
    ; target thread, so a frozen window cannot stall this script.
    DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0
        , "Int", x, "Int", y, "Int", w, "Int", h
        , "UInt", 0x0014 | 0x4000)
}

; SetForegroundWindow never blocks on the target thread.
AsyncActivate(hwnd) {
    if (!hwnd || !DllCall("IsWindow", "Ptr", hwnd, "Int"))
        return
    DllCall("SetForegroundWindow", "Ptr", hwnd)
}

; Force minimize a window using multiple methods
; Parameters:
;   hwnd - Window handle to minimize
ForceMinimize(hwnd) {
    ; Start asynchronously, then force-minimize.  ShowWindowAsync and
    ; PostMessage never block, so a frozen/hung window (e.g. a game suspended
    ; by Ctrl+H) cannot stall the script while it minimizes.
    DllCall("ShowWindowAsync", "Ptr", hwnd, "Int", 6) ; SW_MINIMIZE
    DllCall("PostMessage", "Ptr", hwnd, "UInt", 0x0112, "Ptr", 0xF020, "Ptr", 0)
    DllCall("ShowWindowAsync", "Ptr", hwnd, "Int", 11) ; SW_FORCEMINIMIZE
    if IsWindowHung(hwnd)
        return true  ; A hung window cannot confirm state; treat as minimized.
    return WaitForMinimizedState(hwnd, true)
}

ParkGameWindow(hwnd) {
    ; Some launchers and games immediately undo SW_MINIMIZE. Minimize first so
    ; the application receives the normal transition, then hide the same HWND
    ; while it is throttled. Alt+H's restore path explicitly shows it again.
    if !ForceMinimize(hwnd)
        return false
    DllCall("ShowWindowAsync", "Ptr", hwnd, "Int", 0) ; SW_HIDE
    return true
}

ParkGameWindows(pid, preferredHwnd := 0) {
    parked := true
    if (preferredHwnd && DllCall("IsWindow", "Ptr", preferredHwnd, "Int")
        && DllCall("IsWindowVisible", "Ptr", preferredHwnd, "Int")) {
        parked := ParkGameWindow(preferredHwnd) && parked
    }
    for hwnd in WinGetList("ahk_pid " pid) {
        if (hwnd = preferredHwnd
            || !DllCall("IsWindowVisible", "Ptr", hwnd, "Int")) {
            continue
        }
        parked := ParkGameWindow(hwnd) && parked
    }
    return parked
}

; Exclusive-fullscreen games can permanently lose their Direct3D device when
; their process is suspended.  Detect game/fullscreen windows and use a fully
; reversible low-resource mode instead of NtSuspendProcess.
IsLikelyGameWindow(hwnd) {
    try processName := StrLower(WinGetProcessName("ahk_id " hwnd))
    catch {
        processName := ""
    }
    try processPath := StrLower(WinGetProcessPath("ahk_id " hwnd))
    catch {
        processPath := ""
    }
    try windowClass := StrLower(WinGetClass("ahk_id " hwnd))
    catch {
        windowClass := ""
    }

    ; A maximized Terminal exactly matches the fullscreen geometry test, but it
    ; must never enter game launch/recovery enforcement or be forced visible.
    if (processName = "windowsterminal.exe"
        || windowClass = "cascadia_hosting_window_class"
        || windowClass = "cascadia_window_class") {
        return false
    }

    if (IsWindowFullscreen(hwnd)) {
        return true
    }

    for marker in ["\games\", "\steamapps\common\", "\epic games\", "\gog galaxy\games\", "\xboxgames\"] {
        if (InStr(processPath, marker)) {
            return true
        }
    }

    for marker in ["unitywndclass", "unrealwindow", "sdl_app", "iori_application_class"] {
        if (InStr(windowClass, marker)) {
            return true
        }
    }
    return false
}

; Treat a borderless/exclusive window as fullscreen even when a DSR resolution
; is larger than the physical monitor (Yakuza uses 3840x2160 on a 2560x1440 display).
IsWindowFullscreenLike(hwnd, placement := 0) {
    if (!hwnd || !DllCall("IsWindow", "Ptr", hwnd, "Int")) {
        return false
    }
    try {
        if (IsObject(placement) && placement.w > 0 && placement.h > 0) {
            winX := placement.x
            winY := placement.y
            winW := placement.w
            winH := placement.h
        } else {
            WinGetPos(&winX, &winY, &winW, &winH, "ahk_id " hwnd)
        }
        monitorNum := GetWindowMonitor(hwnd)
        MonitorGet(monitorNum, &mLeft, &mTop, &mRight, &mBottom)
        return Abs(winX - mLeft) <= 5 && Abs(winY - mTop) <= 5
            && winW >= (mRight - mLeft) - 10 && winH >= (mBottom - mTop) - 10
    } catch {
        return false
    }
}

EnsureFullscreenAfterRestore(hwnd, placement) {
    ; Exclusive-fullscreen windows intentionally report IsZoomed=false. Treat
    ; stable monitor-filling foreground bounds as fullscreen. Keep pulsing the
    ; non-destructive show/focus sequence while the swap chain settles; some
    ; games minimize again several seconds after appearing successfully restored.
    startedAt := A_TickCount
    deadline := startedAt + 15000
    stableSince := 0
    nextRecoveryPulse := 0

    while (A_TickCount < deadline) {
        minimized := DllCall("IsIconic", "Ptr", hwnd, "Int")
        visible := DllCall("IsWindowVisible", "Ptr", hwnd, "Int")
        foreground := DllCall("GetForegroundWindow", "Ptr") = hwnd
        fullscreenBounds := IsWindowFullscreenLike(hwnd)
        ready := !minimized && visible && foreground && fullscreenBounds

        if (ready) {
            if (!stableSince) {
                stableSince := A_TickCount
            } else if (A_TickCount - startedAt >= 8000 && A_TickCount - stableSince >= 5000) {
                return true
            }
        } else {
            stableSince := 0
        }

        if (A_TickCount >= nextRecoveryPulse) {
            ; Repeat SW_RESTORE/SW_SHOW even while the window looks ready. This
            ; commits activation without repeatedly maximizing an exclusive-
            ; fullscreen swap chain, which can otherwise turn black.
            DllCall("ShowWindowAsync", "Ptr", hwnd, "Int", 9) ; SW_RESTORE
            DllCall("OpenIcon", "Ptr", hwnd)
            DllCall("ShowWindowAsync", "Ptr", hwnd, "Int", 5) ; SW_SHOW
            DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0
                , "Int", 0, "Int", 0, "Int", 0, "Int", 0
                , "UInt", 0x0043 | 0x4000) ; SHOW | NOMOVE | NOSIZE | ASYNCWINDOWPOS
            if (!fullscreenBounds) {
                DllCall("ShowWindowAsync", "Ptr", hwnd, "Int", 3) ; SW_MAXIMIZE
                DllCall("ShowWindowAsync", "Ptr", hwnd, "Int", 3)
            }
            DllCall("BringWindowToTop", "Ptr", hwnd)
            ; SetForegroundWindow is nonblocking from this controller's point
            ; of view. Never call WinActivate here: after working-set trim it
            ; can synchronously wait for a paging game and stall Alt+H.
            DllCall("SetForegroundWindow", "Ptr", hwnd)
            nextRecoveryPulse := A_TickCount + 500
        }
        Sleep(25)
    }

    return stableSince && A_TickCount - stableSince >= 5000
        && !DllCall("IsIconic", "Ptr", hwnd, "Int")
        && DllCall("IsWindowVisible", "Ptr", hwnd, "Int")
        && DllCall("GetForegroundWindow", "Ptr") = hwnd && IsWindowFullscreenLike(hwnd)
}

global fullscreenRecoveryGuards := Map()

CancelFullscreenRecoveryGuard(hwnd) {
    global fullscreenRecoveryGuards
    if (!fullscreenRecoveryGuards.Has(hwnd)) {
        return
    }
    SetTimer(fullscreenRecoveryGuards[hwnd].callback, 0)
    fullscreenRecoveryGuards.Delete(hwnd)
}

StartFullscreenRecoveryGuard(hwnd, placement) {
    global fullscreenRecoveryGuards
    CancelFullscreenRecoveryGuard(hwnd)
    callback := (*) => FullscreenRecoveryGuardTick(hwnd)
    fullscreenRecoveryGuards[hwnd] := {callback: callback, placement: placement
        , started: A_TickCount, stableSince: 0, nextPulse: 0, expires: A_TickCount + 15000}
    SetTimer(callback, 250)
    FullscreenRecoveryGuardTick(hwnd)
}

RestoreFullscreenPulse(hwnd, fullscreenBounds := false) {
    if (!hwnd || !DllCall("IsWindow", "Ptr", hwnd, "Int")) {
        return false
    }
    DllCall("ShowWindowAsync", "Ptr", hwnd, "Int", 9) ; SW_RESTORE
    DllCall("OpenIcon", "Ptr", hwnd)
    DllCall("ShowWindowAsync", "Ptr", hwnd, "Int", 5) ; SW_SHOW
    DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0
        , "Int", 0, "Int", 0, "Int", 0, "Int", 0
        , "UInt", 0x0043 | 0x4000) ; SHOW | NOMOVE | NOSIZE | ASYNCWINDOWPOS
    if (!fullscreenBounds) {
        DllCall("ShowWindowAsync", "Ptr", hwnd, "Int", 3) ; SW_MAXIMIZE
        DllCall("ShowWindowAsync", "Ptr", hwnd, "Int", 3)
    }
    DllCall("BringWindowToTop", "Ptr", hwnd)
    DllCall("SetForegroundWindow", "Ptr", hwnd)
    return true
}

FinalizeFullscreenRecovery(hwnd, succeeded) {
    global frozenProcesses
    Loop frozenProcesses.Length {
        index := frozenProcesses.Length - A_Index + 1
        if (frozenProcesses[index].hwnd != hwnd) {
            continue
        }
        if (succeeded) {
            frozenProcesses.RemoveAt(index)
        } else {
            frozenProcesses[index].state := "restore_pending"
        }
    }
    SaveFrozenProcesses()
}

FullscreenRecoveryGuardTick(hwnd) {
    global fullscreenRecoveryGuards
    ; Deliberately NOT Critical: a hung game window must never be able to
    ; freeze the whole script while this recovery timer runs.
    if (!fullscreenRecoveryGuards.Has(hwnd)) {
        return
    }
    guard := fullscreenRecoveryGuards[hwnd]
    if (!DllCall("IsWindow", "Ptr", hwnd, "Int")) {
        CancelFullscreenRecoveryGuard(hwnd)
        FinalizeFullscreenRecovery(hwnd, false)
        return
    }

    now := A_TickCount
    minimized := DllCall("IsIconic", "Ptr", hwnd, "Int")
    visible := DllCall("IsWindowVisible", "Ptr", hwnd, "Int")
    foreground := DllCall("GetForegroundWindow", "Ptr") = hwnd
    fullscreenBounds := IsWindowFullscreenLike(hwnd)
    ; A global hotkey is allowed to request focus, but Windows can legitimately
    ; deny that request.  Visibility is mandatory: SW_HIDE leaves a window
    ; non-iconic, so checking only IsIconic would falsely finalize recovery
    ; while the game was still parked and invisible.
    ready := !minimized && visible

    if (ready) {
        if (!guard.stableSince) {
            guard.stableSince := now
        }
    } else {
        guard.stableSince := 0
    }

    if (!ready && now >= guard.nextPulse) {
        RestoreFullscreenPulse(hwnd, fullscreenBounds)
        guard.nextPulse := now + 500
    }

    if (now - guard.started >= 5000 && guard.stableSince && now - guard.stableSince >= 4000) {
        CancelFullscreenRecoveryGuard(hwnd)
        FinalizeFullscreenRecovery(hwnd, true)
    } else if (now >= guard.expires) {
        CancelFullscreenRecoveryGuard(hwnd)
        FinalizeFullscreenRecovery(hwnd, false)
    }
}

CaptureProcessResourceState(pid) {
    hProcess := DllCall("OpenProcess", "UInt", 0x1200, "Int", 0, "UInt", pid, "Ptr") ; SET_INFORMATION | QUERY_LIMITED_INFORMATION
    if (!hProcess) {
        return 0
    }
    processMask := 0
    systemMask := 0
    priorityClass := DllCall("GetPriorityClass", "Ptr", hProcess, "UInt")
    affinityOk := DllCall("GetProcessAffinityMask", "Ptr", hProcess, "UPtr*", &processMask, "UPtr*", &systemMask, "Int")
    memoryInfo := Buffer(4, 0)
    memoryPriorityOk := DllCall("kernel32\GetProcessInformation", "Ptr", hProcess
        , "Int", 0, "Ptr", memoryInfo.Ptr, "UInt", memoryInfo.Size, "Int") ; ProcessMemoryPriority
    powerInfo := Buffer(12, 0)
    NumPut("UInt", 1, powerInfo, 0) ; PROCESS_POWER_THROTTLING_CURRENT_VERSION
    powerThrottleOk := DllCall("kernel32\GetProcessInformation", "Ptr", hProcess
        , "Int", 4, "Ptr", powerInfo.Ptr, "UInt", powerInfo.Size, "Int") ; ProcessPowerThrottling
    DllCall("CloseHandle", "Ptr", hProcess)
    return (priorityClass && affinityOk) ? {priorityClass: priorityClass, affinity: processMask
        , created: GetProcessCreationStamp(pid)
        , memoryPriority: memoryPriorityOk ? NumGet(memoryInfo, 0, "UInt") : 0
        , powerVersion: powerThrottleOk ? NumGet(powerInfo, 0, "UInt") : 0
        , powerControlMask: powerThrottleOk ? NumGet(powerInfo, 4, "UInt") : 0
        , powerStateMask: powerThrottleOk ? NumGet(powerInfo, 8, "UInt") : 0} : 0
}

SetProcessMemoryPriority(hProcess, memoryPriority) {
    if (memoryPriority < 1 || memoryPriority > 5) {
        return false
    }
    memoryInfo := Buffer(4, 0)
    NumPut("UInt", memoryPriority, memoryInfo, 0)
    return DllCall("kernel32\SetProcessInformation", "Ptr", hProcess
        , "Int", 0, "Ptr", memoryInfo.Ptr, "UInt", memoryInfo.Size, "Int") ; ProcessMemoryPriority
}

SetProcessPowerThrottling(hProcess, version, controlMask, stateMask) {
    if (!version) {
        return false
    }
    powerInfo := Buffer(12, 0)
    NumPut("UInt", version, powerInfo, 0)
    NumPut("UInt", controlMask, powerInfo, 4)
    NumPut("UInt", stateMask, powerInfo, 8)
    return DllCall("kernel32\SetProcessInformation", "Ptr", hProcess
        , "Int", 4, "Ptr", powerInfo.Ptr, "UInt", powerInfo.Size, "Int") ; ProcessPowerThrottling
}

GameCpuJobName(pid, created := "") {
    if (created = "")
        created := GetProcessCreationStamp(pid)
    if (created = "")
        return ""
    return "Local\MyMainAHK-PausedGame-" pid "-" created
}

ApplyGameCpuLimiter(pid, created := "") {
    global pausedGameCpuJobs, PAUSED_GAME_CPU_RATE
    name := GameCpuJobName(pid, created)
    if (name = "")
        return false

    hJob := 0
    if pausedGameCpuJobs.Has(pid) {
        hJob := pausedGameCpuJobs[pid].handle
        if !hJob
            pausedGameCpuJobs.Delete(pid)
    }
    if !hJob {
        hJob := DllCall("kernel32\CreateJobObjectW", "Ptr", 0, "Str", name, "Ptr")
        if !hJob {
            LogFreezeAction("Game CPU limiter create failed PID " pid " error " A_LastError)
            return false
        }
    }

    cpuInfo := Buffer(8, 0)
    NumPut("UInt", 0x5, cpuInfo, 0) ; ENABLE | HARD_CAP
    NumPut("UInt", PAUSED_GAME_CPU_RATE, cpuInfo, 4)
    if !DllCall("kernel32\SetInformationJobObject", "Ptr", hJob
        , "Int", 15, "Ptr", cpuInfo.Ptr, "UInt", cpuInfo.Size, "Int") {
        LogFreezeAction("Game CPU limiter configure failed PID " pid " error " A_LastError)
        DllCall("CloseHandle", "Ptr", hJob)
        return false
    }

    hProcess := DllCall("OpenProcess", "UInt", 0x1101, "Int", 0, "UInt", pid, "Ptr")
    if !hProcess {
        LogFreezeAction("Game CPU limiter process open failed PID " pid " error " A_LastError)
        DllCall("CloseHandle", "Ptr", hJob)
        return false
    }
    inThisJob := 0
    queryOk := DllCall("kernel32\IsProcessInJob", "Ptr", hProcess, "Ptr", hJob, "Int*", &inThisJob, "Int")
    assignOk := queryOk && inThisJob
    if (queryOk && !inThisJob)
        assignOk := DllCall("kernel32\AssignProcessToJobObject", "Ptr", hJob, "Ptr", hProcess, "Int")
    DllCall("CloseHandle", "Ptr", hProcess)
    if !assignOk {
        LogFreezeAction("Game CPU limiter assignment failed PID " pid " error " A_LastError)
        DllCall("CloseHandle", "Ptr", hJob)
        return false
    }
    pausedGameCpuJobs[pid] := {handle: hJob, name: name, created: created}
    LogFreezeAction("Game CPU hard cap PID " pid " rate " PAUSED_GAME_CPU_RATE "/10000")
    return true
}

ReleaseGameCpuLimiter(pid, created := "") {
    global pausedGameCpuJobs, pausedGameTrimScheduled
    hJob := 0
    closeAfter := false
    if pausedGameCpuJobs.Has(pid) {
        hJob := pausedGameCpuJobs[pid].handle
    } else {
        name := GameCpuJobName(pid, created)
        if (name = "")
            return true
        hJob := DllCall("kernel32\OpenJobObjectW", "UInt", 0x10, "Int", 0, "Str", name, "Ptr") ; SET_ATTRIBUTES
        closeAfter := true
        if !hJob
            return true ; no limiter exists for this legacy record
    }

    cpuInfo := Buffer(8, 0)
    NumPut("UInt", 0, cpuInfo, 0) ; disable CPU rate control
    NumPut("UInt", 10000, cpuInfo, 4) ; nonzero union value for API validation
    ok := DllCall("kernel32\SetInformationJobObject", "Ptr", hJob
        , "Int", 15, "Ptr", cpuInfo.Ptr, "UInt", cpuInfo.Size, "Int")
    if (ok && pausedGameCpuJobs.Has(pid))
        pausedGameCpuJobs.Delete(pid)
    if (closeAfter || ok)
        DllCall("CloseHandle", "Ptr", hJob)
    trimKey := pid "|" created
    if pausedGameTrimScheduled.Has(trimKey)
        pausedGameTrimScheduled.Delete(trimKey)
    if !ok
        LogFreezeAction("Game CPU limiter release failed PID " pid " error " A_LastError)
    return ok
}

ScheduleGameWorkingSetTrim(pid, created := "") {
    global pausedGameTrimScheduled, PAUSED_GAME_TRIM_DELAY_MS
    if (created = "")
        created := GetProcessCreationStamp(pid)
    if (created = "")
        return false

    trimKey := pid "|" created
    if pausedGameTrimScheduled.Has(trimKey)
        return true

    helper := A_ScriptDir "\\ctrl-h-trim-helper.ahk"
    if !FileExist(helper)
        return false

    try {
        Run('"' A_AhkPath '" "' helper '" "' pid '" "' created '" "' FrozenStateFile() '" "throttle" "' PAUSED_GAME_TRIM_DELAY_MS '"', , "Hide")
        pausedGameTrimScheduled[trimKey] := A_TickCount
        LogFreezeAction("Game working-set trim scheduled PID " pid " delay " PAUSED_GAME_TRIM_DELAY_MS "ms")
        return true
    } catch as err {
        LogFreezeAction("Game working-set trim schedule failed PID " pid " error " err.Message)
        return false
    }
}

ApplyGameLowResourceMode(pid, resourceState, created := "") {
    if (!IsObject(resourceState)) {
        return false
    }
    hProcess := DllCall("OpenProcess", "UInt", 0x1200, "Int", 0, "UInt", pid, "Ptr")
    if (!hProcess) {
        return false
    }

    ; Minimize plus a 1% job CPU hard cap, IDLE priority, execution-speed
    ; throttling, and VERY_LOW memory priority. The separate helper trims
    ; reclaimable pages after a short pause-only delay; it never suspends the
    ; process, and its state/creation checks abort it before an Alt+H restore.
    priorityOk := DllCall("SetPriorityClass", "Ptr", hProcess, "UInt", 0x40, "Int") ; IDLE_PRIORITY_CLASS
    memoryPriorityOk := true
    if (resourceState.HasProp("memoryPriority") && resourceState.memoryPriority) {
        memoryPriorityOk := SetProcessMemoryPriority(hProcess, 1) ; MEMORY_PRIORITY_VERY_LOW
    }
    powerThrottleOk := true
    if (resourceState.HasProp("powerVersion") && resourceState.powerVersion) {
        powerThrottleOk := SetProcessPowerThrottling(hProcess, resourceState.powerVersion
            , resourceState.powerControlMask | 0x1, resourceState.powerStateMask | 0x1)
    }
    DllCall("CloseHandle", "Ptr", hProcess)
    baseApplied := priorityOk && memoryPriorityOk && powerThrottleOk
    cpuLimitOk := false
    if baseApplied {
        limiterCreated := created != "" ? created : (resourceState.HasProp("created") ? resourceState.created : "")
        cpuLimitOk := ApplyGameCpuLimiter(pid, limiterCreated)
    }
    trimScheduled := false
    if (baseApplied && cpuLimitOk)
        trimScheduled := ScheduleGameWorkingSetTrim(pid, limiterCreated)
    LogFreezeAction("Repeat-safe low-resource mode PID " pid " priority IDLE memory "
        (memoryPriorityOk ? "VERY_LOW" : "unchanged") " power "
        (powerThrottleOk ? "THROTTLED" : "unchanged") " cpu "
        (cpuLimitOk ? "HARD_CAP" : "unchanged") " working-set "
        (trimScheduled ? "TRIM_SCHEDULED" : "not-scheduled"))
    applied := baseApplied && cpuLimitOk
    if !applied {
        if cpuLimitOk
            ReleaseGameCpuLimiter(pid, limiterCreated)
        ; Never strand a game with only part of its original resource policy.
        RestoreProcessResources(pid, resourceState)
    }
    return applied
}

ApplySuspendedLowResourceMode(pid, resourceState, trimWorkingSet := true) {
    ; Ordinary applications can be stopped completely. Lower their memory
    ; priority before suspension, then discard only reclaimable working-set
    ; pages so Windows may use that physical RAM elsewhere. The process's
    ; private state remains intact and pages are faulted back normally on resume.
    priorityOk := true
    memoryPriorityOk := true
    powerThrottleOk := true
    hProcess := DllCall("OpenProcess", "UInt", 0x0200, "Int", 0, "UInt", pid, "Ptr") ; SET_INFORMATION
    if (hProcess) {
        priorityOk := DllCall("SetPriorityClass", "Ptr", hProcess, "UInt", 0x40, "Int") ; IDLE_PRIORITY_CLASS
        if (IsObject(resourceState) && resourceState.HasProp("memoryPriority")
            && resourceState.memoryPriority) {
            memoryPriorityOk := SetProcessMemoryPriority(hProcess, 1) ; MEMORY_PRIORITY_VERY_LOW
        }
        if (IsObject(resourceState) && resourceState.HasProp("powerVersion")
            && resourceState.powerVersion) {
            powerThrottleOk := SetProcessPowerThrottling(hProcess, resourceState.powerVersion
                , resourceState.powerControlMask | 0x1, resourceState.powerStateMask | 0x1)
        }
        DllCall("CloseHandle", "Ptr", hProcess)
    } else {
        priorityOk := false
        memoryPriorityOk := false
        powerThrottleOk := false
    }

    if (!SuspendProcess(pid)) {
        ; Roll back every setting changed before the failed suspension.
        hRollback := DllCall("OpenProcess", "UInt", 0x0200, "Int", 0, "UInt", pid, "Ptr")
        if (hRollback) {
            if (IsObject(resourceState) && resourceState.HasProp("priorityClass")
                && resourceState.priorityClass) {
                DllCall("SetPriorityClass", "Ptr", hRollback, "UInt", resourceState.priorityClass, "Int")
            }
            if (IsObject(resourceState) && resourceState.HasProp("memoryPriority")
                && resourceState.memoryPriority) {
                SetProcessMemoryPriority(hRollback, resourceState.memoryPriority)
            }
            if (IsObject(resourceState) && resourceState.HasProp("powerVersion")
                && resourceState.powerVersion) {
                SetProcessPowerThrottling(hRollback, resourceState.powerVersion
                    , resourceState.powerControlMask, resourceState.powerStateMask)
            }
            DllCall("CloseHandle", "Ptr", hRollback)
        }
        return false
    }

    trimOk := !trimWorkingSet
    if (trimWorkingSet) {
        hTrim := DllCall("OpenProcess", "UInt", 0x0500, "Int", 0, "UInt", pid, "Ptr") ; SET_QUOTA | QUERY_INFORMATION
        if (hTrim) {
            trimOk := DllCall("psapi\EmptyWorkingSet", "Ptr", hTrim, "Int")
            DllCall("CloseHandle", "Ptr", hTrim)
        }
    } else {
        created := GetProcessCreationStamp(pid)
        helper := A_ScriptDir "\ctrl-h-trim-helper.ahk"
        if (created != "" && FileExist(helper)) {
            try Run('"' A_AhkPath '" "' helper '" "' pid '" "' created '" "' FrozenStateFile() '"', , "Hide")
        }
    }
    LogFreezeAction("Suspended low-resource mode PID " pid " priority "
        (priorityOk ? "IDLE" : "unchanged") " memory "
        (memoryPriorityOk ? "VERY_LOW" : "unchanged") " power "
        (powerThrottleOk ? "THROTTLED" : "unchanged") " working set "
        (trimWorkingSet ? (trimOk ? "TRIMMED" : "left to Windows") : "managed asynchronously by Windows"))
    return true
}

RestoreSuspendedProcess(pid, resourceState) {
    ; Restore every resource policy while the process is still stopped. The
    ; first resumed instruction therefore runs at the exact pre-Ctrl+H policy.
    hProcess := DllCall("OpenProcess", "UInt", 0x0200, "Int", 0, "UInt", pid, "Ptr")
    if (!hProcess) {
        return false
    }
    priorityOk := true
    memoryPriorityOk := true
    powerThrottleOk := true
    if (IsObject(resourceState) && resourceState.HasProp("priorityClass")
        && resourceState.priorityClass) {
        priorityOk := DllCall("SetPriorityClass", "Ptr", hProcess, "UInt", resourceState.priorityClass, "Int")
    }
    if (IsObject(resourceState) && resourceState.HasProp("memoryPriority")
        && resourceState.memoryPriority) {
        memoryPriorityOk := SetProcessMemoryPriority(hProcess, resourceState.memoryPriority)
    }
    if (IsObject(resourceState) && resourceState.HasProp("powerVersion")
        && resourceState.powerVersion) {
        powerThrottleOk := SetProcessPowerThrottling(hProcess, resourceState.powerVersion
            , resourceState.powerControlMask, resourceState.powerStateMask)
    }
    DllCall("CloseHandle", "Ptr", hProcess)
    if (!priorityOk || !memoryPriorityOk || !powerThrottleOk) {
        return false
    }
    return ResumeProcess(pid)
}

MaintainPausedProcessState() {
    global frozenProcesses
    ; Deliberately NOT Critical: this 250 ms timer must never block hotkeys
    ; (a blocking call here would stall every shortcut).  The debounce guards
    ; in the freeze/resume hotkeys already keep state transitions atomic.
    for _, processInfo in frozenProcesses {
        state := processInfo.HasProp("state") ? processInfo.state : "paused"
        if (state != "paused" || !ProcessExist(processInfo.pid)) {
            continue
        }
        if (processInfo.HasProp("created") && processInfo.created != ""
            && processInfo.created != GetProcessCreationStamp(processInfo.pid)) {
            continue
        }
        mode := processInfo.HasProp("mode") ? processInfo.mode : "suspend"
        if (mode = "throttle") {
            ParkGameWindows(processInfo.pid, processInfo.HasProp("hwnd") ? processInfo.hwnd : 0)
        } else if (processInfo.HasProp("hwnd") && DllCall("IsWindow", "Ptr", processInfo.hwnd, "Int")
            && !DllCall("IsIconic", "Ptr", processInfo.hwnd, "Int")) {
            ForceMinimize(processInfo.hwnd)
        }
        if (mode != "throttle" && mode != "game_suspend") {
            continue
        }
        if (mode = "throttle" && !ApplyGameCpuLimiter(processInfo.pid, processInfo.created)) {
            LogFreezeAction("Game CPU limiter unavailable while paused PID " processInfo.pid)
            continue
        }
        hProcess := DllCall("OpenProcess", "UInt", 0x0200, "Int", 0, "UInt", processInfo.pid, "Ptr")
        if (hProcess) {
            DllCall("SetPriorityClass", "Ptr", hProcess, "UInt", 0x40, "Int") ; IDLE_PRIORITY_CLASS
            if (processInfo.HasProp("memoryPriority") && processInfo.memoryPriority) {
                SetProcessMemoryPriority(hProcess, 1) ; MEMORY_PRIORITY_VERY_LOW
            }
            if (processInfo.HasProp("powerVersion") && processInfo.powerVersion) {
                SetProcessPowerThrottling(hProcess, processInfo.powerVersion
                    , processInfo.powerControlMask | 0x1, processInfo.powerStateMask | 0x1)
            }
            DllCall("CloseHandle", "Ptr", hProcess)
        }
    }
}

RestoreProcessResources(pid, resourceState) {
    if (!IsObject(resourceState)) {
        return false
    }
    limiterCreated := resourceState.HasProp("created") ? resourceState.created : ""
    if !ReleaseGameCpuLimiter(pid, limiterCreated)
        return false
    hProcess := DllCall("OpenProcess", "UInt", 0x1200, "Int", 0, "UInt", pid, "Ptr")
    if (!hProcess) {
        return false
    }

    ; Restore only settings this controller changed, using the exact values
    ; captured before Ctrl+H.
    priorityOk := DllCall("SetPriorityClass", "Ptr", hProcess, "UInt", resourceState.priorityClass, "Int")
    memoryPriorityOk := true
    if (resourceState.HasProp("memoryPriority") && resourceState.memoryPriority) {
        memoryPriorityOk := SetProcessMemoryPriority(hProcess, resourceState.memoryPriority)
    }
    powerThrottleOk := true
    if (resourceState.HasProp("powerVersion") && resourceState.powerVersion) {
        powerThrottleOk := SetProcessPowerThrottling(hProcess, resourceState.powerVersion
            , resourceState.powerControlMask, resourceState.powerStateMask)
    }
    DllCall("CloseHandle", "Ptr", hProcess)
    LogFreezeAction("Restored game resources PID " pid " memory "
        (memoryPriorityOk ? "restored" : "unchanged") " power "
        (powerThrottleOk ? "restored" : "unchanged"))
    return priorityOk && memoryPriorityOk && powerThrottleOk
}

CaptureWindowPlacement(hwnd) {
    placement := {hwnd: hwnd, minMax: 0, x: 0, y: 0, w: 0, h: 0, coordinateSpace: "legacy"}
    if (!hwnd || !DllCall("IsWindow", "Ptr", hwnd, "Int")) {
        return placement
    }

    try {
        placement.minMax := WinGetMinMax("ahk_id " hwnd)
        if ReadWindowRectPmV2(hwnd, &rect) {
            placement.x := rect.x
            placement.y := rect.y
            placement.w := rect.w
            placement.h := rect.h
            placement.coordinateSpace := "pmv2-physical"
        } else {
            WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
            placement.x := x
            placement.y := y
            placement.w := w
            placement.h := h
        }
    }

    return placement
}

ReadWindowRectPmV2(hwnd, &rect) {
    previousContext := DllCall("User32\SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
    if !previousContext
        return false

    rectBuffer := Buffer(16, 0)
    readOk := false
    restoreOk := false
    try {
        currentContext := DllCall("User32\GetThreadDpiAwarenessContext", "Ptr")
        if !DllCall("User32\AreDpiAwarenessContextsEqual", "Ptr", currentContext, "Ptr", -4, "Int")
            return false
        readOk := DllCall("User32\GetWindowRect", "Ptr", hwnd, "Ptr", rectBuffer.Ptr, "Int")
        if readOk {
            rect := {x: NumGet(rectBuffer, 0, "Int"), y: NumGet(rectBuffer, 4, "Int")
                , w: NumGet(rectBuffer, 8, "Int") - NumGet(rectBuffer, 0, "Int")
                , h: NumGet(rectBuffer, 12, "Int") - NumGet(rectBuffer, 4, "Int")}
        }
    } finally {
        restoreOk := DllCall("User32\SetThreadDpiAwarenessContext", "Ptr", previousContext, "Ptr")
        if !restoreOk
            LogFreezeAction("Could not restore thread DPI context after window-rectangle capture")
    }
    return readOk && restoreOk
}

SetWindowRectPmV2(hwnd, x, y, w, h) {
    previousContext := DllCall("User32\SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
    if !previousContext
        return false

    setOk := false
    restoreOk := false
    try {
        currentContext := DllCall("User32\GetThreadDpiAwarenessContext", "Ptr")
        if !DllCall("User32\AreDpiAwarenessContextsEqual", "Ptr", currentContext, "Ptr", -4, "Int")
            return false
        setOk := DllCall("User32\SetWindowPos", "Ptr", hwnd, "Ptr", 0
            , "Int", x, "Int", y, "Int", w, "Int", h
            , "UInt", 0x0040 | 0x4000, "Int") ; SWP_SHOWWINDOW | SWP_ASYNCWINDOWPOS
    } finally {
        restoreOk := DllCall("User32\SetThreadDpiAwarenessContext", "Ptr", previousContext, "Ptr")
        if !restoreOk
            LogFreezeAction("Could not restore thread DPI context after window-rectangle restore")
    }
    return setOk && restoreOk
}

RestoreProcessWindows(pid, preferredHwnd := 0, placement := 0, restoreGeometry := true) {
    restored := false

    if (preferredHwnd && DllCall("IsWindow", "Ptr", preferredHwnd, "Int")) {
        restored := RestoreOneWindow(preferredHwnd, placement, restoreGeometry) || restored
    }

    for hwnd in WinGetList("ahk_pid " pid) {
        if (hwnd = preferredHwnd) {
            continue
        }
        restored := RestoreOneWindow(hwnd, 0) || restored
    }

    return restored
}

RestoreOneWindow(hwnd, placement := 0, restoreGeometry := true) {
    if (!hwnd || !DllCall("IsWindow", "Ptr", hwnd, "Int")) {
        return false
    }

    try {
        ; SW_RESTORE alone can return success while a fullscreen game remains
        ; iconic.  OpenIcon + SW_SHOW + SWP_SHOWWINDOW is the proven recovery
        ; sequence for that state.
        DllCall("ShowWindowAsync", "Ptr", hwnd, "Int", 9) ; SW_RESTORE
        DllCall("OpenIcon", "Ptr", hwnd)
        DllCall("ShowWindowAsync", "Ptr", hwnd, "Int", 5) ; SW_SHOW
        DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x0043 | 0x4000) ; SHOW | NOMOVE | NOSIZE | ASYNCWINDOWPOS

        if (restoreGeometry && IsObject(placement) && placement.w > 0 && placement.h > 0) {
            ; Restore the exact pre-freeze rectangle.  WinMaximize can leave a
            ; borderless game iconic or change its exclusive-fullscreen mode.
            coordinateSpace := placement.HasProp("coordinateSpace") ? placement.coordinateSpace : "legacy"
            if (coordinateSpace = "pmv2-physical") {
                if !SetWindowRectPmV2(hwnd, placement.x, placement.y, placement.w, placement.h)
                    return false
            } else {
                DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0
                    , "Int", placement.x, "Int", placement.y
                    , "Int", placement.w, "Int", placement.h
                    , "UInt", 0x0040 | 0x4000) ; SWP_SHOWWINDOW | ASYNCWINDOWPOS
            }
        }

        DllCall("BringWindowToTop", "Ptr", hwnd)
        ; Do not synchronously activate a process whose pages are returning.
        DllCall("SetForegroundWindow", "Ptr", hwnd)

        ; Every operation above is asynchronous. Returning immediately keeps
        ; Alt+H responsive while a trimmed game faults its working set back in;
        ; the fullscreen recovery guard performs readiness checks in a timer.
        return true
    } catch {
        return false
    }
}

; Force a window to cover its entire current monitor, including the taskbar area.
ForceBorderlessFullscreen(hwnd) {
    if (!hwnd || !WinExist("ahk_id " hwnd)) {
        return false
    }

    monitorNum := GetWindowMonitor(hwnd)
    MonitorGet(monitorNum, &mLeft, &mTop, &mRight, &mBottom)
    fullW := mRight - mLeft
    fullH := mBottom - mTop

    try {
        WinRestore("ahk_id " hwnd)
    }

    ; Remove standard resizable-window chrome so exact monitor bounds are not offset by borders.
    try {
        WinSetStyle("-0xC40000", "ahk_id " hwnd)      ; WS_CAPTION | WS_THICKFRAME
        WinSetExStyle("-0x20201", "ahk_id " hwnd)     ; dialog/client/static edge styles
    }

    ; HWND_TOPMOST plus FRAMECHANGED makes the new borderless size cover the taskbar immediately.
    DllCall("SetWindowPos"
        , "Ptr", hwnd
        , "Ptr", -1
        , "Int", mLeft
        , "Int", mTop
        , "Int", fullW
        , "Int", fullH
        , "UInt", 0x0060)  ; SWP_FRAMECHANGED | SWP_SHOWWINDOW

    try {
        WinActivate("ahk_id " hwnd)
    }

    return IsWindowFullscreen(hwnd)
}

; ============================================================================
; GLOBAL STATE VARIABLES
; ============================================================================
; These global variables maintain state across hotkey invocations

; Track last execution time for hotkeys to prevent rapid-fire issues
; This prevents race conditions and window management glitches from rapid keypresses
global lastCtrl2Time := 0           ; Last time Ctrl+2 was executed (in milliseconds)
global ctrl2Throttle := 100         ; Minimum milliseconds between Ctrl+2 executions (100ms = 0.1 second)

; Track consecutive Ctrl taps for quad-tap fullscreen
global ctrlTapCount := 0
global ctrlLastTapTime := 0
global ctrlTapWindow := 1200        ; 1.2 seconds window for 4 taps

; Track consecutive Alt taps for quad-tap OpenWhisper / 5-tap terminal profile sequence
global altTapCount := 0
global altLastTapTime := 0
global altTapWindow := 1200         ; 1.2 seconds window for 4/5 taps
global altOpenWhisperTimer := 0

; Track consecutive CapsLock taps for 8-tap terminal profile sequence
global capsLockTapCount := 0
global capsLockLastTapTime := 0
global capsLockTapWindow := 3000    ; 3 seconds window for 8 taps

; Track consecutive F10 taps for emergency preserve-state suspend
global f10TapCount := 0
global f10LastTapTime := 0
global f10TapWindow := 3000         ; 3 seconds window for 6 taps

; Track consecutive F6 taps for active-app mute toggle
global f6TapCount := 0
global f6LastTapTime := 0
global f6TapWindow := 3000          ; 3 seconds window for 6 taps

; Preserve the last nonzero default microphone level for mmmute/uunmute.
global microphonePreviousLevel := ""
global microphonePreviousLevelFile := A_Temp "\mic-prev-level.txt"

; Track Space gesture for active-window small mode
global spaceTapCount := 0
global spaceLastTapTime := 0
global spaceTapWindow := 1500       ; 5 Space taps must complete within 1.5 seconds
global spaceDownAt := 0
global spaceLongPressArmed := false
global spaceLongPressMs := 5000     ; Hold Space for 5 seconds to trigger small mode

; Track frozen processes for Ctrl+h / Alt+h functionality
global frozenProcesses := []        ; Array of frozen process info: {pid, hwnd, title}
global lastPauseHotkeyTick := 0
global lastResumeHotkeyTick := 0
global gameControlPipeHandle := 0
global gameControlPipeConnected := false
global gameControlPipeReplySent := false
global gameControlPipeReplyTick := 0
global gameControlPipeConnectedTick := 0
global gameControlPipeName := ""
global gameControlPipeLastStartTick := 0
global gameControlRequests := Map()
global gameControlRequestOrder := []
global pausedGameCpuJobs := Map()
global PAUSED_GAME_CPU_RATE := 100 ; 1% of total processor cycles
global pausedGameTrimScheduled := Map()
global PAUSED_GAME_TRIM_DELAY_MS := 2000 ; let the normal minimize settle first
LoadFrozenProcesses()
StartGameControlPipe()
SetTimer(PollGameControlPipe, 40)
SetTimer(MaintainPausedProcessState, 250)
global kkkkTapCount := 0
global kkkkLastTapTime := 0
global kkkkTapWindow := 1500        ; 4 distinct k presses must complete under 1.5 seconds

; ============================================================================
; HOTKEYS - Keyboard shortcuts
; ============================================================================

; Private pass-through probe used to verify that Windows has not silently
; removed this process's low-level keyboard hook. F24 is not assigned to any
; user shortcut and the tilde preserves it for any future consumer.
~*F24::
{
    try FileAppend(A_TickCount "|" A_Now "`n", A_Temp "\current-ahk-hook-probe.log")
}

; Win+W - Launch Wand
#w::
{
    ; Any Win chord can poison the OpenWhispr Ctrl+Win dictation listener (see
    ; SttGuardTick); freeze it before Wand starts so keys injected during the
    ; launch cannot toggle dictation by mistake.
    SttGuardSuspendForWinChord()
    ; Wand is single-instance and a second launch can toggle its existing
    ; Electron window hidden. Raise a visible instance above every other app,
    ; including fullscreen games, instead of launching a second copy; only
    ; invoke the launcher when no usable window currently exists.
    for hwnd in WinGetList("ahk_exe Wand.exe") {
        try {
            if (WinGetTitle("ahk_id " hwnd) = "")
                continue
            WinShow("ahk_id " hwnd)
            ForceForegroundApplicationWindow(hwnd)
            return
        }
    }
    Run('"C:\Users\Admin\AppData\Local\Wand\Wand.exe"')
}

FindTvMonitor() {
    monitorCount := MonitorGetCount()
    if (monitorCount < 1)
        return 0

    Loop monitorCount {
        if IsTvMonitor(A_Index)
            return A_Index
    }

    return 0
}

MoveActiveWindowToMonitorMaximized(targetMonitor, label := "") {
    try {
        hwnd := WinGetID("A")
    } catch as err {
        ToolTip("Error: Could not get active window")
        SetTimer(() => ToolTip(), -2000)
        return false
    }

    if (!hwnd) {
        ToolTip("No active window to move")
        SetTimer(() => ToolTip(), -1500)
        return false
    }

    try {
        monitorCount := MonitorGetCount()
    } catch as err {
        ToolTip("Error: Could not detect monitors - " err.Message)
        SetTimer(() => ToolTip(), -2000)
        return false
    }

    if (targetMonitor < 1 || targetMonitor > monitorCount) {
        ToolTip("Target monitor " targetMonitor " not available")
        SetTimer(() => ToolTip(), -2000)
        return false
    }

    if (IsWindowHung(hwnd)) {
        ToolTip("Window is not responding and cannot be moved")
        SetTimer(() => ToolTip(), -2000)
        return false
    }

    try {
        MonitorGet(targetMonitor, &tLeft, &tTop, &tRight, &tBottom)
        AsyncWinRestore(hwnd)
        Sleep(100)
        WinGetPos(, , &curW, &curH, "ahk_id " hwnd)
        AsyncWinMove(hwnd, tLeft + 10, tTop + 10, curW, curH)
        Sleep(50)
        AsyncWinMaximize(hwnd)
        suffix := (label != "") ? label : ("Monitor " targetMonitor)
        ToolTip("Moved maximized to " suffix)
        SetTimer(() => ToolTip(), -1500)
        return true
    } catch as err {
        ToolTip("Error moving window: " err.Message)
        SetTimer(() => ToolTip(), -2000)
        return false
    }
}

ForceActiveWindowSmall() {
    try {
        hwnd := WinGetID("A")
    } catch as err {
        ToolTip("Error: Could not get active window")
        SetTimer(() => ToolTip(), -2000)
        return false
    }

    if (!hwnd) {
        ToolTip("No active window")
        SetTimer(() => ToolTip(), -1500)
        return false
    }

    try {
        currentMonitor := GetWindowMonitor(hwnd)
        MonitorGetWorkArea(currentMonitor, &mLeft, &mTop, &mRight, &mBottom)
    } catch {
        MonitorGetWorkArea(, &mLeft, &mTop, &mRight, &mBottom)
    }

    ; Large-restored mode: much bigger than the old 900x600 small window,
    ; but still not fullscreen and still contained inside the monitor work area.
    workW := mRight - mLeft
    workH := mBottom - mTop
    smallW := Floor(workW * 0.95)
    smallH := Floor(workH * 0.95)
    centerX := mLeft + ((mRight - mLeft - smallW) // 2)
    centerY := mTop + ((mBottom - mTop - smallH) // 2)

    if (IsWindowHung(hwnd)) {
        ToolTip("Window is not responding and cannot be resized")
        SetTimer(() => ToolTip(), -2000)
        return false
    }

    try {
        AsyncWinRestore(hwnd)
        Sleep(50)
        AsyncWinMove(hwnd, centerX, centerY, smallW, smallH)
        ToolTip("Window set to large restored (" smallW "x" smallH ")")
        SetTimer(() => ToolTip(), -1500)
        return true
    } catch as err {
        ToolTip("Error: " err.Message)
        SetTimer(() => ToolTip(), -2000)
        return false
    }
}

CheckSpaceLongPress() {
    global spaceTapCount, spaceDownAt, spaceLongPressArmed
    if (spaceLongPressArmed && spaceDownAt && GetKeyState("Space", "P")) {
        spaceLongPressArmed := false
        spaceTapCount := 0
        ForceActiveWindowSmall()
    }
}

; Space x5 or Space hold for 5 seconds - Force current window into a small restored window
~*Space::
{
    global spaceTapCount, spaceLastTapTime, spaceTapWindow, spaceDownAt, spaceLongPressArmed, spaceLongPressMs

    if (spaceDownAt != 0)
        return

    spaceDownAt := A_TickCount
    spaceLongPressArmed := true
    SetTimer(CheckSpaceLongPress, -spaceLongPressMs)

    if (A_TickCount - spaceLastTapTime <= spaceTapWindow)
        spaceTapCount += 1
    else
        spaceTapCount := 1
    spaceLastTapTime := A_TickCount

    if (spaceTapCount >= 5) {
        spaceTapCount := 0
        spaceLongPressArmed := false
        ForceActiveWindowSmall()
    }
}

~*Space Up::
{
    global spaceDownAt, spaceLongPressArmed
    spaceDownAt := 0
    spaceLongPressArmed := false
}

; Ctrl+1 - Move active window to the other monitor and make it fullscreen
; This hotkey moves the currently active window to the opposite monitor
; and always makes it fullscreen (covering entire screen including taskbar)
; Uses the connected physical-monitor pair and ignores persistent virtual displays
^1::
{
    try {
        hwnd := WinGetID("A")
    } catch as err {
        ToolTip("Error: Could not get active window")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    if (!hwnd) {
        ToolTip("No active window to move")
        SetTimer(() => ToolTip(), -1500)
        return
    }

    ; Determine current monitor
    try {
        currentMonitor := GetWindowMonitor(hwnd)
    } catch as err {
        ToolTip("Error detecting current monitor: " err.Message)
        SetTimer(() => ToolTip(), -2000)
        return
    }

    targetMonitor := GetOtherPhysicalMonitor(currentMonitor)
    if !targetMonitor {
        ToolTip("Only 1 connected physical monitor detected")
        SetTimer(() => ToolTip(), -1800)
        return
    }

    ; Get target monitor full bounds (not work area - we want fullscreen)
    try {
        MonitorGet(targetMonitor, &tLeft, &tTop, &tRight, &tBottom)
    } catch as err {
        ToolTip("Error getting monitor bounds: " err.Message)
        SetTimer(() => ToolTip(), -2000)
        return
    }

    ; A hung window (e.g. a game frozen by Ctrl+H) cannot be moved and would
    ; block the synchronous Win* calls, so abort cleanly instead.
    if (IsWindowHung(hwnd)) {
        ToolTip("Window is not responding and cannot be moved")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    ; Restore window first (if maximized or minimized)
    try {
        AsyncWinRestore(hwnd)
        Sleep(100)  ; Allow time for restore to complete
    } catch as err {
        ToolTip("Error restoring window: " err.Message)
        SetTimer(() => ToolTip(), -2000)
        return
    }

    ; Move to target monitor then maximize (true maximized state on target monitor)
    try {
        WinGetPos(, , &curW, &curH, "ahk_id " hwnd)
        AsyncWinMove(hwnd, tLeft + 10, tTop + 10, curW, curH)  ; Nudge onto target monitor
        Sleep(50)
        AsyncWinMaximize(hwnd)
        ToolTip("Moved maximized to Monitor " targetMonitor)
        SetTimer(() => ToolTip(), -1500)
    } catch as err {
        ToolTip("Error moving window: " err.Message)
        SetTimer(() => ToolTip(), -2000)
        return
    }
}

; Ctrl+` - Swap ALL windows between monitors (everything on main â†’ 2nd and 2nd â†’ main)
; Preserves maximized state and scales proportional positions for non-maximized windows
; SC029 = scan code for backtick/grave accent key â€” needed because ` is AHK v2 escape char
^SC029::
{
    pair := GetPhysicalMonitorPair()
    primaryMon := pair["primary"]
    secondaryMon := pair["secondary"]
    if !primaryMon || !secondaryMon {
        ToolTip("Only 1 connected physical monitor detected")
        SetTimer(() => ToolTip(), -1800)
        return
    }

    ; Snapshot all windows grouped by monitor BEFORE moving anything
    windowsByMon := EnumerateWindowsByMonitor()
    primaryWindows   := windowsByMon[primaryMon]
    secondaryWindows := windowsByMon[secondaryMon]

    totalMoved := 0
    totalFailed := 0

    ; Move all primary windows to secondary.
    for hwnd in primaryWindows {
        if MoveWindowScaledBetweenMonitors(hwnd, primaryMon, secondaryMon)
            totalMoved++
        else
            totalFailed++
    }

    ; Move all secondary windows to primary.
    for hwnd in secondaryWindows {
        if MoveWindowScaledBetweenMonitors(hwnd, secondaryMon, primaryMon)
            totalMoved++
        else
            totalFailed++
    }

    message := "Swapped " totalMoved " window(s) between connected physical monitors"
    if totalFailed
        message .= " (" totalFailed " failed)"
    ToolTip(message)
    SetTimer(() => ToolTip(), -2000)
}

; Ctrl+3 - Move active window to the TV / third monitor and maximize it
^3::
{
    targetMonitor := FindTvMonitor()
    if (!targetMonitor) {
        ToolTip("TV / third monitor not detected")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    MoveActiveWindowToMonitorMaximized(targetMonitor, "TV monitor")
}

; Alt+3 - Move active window back to the main monitor and maximize it
!3::
{
    pair := GetPhysicalMonitorPair()
    targetMonitor := pair["primary"]
    if !targetMonitor {
        ToolTip("Main physical monitor not detected")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    MoveActiveWindowToMonitorMaximized(targetMonitor, "main monitor")
}

; Ctrl+4 - Force move ALL windows from primary monitor to secondary monitor
^4::
{
    pair := GetPhysicalMonitorPair()
    primaryMon := pair["primary"]
    secondaryMon := pair["secondary"]
    if !primaryMon || !secondaryMon {
        ToolTip("Only 1 connected physical monitor detected")
        SetTimer(() => ToolTip(), -1800)
        return
    }

    result := MoveAllWindowsBetweenMonitors(primaryMon, secondaryMon)
    ToolTip(result["message"])
    SetTimer(() => ToolTip(), -2000)
}

; Ctrl+5 - Force move ALL windows from every other display to the main monitor
^5::
{
    pair := GetPhysicalMonitorPair()
    primaryMon := pair["primary"]
    if !primaryMon {
        ToolTip("Main physical monitor not detected")
        SetTimer(() => ToolTip(), -1800)
        return
    }

    result := MoveAllWindowsToMonitor(primaryMon)
    ToolTip(result["message"])
    SetTimer(() => ToolTip(), -2000)
}

; Ctrl+2 - Switch focus to the other monitor
; This hotkey switches focus to a window on the opposite monitor
; Workflow:
;   1. Detects which monitor is currently active (based on active window or mouse)
;   2. Targets the other connected physical monitor
;   3. Finds the topmost visible window on target monitor
;   4. Activates that window and moves mouse cursor to its center
;   5. If no window on target monitor, moves mouse to monitor center
; Includes throttling (100ms) to prevent rapid-fire keypresses causing race conditions
; Provides visual feedback via tooltip showing activated window or error
; Used for quickly switching focus between monitors without moving windows
^2::
{
    ; Throttle rapid keypresses to prevent race conditions
    ; This ensures the previous execution completes before starting a new one
    global lastCtrl2Time, ctrl2Throttle
    currentTime := A_TickCount

    if (currentTime - lastCtrl2Time < ctrl2Throttle) {
        ; Too soon after last execution, ignore this keypress
        return
    }

    lastCtrl2Time := currentTime

    pair := GetPhysicalMonitorPair()
    primaryMon := pair["primary"]
    secondaryMon := pair["secondary"]
    if !primaryMon || !secondaryMon {
        ToolTip("Only 1 connected physical monitor detected")
        SetTimer(() => ToolTip(), -1800)
        return
    }

    ; Get active window to determine current monitor
    try {
        activeHwnd := WinGetID("A")
    } catch {
        activeHwnd := 0
    }

    ; Determine current monitor based on active window (or mouse if no active window)
    currentMonitor := primaryMon
    if (activeHwnd) {
        try {
            currentMonitor := GetWindowMonitor(activeHwnd)
        } catch as err {
            currentMonitor := primaryMon
        }
    } else {
        ; Fallback to mouse position if no active window
        try {
            MouseGetPos(&mouseX, &mouseY)
            currentMonitor := GetMonitorAtPoint(mouseX, mouseY)
        } catch as err {
            currentMonitor := primaryMon
        }
    }

    targetMonitor := (currentMonitor = primaryMon) ? secondaryMon : primaryMon

    ; Use the new SwitchFocusBetweenMonitors function
    try {
        result := SwitchFocusBetweenMonitors(targetMonitor)

        ; Display result message as tooltip
        ToolTip(result["message"])
        SetTimer(() => ToolTip(), -1500)
    } catch as err {
        ToolTip("Error switching monitor focus: " err.Message)
        SetTimer(() => ToolTip(), -2000)
    }
}

; Ctrl x4 tap â€” Force borderless fullscreen on the current monitor
; Detects 4 consecutive Ctrl taps within 1.2 seconds
~Ctrl Up::
{
    global ctrlTapCount, ctrlLastTapTime, ctrlTapWindow
    ; A modifier used in a chord is not a modifier tap. Without this guard,
    ; repeated Ctrl+H cycles trigger the unrelated Ctrl x4 fullscreen gesture.
    if (A_PriorKey != "LControl" && A_PriorKey != "RControl") {
        ctrlTapCount := 0
        return
    }
    now := A_TickCount

    if (now - ctrlLastTapTime > ctrlTapWindow) {
        ctrlTapCount := 0
    }

    ctrlTapCount++
    ctrlLastTapTime := now

    if (ctrlTapCount >= 4) {
        ctrlTapCount := 0
        try {
            hwnd := WinGetID("A")
            if (hwnd) {
                if (ForceBorderlessFullscreen(hwnd)) {
                    ToolTip("Forced fullscreen")
                } else {
                    ToolTip("Fullscreen force failed")
                }
                SetTimer(() => ToolTip(), -1500)
            }
        }
    }
}

; Alt x4 tap â€” Launch OpenWhisper
; Alt x4 tap then Z - Run the Alt x5 sequence, then the PS5 restore line
; Alt x5 tap - In the active terminal, run the profile2 commands in sequence
; Detects consecutive Alt taps within 1.2 seconds
~Alt Up::
{
    global altTapCount, altLastTapTime, altTapWindow, altOpenWhisperTimer
    ; Alt+H must never advance the unrelated Alt x4/x5 gesture sequence.
    if (A_PriorKey != "LAlt" && A_PriorKey != "RAlt") {
        if (altOpenWhisperTimer) {
            SetTimer(altOpenWhisperTimer, 0)
            altOpenWhisperTimer := 0
        }
        altTapCount := 0
        return
    }
    now := A_TickCount

    if (now - altLastTapTime > altTapWindow) {
        altTapCount := 0
    }

    altTapCount++
    altLastTapTime := now

    if (altTapCount = 4) {
        altOpenWhisperTimer := () => LaunchOpenWhisperFromAltTap()
        SetTimer(altOpenWhisperTimer, -altTapWindow)
    } else if (altTapCount >= 5) {
        if (altOpenWhisperTimer) {
            SetTimer(altOpenWhisperTimer, 0)
            altOpenWhisperTimer := 0
        }
        altTapCount := 0
        targetHwnd := WinGetID("A")
        if (targetHwnd) {
            RunTerminalProfileSequence("ahk_id " targetHwnd, "F:\study\Devops\backup\backup\profile\profile2.ps1")
        }
    }
}

#HotIf AltX4ZPending()
z::
{
    global altTapCount, altOpenWhisperTimer
    if (altOpenWhisperTimer) {
        SetTimer(altOpenWhisperTimer, 0)
        altOpenWhisperTimer := 0
    }
    altTapCount := 0
    targetHwnd := WinGetID("A")
    if (targetHwnd) {
        RunTerminalProfileSequence("ahk_id " targetHwnd, "F:\study\Devops\backup\backup\profile\profile2.ps1", "Invoke-AhkX4ZFast")
    }
}
#HotIf

AltX4ZPending()
{
    global altTapCount, altOpenWhisperTimer
    return (altTapCount = 4 && altOpenWhisperTimer)
}

LaunchOpenWhisperFromAltTap()
{
    global altTapCount, altOpenWhisperTimer
    if (altTapCount = 4) {
        altTapCount := 0
        Run('wscript.exe //B //Nologo "' A_AppData '\Microsoft\Windows\Start Menu\Programs\Startup\WhisperKeyLocal.vbs"', , "Hide")
        ToolTip("Whisper Key launched")
        SetTimer(() => ToolTip(), -1500)
    }
    altOpenWhisperTimer := 0
}

; CapsLock x8 tap - In the active terminal, run the profile commands in sequence
; Detects 8 consecutive CapsLock taps within 3 seconds
~CapsLock::
{
    global capsLockTapCount, capsLockLastTapTime, capsLockTapWindow
    now := A_TickCount

    if (now - capsLockLastTapTime > capsLockTapWindow) {
        capsLockTapCount := 0
    }

    capsLockTapCount++
    capsLockLastTapTime := now

    if (capsLockTapCount >= 8) {
        capsLockTapCount := 0
        targetHwnd := WinGetID("A")
        if (targetHwnd) {
            RunTerminalProfileSequence("ahk_id " targetHwnd)
        }
    }
}

; F6 x6 tap - Toggle mute for the app that is currently on top
ToggleActiveAppMute()
{
    try {
        processName := WinGetProcessName("A")
        if (processName = "") {
            ToolTip("No active app to mute")
            SetTimer(() => ToolTip(), -1500)
            return
        }
        Run('nircmd.exe muteappvolume "' processName '" 2', , "Hide")
        ToolTip("Toggled mute: " processName)
        SetTimer(() => ToolTip(), -1500)
    } catch as err {
        ToolTip("Mute toggle failed: " err.Message)
        SetTimer(() => ToolTip(), -2500)
    }
}

; mmute/unmute - control the application owning the current foreground window.
; Resolve the process from the HWND first so the hotstring never relies on a
; stale active-window title or on whichever process happens to be under the
; mouse pointer.
SetForegroundAppMute(muteState, commandName)
{
    hwnd := DllCall("GetForegroundWindow", "Ptr")
    if (!hwnd || !DllCall("IsWindow", "Ptr", hwnd, "Int")) {
        ShowCommandStatus(commandName ": no foreground app detected", 2500)
        return false
    }

    pid := 0
    if (!DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &pid)
        || !pid || pid = DllCall("GetCurrentProcessId", "UInt")) {
        ShowCommandStatus(commandName ": no foreground app detected", 2500)
        return false
    }

    try {
        processName := WinGetProcessName("ahk_id " hwnd)
    } catch {
        processName := ""
    }
    if (processName = "") {
        ShowCommandStatus(commandName ": no foreground app detected", 2500)
        return false
    }

    nircmdPath := ResolveNirCmdPath()
    command := '"' nircmdPath '" muteappvolume "' processName '" ' muteState
    try {
        exitCode := RunWait(command, , "Hide")
    } catch as err {
        ShowCommandStatus(commandName ": nircmd failed - " err.Message, 3000)
        return false
    }

    if (exitCode != 0) {
        LogFreezeAction(commandName " failed for " processName " PID " pid " exit " exitCode)
        ShowCommandStatus(commandName ": nircmd failed (exit " exitCode ")", 3000)
        return false
    }

    LogFreezeAction(commandName " succeeded for " processName " PID " pid)
    ShowCommandStatus(commandName ": " (muteState ? "muted " : "unmuted ") processName)
    return true
}

ResolveNirCmdPath()
{
    for path in [
        A_WinDir "\System32\nircmd.exe",
        A_ScriptDir "\nircmd.exe",
        A_WinDir "\Sysnative\nircmd.exe",
        "F:\study\repos\shells\powershell\scripts\microphone\voice_typing_tools\nircmd\nircmd.exe",
        "F:\backup\windowsapps\installed\OpenWhispr\Runtime\resources\bin\nircmd.exe"
    ] {
        if FileExist(path)
            return path
    }
    ; Let Windows search PATH as a final fallback; RunWait reports a clear
    ; failure through the caller if the executable is unavailable.
    return "nircmd.exe"
}

; mmmute/uunmute - use the CoreAudio default capture endpoint's scalar level.
; The saved scalar is kept in memory for the current script session and in a
; small UTF-8 file so a reload can still restore the user's previous level.
MuteDefaultMicrophone()
{
    if !TryGetDefaultCaptureVolume(&level, &errorMessage) {
        ShowCommandStatus("mmmute: could not read microphone - " errorMessage, 3000)
        return false
    }

    if !TryGetDefaultCaptureMute(&isMuted, &errorMessage) {
        ShowCommandStatus("mmmute: could not read microphone mute state - " errorMessage, 3000)
        return false
    }

    if (level <= 0 && isMuted) {
        ShowCommandStatus("mmmute: microphone is already muted")
        return true
    }

    if (level > 0 && !SaveMicrophonePreviousLevel(level, &errorMessage)) {
        ShowCommandStatus("mmmute: could not save microphone level - " errorMessage, 3000)
        return false
    }

    if !TrySetDefaultCaptureVolume(0, &errorMessage) {
        ShowCommandStatus("mmmute: could not mute microphone - " errorMessage, 3000)
        return false
    }

    if !TrySetDefaultCaptureMute(true, &errorMessage) {
        ShowCommandStatus("mmmute: could not set microphone mute state - " errorMessage, 3000)
        return false
    }

    ShowCommandStatus("mmmute: microphone muted (was " FormatMicrophonePercent(level) "%)")
    return true
}

UnmuteDefaultMicrophone()
{
    global microphonePreviousLevel

    if !TryGetDefaultCaptureVolume(&level, &errorMessage) {
        ShowCommandStatus("uunmute: could not read microphone - " errorMessage, 3000)
        return false
    }

    if !TryGetDefaultCaptureMute(&isMuted, &errorMessage) {
        ShowCommandStatus("uunmute: could not read microphone mute state - " errorMessage, 3000)
        return false
    }

    if (level > 0 && !isMuted) {
        ShowCommandStatus("uunmute: microphone is already unmuted at " FormatMicrophonePercent(level) "%")
        return true
    }

    restoreLevel := level
    if (restoreLevel <= 0 && !TryReadSavedMicrophoneLevel(&restoreLevel)) {
        restoreLevel := 1.0
    }

    if !TrySetDefaultCaptureVolume(restoreLevel, &errorMessage) {
        ShowCommandStatus("uunmute: could not unmute microphone - " errorMessage, 3000)
        return false
    }

    if !TrySetDefaultCaptureMute(false, &errorMessage) {
        ShowCommandStatus("uunmute: could not clear microphone mute state - " errorMessage, 3000)
        return false
    }

    microphonePreviousLevel := restoreLevel
    ShowCommandStatus("uunmute: microphone unmuted at " FormatMicrophonePercent(restoreLevel) "%")
    return true
}

ShowCommandStatus(message, duration := 2000)
{
    ToolTip(message)
    SetTimer(() => ToolTip(), -duration)
}

SaveMicrophonePreviousLevel(level, &errorMessage)
{
    global microphonePreviousLevel, microphonePreviousLevelFile
    errorMessage := ""
    file := 0

    try {
        file := FileOpen(microphonePreviousLevelFile, "w", "UTF-8-RAW")
        file.Write(Format("{:.6f}", level))
        file.Close()
        file := 0
        microphonePreviousLevel := level
        return true
    } catch as err {
        if IsObject(file) {
            try file.Close()
        }
        errorMessage := err.Message
        return false
    }
}

TryReadSavedMicrophoneLevel(&level)
{
    global microphonePreviousLevel, microphonePreviousLevelFile
    level := 0.0

    if TryParseMicrophoneLevel(microphonePreviousLevel, &sessionLevel) && sessionLevel > 0 {
        level := sessionLevel
        return true
    }

    if !FileExist(microphonePreviousLevelFile)
        return false

    try {
        savedText := FileRead(microphonePreviousLevelFile)
    } catch {
        return false
    }

    if TryParseMicrophoneLevel(savedText, &fileLevel) && fileLevel > 0 {
        level := fileLevel
        return true
    }
    return false
}

TryParseMicrophoneLevel(value, &level)
{
    level := 0.0
    text := Trim(value)
    if !RegExMatch(text, "^(?:0(?:\.\d+)?|1(?:\.0+)?)$", &match)
        return false
    level := match[0] + 0.0
    return true
}

FormatMicrophonePercent(level)
{
    return Min(100, Max(0, Round(level * 100)))
}

OpenDefaultCaptureEndpointVolume(&endpointVolume, &errorMessage)
{
    endpointVolume := 0
    errorMessage := ""
    device := 0
    opened := false

    try {
        enumerator := ComObject(
            "{BCDE0395-E52F-467C-8E3D-C4579291692E}",
            "{A95664D2-9614-4F35-A746-DE8DB63617E6}")
        ; EDataFlow=eCapture (1), ERole=eConsole (0).
        ComCall(4, enumerator, "Int", 1, "Int", 0, "Ptr*", &device)

        endpointVolumeIid := Buffer(16, 0)
        if DllCall("ole32\CLSIDFromString", "WStr",
            "{5CDF2C82-841E-4546-9722-0CF74078229A}",
            "Ptr", endpointVolumeIid.Ptr, "Int") != 0 {
            throw Error("could not create the CoreAudio endpoint-volume IID")
        }

        ; IMMDevice::Activate is vtable slot 3; CLSCTX_ALL is 0x17.
        ComCall(3, device, "Ptr", endpointVolumeIid.Ptr, "UInt", 0x17,
            "Ptr", 0, "Ptr*", &endpointVolume)
        opened := true
        return true
    } catch as err {
        errorMessage := err.Message
        return false
    } finally {
        ReleaseCoreAudioInterface(device)
        if !opened
            ReleaseCoreAudioInterface(endpointVolume)
    }
}

TryGetDefaultCaptureVolume(&volume, &errorMessage)
{
    volume := 0.0
    errorMessage := ""
    endpointVolume := 0

    if !OpenDefaultCaptureEndpointVolume(&endpointVolume, &errorMessage)
        return false

    try {
        ; IAudioEndpointVolume::GetMasterVolumeLevelScalar is slot 9.
        ComCall(9, endpointVolume, "Float*", &volume)
        if (volume < 0 || volume > 1)
            throw Error("CoreAudio returned an invalid microphone level")
        return true
    } catch as err {
        errorMessage := err.Message
        return false
    } finally {
        ReleaseCoreAudioInterface(endpointVolume)
    }
}

TrySetDefaultCaptureVolume(volume, &errorMessage)
{
    errorMessage := ""
    endpointVolume := 0

    if !OpenDefaultCaptureEndpointVolume(&endpointVolume, &errorMessage)
        return false

    try {
        ; IAudioEndpointVolume::SetMasterVolumeLevelScalar is slot 7.
        ComCall(7, endpointVolume, "Float", volume, "Ptr", 0)
        return true
    } catch as err {
        errorMessage := err.Message
        return false
    } finally {
        ReleaseCoreAudioInterface(endpointVolume)
    }
}

TryGetDefaultCaptureMute(&isMuted, &errorMessage)
{
    isMuted := false
    errorMessage := ""
    endpointVolume := 0

    if !OpenDefaultCaptureEndpointVolume(&endpointVolume, &errorMessage)
        return false

    try {
        ; IAudioEndpointVolume::GetMute is slot 15.
        muteValue := 0
        ComCall(15, endpointVolume, "Int*", &muteValue)
        isMuted := !!muteValue
        return true
    } catch as err {
        errorMessage := err.Message
        return false
    } finally {
        ReleaseCoreAudioInterface(endpointVolume)
    }
}

TrySetDefaultCaptureMute(muteState, &errorMessage)
{
    errorMessage := ""
    endpointVolume := 0

    if !OpenDefaultCaptureEndpointVolume(&endpointVolume, &errorMessage)
        return false

    try {
        ; IAudioEndpointVolume::SetMute is slot 14.
        ComCall(14, endpointVolume, "Int", !!muteState, "Ptr", 0)
        return true
    } catch as err {
        errorMessage := err.Message
        return false
    } finally {
        ReleaseCoreAudioInterface(endpointVolume)
    }
}

ReleaseCoreAudioInterface(interfacePtr)
{
    if interfacePtr {
        ; Release returns ULONG, not HRESULT; specifying UInt prevents a
        ; successful release count from being treated as a COM failure.
        try ComCall(2, interfacePtr, "UInt")
    }
}

; Force-terminate the process tree owning the foreground window.  The old
; implementation launched taskkill.exe /T asynchronously, which could hang
; forever on a console or game tree and gave no indication that the target
; survived.  The helper performs bounded native TerminateProcess calls and
; returns an exit code that this function verifies against the original PID
; and creation stamp.
KillForegroundApp()
{
    hwnd := DllCall("GetForegroundWindow", "Ptr")
    if (!hwnd) {
        ShowKkkkKillStatus("kkkk: no foreground application", true)
        return false
    }

    pid := 0
    DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &pid)
    currentPid := DllCall("GetCurrentProcessId", "UInt")
    if (!pid || pid = currentPid) {
        ShowKkkkKillStatus("kkkk: refused to terminate this shortcut runtime", true)
        return false
    }

    try {
        processName := WinGetProcessName("ahk_id " hwnd)
    } catch {
        processName := ""
    }
    try {
        windowTitle := WinGetTitle("ahk_id " hwnd)
    } catch {
        windowTitle := ""
    }

    if (IsKkkkProtectedProcessName(processName)) {
        ShowKkkkKillStatus("kkkk: protected system window was not terminated", true)
        LogKkkkKill("refused protected process=" processName " pid=" pid)
        return false
    }

    if (!ProcessExist(pid)) {
        ShowKkkkKillStatus("kkkk: foreground application already exited", true)
        return false
    }

    creationStamp := GetProcessCreationStamp(pid)
    targetLabel := processName != "" ? processName : "PID " pid
    if (windowTitle != "") {
        targetLabel .= " (" windowTitle ")"
    }
    LogKkkkKill("request target=" targetLabel " pid=" pid " created=" creationStamp)

    exitCode := RunKkkkKillHelper(pid, creationStamp, false)
    if (WaitForKkkkProcessExit(pid, creationStamp, 2000)) {
        ShowKkkkKillStatus("kkkk: force-killed " targetLabel)
        LogKkkkKill("success target=" targetLabel " exit=" exitCode)
        return true
    }

    ; A non-elevated script cannot terminate a higher-integrity target.  Ask
    ; Windows for one explicit elevation only after the normal attempt failed.
    if (!A_IsAdmin) {
        elevatedExitCode := RunKkkkKillHelper(pid, creationStamp, true)
        if (WaitForKkkkProcessExit(pid, creationStamp, 2500)) {
            ShowKkkkKillStatus("kkkk: force-killed " targetLabel " (elevated)")
            LogKkkkKill("success elevated target=" targetLabel " exit=" elevatedExitCode)
            return true
        }
        exitCode := elevatedExitCode
    }

    errorText := "kkkk: could not terminate " targetLabel
    if (!A_IsAdmin) {
        errorText .= " (approve the elevation prompt or close the protected app)"
    } else {
        errorText .= " (Windows denied termination; exit " exitCode ")"
    }
    ShowKkkkKillStatus(errorText, true)
    LogKkkkKill("failure target=" targetLabel " pid=" pid " exit=" exitCode
        " admin=" A_IsAdmin)
    return false
}

RunKkkkKillHelper(pid, creationStamp, elevated := false)
{
    helper := A_ScriptDir "\kkkk-kill-helper.ahk"
    if (!FileExist(helper)) {
        LogKkkkKill("helper missing: " helper)
        return -1
    }

    stampArg := creationStamp != "" ? '"' creationStamp '"' : '""'
    command := '"' A_AhkPath '" /script "' helper '" "' pid '" ' stampArg
    if (elevated) {
        command := "*RunAs " command
    }

    try {
        return RunWait(command, , "Hide")
    } catch as err {
        LogKkkkKill("helper launch failed elevated=" elevated " error=" err.Message)
        return -1
    }
}

WaitForKkkkProcessExit(pid, expectedCreationStamp := "", timeoutMs := 2000)
{
    deadline := A_TickCount + timeoutMs
    Loop {
        if (!ProcessExist(pid)) {
            return true
        }

        if (expectedCreationStamp != "") {
            currentCreationStamp := GetProcessCreationStamp(pid)
            if (currentCreationStamp != "" && currentCreationStamp != expectedCreationStamp) {
                return true
            }
        }

        if (A_TickCount >= deadline) {
            break
        }
        Sleep(25)
    }

    if (!ProcessExist(pid)) {
        return true
    }
    if (expectedCreationStamp != "") {
        currentCreationStamp := GetProcessCreationStamp(pid)
        if (currentCreationStamp != "" && currentCreationStamp != expectedCreationStamp) {
            return true
        }
    }
    return false
}

IsKkkkProtectedProcessName(processName)
{
    static protected := Map(
        "autohotkey64.exe", true,
        "autohotkeyux.exe", true,
        "csrss.exe", true,
        "dwm.exe", true,
        "explorer.exe", true,
        "lsass.exe", true,
        "services.exe", true,
        "sihost.exe", true,
        "smss.exe", true,
        "startmenuexperiencehost.exe", true,
        "shellexperiencehost.exe", true,
        "system", true,
        "wininit.exe", true,
        "winlogon.exe", true)
    return protected.Has(StrLower(processName))
}

ShowKkkkKillStatus(message, longDuration := false)
{
    ToolTip(message)
    SetTimer(() => ToolTip(), longDuration ? -4000 : -2200)
}

LogKkkkKill(message)
{
    try {
        FileAppend(
            FormatTime(, "yyyy-MM-dd HH:mm:ss") " " message
                Chr(13) Chr(10),
            A_Temp "\current-ahk-kkkk.log",
            "UTF-8")
    }
}

TrackKkkkForceKill()
{
    global kkkkTapCount, kkkkLastTapTime, kkkkTapWindow

    now := A_TickCount
    if (now - kkkkLastTapTime > kkkkTapWindow) {
        kkkkTapCount := 0
    }

    kkkkTapCount++
    kkkkLastTapTime := now

    if (kkkkTapCount >= 4) {
        kkkkTapCount := 0
        return KillForegroundApp()
    }
    return false
}

OpenRebootlessPerformanceMaximizer()
{
    Run('"F:\study\Platforms\windows\system\maintenance\performance\rebootless\refresh\tools\MichRebootlessWindowsPerformanceMaximizer\app\MichRebootlessWindowsPerformanceMaximizer.exe"')
}

OpenFirefox()
{
    ; Prefer the installed executable, then the registered/start-menu launchers.
    paths := [
        "C:\Program Files\Mozilla Firefox\firefox.exe",
        "C:\Program Files (x86)\Mozilla Firefox\firefox.exe",
        "C:\Users\micha\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Firefox.lnk",
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Firefox.lnk",
        EnvGet("LOCALAPPDATA") "\Microsoft\WindowsApps\firefox.exe"
    ]

    for p in paths {
        if FileExist(p) {
            try {
                Run(p)
                return true
            } catch {
            }
        }
    }

    ; App Paths may be registered per-machine or per-user.
    for regKey in [
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe",
        "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe"
    ] {
        try {
            regPath := Trim(RegRead(regKey), '"')
            if FileExist(regPath) {
                Run(regPath)
                return true
            }
        } catch {
        }
    }

    ; Last resort: allow Windows to resolve a registered Firefox command.
    try {
        Run("firefox.exe")
        return true
    } catch {
    }

    MsgBox("Firefox not found!", "Error", "Icon!")
    return false
}

RunApplication(executablePath, arguments := "")
{
    if !FileExist(executablePath)
        return false

    SplitPath(executablePath, , &workingDirectory)
    command := '"' executablePath '"'
    if (arguments != "")
        command .= " " arguments

    try {
        Run(command, workingDirectory)
        return true
    } catch {
        return false
    }
}

RunFirstAvailable(paths, arguments := "")
{
    for path in paths {
        if RunApplication(path, arguments)
            return true
    }
    return false
}

OpenNamedApplication(name, paths, arguments := "")
{
    if RunFirstAvailable(paths, arguments)
        return true

    MsgBox(name " was not found or could not be launched.", "Shortcut error", "Icon!")
    return false
}

OpenAdminDefaultTerminal()
{
    ; No profile argument deliberately means Windows Terminal's configured
    ; default profile.  -w 0 reuses the existing Terminal window and opens a
    ; new tab; when no window exists, Terminal creates the first one.
    terminalPath := EnvGet("LOCALAPPDATA") "\Microsoft\WindowsApps\wt.exe"
    command := FileExist(terminalPath)
        ? '"' terminalPath '" -w 0 nt'
        : "wt.exe -w 0 nt"
    try {
        Run(command)
        return true
    } catch as err {
        MsgBox("Windows Terminal could not be started: " err.Message, "Shortcut error", "Icon!")
        return false
    }
}

OpenDaymark()
{
    return OpenNamedApplication("Daymark", [
        "F:\backup\windowsapps\installed\daymark\Daymark.exe",
        "C:\Users\micha\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Daymark.lnk"
    ])
}

OpenProcessLasso()
{
    return OpenNamedApplication("Process Lasso", [
        "F:\backup\windowsapps\installed\Process Lasso\ProcessLasso.exe"
    ])
}

OpenFreebuff()
{
    return OpenNamedApplication("Freebuff", [
        "C:\Users\micha\AppData\Local\Programs\@codebufffreebuff-desktop\Freebuff.exe",
        "C:\Users\micha\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Freebuff.lnk"
    ])
}

OpenDriverTools()
{
    tools := [
        Map("Name", "GIGABYTE Control Center", "Path", "C:\Program Files\GIGABYTE\Control Center\GCC.exe", "Arguments", ""),
        Map("Name", "AMD Ryzen Master", "Path", "C:\Program Files\AMD\RyzenMaster\bin\AMD Ryzen Master.exe", "Arguments", ""),
        Map("Name", "NVIDIA App", "Path", "C:\Program Files\NVIDIA Corporation\NVIDIA App\CEF\NVIDIA App.exe", "Arguments", ""),
        Map("Name", "AMD Software", "Path", "C:\Program Files\AMD\CNext\CNext\RadeonSoftware.exe", "Arguments", ""),
        Map("Name", "GameSir Connect", "Path", "C:\Users\Admin\AppData\Local\Programs\GameSir Connect\GameSir Connect.exe", "Arguments", ""),
        Map("Name", "Logi Options+", "Path", "C:\Program Files\LogiOptionsPlus\logioptionsplus.exe", "Arguments", "--disable-gpu"),
        Map("Name", "Device Manager", "Path", A_WinDir "\System32\devmgmt.msc", "Arguments", ""),
        Map("Name", "Snappy Driver Installer Origin 2.0.3 (automatic missing/better)", "Path", "F:\backup\windowsapps\installed\Snappy Driver Installer Origin\SDIO_x64_R886.exe", "Arguments", "-autoclose -script:scripts\install.txt")
    ]

    opened := 0
    unavailable := ""
    for tool in tools {
        if RunApplication(tool["Path"], tool["Arguments"]) {
            opened += 1
        } else {
            if (unavailable != "")
                unavailable .= ", "
            unavailable .= tool["Name"]
        }
    }

    ; Windows Update is the only source that can promise zero pending driver
    ; packages, so the sweep is only complete once it is open too.
    try {
        Run("ms-settings:windowsupdate")
        opened += 1
    } catch {
        if (unavailable != "")
            unavailable .= ", "
        unavailable .= "Windows Update"
    }

    totalTools := tools.Length + 1

    if (unavailable != "")
        ToolTip("Driver tools opened: " opened "/" totalTools "; unavailable: " unavailable)
    else
        ToolTip("Driver tools opened: " opened "/" totalTools)
    SetTimer(() => ToolTip(), -3000)
    return opened = totalTools
}

FindApplicationWindow(processName)
{
    fallbackHwnd := 0
    for hwnd in WinGetList("ahk_exe " processName) {
        if !DllCall("IsWindow", "Ptr", hwnd, "Int")
            continue
        if !fallbackHwnd
            fallbackHwnd := hwnd
        if (DllCall("IsWindowVisible", "Ptr", hwnd, "Int")
            && DllCall("GetWindowTextLength", "Ptr", hwnd, "Int") > 0)
            return hwnd
    }
    return fallbackHwnd
}

ForceForegroundApplicationWindow(hwnd)
{
    if (!hwnd || !DllCall("IsWindow", "Ptr", hwnd, "Int"))
        return false

    ; Temporarily raise the window above every other app - including topmost
    ; fullscreen games - focus it, then undo the temporary raise only when no
    ; topmost window would immediately cover it again.
    flags := 0x0001 | 0x0002 | 0x0040 | 0x4000 ; NOSIZE | NOMOVE | SHOWWINDOW | ASYNCWINDOWPOS
    try wasTopmost := (WinGetExStyle("ahk_id " hwnd) & 0x8) != 0 ; WS_EX_TOPMOST
    catch
        return false
    foreHwnd := DllCall("GetForegroundWindow", "Ptr")
    foreTopmost := false
    attached := false
    foreThread := 0
    thisThread := DllCall("GetCurrentThreadId", "UInt")
    if (foreHwnd && foreHwnd != hwnd) {
        try foreTopmost := (WinGetExStyle("ahk_id " foreHwnd) & 0x8) != 0
        ; A fullscreen game keeps the foreground locked; borrowing its input
        ; thread's state is what lets SetForegroundWindow actually take it.
        foreThread := DllCall("GetWindowThreadProcessId", "Ptr", foreHwnd, "Ptr", 0, "UInt")
        if (foreThread && foreThread != thisThread)
            attached := DllCall("AttachThreadInput", "UInt", thisThread, "UInt", foreThread, "Int", true)
    }

    ; Bring the window up without touching its size: un-minimize a minimized
    ; window, but never SW_RESTORE a maximized one back to small.
    try minMax := WinGetMinMax("ahk_id " hwnd)
    catch
        return false
    if (minMax = -1)
        DllCall("ShowWindowAsync", "Ptr", hwnd, "Int", 9) ; SW_RESTORE: un-minimize only
    else
        DllCall("ShowWindowAsync", "Ptr", hwnd, "Int", 5) ; SW_SHOW: keep maximized geometry

    DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", -1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", flags) ; HWND_TOPMOST
    DllCall("BringWindowToTop", "Ptr", hwnd, "Int")
    DllCall("SetForegroundWindow", "Ptr", hwnd, "Int")

    deadline := A_TickCount + 1000
    while (DllCall("GetForegroundWindow", "Ptr") != hwnd && A_TickCount < deadline) {
        DllCall("SetForegroundWindow", "Ptr", hwnd, "Int")
        Sleep(25)
    }
    activated := DllCall("GetForegroundWindow", "Ptr") = hwnd
    if (attached)
        DllCall("AttachThreadInput", "UInt", thisThread, "UInt", foreThread, "Int", false)
    ; Demote the temporary always-on-top raise unless the window was topmost
    ; before or a topmost window (a fullscreen game) would sit right back
    ; above it; otherwise the application keeps normal z-order behavior.
    if (!wasTopmost && !foreTopmost)
        DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", -2, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", flags) ; HWND_NOTOPMOST
    return activated
}

OpenOrActivateApplication(executablePath, processName, displayName)
{
    if !FileExist(executablePath) {
        ShowCommandStatus(displayName ": executable not found", 3000)
        return false
    }

    hwnd := FindApplicationWindow(processName)
    if (hwnd && ForceForegroundApplicationWindow(hwnd))
        return true

    try Run('"' executablePath '"')
    catch as err {
        ShowCommandStatus(displayName ": launch failed - " err.Message, 3000)
        return false
    }

    deadline := A_TickCount + 10000
    while (A_TickCount < deadline) {
        hwnd := FindApplicationWindow(processName)
        if (hwnd && ForceForegroundApplicationWindow(hwnd))
            return true
        Sleep(50)
    }

    ShowCommandStatus(displayName ": no usable window appeared", 3000)
    return false
}

; Launch an app, or when it already runs, force its window above every other
; app - including fullscreen games - by deriving the process name from the exe.
OpenOrForegroundApplication(executablePath)
{
    SplitPath(executablePath, &processName)
    return OpenOrActivateApplication(executablePath, processName, processName)
}

OpenGameLibraryManager()
{
    primaryPath := "F:\study\repos\game-library-manager-native\dist\GameLibrary.exe"
    fallbackPath := "F:\study\repos\game-library-manager-native\native\dist\GameLibrary.exe"
    executablePath := FileExist(primaryPath) ? primaryPath : fallbackPath
    return OpenOrActivateApplication(executablePath, "GameLibrary.exe", "Game Library")
}

OpenMichStartupMaster()
{
    executablePath := "F:\study\Windows\Applications\Desktop\Utilities\System\Startup\Managers\mich-startup-master\build\MichStartupMaster.exe"
    return OpenOrActivateApplication(executablePath, "MichStartupMaster.exe", "Mich Startup Master")
}

OpenEverything()
{
    return OpenNamedApplication("Everything", [
        "C:\Program Files\Everything\Everything.exe",
        "F:\study\Dev_Toolchain\programming\python\apps\systemTools\sizes\tools\Everything\everything.exe",
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Everything.lnk"
    ])
}

ForceCloseOpenWhisprProcess(processName)
{
    ; /IM terminates every matching Electron process, rather than only the
    ; first PID returned by ProcessExist.  /T also removes child processes
    ; which can otherwise keep the runtime alive after its parent exits.
    taskkillCommand := Chr(34) . A_WinDir . "\System32\taskkill.exe" . Chr(34)
        . " /F /T /IM " . processName
    try RunWait(taskkillCommand, , "Hide")
    return !ProcessExist(processName)
}

OpenWhisprProcessesAreRunning()
{
    for processName in [
        "OpenWhisprWatchdog.exe",
        "OpenWhisprLauncher.exe",
        "OpenWhispr.exe"
    ] {
        if ProcessExist(processName)
            return true
    }
    return false
}

StopOpenWhisprProcessSet(timeoutMs := 12000)
{
    ; The supervisor recreates a missing watchdog every two seconds, and the
    ; watchdog can recreate a missing supervisor.  A single pass therefore
    ; races with that recovery loop.  Keep closing the complete process set
    ; until it has stayed absent for longer than the watchdog timeout.
    deadline := A_TickCount + timeoutMs
    quietSince := 0
    while (A_TickCount < deadline) {
        if !OpenWhisprProcessesAreRunning() {
            if !quietSince
                quietSince := A_TickCount
            if (A_TickCount - quietSince >= 2250)
                return true
            Sleep(100)
            continue
        }

        quietSince := 0
        ; Stop the runtime and its supervisor before the watchdog.  Repeating
        ; this tight sequence catches a supervisor launched between passes.
        for processName in [
            "OpenWhispr.exe",
            "OpenWhisprLauncher.exe",
            "OpenWhisprWatchdog.exe"
        ] {
            ForceCloseOpenWhisprProcess(processName)
        }
        Sleep(100)
    }
    return false
}

StartOpenWhisprAndWait(executablePath, timeoutMs := 10000)
{
    try Run('"' executablePath '"')
    catch as err {
        MsgBox("OpenWhispr launch failed: " err.Message, "Shortcut error", "Icon!")
        return false
    }

    deadline := A_TickCount + timeoutMs
    while (A_TickCount < deadline) {
        if ProcessExist("OpenWhisprLauncher.exe") || ProcessExist("OpenWhispr.exe")
            return true
        Sleep(100)
    }

    MsgBox("OpenWhispr did not start after the restart request.", "Shortcut error", "Icon!")
    return false
}

RestartOpenWhispr()
{
    static restartInProgress := false
    executablePath := "F:\backup\windowsapps\installed\OpenWhispr\OpenWhisprLauncher.exe"
    if !FileExist(executablePath) {
        MsgBox("OpenWhispr launcher not found.", "Shortcut error", "Icon!")
        return false
    }

    if restartInProgress {
        ShowCommandStatus("ss2t: OpenWhispr restart already in progress", 2000)
        return true
    }

    restartInProgress := true
    try {
        if !StopOpenWhisprProcessSet() {
            MsgBox("OpenWhispr did not fully stop before the restart timeout.", "Shortcut error", "Icon!")
            return false
        }

        return StartOpenWhisprAndWait(executablePath)
    } finally {
        restartInProgress := false
    }
}

~F6 Up::
{
    global f6TapCount, f6LastTapTime, f6TapWindow
    now := A_TickCount

    if (now - f6LastTapTime > f6TapWindow) {
        f6TapCount := 0
    }

    f6TapCount++
    f6LastTapTime := now

    if (f6TapCount >= 6) {
        f6TapCount := 0
        ToggleActiveAppMute()
    }
}

; F10 x6 tap - Emergency preserve-state suspend for frozen PC recovery
; Uses the same Windows power API path as: rundll32.exe powrprof.dll,SetSuspendState 0,1,0
; Before suspend, leave only keyboard wake enabled so wake is limited to Space/keyboard or the PC power button.
; Runs a powercfg query with a hard deadline so a hung powercfg can never
; block the script.  The poll loop uses Sleep, so other hotkeys keep firing.
RunPowerConfigQuery(shell, query, deadline) {
    exec := shell.Exec(A_ComSpec ' /c powercfg ' query)
    while (!exec.Status && A_TickCount < deadline)
        Sleep(50)
    if (exec.Status != 1)
        return ""  ; Timed out: do not block on StdOut.ReadAll().
    return exec.StdOut.ReadAll()
}

ConfigureF10WakeSources()
{
    shell := ComObject("WScript.Shell")
    deadline := A_TickCount + 15000  ; bound the whole wake-source pass

    programmable := RunPowerConfigQuery(shell, "/devicequery wake_programmable", deadline)
    for _, device in StrSplit(Trim(programmable, "`r`n"), "`n", "`r") {
        device := Trim(device)
        if (device != "" && InStr(device, "Keyboard")) {
            Run(A_ComSpec ' /c powercfg /deviceenablewake "' device '"', , "Hide")
        }
    }

    armed := RunPowerConfigQuery(shell, "/devicequery wake_armed", deadline)
    for _, device in StrSplit(Trim(armed, "`r`n"), "`n", "`r") {
        device := Trim(device)
        if (device != "" && !InStr(device, "Keyboard")) {
            Run(A_ComSpec ' /c powercfg /devicedisablewake "' device '"', , "Hide")
        }
    }
}

~F10 Up::
{
    global f10TapCount, f10LastTapTime, f10TapWindow
    now := A_TickCount

    if (now - f10LastTapTime > f10TapWindow) {
        f10TapCount := 0
    }

    f10TapCount++
    f10LastTapTime := now

    if (f10TapCount >= 6) {
        f10TapCount := 0
        ConfigureF10WakeSources()
        DllCall("PowrProf\SetSuspendState", "Int", 0, "Int", 1, "Int", 0)
    }
}

; REMOVED: Ctrl+S and Alt+S hotkeys (were causing nano/terminal freeze issues)

; Ctrl+h remains the foreground wrapper; native game-card requests call the same
; target-specific path after pinning the exact process and window identities.
FreezeForegroundApp() {
    global lastPauseHotkeyTick
    now := A_TickCount
    if (lastPauseHotkeyTick && now - lastPauseHotkeyTick < 500) {
        return "running"
    }
    lastPauseHotkeyTick := now
    hwnd := DllCall("GetForegroundWindow", "Ptr")
    return PauseTargetWindow(hwnd)
}

PauseTargetWindow(hwnd, expectedPid := 0, expectedCreated := "") {
    global frozenProcesses, lastProcessActionError
    Critical("On")
    if (!hwnd || !DllCall("IsWindow", "Ptr", hwnd, "Int"))
        return "failed"

    pid := 0
    DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &pid)
    if (!pid || (expectedPid && pid != expectedPid))
        return "failed"
    created := GetProcessCreationStamp(pid)
    if (created = "" || (expectedCreated != "" && StrUpper(created) != StrUpper(expectedCreated)))
        return "failed"
    targetPath := GetProcessImagePath(pid)
    targetName := StrLower(RegExReplace(targetPath, ".*\\", ""))
    if (pid = DllCall("GetCurrentProcessId", "UInt") || targetName = "gamelibrary.exe"
        || targetName = "autohotkey64.exe" || targetName = "autohotkey.exe")
        return "failed"

    Loop frozenProcesses.Length {
        processInfo := frozenProcesses[A_Index]
        if (processInfo.pid != pid) {
            continue
        }
        if (processInfo.HasProp("created") && processInfo.created != ""
            && processInfo.created != created) {
            frozenProcesses.RemoveAt(A_Index)
            SaveFrozenProcesses()
            break
        }

        ; Ctrl+H is idempotent. If this process is still settling from Alt+H,
        ; cancel that asynchronous restore and immediately return it to paused.
        CancelFullscreenRecoveryGuard(processInfo.hwnd)
        resourceState := {priorityClass: processInfo.HasProp("priorityClass") ? processInfo.priorityClass : 0
            , affinity: processInfo.HasProp("affinity") ? processInfo.affinity : 0
            , created: processInfo.HasProp("created") ? processInfo.created : ""
            , memoryPriority: processInfo.HasProp("memoryPriority") ? processInfo.memoryPriority : 0
            , powerVersion: processInfo.HasProp("powerVersion") ? processInfo.powerVersion : 0
            , powerControlMask: processInfo.HasProp("powerControlMask") ? processInfo.powerControlMask : 0
            , powerStateMask: processInfo.HasProp("powerStateMask") ? processInfo.powerStateMask : 0}
        mode := processInfo.HasProp("mode") ? processInfo.mode : "suspend"
        ; True suspension can disconnect Wand and permanently invalidate a
        ; Direct3D device. Recover legacy suspended games before moving them to
        ; the repeat-safe game throttle path; legacy connected records migrate
        ; directly because they were never suspended.
        if (mode = "game_suspend") {
            if !RestoreSuspendedProcess(pid, resourceState) {
                ToolTip("Ctrl+H could not recover the legacy suspended game")
                SetTimer(() => ToolTip(), -2500)
                return
            }
            mode := "throttle"
            processInfo.mode := mode
        } else if (mode = "connected") {
            mode := "throttle"
            processInfo.mode := mode
        }
        actionOk := ((mode = "throttle") ? ParkGameWindows(pid, processInfo.hwnd) : ForceMinimize(processInfo.hwnd))
            && ((mode = "throttle")
                ? ApplyGameLowResourceMode(pid, resourceState, processInfo.created)
                : ApplySuspendedLowResourceMode(pid, resourceState))
        if (actionOk) {
            processInfo.state := "paused"
            SaveFrozenProcesses()
            return "paused"
        } else {
            RestoreOneWindow(processInfo.hwnd, processInfo.HasProp("placement") ? processInfo.placement : 0)
            processInfo.state := "restore_pending"
            SaveFrozenProcesses()
            return "failed"
        }
    }

    placement := CaptureWindowPlacement(hwnd)
    wasFullscreen := IsWindowFullscreenLike(hwnd, placement)
    ; Games must stay alive so Wand trainer IPC and the Direct3D device survive
    ; indefinitely. Minimize them and apply IDLE CPU, EcoQoS execution-speed
    ; throttling, and VERY_LOW memory priority. Ordinary applications can use
    ; true suspension because they do not own a live game/trainer connection.
    mode := IsLikelyGameWindow(hwnd) ? "throttle" : "suspend"
    resourceState := CaptureProcessResourceState(pid)
    if (!IsObject(resourceState)) {
        ToolTip("Ctrl+H could not capture the app's resource state")
        SetTimer(() => ToolTip(), -2500)
        return "failed"
    }

    ; Track before suspension so Alt+H can recover even if the app stops repainting immediately.
    frozenProcesses.Push({pid: pid, hwnd: hwnd, created: created, title: "", placement: placement
        , mode: mode
        , state: "pausing"
        , priorityClass: IsObject(resourceState) ? resourceState.priorityClass : 0
        , affinity: IsObject(resourceState) ? resourceState.affinity : 0
        , memoryPriority: IsObject(resourceState) && resourceState.HasProp("memoryPriority") ? resourceState.memoryPriority : 0
        , powerVersion: IsObject(resourceState) && resourceState.HasProp("powerVersion") ? resourceState.powerVersion : 0
        , powerControlMask: IsObject(resourceState) && resourceState.HasProp("powerControlMask") ? resourceState.powerControlMask : 0
        , powerStateMask: IsObject(resourceState) && resourceState.HasProp("powerStateMask") ? resourceState.powerStateMask : 0
        , wasFullscreen: wasFullscreen})
    SaveFrozenProcesses()

    ; Games are hidden after the normal minimize transition so self-restoring
    ; launchers cannot surface them again while the throttle remains active.
    windowParked := (mode = "throttle") ? ParkGameWindows(pid, hwnd) : ForceMinimize(hwnd)
    if (!windowParked) {
        Loop frozenProcesses.Length {
            idx := frozenProcesses.Length - A_Index + 1
            if (frozenProcesses[idx].pid = pid) {
                frozenProcesses.RemoveAt(idx)
                break
            }
        }
        SaveFrozenProcesses()
        ToolTip("Ctrl+H could not minimize the foreground app")
        SetTimer(() => ToolTip(), -2500)
        return "failed"
    }

    actionOk := (mode = "throttle")
        ? ApplyGameLowResourceMode(pid, resourceState, GetProcessCreationStamp(pid))
        : ApplySuspendedLowResourceMode(pid, resourceState)
    if (!actionOk) {
        Loop frozenProcesses.Length {
            idx := frozenProcesses.Length - A_Index + 1
            if (frozenProcesses[idx].pid = pid) {
                frozenProcesses.RemoveAt(idx)
                break
            }
        }
        SaveFrozenProcesses()
        RestoreOneWindow(hwnd, placement)
        ToolTip("Ctrl+H failed: " lastProcessActionError)
        SetTimer(() => ToolTip(), -2500)
        return "failed"
    }
    Loop frozenProcesses.Length {
        if (frozenProcesses[A_Index].pid = pid && frozenProcesses[A_Index].created = created) {
            frozenProcesses[A_Index].state := "paused"
            break
        }
    }
    SaveFrozenProcesses()
    return "paused"
}

; Alt+h - INSTANT UNFREEZE - registered once via RegisterHotKey/MOD_NOREPEAT
; Unfreezes and restores windows immediately
RestoreFrozenApps(targetPid := 0, targetCreated := "", targetHwnd := 0, targeted := false) {
    global frozenProcesses, lastResumeHotkeyTick
    Critical("On")
    if (!targeted) {
        now := A_TickCount
        if (lastResumeHotkeyTick && now - lastResumeHotkeyTick < 500) {
            return "running"
        }
        lastResumeHotkeyTick := now
    }

    count := frozenProcesses.Length
    if (count = 0) {
        if (targeted)
            return "running"
        ; A previous restore may have looked successful before the game
        ; minimized itself again. Re-arm the last validated persisted record so
        ; Alt+H remains an idempotent recovery key instead of becoming a no-op.
        recoveryCandidate := LoadLastRecoveryCandidate()
        if (!IsObject(recoveryCandidate)) {
            return "running"
        }
        frozenProcesses.Push(recoveryCandidate)
        SaveFrozenProcesses()
        count := 1
    }

    stillFrozen := []
    guardsToStart := []

    ; Resume ALL frozen processes and restore windows
    Loop count {
        processInfo := frozenProcesses[A_Index]

        if (targeted && (processInfo.pid != targetPid
            || (processInfo.HasProp("created") && processInfo.created != targetCreated))) {
            stillFrozen.Push(processInfo)
            continue
        }

        if (!ProcessExist(processInfo.pid)) {
            continue
        }

        ; Never act on a reused PID after a long pause or an AHK restart.
        if (processInfo.HasProp("created") && processInfo.created != "" && processInfo.created != GetProcessCreationStamp(processInfo.pid)) {
            continue
        }

        mode := processInfo.HasProp("mode") ? processInfo.mode : "suspend"
        resourceState := {priorityClass: processInfo.HasProp("priorityClass") ? processInfo.priorityClass : 0
            , affinity: processInfo.HasProp("affinity") ? processInfo.affinity : 0
            , created: processInfo.HasProp("created") ? processInfo.created : ""
            , memoryPriority: processInfo.HasProp("memoryPriority") ? processInfo.memoryPriority : 0
            , powerVersion: processInfo.HasProp("powerVersion") ? processInfo.powerVersion : 0
            , powerControlMask: processInfo.HasProp("powerControlMask") ? processInfo.powerControlMask : 0
            , powerStateMask: processInfo.HasProp("powerStateMask") ? processInfo.powerStateMask : 0}

        ; Close the pause window before touching process resources. The delayed
        ; game working-set helper checks this persisted state and therefore
        ; cannot trim pages concurrently with Alt+H.
        processInfo.state := "resuming"
        SaveFrozenProcesses()

        ; Restore CPU/power resources for games; truly resume ordinary apps.
        resourcesRestored := (mode = "connected" || mode = "throttle")
            ? RestoreProcessResources(processInfo.pid, resourceState)
            : RestoreSuspendedProcess(processInfo.pid, resourceState)
        if (!resourcesRestored) {
            processInfo.state := "restore_pending"
            stillFrozen.Push(processInfo)
            continue
        }

        placement := processInfo.HasProp("placement") ? processInfo.placement : 0
        restored := RestoreProcessWindows(processInfo.pid, processInfo.hwnd, placement)
        if (restored && processInfo.HasProp("wasFullscreen") && processInfo.wasFullscreen) {
            ; Fullscreen stabilization is asynchronous. Keeping this record in
            ; state=restoring lets Ctrl+H cancel it immediately and prevents
            ; rapid alternating hotkeys from being ignored during an 8s wait.
            processInfo.state := "restoring"
            stillFrozen.Push(processInfo)
            guardsToStart.Push({hwnd: processInfo.hwnd, placement: placement})
            continue
        }
        if (!restored) {
            ; The process is no longer suspended, but keep the entry so Alt+H can retry restore.
            processInfo.state := "restore_pending"
            stillFrozen.Push(processInfo)
        }
    }

    ; Keep any process that failed to resume so Alt+H can retry instead of losing it.
    frozenProcesses := stillFrozen
    SaveFrozenProcesses()
    for _, guardInfo in guardsToStart {
        StartFullscreenRecoveryGuard(guardInfo.hwnd, guardInfo.placement)
    }
    return targeted ? GetGameControlState(targetPid, targetCreated, targetHwnd) : "running"
}

ResumeTargetProcess(pid, created, hwnd) {
    if (!ValidateGameControlTarget(pid, created, hwnd, 0))
        return "failed"
    return RestoreFrozenApps(pid, created, hwnd, true)
}

; Persist only the minimum identity/placement data needed to recover a process
; after this script is reloaded.  The creation stamp prevents PID reuse from
; ever resuming an unrelated process weeks later.
FrozenStateFile() {
    return A_ScriptDir "\\frozen-processes.ini"
}

ReadFrozenCoordinateSpace(stateFile, section) {
    coordinateSpace := StrLower(IniRead(stateFile, section, "DpiContext", "legacy"))
    return coordinateSpace = "pmv2-physical" ? coordinateSpace : "legacy"
}

LoadLastRecoveryCandidate() {
    stateFile := FrozenStateFile()
    Loop 1 {
        section := "FrozenProcess" A_Index
        pidText := IniRead(stateFile, section, "Pid", "")
        if (pidText = "") {
            continue
        }
        try pid := Integer(pidText)
        catch {
            continue
        }
        created := IniRead(stateFile, section, "Created", "")
        try hwnd := Integer(IniRead(stateFile, section, "Hwnd", "0"))
        catch {
            continue
        }
        if (!pid || !hwnd || !ProcessExist(pid) || !DllCall("IsWindow", "Ptr", hwnd, "Int")
            || (created != "" && created != GetProcessCreationStamp(pid))
            || !DllCall("IsIconic", "Ptr", hwnd, "Int")) {
            continue
        }

        placement := {hwnd: hwnd
            , minMax: Integer(IniRead(stateFile, section, "MinMax", "0"))
            , x: Integer(IniRead(stateFile, section, "X", "0"))
            , y: Integer(IniRead(stateFile, section, "Y", "0"))
            , w: Integer(IniRead(stateFile, section, "W", "0"))
            , h: Integer(IniRead(stateFile, section, "H", "0"))}
        placement.coordinateSpace := ReadFrozenCoordinateSpace(stateFile, section)
        return {pid: pid, hwnd: hwnd, created: created, title: "", placement: placement
            , mode: IniRead(stateFile, section, "Mode", "suspend")
            , state: IniRead(stateFile, section, "State", "restore_pending")
            , priorityClass: Integer(IniRead(stateFile, section, "PriorityClass", "0"))
            , affinity: Integer(IniRead(stateFile, section, "Affinity", "0"))
            , memoryPriority: Integer(IniRead(stateFile, section, "MemoryPriority", "0"))
            , powerVersion: Integer(IniRead(stateFile, section, "PowerVersion", "0"))
            , powerControlMask: Integer(IniRead(stateFile, section, "PowerControlMask", "0"))
            , powerStateMask: Integer(IniRead(stateFile, section, "PowerStateMask", "0"))
            , wasFullscreen: Integer(IniRead(stateFile, section, "WasFullscreen", "0")) != 0}
    }
    return 0
}

GetProcessCreationStamp(pid) {
    hProcess := DllCall("OpenProcess", "UInt", 0x1000, "Int", 0, "UInt", pid, "Ptr")
    if (!hProcess) {
        return ""
    }
    times := Buffer(32, 0)
    ok := DllCall("GetProcessTimes", "Ptr", hProcess, "Ptr", times, "Ptr", times.Ptr + 8, "Ptr", times.Ptr + 16, "Ptr", times.Ptr + 24, "Int")
    DllCall("CloseHandle", "Ptr", hProcess)
    return ok ? Format("{:016X}", NumGet(times, 0, "Int64")) : ""
}

SaveFrozenProcesses() {
    global frozenProcesses
    stateFile := FrozenStateFile()
    tempFile := stateFile ".tmp-" DllCall("GetCurrentProcessId", "UInt") "-" A_TickCount "-" Random(10000, 99999)
    try {
        IniWrite(frozenProcesses.Length, tempFile, "FrozenProcesses", "Count")
        if (frozenProcesses.Length > 0) {
            for index, processInfo in frozenProcesses
                WriteFrozenProcessRecord(tempFile, index, processInfo)
        } else {
            ; Keep the existing section-1 recovery candidate even when the
            ; current active count is zero. Alt+H still validates PID, creation
            ; time, and window state before it can restore that fallback.
            PreserveFrozenRecoveryRecord(stateFile, tempFile)
        }
        if !DllCall("MoveFileExW", "WStr", tempFile, "WStr", stateFile, "UInt", 0x9, "Int")
            throw OSError(A_LastError, "MoveFileEx", "Could not atomically publish the frozen-process state.")
    } catch as ex {
        LogFreezeAction("Could not publish frozen-process state atomically: " ex.Message)
        if FileExist(tempFile)
            try FileDelete(tempFile)
    }
}

WriteFrozenProcessRecord(path, index, processInfo) {
    section := "FrozenProcess" index
    placement := processInfo.HasProp("placement") ? processInfo.placement : 0
    IniWrite(processInfo.pid, path, section, "Pid")
    IniWrite(processInfo.hwnd, path, section, "Hwnd")
    IniWrite(processInfo.HasProp("created") ? processInfo.created : "", path, section, "Created")
    IniWrite(processInfo.HasProp("mode") ? processInfo.mode : "suspend", path, section, "Mode")
    IniWrite(processInfo.HasProp("state") ? processInfo.state : "paused", path, section, "State")
    IniWrite(processInfo.HasProp("priorityClass") ? processInfo.priorityClass : 0, path, section, "PriorityClass")
    IniWrite(processInfo.HasProp("affinity") ? processInfo.affinity : 0, path, section, "Affinity")
    IniWrite(processInfo.HasProp("memoryPriority") ? processInfo.memoryPriority : 0, path, section, "MemoryPriority")
    IniWrite(processInfo.HasProp("powerVersion") ? processInfo.powerVersion : 0, path, section, "PowerVersion")
    IniWrite(processInfo.HasProp("powerControlMask") ? processInfo.powerControlMask : 0, path, section, "PowerControlMask")
    IniWrite(processInfo.HasProp("powerStateMask") ? processInfo.powerStateMask : 0, path, section, "PowerStateMask")
    IniWrite(processInfo.HasProp("wasFullscreen") && processInfo.wasFullscreen ? 1 : 0, path, section, "WasFullscreen")
    IniWrite(IsObject(placement) ? placement.minMax : 0, path, section, "MinMax")
    IniWrite(IsObject(placement) ? placement.x : 0, path, section, "X")
    IniWrite(IsObject(placement) ? placement.y : 0, path, section, "Y")
    IniWrite(IsObject(placement) ? placement.w : 0, path, section, "W")
    IniWrite(IsObject(placement) ? placement.h : 0, path, section, "H")
    IniWrite(IsObject(placement) && placement.HasProp("coordinateSpace") ? placement.coordinateSpace : "legacy", path, section, "DpiContext")
}

PreserveFrozenRecoveryRecord(sourcePath, targetPath) {
    if !FileExist(sourcePath)
        return
    keys := ["Pid", "Hwnd", "Created", "Mode", "State", "PriorityClass", "Affinity"
        , "MemoryPriority", "PowerVersion", "PowerControlMask", "PowerStateMask", "WasFullscreen"
        , "MinMax", "X", "Y", "W", "H", "DpiContext"]
    for _, key in keys {
        value := IniRead(sourcePath, "FrozenProcess1", key, "__missing__")
        if (value != "__missing__")
            IniWrite(value, targetPath, "FrozenProcess1", key)
    }
}

LoadFrozenProcesses() {
    global frozenProcesses
    stateFile := FrozenStateFile()
    try count := Integer(IniRead(stateFile, "FrozenProcesses", "Count", "0"))
    catch {
        return
    }
    Loop count {
        section := "FrozenProcess" A_Index
        try pid := Integer(IniRead(stateFile, section, "Pid", "0"))
        catch {
            continue
        }
        created := IniRead(stateFile, section, "Created", "")
        try hwnd := Integer(IniRead(stateFile, section, "Hwnd", "0"))
        catch {
            continue
        }
        if (!pid || !hwnd || !ProcessExist(pid) || !DllCall("IsWindow", "Ptr", hwnd, "Int")
            || (created != "" && created != GetProcessCreationStamp(pid))) {
            continue
        }
        placement := {hwnd: hwnd, minMax: Integer(IniRead(stateFile, section, "MinMax", "0")), x: Integer(IniRead(stateFile, section, "X", "0")), y: Integer(IniRead(stateFile, section, "Y", "0")), w: Integer(IniRead(stateFile, section, "W", "0")), h: Integer(IniRead(stateFile, section, "H", "0"))
            , coordinateSpace: ReadFrozenCoordinateSpace(stateFile, section)}
        mode := IniRead(stateFile, section, "Mode", "suspend")
        if (mode = "connected")
            mode := "throttle"
        state := IniRead(stateFile, section, "State", "paused")
        priorityClass := Integer(IniRead(stateFile, section, "PriorityClass", "0"))
        affinity := Integer(IniRead(stateFile, section, "Affinity", "0"))
        memoryPriority := Integer(IniRead(stateFile, section, "MemoryPriority", "0"))
        powerVersion := Integer(IniRead(stateFile, section, "PowerVersion", "0"))
        powerControlMask := Integer(IniRead(stateFile, section, "PowerControlMask", "0"))
        powerStateMask := Integer(IniRead(stateFile, section, "PowerStateMask", "0"))
        wasFullscreen := Integer(IniRead(stateFile, section, "WasFullscreen", "0")) != 0
        processInfo := {pid: pid, hwnd: placement.hwnd, created: created, title: "", placement: placement
            , mode: mode, state: state, priorityClass: priorityClass, affinity: affinity
            , memoryPriority: memoryPriority, powerVersion: powerVersion
            , powerControlMask: powerControlMask, powerStateMask: powerStateMask
            , wasFullscreen: wasFullscreen}
        frozenProcesses.Push(processInfo)
        if (mode = "throttle") {
            resourceState := {priorityClass: priorityClass, affinity: affinity, memoryPriority: memoryPriority
                , created: created, powerVersion: powerVersion, powerControlMask: powerControlMask, powerStateMask: powerStateMask}
            ApplyGameLowResourceMode(pid, resourceState, created)
        }
    }
    SaveFrozenProcesses()
}

; ============================================================================
; SMART SPLIT MOVE FUNCTION
; ============================================================================
; Shared by 666y and 666r â€” moves active window to target monitor and splits
; with any existing window there, placing them on opposite sides.

SmartSplitMove(target) {
    pair := GetPhysicalMonitorPair()
    targetMon := (target = "primary") ? pair["primary"] : pair["secondary"]
    if !targetMon {
        ToolTip(target = "primary" ? "Main physical monitor not detected" : "Only 1 connected physical monitor detected")
        SetTimer(() => ToolTip(), -1800)
        return
    }

    try {
        activeHwnd := WinGetID("A")
    } catch {
        activeHwnd := 0
    }
    if (!activeHwnd) {
        ToolTip("No active window to move")
        SetTimer(() => ToolTip(), -1500)
        return
    }

    ; Get target monitor work area
    MonitorGetWorkArea(targetMon, &mLeft, &mTop, &mRight, &mBottom)
    mWidth := mRight - mLeft
    mHeight := mBottom - mTop
    halfWidth := mWidth // 2

    ; Find topmost window already on target monitor (excluding active window)
    windowsByMon := EnumerateWindowsByMonitor()
    targetWindows := windowsByMon[targetMon]
    partnerHwnd := 0
    for hw in targetWindows {
        if (hw != activeHwnd) {
            partnerHwnd := hw
            break
        }
    }

    if (!partnerHwnd) {
        ; No partner â€” just move active to left half
        WinRestore("ahk_id " activeHwnd)
        Sleep(50)
        WinMove(mLeft, mTop, halfWidth, mHeight, "ahk_id " activeHwnd)
        ToolTip("Moved to monitor " targetMon " (left half)")
        SetTimer(() => ToolTip(), -1500)
        return
    }

    ; === KEY FIX: Read partner position BEFORE restoring ===
    ; WinRestore unsnaps windows, destroying their snap position.
    ; We must read coordinates while still snapped.
    try {
        WinGetPos(&pX, &pY, &pW, &pH, "ahk_id " partnerHwnd)
    } catch {
        pX := mLeft
        pW := mWidth
    }

    ; Calculate where partner's center is RELATIVE to monitor left edge
    ; This makes it independent of absolute screen coordinates
    relCenterX := (pX - mLeft) + (pW // 2)
    monHalfWidth := mWidth // 2

    ; Debug disabled

    ; Determine: is the partner in the left or right half?
    ; If partner is wide (>75% of monitor), treat as fullscreen â†’ put it left
    if (pW > mWidth * 0.75) {
        ; Partner is maximized/fullscreen â†’ force it LEFT, new window RIGHT
        WinRestore("ahk_id " partnerHwnd)
        Sleep(50)
        WinMove(mLeft, mTop, halfWidth, mHeight, "ahk_id " partnerHwnd)
        WinRestore("ahk_id " activeHwnd)
        Sleep(50)
        WinMove(mLeft + halfWidth, mTop, halfWidth, mHeight, "ahk_id " activeHwnd)
    } else if (relCenterX < monHalfWidth) {
        ; Partner is in LEFT half â†’ keep partner LEFT, new window RIGHT
        WinRestore("ahk_id " partnerHwnd)
        Sleep(50)
        WinMove(mLeft, mTop, halfWidth, mHeight, "ahk_id " partnerHwnd)
        WinRestore("ahk_id " activeHwnd)
        Sleep(50)
        WinMove(mLeft + halfWidth, mTop, halfWidth, mHeight, "ahk_id " activeHwnd)
    } else {
        ; Partner is in RIGHT half â†’ keep partner RIGHT, new window LEFT
        WinRestore("ahk_id " partnerHwnd)
        Sleep(50)
        WinMove(mLeft + halfWidth, mTop, halfWidth, mHeight, "ahk_id " partnerHwnd)
        WinRestore("ahk_id " activeHwnd)
        Sleep(50)
        WinMove(mLeft, mTop, halfWidth, mHeight, "ahk_id " activeHwnd)
    }

    label := (target = "primary") ? "primary" : "secondary"
    ToolTip("Split on " label " monitor")
    SetTimer(() => ToolTip(), -1500)
}

; ============================================================================
; SMART THREE-WAY SPLIT FUNCTION
; ============================================================================
; Shared by 555t and 555y â€” moves active window to target monitor and splits
; 3 windows into thirds. Finds the empty third and places new window there.

SmartThreeWaySplit(target) {
    pair := GetPhysicalMonitorPair()
    targetMon := (target = "primary") ? pair["primary"] : pair["secondary"]
    if !targetMon {
        ToolTip(target = "primary" ? "Main physical monitor not detected" : "Only 1 connected physical monitor detected")
        SetTimer(() => ToolTip(), -1800)
        return
    }

    try {
        activeHwnd := WinGetID("A")
    } catch {
        activeHwnd := 0
    }
    if (!activeHwnd) {
        ToolTip("No active window to move")
        SetTimer(() => ToolTip(), -1500)
        return
    }

    ; Get target monitor work area
    MonitorGetWorkArea(targetMon, &mLeft, &mTop, &mRight, &mBottom)
    mWidth := mRight - mLeft
    mHeight := mBottom - mTop
    thirdWidth := mWidth // 3

    ; Find top 2 windows already on target monitor (excluding active window)
    windowsByMon := EnumerateWindowsByMonitor()
    targetWindows := windowsByMon[targetMon]
    partners := []
    for hw in targetWindows {
        if (hw != activeHwnd) {
            partners.Push(hw)
            if (partners.Length >= 2)
                break
        }
    }

    if (partners.Length < 2) {
        ToolTip("Need at least 2 windows on target monitor for 3-way split (found " partners.Length ")")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    ; Read positions of both partners BEFORE any restore
    ; Determine which thirds are occupied
    ; Thirds: LEFT = mLeft to mLeft+thirdWidth, MIDDLE = +thirdWidth to +2*thirdWidth, RIGHT = +2*thirdWidth to end
    occupiedThirds := [false, false, false]  ; [left, middle, right]
    partnerThirds := [0, 0]  ; which third each partner is in (1=left, 2=mid, 3=right)

    Loop 2 {
        try {
            WinGetPos(&pX, &pY, &pW, &pH, "ahk_id " partners[A_Index])
            relCenter := (pX - mLeft) + (pW // 2)
            if (relCenter < thirdWidth) {
                occupiedThirds[1] := true
                partnerThirds[A_Index] := 1
            } else if (relCenter < thirdWidth * 2) {
                occupiedThirds[2] := true
                partnerThirds[A_Index] := 2
            } else {
                occupiedThirds[3] := true
                partnerThirds[A_Index] := 3
            }
        }
    }

    ; Find the empty third for the new window
    emptyThird := 0
    if (!occupiedThirds[1])
        emptyThird := 1
    else if (!occupiedThirds[2])
        emptyThird := 2
    else if (!occupiedThirds[3])
        emptyThird := 3
    else
        emptyThird := 3  ; fallback: rightmost

    ; Place partner 1 in its detected third (snapped properly)
    WinRestore("ahk_id " partners[1])
    Sleep(50)
    WinMove(mLeft + (thirdWidth * (partnerThirds[1] - 1)), mTop, thirdWidth, mHeight, "ahk_id " partners[1])

    ; Place partner 2 in its detected third
    WinRestore("ahk_id " partners[2])
    Sleep(50)
    WinMove(mLeft + (thirdWidth * (partnerThirds[2] - 1)), mTop, thirdWidth, mHeight, "ahk_id " partners[2])

    ; Place active window in the empty third
    WinRestore("ahk_id " activeHwnd)
    Sleep(50)
    WinMove(mLeft + (thirdWidth * (emptyThird - 1)), mTop, thirdWidth, mHeight, "ahk_id " activeHwnd)

    label := (target = "primary") ? "primary" : "secondary"
    ToolTip("3-way split on " label " monitor")
    SetTimer(() => ToolTip(), -1500)
}

; ============================================================================
; FORCE TWO-WAY SPLIT FUNCTION
; ============================================================================
; Used by yyyy (primary) and 555y (secondary) â€” grabs the 2 most recently used
; windows from ANY monitor and force-moves them into left/right halves on target monitor.

ForceTwoWaySplit(target) {
    pair := GetPhysicalMonitorPair()
    targetMon := (target = "primary") ? pair["primary"] : pair["secondary"]
    if !targetMon {
        ToolTip(target = "primary" ? "Main physical monitor not detected" : "Only 1 connected physical monitor detected")
        SetTimer(() => ToolTip(), -1800)
        return
    }

    recentWindows := GetRecentWindows(2)

    if (recentWindows.Length < 2) {
        ToolTip("Need at least 2 app windows (found " recentWindows.Length ")")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    MonitorGetWorkArea(targetMon, &mLeft, &mTop, &mRight, &mBottom)
    mWidth := mRight - mLeft
    mHeight := mBottom - mTop
    halfWidth := mWidth // 2

    WinRestore("ahk_id " recentWindows[1])
    Sleep(30)
    WinMove(mLeft, mTop, halfWidth, mHeight, "ahk_id " recentWindows[1])

    WinRestore("ahk_id " recentWindows[2])
    Sleep(30)
    WinMove(mLeft + halfWidth, mTop, halfWidth, mHeight, "ahk_id " recentWindows[2])

    label := (target = "primary") ? "primary" : "secondary"
    ToolTip("2 windows split on " label " monitor")
    SetTimer(() => ToolTip(), -1500)
}

; ============================================================================
; FORCE THREE-WAY SPLIT FUNCTION
; ============================================================================
; Used by tttt (primary) and 555y (secondary) â€” grabs the 3 most recently used
; windows from ANY monitor and force-moves them into equal thirds on target monitor.

ForceThreeWaySplit(target) {
    pair := GetPhysicalMonitorPair()
    targetMon := (target = "primary") ? pair["primary"] : pair["secondary"]
    if !targetMon {
        ToolTip(target = "primary" ? "Main physical monitor not detected" : "Only 1 connected physical monitor detected")
        SetTimer(() => ToolTip(), -1800)
        return
    }

    ; Get 3 most recent windows from Z-order (any monitor)
    recentWindows := GetRecentWindows(3)

    if (recentWindows.Length < 3) {
        ToolTip("Need at least 3 app windows (found " recentWindows.Length ")")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    MonitorGetWorkArea(targetMon, &mLeft, &mTop, &mRight, &mBottom)
    mWidth := mRight - mLeft
    mHeight := mBottom - mTop
    thirdWidth := mWidth // 3

    ; Window 1 (most recent) â†’ LEFT third
    WinRestore("ahk_id " recentWindows[1])
    Sleep(30)
    WinMove(mLeft, mTop, thirdWidth, mHeight, "ahk_id " recentWindows[1])

    ; Window 2 â†’ MIDDLE third
    WinRestore("ahk_id " recentWindows[2])
    Sleep(30)
    WinMove(mLeft + thirdWidth, mTop, thirdWidth, mHeight, "ahk_id " recentWindows[2])

    ; Window 3 â†’ RIGHT third
    WinRestore("ahk_id " recentWindows[3])
    Sleep(30)
    WinMove(mLeft + (thirdWidth * 2), mTop, thirdWidth, mHeight, "ahk_id " recentWindows[3])

    label := (target = "primary") ? "primary" : "secondary"
    ToolTip("3 windows split on " label " monitor")
    SetTimer(() => ToolTip(), -1500)
}

; ============================================================================
; HOTSTRINGS - Type these anywhere to trigger actions
; ============================================================================

; ssstuck - Run the Windows servicing/process unstuck monitor
:*:ssstuck::
{
    Run('"F:\study\Windows\PowerShell\System\Maintenance\Servicing\Tools\unstuck-command\UnstuckCommandLauncher.exe"', , "Hide")
    ToolTip("unstuck-command launched")
    SetTimer(() => ToolTip(), -1500)
}

; mmon - Show monitor layout info (AHK index vs physical position)
; Use this anytime to instantly see which AHK monitor number = which physical screen
:*:mmon::
{
    monCount := MonitorGetCount()
    primaryMon := MonitorGetPrimary()
    pair := GetPhysicalMonitorPair()
    tvMonitor := FindTvMonitor()
    info := "=== MONITOR LAYOUT ===`n"
    Loop monCount {
        MonitorGet(A_Index, &mL, &mT, &mR, &mB)
        deviceInfo := GetMonitorDeviceInfo(A_Index)
        typeTag := IsVirtualMonitor(A_Index) ? "VIRTUAL" : "PHYSICAL"
        primaryTag := (A_Index = primaryMon) ? " MAIN" : ""
        info .= "AHK " A_Index " [" typeTag primaryTag "] "
            . deviceInfo["name"] " | " deviceInfo["adapter"]
            . " | X=" mL " W=" (mR - mL) "`n"
    }
    info .= "`nPhysical main: " pair["primary"]
        . "`nPhysical secondary: " (pair["secondary"] ? pair["secondary"] : "not connected")
        . "`nTV virtual: " (tvMonitor ? tvMonitor : "not active")
    MsgBox(info, "Monitor Layout", "T5")
}

; kkkk - Force kill the foreground application (no mercy)
~*k::
{
    TrackKkkkForceKill()
    ; Count distinct taps, not autorepeat events from holding K.
    KeyWait("k")
}

; yyyt - Open YouTube account chooser silently (no terminal window)
:*:yyyt::
{
    Run('powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "F:\backup\windowsapps\Credentials\youtube\login\a.ps1"', , "Hide")
}

; eeeeeee - Run MichRebootlessWindowsPerformanceMaximizer
:*:eeeeeee::
{
    OpenRebootlessPerformanceMaximizer()
}

; aboveit - Make current window always on top
:*:aboveit::
{
    hwnd := WinGetID("A")
    if (hwnd) {
        WinSetAlwaysOnTop(1, "ahk_id " hwnd)
        ToolTip("Window set to Always On Top")
        SetTimer(() => ToolTip(), -1500)
    }
}

; downit - Remove always on top from current window
:*:downit::
{
    hwnd := WinGetID("A")
    if (hwnd) {
        WinSetAlwaysOnTop(0, "ahk_id " hwnd)
        ToolTip("Always On Top removed")
        SetTimer(() => ToolTip(), -1500)
    }
}

; rroll - Open RollBack Rx Home
:*:rroll::
{
    Run('"C:\ProgramData\Microsoft\Windows\Start Menu\Programs\RollBack Rx Home\RollBack Rx Home.lnk"')
}

; allit - Open Everything search
:*:allit::
{
    OpenEverything()
}

; ddownloads - Open Downloads folder
:*:ddownloads::
{
    Run("explorer.exe shell:Downloads")
}

; rrer - Open a new Windows Terminal tab using its configured default profile
:*:rrer::
{
    OpenAdminDefaultTerminal()
}

; DDDDD - Open Daymark
:*:ddddd::
{
    OpenDaymark()
}

; pplex - Immediately open Plex Media Server without a terminal
:*:pplex::
{
    RunApplication("F:\backup\windowsapps\installed\plex\Plex Media Server.exe")
}

; ddrivers - Open every driver vendor app, Device Manager, SDIO, and Windows Update
:*:ddrivers::
{
    OpenDriverTools()
}

; mmmute - Mute the default CoreAudio capture endpoint
:*:mmmute::
{
    MuteDefaultMicrophone()
}

; uunmute - Restore the saved default CoreAudio capture level
:*:uunmute::
{
    UnmuteDefaultMicrophone()
}

; mmute - Mute the app owning the current foreground window
:*:mmute::
{
    SetForegroundAppMute(1, "mmute")
}

; unmute - Unmute the app owning the current foreground window
:*:unmute::
{
    SetForegroundAppMute(0, "unmute")
}

; xccc - Open Google Chrome
:*:xccc::
{
    OpenOrForegroundApplication("C:\Program Files\Google\Chrome\Application\chrome.exe")
}

; ggmail - Open Gmail (account u/2) in Chrome profile 2
:*:ggmail::
{
    Run('"C:\Program Files\Google\Chrome\Application\chrome.exe" --profile-directory="Profile 2" "https://mail.google.com/mail/u/2/#inbox"')
}

; xccx - Open Chrome profile for michaelovsky55@gmail.com
:*:xccx::
{
    chromePath := "C:\Program Files\Google\Chrome\Application\chrome.exe"
    dir := ChromeProfileDirForEmail("michaelovsky55@gmail.com")
    if (dir = "") {
        ToolTip("xccx: no Chrome profile signed in as michaelovsky55@gmail.com")
        SetTimer(() => ToolTip(), -2500)
        return
    }
    Run('"' chromePath '" --profile-directory="' dir '"')
}

; ffff - Open Firefox (auto-find)
:*:ffff::
{
    OpenFirefox()
}

; mymail - Copy email to clipboard
:*:mymail::
{
    A_Clipboard := "michaelovsky5@gmail.com"
    ToolTip("Email copied to clipboard")
    SetTimer(() => ToolTip(), -1500)
}

; myp - Copy password to clipboard
:*:myp::
{
    A_Clipboard := "Blackablacka3!"
    ToolTip("Password copied to clipboard")
    SetTimer(() => ToolTip(), -1500)
}

; pym - Copy phone number to clipboard
:*:pym::
{
    A_Clipboard := "547632418"
    ToolTip("Phone number copied to clipboard")
    SetTimer(() => ToolTip(), -1500)
}

; toto - Open Todoist (UWP app launched via shell protocol)
:*:toto::
{
    Run('cmd /c start shell:AppsFolder\88449BC3.TodoistPlannerCalendarMSIX_71ef4824z52ta!BC3.TodoistPlannerCalendarMSIX', , "Hide")
}

; sslack - Open Slack (UWP app launched via shell protocol)
:*:sslack::
{
    Run('cmd /c start shell:AppsFolder\91750D7E.Slack_8she8kybcnzg4!Slack', , "Hide")
}

; pass - Copy password to clipboard
:*:pass::
{
    A_Clipboard := "Aa1111111!"
    ToolTip("Password copied to clipboard")
    SetTimer(() => ToolTip(), -1500)
}

; yyyy - Take 2 most recently used windows and split into halves on PRIMARY monitor
:*:yyyy::
{
    ForceTwoWaySplit("primary")
}

; tttt - Take the 3 most recently used windows (Z-order) and split into thirds on PRIMARY monitor
:*:tttt::
{
    ForceThreeWaySplit("primary")
}

; 555y hotstring is defined elsewhere â€” uses SmartThreeWaySplit for moving+splitting

; 666y - Move active window to SECONDARY monitor, smart-split with existing window
; Detects which side existing window is on and places new window on OPPOSITE side
:*:666y::
{
    SmartSplitMove("secondary")
}

; 555t - Take the 3 most recently used windows and split into thirds on SECONDARY monitor
:*:555t::
{
    ForceThreeWaySplit("secondary")
}

; 555y - Take 2 most recently used windows and split into halves on SECONDARY monitor
:*:555y::
{
    ForceTwoWaySplit("secondary")
}

; 666r - Move active window to PRIMARY monitor, smart-split with existing window
; Detects which side existing window is on and places new window on OPPOSITE side
:*:666r::
{
    SmartSplitMove("primary")
}

; asc - Open Advanced SystemCare
:*:asc::
{
    OpenOrForegroundApplication("C:\Program Files (x86)\IObit\Advanced SystemCare\ASC.exe")
}

; gggit - Open GitHub Desktop
:*:gggit::
{
    OpenOrForegroundApplication("C:\Users\micha\AppData\Local\GitHubDesktop\GitHubDesktop.exe")
}

; plaso - Open Process Lasso
:*:plaso::
{
    OpenProcessLasso()
}

; fbuff - Open Freebuff
:*:fbuff::
{
    OpenFreebuff()
}

; qqbit - Open qBittorrent
:*:qqbit::
{
    OpenOrForegroundApplication("C:\Program Files\qBittorrent\qbittorrent.exe")
}

; iinstalled - Open installed apps folder
:*:iinstalled::
{
    Run("explorer.exe F:\backup\windowsapps\installed")
}

; savegame - Open GameSave Manager
:*:savegame::
{
    OpenOrForegroundApplication("F:\backup\windowsapps\installed\gamesavemanager\gs_mngr_3.exe")
}

; ssave - Open and relaunch GameSave Manager
:*:ssave::
{
    ; Kill any running instance first
    try {
        ProcessClose("gs_mngr_3.exe")
        Sleep(1000)
    }
    Run('"F:\backup\windowsapps\installed\gamesavemanager\gs_mngr_3.exe"')
}

; rrram - Open RAM Monitor Pro
:*:rrram::
{
    OpenOrForegroundApplication("F:\study\Dev_Toolchain\programming\python\apps\RamManager\dist\RAM Monitor Pro\RAM Monitor Pro.exe")
}

; rrevo - Open Revo Uninstaller Pro
:*:rrevo::
{
    OpenOrForegroundApplication("C:\Program Files\VS Revo Group\Revo Uninstaller Pro\RevoUninPro.exe")
}

; ggggg - Open the native Game Library, or foreground its existing window
:*:ggggg::
{
    OpenGameLibraryManager()
}

; sstartup - Open Mich Startup Master, or foreground its existing window
:*:sstartup::
{
    OpenMichStartupMaster()
}

; sstart - Open Mich Startup Master, or foreground its existing window
:*:sstart::
{
    OpenMichStartupMaster()
}

; sspeed - Open OpenSpeedy, or force its window over everything including fullscreen games
:*:sspeed::
{
    OpenOrForegroundApplication("F:\backup\windowsapps\installed\OpenSpeedy\openspeedy.exe")
}

; zzcode - Open ZCode, or force its window over everything including fullscreen games
:*:zzcode::
{
    OpenOrForegroundApplication("F:\backup\windowsapps\installed\ZCode\ZCode.exe")
}

; mmed - Open the black cinema app in the default browser
:*:mmed::
{
    Run("https://black-cinema-app.vercel.app/")
}

; rrotate - Open Auto IP Changer, or force its window over everything including fullscreen games
:*:rrotate::
{
    OpenOrForegroundApplication("F:\study\projects\IpRotator\AutoIpChanger.exe")
}

; ssplit - Open Monitor Isolate, or force its window over everything including fullscreen games
:*:ssplit::
{
    OpenOrForegroundApplication("F:\study\Windows\Applications\PowerShell\Automation\OpenCode\Scripts\starnet\monitor-isolate\dist\MonitorIsolate.exe")
}

; sskill <appname> - Kill everything related to the app via the profile skill function
; Type sskill, then the app name (e.g. chrome), then Enter - the trigger waits
; up to two minutes for you to type it, showing what it captured live. Kept
; keystrokes are swallowed so nothing leaks into whatever window has focus;
; Esc cancels. Reuses the user's own `skill` profile function so process
; matching, services, scheduled tasks, disk images, descendant trees, and the
; elevated retry behave identically - fully hidden, no visible terminal - and
; the tooltip reports how many items were closed.
:*:sskill::
{
    ih := InputHook("T120", "{Enter}{Esc}")
    echo := () => ToolTip("sskill: " ih.Input "   [Enter = force kill  |  Esc = cancel]")
    SetTimer(echo, 100)
    ih.Start()
    ih.Wait()
    SetTimer(echo, 0)
    if (ih.EndReason = "EndKey" && ih.EndKey = "Esc") {
        ToolTip("sskill cancelled")
        SetTimer(() => ToolTip(), -1500)
        return
    }
    if (ih.EndReason != "EndKey") {
        ToolTip()
        return
    }
    targets := Trim(ih.Input)
    if (targets = "") {
        ToolTip("sskill: nothing typed - type an app name after sskill, then Enter")
        SetTimer(() => ToolTip(), -3000)
        return
    }
    tokens := []
    for token in StrSplit(targets, [" ", A_Tab]) {
        if (token != "")
            tokens.Push(token)
    }
    manifest := EnvGet("USERPROFILE") "\Documents\WindowsPowerShell\Modules\CodexProfileFunctions\CodexProfileFunctions.psd1"
    if !FileExist(manifest) {
        ToolTip("sskill: CodexProfileFunctions module not found")
        SetTimer(() => ToolTip(), -3000)
        return
    }
    quotedList := ""
    for token in tokens {
        escaped := StrReplace(token, "'", "''")
        quotedList .= (quotedList = "" ? "" : ",") "'" escaped "'"
    }
    resultFile := A_Temp "\sskill-result-" A_TickCount ".txt"
    resultFileEscaped := StrReplace(resultFile, "'", "''")
    q := Chr(34)
    command := "Import-Module '" manifest "' -DisableNameChecking -Force"
        . "; Initialize-CodexProfileFunctions; $n = skill @(" quotedList ")"
        . "; Set-Content -LiteralPath '" resultFileEscaped "' ([string]$n)"
    Run("powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command " q command q, , "Hide")
    ToolTip("sskill: force-killing everything for " targets " ...")
    deadline := A_TickCount + 20000
    while (A_TickCount < deadline && !FileExist(resultFile))
        Sleep(100)
    count := ""
    if FileExist(resultFile) {
        try count := Trim(FileRead(resultFile))
        try FileDelete(resultFile)
    }
    if (count != "")
        ToolTip("sskill: killed " targets " - closed " count " item(s)")
    else
        ToolTip("sskill: kill running for " targets " (an elevated pass may need your UAC click)")
    SetTimer(() => ToolTip(), -4000)
}

; ss2t - Force-close OpenWhispr and reopen it
:*:ss2t::
{
    RestartOpenWhispr()
}

; oobsi - Open Obsidian
:*:oobsi::
{
    OpenOrForegroundApplication("C:\Program Files\Obsidian\Obsidian.exe")
}

; wwsl - Open WSL terminal
:*:wwsl::
{
    Run('"C:\Program Files\WSL\wsl.exe"')
}

; gagaga - Open games folder
:*:gagaga::
{
    Run("explorer.exe E:\games")
}

; tetete - Open Telegram app
:*:tetete::
{
    Run("tg://")
}

; ============================================================================
; PARAGON HARD DISK MANAGER AUTOMATION
; ============================================================================
; Type "ppppp" to run FULL automation including restart
; âš ï¸ WARNING: This WILL restart your computer!
; ============================================================================

; Global variable for Paragon Python script path and executable
global ParagonPythonExe := "C:\Users\micha\AppData\Local\Programs\Python\Python312\python.exe"
global ParagonPythonScript := "C:\Users\micha\.openclaw\workspace-openclaw-main\paragon_complete.py"
global ParagonExePath := "F:\backup\windowsapps\installed\Fit Launcher\fixers\Paragon Software\Hard Disk Manager 17 Business\program\hdm17.exe"
global ParagonWindowTitlePart := "Paragon Hard Disk Manager"

; ppppp - Run complete Paragon disk check automation (WILL RESTART COMPUTER!)
:*:ppppp::
{
    global ParagonPythonExe, ParagonPythonScript, ParagonExePath

    ; Show warning tooltip
    ToolTip("Starting Paragon automation - Computer will restart!")
    SetTimer(() => ToolTip(), -3000)

    try {
        if (!FileExist(ParagonExePath))
            throw Error("Paragon EXE not found: " ParagonExePath)

        Run('"' ParagonExePath '"', , , &paragonPid)

        if (!ProcessWait(paragonPid, 15))
            throw Error("Paragon process did not start in time.")

        ToolTip("Waiting for Paragon to fully load before automation...")
        SetTimer(() => ToolTip(), -5000)

        paragonHwnd := WaitForParagonReady(paragonPid)

        try WinActivate("ahk_id " paragonHwnd)

        if (!FileExist(ParagonPythonExe))
            throw Error("Paragon Python EXE not found: " ParagonPythonExe)
        if (!FileExist(ParagonPythonScript))
            throw Error("Paragon automation script not found: " ParagonPythonScript)

        ; Run the complete Python automation script only after Paragon is actually ready.
        ToolTip("Paragon loaded - starting automation...")
        SetTimer(() => ToolTip(), -3000)
        RunWait('"' ParagonPythonExe '" "' ParagonPythonScript '"')

        ; If we get here, automation completed (computer restarting)
        ToolTip("Paragon complete - Computer restarting...")
        SetTimer(() => ToolTip(), -2000)
    } catch as err {
        ToolTip("Error: " err.Message)
        SetTimer(() => ToolTip(), -3000)
    }
}

WaitForParagonReady(pid, timeoutMs := 180000, stablePollsRequired := 4, pollMs := 500) {
    global ParagonWindowTitlePart

    deadline := A_TickCount + timeoutMs
    stablePolls := 0
    lastHwnd := 0
    lastTitle := ""

    while (A_TickCount < deadline) {
        if (!ProcessExist(pid))
            throw Error("Paragon closed before it finished loading.")

        hwnd := WinExist("ahk_pid " pid)
        if (hwnd && IsParagonWindowReady(hwnd, ParagonWindowTitlePart)) {
            title := WinGetTitle("ahk_id " hwnd)
            if (hwnd = lastHwnd && title = lastTitle) {
                stablePolls++
            } else {
                stablePolls := 1
                lastHwnd := hwnd
                lastTitle := title
            }

            if (stablePolls >= stablePollsRequired)
                return hwnd
        } else {
            stablePolls := 0
            lastHwnd := 0
            lastTitle := ""
        }

        Sleep(pollMs)
    }

    throw Error("Timed out waiting for Paragon to fully load.")
}

IsParagonWindowReady(hwnd, expectedTitlePart := "") {
    if (!hwnd || !WinExist("ahk_id " hwnd))
        return false

    try {
        title := WinGetTitle("ahk_id " hwnd)
        if (expectedTitlePart != "" && !InStr(title, expectedTitlePart))
            return false

        if (WinGetMinMax("ahk_id " hwnd) = -1)
            return false

        style := WinGetStyle("ahk_id " hwnd)
        if !(style & 0x10000000)
            return false

        if !DllCall("user32\IsWindowEnabled", "ptr", hwnd, "int")
            return false

        if DllCall("user32\IsHungAppWindow", "ptr", hwnd, "int")
            return false
    } catch {
        return false
    }

    return true
}

; ============================================================================
; HELPER FUNCTIONS
; ============================================================================

; Helper function to get recent windows (excluding desktop, taskbar, etc.)
GetRecentWindows(count) {
    windows := []
    excludeList := ["Program Manager", "Windows Input Experience", ""]

    for hwnd in WinGetList() {
        if (windows.Length >= count)
            break

        try {
            title := WinGetTitle("ahk_id " hwnd)
            winClass := WinGetClass("ahk_id " hwnd)
            style := WinGetStyle("ahk_id " hwnd)

            ; Skip empty titles and non-visible windows
            if (title = "" || !(style & 0x10000000))  ; WS_VISIBLE
                continue

            ; Skip taskbar, system tray, etc.
            if (winClass = "Shell_TrayWnd" || winClass = "Shell_SecondaryTrayWnd" || winClass = "Progman")
                continue

            ; Skip windows without caption bar (likely not app windows)
            if !(style & 0xC00000)  ; WS_CAPTION
                continue

            for exclude in excludeList {
                if (title = exclude)
                    continue 2
            }

            windows.Push(hwnd)
        }
    }
    return windows
}

; Hotstring: nnvid -> Open NVIDIA App
:*:nnvid::
{
    Run('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'
        A_ScriptDir '\Open-NvidiaAppSafely.ps1"', A_ScriptDir, "Hide")
}

; Hotstring: rryz -> Open AMD Ryzen Master
:*:rryz::
{
    Run("C:\Program Files\AMD\RyzenMaster\bin\AMD Ryzen Master.exe")
}

; Hotstring: aamd -> Open AMD Ryzen Master
:*:aamd::
{
    OpenOrForegroundApplication("C:\Program Files\AMD\RyzenMaster\bin\AMD Ryzen Master.exe")
}


; ============================================================================
; CUSTOM COMMANDS - Added by OpenClaw
; ============================================================================

; ddock - Run Docker kill script
:*:ddock::
{
    Run('powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "F:\study\containers\docker\scripts\dkill\dkill.ps1"', , "Hide")
}

; rref - Open Macrium Reflect (requires ending character so rreflect can also work)
::rref::
{
    OpenOrForegroundApplication("F:\backup\windowsapps\installed\Reflect\Reflect.exe")
}

; rreflect - Open Macrium Reflect
:*:rreflect::
{
    OpenOrForegroundApplication("F:\backup\windowsapps\installed\Reflect\Reflect.exe")
}

; mmacback - Run Macrium backup
:*:mmacback::
{
    Run('powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Windows\Temp\macback.ps1"', , "Hide")
    ToolTip("Macrium backup started")
    SetTimer(() => ToolTip(), -2000)
}

; rrmackback - Cleanup Macrium backups
:*:rrmackback::
{
    Run('powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "F:\study\Devops\backup\MacriumReflect\DisableGuardPurgeBackups\CleanupBackups.ps1"', , "Hide")
    ToolTip("Macrium cleanup started")
    SetTimer(() => ToolTip(), -2000)
}

; ggcc - Open GIGABYTE Control Center
:*:ggcc::
{
    OpenOrForegroundApplication("C:\Program Files\GIGABYTE\Control Center\GCC.exe")
}

; lockit - Lock workstation
:*:lockit::
{
    DllCall("LockWorkStation")
}

; bbin - Empty Recycle Bin
:*:bbin::
{
    Run('powershell.exe -WindowStyle Hidden -Command "Clear-RecycleBin -Force -ErrorAction SilentlyContinue"', , "Hide")
    ToolTip("Recycle Bin emptied")
    SetTimer(() => ToolTip(), -2000)
}

; mmin - Minimize all windows except active one
:*:mmin::
{
    activeHwnd := WinGetID("A")
    for hwnd in WinGetList() {
        try {
            if (hwnd = activeHwnd)
                continue
            style := WinGetStyle("ahk_id " hwnd)
            if !(style & 0x10000000)
                continue
            title := WinGetTitle("ahk_id " hwnd)
            if (!title || title = "")
                continue
            winClass := WinGetClass("ahk_id " hwnd)
            if (winClass = "Shell_TrayWnd" || winClass = "Shell_SecondaryTrayWnd" || winClass = "Progman" || winClass = "WorkerW")
                continue
            WinMinimize("ahk_id " hwnd)
        }
    }
    ToolTip("All minimized except active")
    SetTimer(() => ToolTip(), -1500)
}

; ccdclaw - Open .openclaw folder
:*:ccdclaw::
{
    Run('explorer.exe "C:\Users\micha\.openclaw"')
}

; rregate - Restart OpenClaw gateway (kill port 18789 + relaunch VBS)
:*:rregate::
{
    Run('powershell.exe -Version 5 -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Windows\Temp\regate.ps1"', , "Hide")
    ToolTip("Gateway restarting...")
    SetTimer(() => ToolTip(), -3000)
}

; ============================================================================
; FOLDER NAVIGATION - Auto-generated by OpenClaw
; ============================================================================

; sstudy - Open F:\study
:*:sstudy::
{
    Run('explorer.exe "F:\study"')
}

; bbackup - Open F:\backup
:*:bbackup::
{
    Run('explorer.exe "F:\backup"')
}

; wwin11recovery - Open F:\win11recovery
:*:wwin11recovery::
{
    Run('explorer.exe "F:\win11recovery"')
}

; ttovtech - Open F:\tovtech
:*:ttovtech::
{
    Run('explorer.exe "F:\tovtech"')
}

; aaiml - Open F:\study\AI_ML
:*:aaiml::
{
    Run('explorer.exe "F:\study\AI_ML"')
}

; bbrowsers - Open F:\study\Browsers
:*:bbrowsers::
{
    Run('explorer.exe "F:\study\Browsers"')
}

; ccloud - Open F:\study\cloud
:*:ccloud::
{
    Run('explorer.exe "F:\study\cloud"')
}

; ccollaboration - Open F:\study\collaboration
:*:ccollaboration::
{
    Run('explorer.exe "F:\study\collaboration"')
}

; ccommunication - Open F:\study\communication
:*:ccommunication::
{
    Run('explorer.exe "F:\study\communication"')
}

; ccontainers - Open F:\study\Containers
:*:ccontainers::
{
    Run('explorer.exe "F:\study\Containers"')
}

; ddatabases - Open F:\study\Databases
:*:ddatabases::
{
    Run('explorer.exe "F:\study\Databases"')
}

; ddevops - Open F:\study\Devops
:*:ddevops::
{
    Run('explorer.exe "F:\study\Devops"')
}

; ddevtoolchain - Open F:\study\Dev_Toolchain
:*:ddevtoolchain::
{
    Run('explorer.exe "F:\study\Dev_Toolchain"')
}

; ddistributedsystems - Open F:\study\Distributed_Systems
:*:ddistributedsystems::
{
    Run('explorer.exe "F:\study\Distributed_Systems"')
}

; ddocuments - Open F:\study\documents
:*:ddocuments::
{
    Run('explorer.exe "F:\study\documents"')
}

; eenterpriseapps - Open F:\study\Enterprise_Apps
:*:eenterpriseapps::
{
    Run('explorer.exe "F:\study\Enterprise_Apps"')
}

; eexams - Open F:\study\exams
:*:eexams::
{
    Run('explorer.exe "F:\study\exams"')
}

; mmediaworkflow - Open F:\study\Media_Workflow
:*:mmediaworkflow::
{
    Run('explorer.exe "F:\study\Media_Workflow"')
}

; hhosting - Open F:\study\hosting
:*:hhosting::
{
    Run('explorer.exe "F:\study\hosting"')
}

; mmonitoring - Open F:\study\monitoring
:*:mmonitoring::
{
    Run('explorer.exe "F:\study\monitoring"')
}

; mmobiledev - Open F:\study\mobile_dev
:*:mmobiledev::
{
    Run('explorer.exe "F:\study\mobile_dev"')
}

; mmemorymanagement - Open F:\study\memory_management
:*:mmemorymanagement::
{
    Run('explorer.exe "F:\study\memory_management"')
}

; nnetworking - Open F:\study\networking
:*:nnetworking::
{
    Run('explorer.exe "F:\study\networking"')
}

; oobservability - Open F:\study\Observability
:*:oobservability::
{
    Run('explorer.exe "F:\study\Observability"')
}

; pplatforms - Open F:\study\Platforms
:*:pplatforms::
{
    Run('explorer.exe "F:\study\Platforms"')
}

; ssecurity - Open F:\study\security
:*:ssecurity::
{
    Run('explorer.exe "F:\study\security"')
}

; sservicemeshorchestration - Open F:\study\Service_Mesh_Orchestration
:*:sservicemeshorchestration::
{
    Run('explorer.exe "F:\study\Service_Mesh_Orchestration"')
}

; pprojects - Open F:\study\projects
:*:pprojects::
{
    Run('explorer.exe "F:\study\projects"')
}

; rresume - Open F:\study\resume
:*:rresume::
{
    Run('explorer.exe "F:\study\resume"')
}

; sshells - Open F:\study\Shells
:*:sshells::
{
    Run('explorer.exe "F:\study\Shells"')
}

; sstorageandfilesystems - Open F:\study\Storage_and_Filesystems
:*:sstorageandfilesystems::
{
    Run('explorer.exe "F:\study\Storage_and_Filesystems"')
}

; ssetups - Open F:\study\setups
:*:ssetups::
{
    Run('explorer.exe "F:\study\setups"')
}

; ssystemsvirtualization - Open F:\study\Systems_Virtualization
:*:ssystemsvirtualization::
{
    Run('explorer.exe "F:\study\Systems_Virtualization"')
}

; ttravel - Open F:\study\Travel
:*:ttravel::
{
    Run('explorer.exe "F:\study\Travel"')
}

; vversioncontrol - Open F:\study\Version_control
:*:vversioncontrol::
{
    Run('explorer.exe "F:\study\Version_control"')
}

; ttroubleshooting - Open F:\study\troubleshooting
:*:ttroubleshooting::
{
    Run('explorer.exe "F:\study\troubleshooting"')
}

; wwebbuilding - Open F:\study\WebBuilding
:*:wwebbuilding::
{
    Run('explorer.exe "F:\study\WebBuilding"')
}

; wwindows - Open F:\study\Platforms\windows
:*:wwindows::
{
    Run('explorer.exe "F:\study\Platforms\windows"')
}

; llinux - Open F:\study\Platforms\linux
:*:llinux::
{
    Run('explorer.exe "F:\study\Platforms\linux"')
}

; aandroid - Open F:\study\Platforms\Android
:*:aandroid::
{
    Run('explorer.exe "F:\study\Platforms\Android"')
}

; pprogramming - Open F:\study\Dev_Toolchain\programming
:*:pprogramming::
{
    Run('explorer.exe "F:\study\Dev_Toolchain\programming"')
}

; ddocker - Open F:\study\Containers\docker
:*:ddocker::
{
    Run('explorer.exe "F:\study\Containers\docker"')
}

; ccisco - Open F:\study\networking\Cisco
:*:ccisco::
{
    Run('explorer.exe "F:\study\networking\Cisco"')
}

; vvpn - Open F:\study\networking\VPN
:*:vvpn::
{
    Run('explorer.exe "F:\study\networking\VPN"')
}

; bbash - Open F:\study\Shells\bash
:*:bbash::
{
    Run('explorer.exe "F:\study\Shells\bash"')
}

; ppowershell - Open F:\study\Shells\powershell
:*:ppowershell::
{
    Run('explorer.exe "F:\study\Shells\powershell"')
}

; zzsh - Open F:\study\Shells\zsh
:*:zzsh::
{
    Run('explorer.exe "F:\study\Shells\zsh"')
}

; ggit - Open F:\study\Version_control\git
:*:ggit::
{
    Run('explorer.exe "F:\study\Version_control\git"')
}

; ggithub - Open F:\study\Version_control\github
:*:ggithub::
{
    Run('explorer.exe "F:\study\Version_control\github"')
}

; vvirtualmachines - Open F:\study\Systems_Virtualization\virtualmachines
:*:vvirtualmachines::
{
    Run('explorer.exe "F:\study\Systems_Virtualization\virtualmachines"')
}

; rremote - Open F:\study\Systems_Virtualization\Remote
:*:rremote::
{
    Run('explorer.exe "F:\study\Systems_Virtualization\Remote"')
}

; yyoutube - Open F:\study\hosting\youtube
:*:yyoutube::
{
    Run('explorer.exe "F:\study\hosting\youtube"')
}

; ttunneling - Open F:\study\hosting\tunneling
:*:ttunneling::
{
    Run('explorer.exe "F:\study\hosting\tunneling"')
}

; wwebhosting - Open F:\study\hosting\WebHosting
:*:wwebhosting::
{
    Run('explorer.exe "F:\study\hosting\WebHosting"')
}

; nnotifications - Open F:\study\Observability\notifications
:*:nnotifications::
{
    Run('explorer.exe "F:\study\Observability\notifications"')
}

; wwebdevelopment - Open F:\study\projects\Web_Development
:*:wwebdevelopment::
{
    Run('explorer.exe "F:\study\projects\Web_Development"')
}

; ddesktopapps - Open F:\study\projects\Desktop_Apps
:*:ddesktopapps::
{
    Run('explorer.exe "F:\study\projects\Desktop_Apps"')
}

; ddevopsinfrastructure - Open F:\study\projects\DevOps_Infrastructure
:*:ddevopsinfrastructure::
{
    Run('explorer.exe "F:\study\projects\DevOps_Infrastructure"')
}

; aautomationscripting - Open F:\study\projects\Automation_Scripting
:*:aautomationscripting::
{
    Run('explorer.exe "F:\study\projects\Automation_Scripting"')
}

; ssecuritytools - Open F:\study\projects\Security_Tools
:*:ssecuritytools::
{
    Run('explorer.exe "F:\study\projects\Security_Tools"')
}

; wwindowsapps - Open F:\backup\windowsapps
:*:wwindowsapps::
{
    Run('explorer.exe "F:\backup\windowsapps"')
}

; oobsidion - Open F:\backup\obsidion
:*:oobsidion::
{
    Run('explorer.exe "F:\backup\obsidion"')
}

; llocalai - Open F:\study\AI_ML\LocalAI
:*:llocalai::
{
    Run('explorer.exe "F:\study\AI_ML\LocalAI"')
}

; ggames - Open E:\games
:*:ggames::
{
    Run('explorer.exe "E:\games"')
}

; ggamesinstallers - Open E:\GamesInstallers
:*:ggamesinstallers::
{
    Run('explorer.exe "E:\GamesInstallers"')
}

; iisos - Open E:\isos
:*:iisos::
{
    Run('explorer.exe "E:\isos"')
}

; mmicha - Open C:\Users\micha
:*:mmicha::
{
    Run('explorer.exe "C:\Users\micha"')
}

; ddesktop - Open C:\Users\micha\Desktop
:*:ddesktop::
{
    Run('explorer.exe "C:\Users\micha\Desktop"')
}

; pprogramfiles - Open C:\Program Files
:*:pprogramfiles::
{
    Run('explorer.exe "C:\Program Files"')
}

; pprogramfilesx86 - Open C:\Program Files (x86)
:*:pprogramfilesx86::
{
    Run('explorer.exe "C:\Program Files (x86)"')
}

; mmsi - Open MSI Afterburner
:*:mmsi::
{
    OpenOrForegroundApplication("F:\backup\windowsapps\installed\MSI Afterburner\MSIAfterburner.exe")
}

; launchit - Force reload this AHK script (kills old instance and relaunches)
:*:launchit::
{
    Run('"' . A_AhkPath . '" "' . A_ScriptFullPath . '"')
    ExitApp()
}

RunTerminalProfileSequence(targetWin, profileScript := "F:\study\Devops\backup\backup\profile\profile.ps1", extraCommand := "")
{
    targetClass := WinGetClass(targetWin)
    targetExe := WinGetProcessName(targetWin)
    if !(targetExe = "WindowsTerminal.exe" || targetClass = "ConsoleWindowClass" || targetClass = "VirtualConsoleClass")
        return

    WinActivate(targetWin)
    if !WinWaitActive(targetWin, , 1)
        return

    Sleep(300)
    commandText := profileScript "`n"
    if (extraCommand != "")
        commandText .= extraCommand "`n"
    SendText(commandText)
}

CheckMcsPostRestoreMarker()
{
    markerPath := "F:\study\Windows\System\Recovery\Macrium\mcs-restore-automation\state\pending.flag"
    runnerPath := "F:\study\Windows\System\Recovery\Macrium\mcs-restore-automation\Invoke-McsRestore.ps1"
    ps5Path := "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"

    if !FileExist(markerPath)
        return

    markerTime := FileGetTime(markerPath, "M")
    bootTime := DateAdd(A_Now, -Floor(A_TickCount / 1000), "Seconds")
    if (markerTime >= bootTime)
        return

    markerText := ""
    try {
        markerText := FileRead(markerPath)
    } catch {
        markerText := ""
    }

    try {
        FileMove(markerPath, markerPath ".running-" A_Now, 1)
    } catch {
        return
    }

    if FileExist(runnerPath) && FileExist(ps5Path) {
        args := '"' ps5Path '" -NoProfile -ExecutionPolicy Bypass -File "' runnerPath '" -RunPostRestore'
        if InStr(markerText, "selftest=1")
            args .= " -SelfTestOnly"
        Run(args)
    }
}

; needhelp - Show every shortcut in a categorised, human-readable GUI
; Dynamically re-parses THIS FILE on every launch so it is always up to date
:*:needhelp::
{
    helpGui := 0
    scriptFile := A_ScriptFullPath

    ; ── Load all lines for lookahead ──────────────────────────────────────────
    allLines := []
    Loop Read, scriptFile
        allLines.Push(Trim(A_LoopReadLine))
    lineCount := allLines.Length

    ; ── Category buckets (ordered) ────────────────────────────────────────────
    ; Each value is an object with .title and .items array
    c_winmgmt  := {title: "WINDOW MANAGEMENT  (move · resize · split · freeze windows)", items: []}
    c_tap      := {title: "TAP GESTURES  (press the key N times rapidly)", items: []}
    c_app      := {title: "APP LAUNCHERS  (open applications)", items: []}
    c_explorer := {title: "FILE EXPLORER  (open folders)", items: []}
    c_clip     := {title: "CLIPBOARD  (instantly copy to clipboard)", items: []}
    c_system   := {title: "SYSTEM & TOOLS  (maintenance, backups, system ops)", items: []}
    c_danger   := {title: "DANGER ZONE  (destructive or irreversible actions)", items: []}
    catList    := [c_winmgmt, c_tap, c_app, c_explorer, c_clip, c_system, c_danger]

    ; ── Parse ─────────────────────────────────────────────────────────────────
    prevComment := ""
    i := 1
    while (i <= lineCount) {
        line := allLines[i]

        ; Collect the most recent comment line as description candidate
        if RegExMatch(line, "^;\s*(.+)$", &cm) {
            prevComment := cm[1]
            i++
            continue
        }

        ; ── Hotstrings  :*:trigger::
        if RegExMatch(line, "^:([^:]*):([^:]+)::$", &hm) {
            trigger := hm[2]
            raw     := (prevComment != "") ? prevComment : trigger
            desc    := NeedHelpCleanDesc(raw, trigger)
            NeedHelpCategorize(trigger, desc, c_winmgmt, c_app, c_explorer, c_clip, c_system, c_danger)
                .items.Push({key: trigger, desc: desc})
            prevComment := ""
            i++
            continue
        }

        ; ── Tap-Up gestures  ~Ctrl Up::  ~Alt Up::
        if RegExMatch(line, "^~(Ctrl|Alt)\s+Up::$", &tm) {
            ; Look ahead up to 20 lines for the repeat-count threshold
            tapN := "4"
            j := i + 1
            while (j <= Min(i + 20, lineCount)) {
                if RegExMatch(allLines[j], ">= (\d+)", &nm)
                    tapN := nm[1]
                j++
            }
            key  := tm[1] . " x" . tapN . " taps"
            desc := (prevComment != "") ? NeedHelpCleanDesc(prevComment, key) : "-"
            c_tap.items.Push({key: key, desc: desc})
            prevComment := ""
            i++
            continue
        }

        ; ── Counter-tap hotkeys  ~F9::  ~LShift::  ~RShift::
        if RegExMatch(line, "^~(F\d+|LShift|RShift)::$", &fm) {
            tapN := "6"
            j := i + 1
            while (j <= Min(i + 25, lineCount)) {
                if RegExMatch(allLines[j], ">= (\d+)", &nm)
                    tapN := nm[1]
                j++
            }
            key  := fm[1] . " x" . tapN . " taps"
            desc := (prevComment != "") ? NeedHelpCleanDesc(prevComment, key) : "-"
            c_tap.items.Push({key: key, desc: desc})
            prevComment := ""
            i++
            continue
        }

        ; ── Regular hotkeys  ^1::  #w::  !h::  ^SC029::
        if RegExMatch(line, "^([#\^!+~<>*]*(?:[A-Za-z][A-Za-z0-9_]*|[0-9]|F[0-9]+|SC[0-9A-Fa-f]+|Wheel(?:Up|Down)|XButton[12]))::$", &km) {
            raw := km[1]
            ; Skip bare shift lines (they are handled by counter-tap block above)
            if (raw = "~LShift" || raw = "~RShift") {
                prevComment := ""
                i++
                continue
            }
            key  := NeedHelpParseKey(raw)
            desc := (prevComment != "") ? NeedHelpCleanDesc(prevComment, key) : "-"
            c_winmgmt.items.Push({key: key, desc: desc})
            prevComment := ""
            i++
            continue
        }

        prevComment := ""
        i++
    }

    ; ── Build display text ────────────────────────────────────────────────────
    total    := 0
    fullText := ""
    for cat in catList {
        fullText .= NeedHelpSection(cat.title, cat.items)
        total += cat.items.Length
    }
    fullText .= "`n================================================================`n"
    fullText .= "  " . total . " shortcuts total     source: " . scriptFile . "`n"

    ; ── GUI ───────────────────────────────────────────────────────────────────
    helpGui := Gui("+Resize +MinSize820x500", "AHK Shortcuts Reference")
    helpGui.BackColor := "0F0F1A"

    helpGui.SetFont("s17 cE0AAFF Bold", "Consolas")
    helpGui.Add("Text", "x16 y10 w960", "  AHK Shortcuts Reference")

    helpGui.SetFont("s9 c5C5F7A", "Consolas")
    helpGui.Add("Text", "x16 y36 w960", "  Auto-parsed from current.ahk on every launch — always up to date")

    helpGui.SetFont("s10 cD4D4D4", "Consolas")
    helpEdit := helpGui.Add("Edit", "x8 y58 w984 h548 ReadOnly -E0x200 vMainEdit HScroll VScroll", fullText)
    helpEdit.Opt("Background1A1A2E")

    helpGui.SetFont("s11 cFF6B6B Bold", "Consolas")
    btn := helpGui.Add("Button", "x8 y616 w130 h36 Default", "  Close [Esc]")
    btn.OnEvent("Click", ObjBindMethod(helpGui, "Destroy"))

    helpGui.SetFont("s9 c4A4A6A", "Consolas")
    helpGui.Add("Text", "x148 y624 w700", "Ctrl+A then Ctrl+C inside the box to copy all shortcuts")

    helpGui.OnEvent("Close",  ObjBindMethod(helpGui, "Destroy"))
    helpGui.OnEvent("Escape", ObjBindMethod(helpGui, "Destroy"))
    helpGui.OnEvent("Size",   NeedHelpResize.Bind(helpEdit, btn))

    helpGui.Show("w1000 h660")
}

; ── needhelp top-level helpers ────────────────────────────────────────────────

; Parse modifier symbols into human-readable key name (no corruption bug)
NeedHelpParseKey(raw) {
    k    := StrReplace(raw, "~", "")
    mods := ""
    if InStr(k, "#") {
        mods .= "Win+"
        k := StrReplace(k, "#", "")
    }
    if InStr(k, "^") {
        mods .= "Ctrl+"
        k := StrReplace(k, "^", "")
    }
    if InStr(k, "!") {
        mods .= "Alt+"
        k := StrReplace(k, "!", "")
    }
    if InStr(k, "+") {
        mods .= "Shift+"
        k := StrReplace(k, "+", "")
    }
    k := StrReplace(k, "SC029", "` (backtick)")
    return mods . k
}

; Strip redundant trigger-name prefixes from raw comment text
NeedHelpCleanDesc(d, trigger := "") {
    ; Remove "trigger - " prefix  e.g. "kkkk - Force kill..."  -> "Force kill..."
    if (trigger != "")
        d := RegExReplace(d, "^\Q" . trigger . "\E\s*-\s*", "")
    ; Remove "Hotstring: xxxx -> " prefix
    d := RegExReplace(d, "^Hotstring:\s*\S+\s*->\s*", "")
    ; Remove leading hotkey pattern "Ctrl+x - "
    d := RegExReplace(d, "^(?:Ctrl|Alt|Win|Shift)\+\S+\s*-\s*", "")
    ; Remove section-header lines (all-caps + description)
    d := RegExReplace(d, "^[A-Z ]+$", "")
    return Trim(d) = "" ? "-" : Trim(d)
}

; Decide which category bucket an entry belongs to
NeedHelpCategorize(trigger, desc, c_winmgmt, c_app, c_explorer, c_clip, c_system, c_danger) {
    d := StrLower(desc)
    t := StrLower(trigger)
    ; Danger: reboot / kill / paragon
    if InStr(d, "reboot") || InStr(d, "restart") || InStr(d, "force kill")
        || InStr(d, "shutdown") || InStr(d, "paragon") || InStr(d, "will restart")
        return c_danger
    ; Clipboard
    if InStr(d, "clipboard") || InStr(d, "copy ") || InStr(d, "copied")
        return c_clip
    ; File Explorer (folder open)
    if RegExMatch(d, "open [a-z]:\\") || InStr(d, "open downloads") || InStr(d, "installed apps")
        return c_explorer
    ; Window management
    if InStr(d, "monitor") || InStr(d, "window") || InStr(d, "split") || InStr(d, "thirds")
        || InStr(d, "halves") || InStr(d, "maximiz") || InStr(d, "minimiz") || InStr(d, "fullscreen")
        || InStr(d, "always on top") || InStr(d, "freeze") || InStr(d, "unfreeze") || InStr(d, "focus")
        || InStr(d, "restore") || InStr(d, "swap") || InStr(d, "recycle bin")
        return c_winmgmt
    ; System/tools
    if InStr(d, "backup") || InStr(d, "cleanup") || InStr(d, "lock workstation") || InStr(d, "docker")
        || InStr(d, "macrium") || InStr(d, "gateway") || InStr(d, "openclaw")
        || InStr(d, "purge") || InStr(d, "terminal") || InStr(d, "wsl") || InStr(d, "disk")
        || InStr(d, "empty recycle")
        return c_system
    ; Default: app launcher
    return c_app
}

; Build one category section block
NeedHelpSection(title, items) {
    bar := "================================================================"
    out := "`n" . bar . "`n  " . title . "`n" . bar . "`n"
    if (items.Length = 0)
        return out . "  (none)`n"
    for item in items {
        k   := item.key
        pad := Max(1, 32 - StrLen(k))
        sp  := ""
        Loop pad
            sp .= " "
        out .= "  " . k . sp . item.desc . "`n"
    }
    return out
}

; Resize callback — keeps the edit control filling the window
NeedHelpResize(editCtrl, btnCtrl, gObj, minMax, w, h) {
    if (minMax = -1)
        return
    editCtrl.Move(, , w - 16, h - 112)
    btnCtrl.Move(, h - 48)
}

; ============================================================================
; F9 x8 or hold 5s SAFE FORCE REBOOT
; Press F9 eight times within five seconds, or hold it for five seconds, to trigger an immediate safe force reboot
; ============================================================================
F9PressCount := 0
F9HoldStartTick := 0
F9HoldThresholdMs := 5000
F9IsDown := false
F9HoldTriggered := false
F9LogFile := A_Temp "\current-ahk-f9.log"
F9DryRunFlagFile := A_Temp "\current-ahk-f9-dry-run.flag"

F9Log(message) {
    global F9LogFile, F9DryRunFlagFile
    if !FileExist(F9DryRunFlagFile)
        return
    try FileAppend(A_Now " | " message "`n", F9LogFile)
}

F9ResetTimer() {
    global F9PressCount
    F9PressCount := 0
    F9Log("reset")
}

F9TriggerAction(reason) {
    global F9PressCount, F9DryRunFlagFile, F9HoldTriggered
    F9PressCount := 0
    F9HoldTriggered := true
    SetTimer(F9ResetTimer, 0)
    SetTimer(F9CheckHold, 0)
    if FileExist(F9DryRunFlagFile) {
        F9Log("trigger dry-run via " reason)
        return
    }
    F9Log("trigger reboot via " reason)
    try Shutdown 6
    catch
        Run(A_WinDir "\System32\shutdown.exe /r /f /t 0", , "Hide")
}

F9CheckHold() {
    global F9IsDown, F9HoldStartTick, F9HoldThresholdMs, F9HoldTriggered
    if (!F9IsDown || F9HoldTriggered || !GetKeyState("F9", "P"))
        return
    holdMs := F9HoldStartTick ? (A_TickCount - F9HoldStartTick) : F9HoldThresholdMs
    F9Log("hold ms=" holdMs)
    F9TriggerAction("hold")
}

; Force reboot the PC immediately (no confirmation, no delay)
~F9::
{
    global F9PressCount, F9HoldStartTick, F9HoldThresholdMs, F9IsDown, F9HoldTriggered
    if F9IsDown
        return
    F9IsDown := true
    F9HoldTriggered := false
    F9HoldStartTick := A_TickCount
    F9PressCount++
    F9Log("press count=" F9PressCount)
    SetTimer(F9ResetTimer, -5000)
    SetTimer(F9CheckHold, -F9HoldThresholdMs)
    if (F9PressCount >= 8) {
        F9TriggerAction("tap")
        return
    }
}

~F9 Up::
{
    global F9HoldStartTick, F9IsDown, F9HoldTriggered
    F9HoldStartTick := 0
    F9HoldTriggered := false
    F9IsDown := false
}


; ============================================================================
; xccx helper - resolve the Chrome profile directory signed in with an email
; ============================================================================
; Reads Chrome Local State on every call so it stays correct even if the
; profile folder is renamed or renumbered by Chrome later.
ChromeProfileDirForEmail(email) {
    localState := EnvGet("LOCALAPPDATA") "\Google\Chrome\User Data\Local State"
    if !FileExist(localState)
        return ""
    try {
        text := FileRead(localState)
    } catch {
        return ""
    }
    needle := '"user_name":"' email '"'
    pos := InStr(text, needle)
    if (pos = 0)
        return ""
    head := SubStr(text, 1, pos - 1)
    if RegExMatch(head, '(?s).*"(Default|Profile ?\d*)"\s*:\s*\{', &m)
        return m[1]
    return ""
}

; ============================================================================
; CTRL+WIN DICTATION TRIGGER GUARD
; OpenWhispr watches its Control+Super hotkey through windows-key-listener.exe,
; whose modifier-only hook emits KEY_DOWN whenever ANY key arrives while it
; believes Ctrl and Win are both held. A held Win key plus a second app's
; injected Ctrl (for example a launcher pasting after Win+W) therefore toggles
; dictation without the user ever pressing Ctrl+Win. While Win is held with
; any key other than Ctrl, the listener is suspended; it resumes shortly after
; Win is released, so a plain Ctrl+Win tap still toggles recording exactly as
; before.
; ============================================================================
SttGuardTick()
{
    global sttGuardArmed, sttGuardForeign, sttGuardSuspended, sttGuardResumeAt
    winHeld := GetKeyState("LWin", "P") || GetKeyState("RWin", "P")
    if (winHeld && !sttGuardArmed) {
        sttGuardArmed := true
        ; A Ctrl+Win tap is only clean while nothing but Ctrl joins Win. If a
        ; previous hold left the listener suspended, stay suspended for this
        ; hold too so its state cannot leak into a fresh tap.
        sttGuardForeign := sttGuardSuspended
        ; Keys released in the instant before Win went down are not part of
        ; this chord; flush their pressed-since-last-query edges.
        SttGuardFlushKeyEdges()
    } else if (!winHeld && sttGuardArmed) {
        sttGuardArmed := false
        if (sttGuardForeign)
            sttGuardResumeAt := A_TickCount + 250 ; grace for late injected keys
    }
    if (!sttGuardArmed) {
        if (sttGuardSuspended && A_TickCount >= sttGuardResumeAt)
            SttGuardSetSuspended(false)
        return
    }
    if (!sttGuardForeign && SttGuardForeignKeyDown()) {
        sttGuardForeign := true
        SttGuardSetSuspended(true)
    }
}

; Called synchronously from Win+X hotkey handlers so the listener is already
; frozen before the launched app gets a chance to inject any keys.
SttGuardSuspendForWinChord()
{
    global sttGuardArmed, sttGuardForeign
    sttGuardArmed := true
    sttGuardForeign := true
    SttGuardSetSuspended(true)
}

SttGuardSetSuspended(suspend)
{
    global sttGuardSuspended
    fn := suspend ? "ntdll\NtSuspendProcess" : "ntdll\NtResumeProcess"
    for pid in SttGuardListenerPids() {
        handle := DllCall("OpenProcess", "UInt", 0x0800, "Int", false, "UInt", pid, "Ptr") ; PROCESS_SUSPEND_RESUME
        if (handle) {
            DllCall(fn, "Ptr", handle)
            DllCall("CloseHandle", "Ptr", handle)
        }
    }
    sttGuardSuspended := suspend
}

SttGuardListenerPids()
{
    pids := []
    try {
        for process in ComObjGet("winmgmts:").ExecQuery("SELECT ProcessId FROM Win32_Process WHERE Name = 'windows-key-listener.exe'")
            pids.Push(process.ProcessId)
    } catch {
    }
    return pids
}

SttGuardFlushKeyEdges()
{
    vk := 0x08
    while (vk <= 0xFE) {
        DllCall("GetAsyncKeyState", "Short", vk, "Short")
        vk += 1
    }
}

; True when any key besides Ctrl and Win is down or was pressed since the last
; query (mouse buttons are not part of a keyboard chord and start at VK 0x08).
SttGuardForeignKeyDown()
{
    vk := 0x08
    while (vk <= 0xFE) {
        if (vk = 0x11 || vk = 0xA2 || vk = 0xA3 || vk = 0x5B || vk = 0x5C) {
            vk += 1
            continue
        }
        state := DllCall("GetAsyncKeyState", "Short", vk, "Short")
        if ((state & 0x8000) || (state & 0x0001))
            return true
        vk += 1
    }
    return false
}

SttGuardOnExit(exitReason, exitCode)
{
    global sttGuardSuspended
    if (sttGuardSuspended)
        SttGuardSetSuspended(false)
    return 0
}
