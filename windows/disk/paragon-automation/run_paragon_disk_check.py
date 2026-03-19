"""
Paragon Hard Disk Manager - Complete Disk Check Automation
Standalone script that performs full disk check with automatic restart.

This script automates the entire process:
1. Launch Paragon Hard Disk Manager
2. Navigate to "Disks and volumes"
3. Select Local Disk (C:)
4. Open "Check file system" dialog
5. Enable both repair options
6. Start the check
7. Automatically restart the computer

⚠️ WARNING: This script WILL restart your computer automatically!
Save all work before running.

Usage: Double-click this file or run: python run_paragon_disk_check.py
"""

import subprocess
import time
import sys
from pathlib import Path

# Add win-control skill path for DPI awareness
SKILL_PATH = Path.home() / ".openclaw" / "skills" / "win-control"
if SKILL_PATH.exists():
    sys.path.insert(0, str(SKILL_PATH))

try:
    from dpi_aware import get_dpi_aware_coords
    DPI_AWARE = True
except ImportError:
    DPI_AWARE = False
    print("⚠️ DPI awareness module not found - using raw coordinates")

# Configuration
PARAGON_EXE = r"F:\backup\windowsapps\installed\fixers\Paragon Software\Hard Disk Manager 17 Business\program\hdm17.exe"
WINDOW_TITLE = "Hard Disk Manager"

# Coordinates (all verified working)
# Window-relative coordinates for main UI
DISKS_AND_VOLUMES_OFFSET = (37, 355)  # Relative to window top-left
LOCAL_DISK_C_OFFSET = (1650, 218)     # Relative to window top-left
CHECK_FILE_SYSTEM_OFFSET = (228, 1137) # Relative to window top-left

# Absolute screen coordinates for dialog elements (already DPI-aware)
CHECKBOX_1 = (1361, 947)   # "Search and try to recover bad sectors"
CHECKBOX_2 = (1352, 1003)  # "Automatically fix file system errors"
CHECK_NOW_BUTTON = (1863, 1532)
RESTART_BUTTON = (1635, 985)

# Wait times (calibrated for reliability)
LAUNCH_WAIT = 20  # Wait for Paragon to fully launch
UI_LOAD_WAIT = 3  # Wait for UI to be ready
RESTART_DIALOG_WAIT = 12  # Wait for restart dialog to appear


def click_absolute(x, y):
    """Click at absolute screen coordinates using pyautogui."""
    try:
        import pyautogui
        if DPI_AWARE:
            x, y = get_dpi_aware_coords(x, y)
        pyautogui.click(x, y)
        return True
    except Exception as e:
        print(f"❌ Click failed at ({x}, {y}): {e}")
        return False


def click_window_relative(window_x, window_y, offset_x, offset_y):
    """Click at window-relative coordinates."""
    try:
        import pyautogui
        abs_x = window_x + offset_x
        abs_y = window_y + offset_y
        if DPI_AWARE:
            abs_x, abs_y = get_dpi_aware_coords(abs_x, abs_y)
        pyautogui.click(abs_x, abs_y)
        return True
    except Exception as e:
        print(f"❌ Window-relative click failed: {e}")
        return False


def find_window(title, max_attempts=5):
    """Find window by title with retry logic."""
    try:
        import pywinauto
        from pywinauto import Application
    except ImportError:
        print("❌ pywinauto not installed. Run: pip install pywinauto")
        return None

    for attempt in range(1, max_attempts + 1):
        try:
            print(f"  Attempt {attempt}/{max_attempts}: Looking for window '{title}'...")
            app = Application(backend="uia").connect(title=title, timeout=2)
            window = app.window(title=title)
            if window.exists():
                rect = window.rectangle()
                print(f"  ✅ Window found! Position: ({rect.left}, {rect.top})")
                return window, rect.left, rect.top
        except Exception as e:
            if attempt < max_attempts:
                print(f"  ⏳ Not found yet, waiting 2s...")
                time.sleep(2)
            else:
                print(f"  ❌ Window not found after {max_attempts} attempts: {e}")
                return None

    return None


