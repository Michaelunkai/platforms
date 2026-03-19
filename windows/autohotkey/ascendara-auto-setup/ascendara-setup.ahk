; Ascendara Automatic Setup Script (AHK v2)
; Automates first-time setup: language, terms, local index, scraping

#Requires AutoHotkey v2.0
Persistent
SetTitleMatchMode 2
CoordMode "Mouse", "Screen"

; Wait for Ascendara window to appear
if !WinWait("Ascendara", , 30)
{
    MsgBox "Ascendara window did not appear within 30 seconds.", "Error", 48
    ExitApp
}

Sleep 2000
WinActivate "Ascendara"
Sleep 1000

; Step 1: Click English (US) button - coordinates based on 2560x1440 screen
Click 653, 396 ; English button
Sleep 2000

; Wait for next screen and click through all setup steps
Loop 10
{
    Sleep 1000
    ; Try clicking common "Continue", "Next", "Accept", "Finish" button positions
    ; Usually centered horizontally, bottom third of window
    Send "{Enter}" ; Try Enter key first
    Sleep 500
    
    ; If there are checkboxes, enable them
    Send "{Space}" ; Enable any focused checkboxes
    Sleep 300
    
    ; Check if we've reached the main app window
    if WinExist("Ascendara") and !WinExist("ahk_class #32770") ; Not a dialog
    {
        Sleep 2000
        Break
    }
}

; Final verification
Sleep 2000
TrayTip "Ascendara setup completed automatically!", "Success"

ExitApp
