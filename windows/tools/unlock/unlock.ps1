<#
.SYNOPSIS
    unlock
#>
REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /t REG_SZ /d 1 /f;
    REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUsername /t REG_SZ /d "$env:USERNAME" /f;
    REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /t REG_SZ /d "13571357" /f;
    REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v ForceAutoLogon /t REG_SZ /d 1 /f;
    REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v DisablePasswordChange /t REG_DWORD /d 1 /f;
    REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v DisableLockWorkstation /t REG_DWORD /d 1 /f;
    REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v InactivityTimeoutSecs /t REG_DWORD /d 0 /f;
    powercfg -change -standby-timeout-ac 0;
    powercfg -change -monitor-timeout-ac 0;
    powercfg -change -disk-timeout-ac 0;
    REG ADD "HKCU\Control Panel\Desktop" /v ScreenSaveActive /t REG_SZ /d 0 /f;
    REG ADD "HKCU\Software\Policies\Microsoft\Windows\System" /v AllowDomainPINLogon /t REG_DWORD /d 0 /f;
    REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v AllowDomainPINLogon /t REG_DWORD /d 0 /f;
    REG DELETE "HKLM\SOFTWARE\Microsoft\PolicyManager\default\Settings\AllowSignInOptions" /f 2>$null;
    REG DELETE "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\UserTile" /f 2>$null;
    New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorAdmin" -Value 0 -PropertyType DWord -Force; New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -Value 0 -PropertyType DWord -Force
