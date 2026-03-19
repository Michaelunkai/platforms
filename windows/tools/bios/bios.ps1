<#
.SYNOPSIS
    bios
#>
# Reboot to UEFI firmware using Windows API
    Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;
    public class FirmwareBoot {
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern IntPtr GetCurrentProcess();
        [DllImport("advapi32.dll", SetLastError = true)]
        static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);
        [DllImport("advapi32.dll", SetLastError = true)]
        static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out long lpLuid);
        [DllImport("advapi32.dll", SetLastError = true)]
        static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges, ref TOKEN_PRIVILEGES NewState, uint BufferLength, IntPtr PreviousState, IntPtr ReturnLength);
        [DllImport("ntdll.dll", SetLastError = true)]
        static extern int NtSetSystemPowerState(int SystemAction, int MinSystemState, int Flags);
        [StructLayout(LayoutKind.Sequential)]
        struct TOKEN_PRIVILEGES { public uint PrivilegeCount; public long Luid; public uint Attributes; }
        public static void RebootToFirmware() {
            IntPtr token;
            OpenProcessToken(GetCurrentProcess(), 0x28, out token);
            TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES { PrivilegeCount = 1, Attributes = 2 };
            LookupPrivilegeValue(null, "SeShutdownPrivilege", out tp.Luid);
            AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
        }
    }
"@
    shutdown /r /fw /t 0
