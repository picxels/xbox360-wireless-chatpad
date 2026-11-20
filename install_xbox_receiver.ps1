<#
.SYNOPSIS
    Binds Microsoft's built-in Xbox 360 Wireless Receiver driver (xusb22.inf)
    to official (PID_0719), third-party (PID_0291), and Xbox 360 console RF board
    (PID_02A9) USB wireless receivers via Windows SetupAPI.

.DESCRIPTION
    Run in an Administrator PowerShell window:
    powershell -ExecutionPolicy Bypass -File .\install_xbox_receiver.ps1
#>

$ErrorActionPreference = 'Stop'

$code = @'
using System;
using System.Runtime.InteropServices;

public class XboxDriverInstaller {
    public const int SPDIT_CLASSDRIVER = 1;
    public const int DI_ENUMSINGLEINF = 0x00010000;
    public const int DI_FLAGSEX_ALLOWEXCLUDEDDRVS = 0x00000800;
    public const int DIOD_INHERIT_CLASSDRVS = 0x00000002;

    [StructLayout(LayoutKind.Sequential)]
    public struct SP_DEVINFO_DATA {
        public uint cbSize;
        public Guid ClassGuid;
        public uint DevInst;
        public IntPtr Reserved;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct SP_DEVINSTALL_PARAMS {
        public uint cbSize;
        public uint Flags;
        public uint FlagsEx;
        public IntPtr hwndParent;
        public IntPtr InstallMsgHandler;
        public IntPtr InstallMsgHandlerContext;
        public IntPtr FileQueue;
        public IntPtr ClassInstallReserved;
        public uint Reserved;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
        public string DriverPath;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct SP_DRVINFO_DATA {
        public uint cbSize;
        public uint DriverType;
        public IntPtr Reserved;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string Description;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string MfgName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string ProviderName;
        public System.Runtime.InteropServices.ComTypes.FILETIME DriverDate;
        public ulong DriverVersion;
    }

    [DllImport("setupapi.dll", SetLastError = true)]
    public static extern IntPtr SetupDiCreateDeviceInfoList(IntPtr ClassGuid, IntPtr hwndParent);

    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SetupDiOpenDeviceInfo(IntPtr DeviceInfoSet, string DeviceInstanceId, IntPtr hwndParent, uint OpenFlags, ref SP_DEVINFO_DATA DeviceInfoData);

    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SetupDiGetDeviceInstallParams(IntPtr DeviceInfoSet, IntPtr DeviceInfoData, ref SP_DEVINSTALL_PARAMS DeviceInstallParams);

    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SetupDiSetDeviceInstallParams(IntPtr DeviceInfoSet, IntPtr DeviceInfoData, ref SP_DEVINSTALL_PARAMS DeviceInstallParams);

    [DllImport("setupapi.dll", SetLastError = true)]
    public static extern bool SetupDiBuildDriverInfoList(IntPtr DeviceInfoSet, IntPtr DeviceInfoData, uint DriverType);

    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SetupDiEnumDriverInfo(IntPtr DeviceInfoSet, ref SP_DEVINFO_DATA DeviceInfoData, uint DriverType, uint MemberIndex, ref SP_DRVINFO_DATA DriverInfoData);

    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SetupDiSetSelectedDriver(IntPtr DeviceInfoSet, ref SP_DEVINFO_DATA DeviceInfoData, ref SP_DRVINFO_DATA DriverInfoData);

    [DllImport("newdev.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool DiInstallDevice(IntPtr hwndParent, IntPtr DeviceInfoSet, ref SP_DEVINFO_DATA DeviceInfoData, ref SP_DRVINFO_DATA DriverInfoData, uint Flags, out bool NeedReboot);

    [DllImport("setupapi.dll", SetLastError = true)]
    public static extern bool SetupDiDestroyDeviceInfoList(IntPtr DeviceInfoSet);
}
'@

Add-Type -TypeDefinition $code

$device = Get-PnpDevice | Where-Object {
    $_.InstanceId -match '^USB\\VID_045E&PID_(02A9|0291|0719)\\' -and $_.Present
} | Select-Object -First 1

if (-not $device) {
    Write-Host "No connected Xbox 360 Wireless Receiver (VID_045E & PID_02A9 / 0291 / 0719) found." -ForegroundColor Red
    exit 1
}

$deviceId = $device.InstanceId
Write-Host "Found receiver: $deviceId" -ForegroundColor Cyan

$infFile = (Get-ChildItem "C:\Windows\INF\xusb*.inf" | Sort-Object Name -Descending | Select-Object -First 1).FullName
if (-not $infFile) {
    throw "No xusb*.inf found in C:\Windows\INF\"
}

$hDevInfo = [XboxDriverInstaller]::SetupDiCreateDeviceInfoList([IntPtr]::Zero, [IntPtr]::Zero)
try {
    $instParams = New-Object XboxDriverInstaller+SP_DEVINSTALL_PARAMS
    $instParams.cbSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf($instParams)
    [void][XboxDriverInstaller]::SetupDiGetDeviceInstallParams($hDevInfo, [IntPtr]::Zero, [ref]$instParams)
    $instParams.Flags = $instParams.Flags -bor [XboxDriverInstaller]::DI_ENUMSINGLEINF
    $instParams.FlagsEx = $instParams.FlagsEx -bor [XboxDriverInstaller]::DI_FLAGSEX_ALLOWEXCLUDEDDRVS
    $instParams.DriverPath = $infFile
    if (-not [XboxDriverInstaller]::SetupDiSetDeviceInstallParams($hDevInfo, [IntPtr]::Zero, [ref]$instParams)) {
        throw "SetupDiSetDeviceInstallParams failed with Win32 error $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }

    if (-not [XboxDriverInstaller]::SetupDiBuildDriverInfoList($hDevInfo, [IntPtr]::Zero, [XboxDriverInstaller]::SPDIT_CLASSDRIVER)) {
        throw "SetupDiBuildDriverInfoList failed with Win32 error $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }

    $devData = New-Object XboxDriverInstaller+SP_DEVINFO_DATA
    $devData.cbSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf($devData)
    if (-not [XboxDriverInstaller]::SetupDiOpenDeviceInfo($hDevInfo, $deviceId, [IntPtr]::Zero, [XboxDriverInstaller]::DIOD_INHERIT_CLASSDRVS, [ref]$devData)) {
        throw "SetupDiOpenDeviceInfo failed with Win32 error $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }

    $drvData = New-Object XboxDriverInstaller+SP_DRVINFO_DATA
    $drvData.cbSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf($drvData)
    $found = $false
    $idx = 0
    while ([XboxDriverInstaller]::SetupDiEnumDriverInfo($hDevInfo, [ref]$devData, [XboxDriverInstaller]::SPDIT_CLASSDRIVER, $idx, [ref]$drvData)) {
        if ($drvData.Description -eq "Xbox 360 Wireless Receiver for Windows") {
            $found = $true
            break
        }
        $idx++
    }

    if (-not $found) {
        throw "Driver 'Xbox 360 Wireless Receiver for Windows' not found in $infFile"
    }

    if (-not [XboxDriverInstaller]::SetupDiSetSelectedDriver($hDevInfo, [ref]$devData, [ref]$drvData)) {
        throw "SetupDiSetSelectedDriver failed with Win32 error $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }

    $needReboot = $false
    if (-not [XboxDriverInstaller]::DiInstallDevice([IntPtr]::Zero, $hDevInfo, [ref]$devData, [ref]$drvData, 0, [ref]$needReboot)) {
        $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "DiInstallDevice failed with Win32 error $err (0x$($err.ToString('X8'))). Make sure PowerShell is running as Administrator!"
    }

    Write-Host "SUCCESS: Installed 'Xbox 360 Wireless Receiver for Windows' ($infFile) on $deviceId" -ForegroundColor Green
    Get-PnpDevice -InstanceId $deviceId | Select-Object Status, Class, FriendlyName, InstanceId | Format-Table -AutoSize
} finally {
    [void][XboxDriverInstaller]::SetupDiDestroyDeviceInfoList($hDevInfo)
}
