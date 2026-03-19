# Paragon Hard Disk Manager - Automated Disk Check

Complete automation for running disk check with automatic restart.

## ⚠️ WARNING
**This automation WILL restart your computer automatically!**  
Save all work before running.

## What It Does
1. ✅ Launches Paragon Hard Disk Manager
2. ✅ Navigates to "Disks and volumes"
3. ✅ Selects Local Disk (C:)
4. ✅ Opens "Check file system" dialog
5. ✅ Enables both repair options:
   - Search and try to recover bad sectors
   - Automatically fix file system errors
6. ✅ Starts the disk check
7. ✅ Waits for restart dialog (12 seconds)
8. ✅ **Automatically clicks "Restart the computer"**

## How to Use

### Option 1: Batch File (Recommended)
Double-click: **`RUN_DISK_CHECK.bat`**

### Option 2: Python Script Directly
```bash
python run_paragon_disk_check.py
```

### Option 3: AutoHotkey Hotstring
Type anywhere: **`ppppp`** (if AutoHotkey is running)

## Requirements
- Python 3.x installed
- Python packages: `pyautogui`, `pywinauto`, `pillow`
- Paragon Hard Disk Manager 17 Business installed at:
  `F:\backup\windowsapps\installed\fixers\Paragon Software\Hard Disk Manager 17 Business\program\hdm17.exe`

### Install Requirements
```bash
pip install pyautogui pywinauto pillow
```

## Technical Details
- **Resolution**: 3840x2160 (multi-monitor setup)
- **DPI-aware**: Uses `dpi_aware.py` module if available
- **Wait times**: Calibrated for reliable execution
  - 20s for Paragon launch
  - 3s for UI load
  - 12s for restart dialog
- **Window detection**: 5 retry attempts with 2s intervals
- **Coordinates**: Mix of window-relative and absolute positions

## Files
- `run_paragon_disk_check.py` - Main automation script
- `RUN_DISK_CHECK.bat` - Convenient batch launcher
- `README.md` - This file

## Troubleshooting
- **"Paragon executable not found"**: Update `PARAGON_EXE` path in script
- **"Window not found"**: Increase `LAUNCH_WAIT` time (line 39)
- **Clicks miss targets**: Check DPI scaling or recalibrate coordinates
- **Restart doesn't trigger**: Increase `RESTART_DIALOG_WAIT` time (line 42)

## Created
2026-03-16 - Complete standalone automation
