#Requires AutoHotkey v2.0

logf := "F:\study\Platforms\windows\autohotkey\mymainahk\blocktest-result.txt"
FileAppend("start`n", logf)
hwnd := WinGetID("ahk_pid 23004")
FileAppend("hwnd=" hwnd "`n", logf)
if (hwnd) {
    FileAppend("hung=" DllCall("IsHungAppWindow", "Ptr", hwnd, "Int") "`n", logf)
    FileAppend("minMax=" WinGetMinMax("ahk_id " hwnd) "`n", logf)
    FileAppend("BEFORE WinRestore`n", logf)
    WinRestore("ahk_id " hwnd)
    FileAppend("AFTER WinRestore`n", logf)
    FileAppend("BEFORE WinMove`n", logf)
    WinMove(100, 100, , , "ahk_id " hwnd)
    FileAppend("AFTER WinMove`n", logf)
}
FileAppend("done`n", logf)
ExitApp()
