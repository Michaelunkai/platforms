# Windows 11 Reset - Keep Files Only

## What This Does
This tool performs a Windows 11 reset that is **one level lower** than the repair install:

| Feature | Repair Install (winupg) | Reset Keep Files (winupgg) |
|---------|------------------------|---------------------------|
| Personal Files | ✓ Kept | ✓ Kept |
| Installed Programs | ✓ Kept | ✗ Removed |
| Windows Settings | ✓ Kept | ✗ Removed |
| Drivers | ✓ Kept | ✗ Reset to defaults |

## Usage
In PowerShell: `winupgg`

## What Happens
1. Shows warning about what will be removed
2. Asks for confirmation
3. Reminds about backups (browser data, game saves, etc.)
4. Runs `systemreset.exe -factoryreset -keepuserdata -quiet`
5. If that fails, opens Windows Settings as fallback

## Duration
30-60 minutes typically

## After Reset
- Windows will be like freshly installed
- All your documents/photos/videos remain
- You'll need to reinstall all programs
- You'll need to reconfigure all settings