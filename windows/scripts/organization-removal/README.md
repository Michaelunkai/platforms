# Windows Organization Control Removal Tool

**Safely removes all organizational control from Windows 11/10**

Removes:
- ✅ MDM (Mobile Device Management) enrollment
- ✅ Azure AD joins
- ✅ Workplace/School accounts
- ✅ Enterprise policies
- ✅ Organization branding
- ✅ Management services

## Quick Start

### Option 1: Interactive Mode (Recommended)
```powershell
# Right-click PowerShell -> Run as Administrator
cd "F:\study\Platforms\windows\scripts\organization-removal"
.\Remove-OrganizationControl.ps1
```

### Option 2: One-Liner (No confirmation)
```powershell
powershell -ExecutionPolicy Bypass -File "F:\study\Platforms\windows\scripts\organization-removal\Remove-OrganizationControl.ps1" -Force
```

### Option 3: Preview Changes (WhatIf mode)
```powershell
.\Remove-OrganizationControl.ps1 -WhatIf
```

## Parameters

| Parameter | Description |
|-----------|-------------|
| `-WhatIf` | Preview what would be removed (no actual changes) |
| `-Force` | Skip confirmation prompts |

## What It Does

1. **Checks current status** - scans for MDM, Azure AD, workplace accounts
2. **Removes MDM enrollment** - deletes enrollment registry keys
3. **Leaves Azure AD** - runs `dsregcmd /leave`
4. **Removes workplace accounts** - clears work/school accounts
5. **Clears policies** - removes organizational policies
6. **Disables branding** - removes lock screen/org branding
7. **Stops management tasks** - removes scheduled management tasks
8. **Clears group policy** - deletes cached group policies
9. **Disables services** - stops device management services

## Verification

After running the script and restarting, verify:

```powershell
dsregcmd /status
```

Look for:
- `AzureAdJoined: NO`
- `WorkplaceJoined: NO`
- `DomainJoined: NO` (if you want to be unmanaged)

## Safety

- ✅ Requires Administrator rights
- ✅ Shows confirmation prompt (unless `-Force`)
- ✅ WhatIf mode available
- ✅ Detailed logging of all actions
- ✅ Only removes organizational control (doesn't break Windows)

## Warnings

⚠️ **This will:**
- Remove access to organizational resources (OneDrive, Teams, etc.)
- Clear company policies
- Require reconfiguration if you need to rejoin later

⚠️ **Do NOT use if:**
- You need access to work/school resources
- Device is company-owned
- You're still employed and need the connection

## Troubleshooting

### "Access Denied" errors
- Run PowerShell as Administrator
- Check if BitLocker is enabled (may need recovery key)

### Script execution blocked
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
```

### Still shows as managed after restart
- Run `gpupdate /force`
- Check Settings > Accounts > Access work or school
- Manually remove any remaining accounts

## Author

Till Thelet / OpenClaw  
Created: 2026-03-12

## License

Free to use, modify, distribute.