def main():
    """Main automation routine."""
    print("=" * 70)
    print("🔧 PARAGON HARD DISK MANAGER - AUTOMATED DISK CHECK")
    print("=" * 70)
    print()
    print("⚠️  WARNING: This script will RESTART YOUR COMPUTER!")
    print("⚠️  Save all work before continuing.")
    print()
    
    # Check if pyautogui and pywinauto are installed
    try:
        import pyautogui
        import pywinauto
    except ImportError as e:
        print("❌ Missing required module:", e)
        print("\nInstall required packages:")
        print("  pip install pyautogui pywinauto pillow")
        input("\nPress Enter to exit...")
        return 1

    # Check if Paragon executable exists
    if not Path(PARAGON_EXE).exists():
        print(f"❌ Paragon executable not found: {PARAGON_EXE}")
        input("\nPress Enter to exit...")
        return 1

    print("🚀 STEP 1/8: Launching Paragon Hard Disk Manager...")
    try:
        subprocess.Popen([PARAGON_EXE])
        print(f"  ⏳ Waiting {LAUNCH_WAIT}s for application to start...")
        time.sleep(LAUNCH_WAIT)
    except Exception as e:
        print(f"  ❌ Failed to launch: {e}")
        input("\nPress Enter to exit...")
        return 1

    print("\n🔍 STEP 2/8: Finding Paragon window...")
    result = find_window(WINDOW_TITLE)
    if not result:
        print("  ❌ Could not find Paragon window")
        input("\nPress Enter to exit...")
        return 1
    
    window, window_x, window_y = result
    time.sleep(UI_LOAD_WAIT)

    print("\n🖱️ STEP 3/8: Clicking 'Disks and volumes'...")
    if not click_window_relative(window_x, window_y, *DISKS_AND_VOLUMES_OFFSET):
        input("\nPress Enter to exit...")
        return 1
    print("  ✅ Clicked")
    time.sleep(2)

    print("\n🖱️ STEP 4/8: Selecting Local Disk (C:)...")
    if not click_window_relative(window_x, window_y, *LOCAL_DISK_C_OFFSET):
        input("\nPress Enter to exit...")
        return 1
    print("  ✅ Clicked")
    time.sleep(1)

    print("\n🖱️ STEP 5/8: Opening 'Check file system' dialog...")
    if not click_window_relative(window_x, window_y, *CHECK_FILE_SYSTEM_OFFSET):
        input("\nPress Enter to exit...")
        return 1
    print("  ✅ Clicked")
    time.sleep(3)

    print("\n☑️ STEP 6/8: Enabling repair options...")
    print("  Checkbox 1: Search and try to recover bad sectors")
    if not click_absolute(*CHECKBOX_1):
        input("\nPress Enter to exit...")
        return 1
    time.sleep(0.5)
    
    print("  Checkbox 2: Automatically fix file system errors")
    if not click_absolute(*CHECKBOX_2):
        input("\nPress Enter to exit...")
        return 1
    print("  ✅ Both checkboxes enabled")
    time.sleep(1)

    print("\n▶️ STEP 7/8: Starting disk check...")
    if not click_absolute(*CHECK_NOW_BUTTON):
        input("\nPress Enter to exit...")
        return 1
    print("  ✅ Disk check started")
    print(f"  ⏳ Waiting {RESTART_DIALOG_WAIT}s for restart dialog...")
    time.sleep(RESTART_DIALOG_WAIT)

    print("\n🔄 STEP 8/8: Clicking 'Restart the computer'...")
    if not click_absolute(*RESTART_BUTTON):
        print("  ⚠️ Failed to click restart button - you may need to restart manually")
        input("\nPress Enter to exit...")
        return 1
    
    print("  ✅ Restart initiated!")
    print("\n" + "=" * 70)
    print("✅ AUTOMATION COMPLETE - COMPUTER RESTARTING NOW")
    print("=" * 70)
    
    time.sleep(3)
    return 0


if __name__ == "__main__":
    try:
        exit_code = main()
        sys.exit(exit_code)
    except KeyboardInterrupt:
        print("\n\n⚠️ Interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n\n❌ Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        input("\nPress Enter to exit...")
        sys.exit(1)
