Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    using System.Windows.Forms;
    
    public class KeyboardSimulator
    {
        [DllImport("user32.dll")]
        public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, int dwExtraInfo);
        
        public const int KEYEVENTF_EXTENDEDKEY = 0x0001;
        public const int KEYEVENTF_KEYUP = 0x0002;
        
        public static void SendCtrlAltS()
        {
            // Press Ctrl+Alt+S
            keybd_event(0x11, 0, 0, 0); // Ctrl down
            keybd_event(0x12, 0, 0, 0); // Alt down
            keybd_event(0x53, 0, 0, 0); // S down
            System.Threading.Thread.Sleep(50);
            keybd_event(0x53, 0, KEYEVENTF_KEYUP, 0); // S up
            keybd_event(0x12, 0, KEYEVENTF_KEYUP, 0); // Alt up
            keybd_event(0x11, 0, KEYEVENTF_KEYUP, 0); // Ctrl up
        }
        
        public static void SendPrintScreen()
        {
            keybd_event(0x2C, 0, KEYEVENTF_EXTENDEDKEY, 0); // PrintScreen down
            System.Threading.Thread.Sleep(50);
            keybd_event(0x2C, 0, KEYEVENTF_EXTENDEDKEY | KEYEVENTF_KEYUP, 0); // PrintScreen up
        }
        
        public static void SendAltS()
        {
            // Press Alt+S
            keybd_event(0x12, 0, 0, 0); // Alt down
            keybd_event(0x53, 0, 0, 0); // S down
            System.Threading.Thread.Sleep(50);
            keybd_event(0x53, 0, KEYEVENTF_KEYUP, 0); // S up
            keybd_event(0x12, 0, KEYEVENTF_KEYUP, 0); // Alt up
        }
    }
"@

Write-Host ""
Write-Host "TESTING FULLSCREENSNIP - ENHANCED VERSION" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# Test 1: Full Screen with Ctrl+Alt+S
Write-Host ""
Write-Host "1. Testing Full Screen (Ctrl+Alt+S)..." -ForegroundColor Yellow
[KeyboardSimulator]::SendCtrlAltS()
Start-Sleep -Seconds 2

# Check clipboard
try {
    $clipboardContent = Get-Clipboard -Format Image -ErrorAction Stop
    if ($clipboardContent) {
        Write-Host "   SUCCESS: Screenshot captured to clipboard!" -ForegroundColor Green
    } else {
        Write-Host "   FAILED: No image in clipboard" -ForegroundColor Red
    }
} catch {
    Write-Host "   INFO: Could not verify clipboard content" -ForegroundColor Yellow
}

# Test 2: Full Screen with PrintScreen
Write-Host ""
Write-Host "2. Testing Full Screen (PrintScreen)..." -ForegroundColor Yellow
[KeyboardSimulator]::SendPrintScreen()
Start-Sleep -Seconds 2

# Check clipboard again
try {
    $clipboardContent = Get-Clipboard -Format Image -ErrorAction Stop
    if ($clipboardContent) {
        Write-Host "   SUCCESS: Screenshot captured to clipboard!" -ForegroundColor Green
    } else {
        Write-Host "   FAILED: No image in clipboard" -ForegroundColor Red
    }
} catch {
    Write-Host "   INFO: Could not verify clipboard content" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "3. For Free Snip (Alt+S), please test manually:" -ForegroundColor Yellow
Write-Host "   - Press Alt+S to start selection mode"
Write-Host "   - Drag to select an area"
Write-Host "   - Release to capture"

Write-Host ""
Write-Host "CLIPBOARD HISTORY CHECK:" -ForegroundColor Cyan
Write-Host "   Press Win+V to open Clipboard History and verify screenshots are saved there!" -ForegroundColor White

Write-Host ""
Write-Host "All tests completed! Check your system tray for the blue camera icon." -ForegroundColor Green
Write-Host "Double-click it to see all options." -ForegroundColor White