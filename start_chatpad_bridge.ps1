<#
.SYNOPSIS
    Xbox 360 Wireless Controller + Wireless Chatpad (Official & DOBE TYX-517) Bridge for Windows 10/11.

.DESCRIPTION
    Uses Windows's built-in signed WinUSB driver (C:\Windows\INF\winusb.inf) + Nefarius ViGEmBus
    to provide:
      - Up to 4 native XInput Xbox 360 Wireless Controllers (sticks, triggers, buttons, LEDs, rumble)
      - Full wireless Xbox 360 Chatpad / DOBE TYX-517 keyboard input (normal keys, Shift, CapsLock,
        Green symbols, Orange symbols, Messenger/Tab) via Win32 SendInput.

.PARAMETER InstallWinUsbOnly
    Switches the receiver driver to WinUSB and exits.

.PARAMETER RestoreMicrosoftDriver
    Restores the stock Microsoft Xbox 360 Wireless Receiver driver (C:\Windows\INF\xusb22.inf) and exits.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\start_chatpad_bridge.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\start_chatpad_bridge.ps1 -RestoreMicrosoftDriver
#>

param(
    [switch]$InstallWinUsbOnly,
    [switch]$RestoreMicrosoftDriver
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.FullName

# Ensure native x64 vigemclient.dll is available next to the script
$vigemNativeDll = Join-Path $scriptDir "vigemclient.dll"
if (-not $RestoreMicrosoftDriver -and -not (Test-Path $vigemNativeDll)) {
    Write-Host "Downloading Nefarius.ViGEm.Client runtime to extract vigemclient.dll..." -ForegroundColor Cyan
    $tempDir = Join-Path $scriptDir "vigem"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    $nupkg = Join-Path $tempDir "vigem.zip"
    Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/Nefarius.ViGEm.Client/1.21.256" -OutFile $nupkg
    Expand-Archive -Path $nupkg -DestinationPath "$tempDir\extracted" -Force
    $managedDll = (Get-ChildItem "$tempDir\extracted" -Filter "Nefarius.ViGEm.Client.dll" -Recurse | Select-Object -First 1).FullName
    $asm = [System.Reflection.Assembly]::LoadFrom($managedDll)
    $stream = $asm.GetManifestResourceStream("costura64.vigemclient.dll")
    $outFile = [System.IO.File]::Create($vigemNativeDll)
    $stream.CopyTo($outFile)
    $outFile.Close()
    $stream.Close()
    Write-Host "Extracted vigemclient.dll ($((Get-Item $vigemNativeDll).Length) bytes)." -ForegroundColor Green
}

$env:PATH = "$scriptDir;$env:PATH"

$code = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.Win32.SafeHandles;

public class ReceiverDriverSwitcher {
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

    public static void InstallInfDriver(string deviceId, string infPath, string driverDescription) {
        IntPtr hDevInfo = SetupDiCreateDeviceInfoList(IntPtr.Zero, IntPtr.Zero);
        try {
            SP_DEVINSTALL_PARAMS instParams = new SP_DEVINSTALL_PARAMS();
            instParams.cbSize = (uint)Marshal.SizeOf(typeof(SP_DEVINSTALL_PARAMS));
            SetupDiGetDeviceInstallParams(hDevInfo, IntPtr.Zero, ref instParams);
            instParams.Flags |= DI_ENUMSINGLEINF;
            instParams.FlagsEx |= DI_FLAGSEX_ALLOWEXCLUDEDDRVS;
            instParams.DriverPath = infPath;
            if (!SetupDiSetDeviceInstallParams(hDevInfo, IntPtr.Zero, ref instParams)) {
                throw new Exception("SetupDiSetDeviceInstallParams failed: " + Marshal.GetLastWin32Error());
            }
            if (!SetupDiBuildDriverInfoList(hDevInfo, IntPtr.Zero, SPDIT_CLASSDRIVER)) {
                throw new Exception("SetupDiBuildDriverInfoList failed: " + Marshal.GetLastWin32Error());
            }

            SP_DEVINFO_DATA devData = new SP_DEVINFO_DATA();
            devData.cbSize = (uint)Marshal.SizeOf(typeof(SP_DEVINFO_DATA));
            if (!SetupDiOpenDeviceInfo(hDevInfo, deviceId, IntPtr.Zero, DIOD_INHERIT_CLASSDRVS, ref devData)) {
                throw new Exception("SetupDiOpenDeviceInfo failed: " + Marshal.GetLastWin32Error());
            }

            SP_DRVINFO_DATA drvData = new SP_DRVINFO_DATA();
            drvData.cbSize = (uint)Marshal.SizeOf(typeof(SP_DRVINFO_DATA));
            bool found = false;
            uint idx = 0;
            while (SetupDiEnumDriverInfo(hDevInfo, ref devData, SPDIT_CLASSDRIVER, idx, ref drvData)) {
                if (string.Equals(drvData.Description, driverDescription, StringComparison.OrdinalIgnoreCase)) {
                    found = true;
                    break;
                }
                idx++;
            }
            if (!found) {
                throw new Exception("Driver '" + driverDescription + "' not found in " + infPath);
            }
            if (!SetupDiSetSelectedDriver(hDevInfo, ref devData, ref drvData)) {
                throw new Exception("SetupDiSetSelectedDriver failed: " + Marshal.GetLastWin32Error());
            }
            bool needReboot;
            if (!DiInstallDevice(IntPtr.Zero, hDevInfo, ref devData, ref drvData, 0, out needReboot)) {
                int err = Marshal.GetLastWin32Error();
                throw new Exception(string.Format("DiInstallDevice failed with error {0} (0x{0:X8}). Make sure PowerShell is running as Administrator.", err));
            }
        } finally {
            SetupDiDestroyDeviceInfoList(hDevInfo);
        }
    }
}

public class XboxWirelessChatpadBridge : IDisposable {
    // WinUSB & File P/Invoke
    private const uint GENERIC_READ = 0x80000000;
    private const uint GENERIC_WRITE = 0x40000000;
    private const uint FILE_SHARE_READ = 0x00000001;
    private const uint FILE_SHARE_WRITE = 0x00000002;
    private const uint OPEN_EXISTING = 3;
    private const uint FILE_FLAG_OVERLAPPED = 0x40000000;
    private const uint PIPE_TRANSFER_TIMEOUT = 0x03;

    [StructLayout(LayoutKind.Sequential)]
    public struct USB_INTERFACE_DESCRIPTOR {
        public byte bLength;
        public byte bDescriptorType;
        public byte bInterfaceNumber;
        public byte bAlternateSetting;
        public byte bNumEndpoints;
        public byte bInterfaceClass;
        public byte bInterfaceSubClass;
        public byte bInterfaceProtocol;
        public byte iInterface;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct WINUSB_PIPE_INFORMATION {
        public int PipeType;
        public byte PipeId;
        public ushort MaximumPacketSize;
        public byte Interval;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(
        string lpFileName,
        uint dwDesiredAccess,
        uint dwShareMode,
        IntPtr lpSecurityAttributes,
        uint dwCreationDisposition,
        uint dwFlagsAndAttributes,
        IntPtr hTemplateFile);

    [DllImport("winusb.dll", SetLastError = true)]
    private static extern bool WinUsb_Initialize(SafeFileHandle DeviceHandle, out IntPtr InterfaceHandle);

    [DllImport("winusb.dll", SetLastError = true)]
    private static extern bool WinUsb_Free(IntPtr InterfaceHandle);

    [DllImport("winusb.dll", SetLastError = true)]
    private static extern bool WinUsb_GetAssociatedInterface(IntPtr InterfaceHandle, byte AssociatedInterfaceIndex, out IntPtr AssociatedInterfaceHandle);

    [DllImport("winusb.dll", SetLastError = true)]
    private static extern bool WinUsb_QueryInterfaceSettings(IntPtr InterfaceHandle, byte AlternateInterfaceNumber, out USB_INTERFACE_DESCRIPTOR UsbAltInterfaceDescriptor);

    [DllImport("winusb.dll", SetLastError = true)]
    private static extern bool WinUsb_QueryPipe(IntPtr InterfaceHandle, byte AlternateInterfaceNumber, byte PipeIndex, out WINUSB_PIPE_INFORMATION PipeInformation);

    [DllImport("winusb.dll", SetLastError = true)]
    private static extern bool WinUsb_SetPipePolicy(IntPtr InterfaceHandle, byte PipeId, uint PolicyType, uint ValueLength, ref uint Value);

    [DllImport("winusb.dll", SetLastError = true)]
    private static extern bool WinUsb_ReadPipe(IntPtr InterfaceHandle, byte PipeId, byte[] Buffer, uint BufferLength, out uint LengthTransferred, IntPtr Overlapped);

    [DllImport("winusb.dll", SetLastError = true)]
    private static extern bool WinUsb_WritePipe(IntPtr InterfaceHandle, byte PipeId, byte[] Buffer, uint BufferLength, out uint LengthTransferred, IntPtr Overlapped);

    // Native ViGEmClient P/Invoke
    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    public struct XUSB_REPORT {
        public ushort wButtons;
        public byte bLeftTrigger;
        public byte bRightTrigger;
        public short sThumbLX;
        public short sThumbLY;
        public short sThumbRX;
        public short sThumbRY;
    }

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate void EVT_VIGEM_X360_NOTIFICATION(
        IntPtr Client,
        IntPtr Target,
        byte LargeMotor,
        byte SmallMotor,
        byte LedNumber,
        IntPtr UserData);

    [DllImport("vigemclient.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr vigem_alloc();

    [DllImport("vigemclient.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern void vigem_free(IntPtr vigem);

    [DllImport("vigemclient.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern uint vigem_connect(IntPtr vigem);

    [DllImport("vigemclient.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern void vigem_disconnect(IntPtr vigem);

    [DllImport("vigemclient.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr vigem_target_x360_alloc();

    [DllImport("vigemclient.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern void vigem_target_free(IntPtr target);

    [DllImport("vigemclient.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern uint vigem_target_add(IntPtr vigem, IntPtr target);

    [DllImport("vigemclient.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern uint vigem_target_remove(IntPtr vigem, IntPtr target);

    [DllImport("vigemclient.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern uint vigem_target_x360_update(IntPtr vigem, IntPtr target, XUSB_REPORT report);

    [DllImport("vigemclient.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern uint vigem_target_x360_register_notification(IntPtr vigem, IntPtr target, EVT_VIGEM_X360_NOTIFICATION notification, IntPtr userData);

    // SendInput P/Invoke
    private const int INPUT_KEYBOARD = 1;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const uint KEYEVENTF_UNICODE = 0x0004;

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT {
        public int type;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public HARDWAREINPUT hi;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct HARDWAREINPUT {
        public uint uMsg;
        public ushort wParamL;
        public ushort wParamH;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll")]
    private static extern uint MapVirtualKeyW(uint uCode, uint uMapType);

    private static void SendVirtualKey(ushort vk, bool keyUp) {
        ushort scan = (ushort)MapVirtualKeyW(vk, 0);
        uint flags = keyUp ? KEYEVENTF_KEYUP : 0;
        if (vk == 0x25 || vk == 0x26 || vk == 0x27 || vk == 0x28) {
            flags |= 0x0001; // KEYEVENTF_EXTENDEDKEY
        }
        INPUT[] inputs = new INPUT[1];
        inputs[0].type = INPUT_KEYBOARD;
        inputs[0].U.ki.wVk = vk;
        inputs[0].U.ki.wScan = scan;
        inputs[0].U.ki.dwFlags = flags;
        SendInput(1, inputs, Marshal.SizeOf(typeof(INPUT)));
    }

    private static void SendUnicodeString(string text) {
        if (string.IsNullOrEmpty(text)) return;
        foreach (char c in text) {
            INPUT[] inputs = new INPUT[2];
            inputs[0].type = INPUT_KEYBOARD;
            inputs[0].U.ki.wVk = 0;
            inputs[0].U.ki.wScan = (ushort)c;
            inputs[0].U.ki.dwFlags = KEYEVENTF_UNICODE;

            inputs[1].type = INPUT_KEYBOARD;
            inputs[1].U.ki.wVk = 0;
            inputs[1].U.ki.wScan = (ushort)c;
            inputs[1].U.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;

            SendInput(2, inputs, Marshal.SizeOf(typeof(INPUT)));
        }
    }

    private class ControllerSlot {
        public int SlotIndex;
        public IntPtr InterfaceHandle;
        public byte InPipe;
        public byte OutPipe;
        public object WriteLock = new object();

        public bool Connected = false;
        public bool ChatpadInitNeeded = true;
        public bool KeepAliveToggle = false;
        public IntPtr ViGEmTarget = IntPtr.Zero;
        public EVT_VIGEM_X360_NOTIFICATION NotificationDelegate;

        public byte[] LastChatpadBytes = new byte[3];
        public bool ModGreen = false;
        public bool ModOrange = false;
        public bool ModShift = false;
        public bool ModMessenger = false;
        public bool CapsLock = false;

        public bool LedGreen = false;
        public bool LedOrange = false;
        public bool LedMessenger = false;
        public bool LedCapsLock = false;
        public bool ShiftSentDown = false;

        public List<byte> HeldChatpadKeys = new List<byte>();
        public List<ushort> HeldVirtualKeys = new List<ushort>();
    }

    private SafeFileHandle _deviceFileHandle;
    private IntPtr _rootWinUsbHandle = IntPtr.Zero;
    private List<IntPtr> _assocHandles = new List<IntPtr>();
    private IntPtr _vigemClient = IntPtr.Zero;
    private ControllerSlot[] _slots = new ControllerSlot[4];
    private volatile bool _running = false;
    private List<Thread> _threads = new List<Thread>();

    // Chatpad Key Tables (Standard QWERTY / DOBE TYX-517)
    private static readonly Dictionary<byte, ushort> KeyMap = new Dictionary<byte, ushort>() {
        { 23, 0x31 }, { 22, 0x32 }, { 21, 0x33 }, { 20, 0x34 }, { 19, 0x35 },
        { 18, 0x36 }, { 17, 0x37 }, { 103, 0x38 }, { 102, 0x39 }, { 101, 0x30 },
        { 39, 0x51 }, { 38, 0x57 }, { 37, 0x45 }, { 36, 0x52 }, { 35, 0x54 },
        { 34, 0x59 }, { 33, 0x55 }, { 118, 0x49 }, { 117, 0x4F }, { 100, 0x50 },
        { 55, 0x41 }, { 54, 0x53 }, { 53, 0x44 }, { 52, 0x46 }, { 51, 0x47 },
        { 50, 0x48 }, { 49, 0x4A }, { 119, 0x4B }, { 114, 0x4C }, { 98, 0xBC },
        { 70, 0x5A }, { 69, 0x58 }, { 68, 0x43 }, { 67, 0x56 }, { 66, 0x42 },
        { 65, 0x4E }, { 82, 0x4D }, { 83, 0xBE },
        { 99, 0x0D }, // Enter
        { 85, 0x25 }, // Left
        { 84, 0x20 }, // Space
        { 81, 0x27 }, // Right
        { 113, 0x08 } // Backspace
    };

    private static readonly Dictionary<byte, string> GreenMap = new Dictionary<byte, string>() {
        { 39, "!" }, { 38, "@" }, { 37, "€" }, { 36, "#" }, { 35, "%" },
        { 34, "^" }, { 33, "&" }, { 118, "*" }, { 117, "(" }, { 100, ")" },
        { 55, "~" }, { 54, "š" }, { 53, "{" }, { 52, "}" }, { 51, "¨" },
        { 50, "/" }, { 49, "'" }, { 119, "[" }, { 114, "]" }, { 98, ":" },
        { 70, "`" }, { 69, "«" }, { 68, "»" }, { 67, "-" }, { 66, "|" },
        { 65, "<" }, { 82, ">" }, { 83, "?" }
    };

    private static readonly Dictionary<byte, string> OrangeMap = new Dictionary<byte, string>() {
        { 39, "¡" }, { 38, "å" }, { 37, "é" }, { 36, "$" }, { 35, "Þ" },
        { 34, "ý" }, { 33, "ú" }, { 118, "í" }, { 117, "ó" }, { 100, "=" },
        { 55, "á" }, { 54, "ß" }, { 53, "ð" }, { 52, "£" }, { 51, "¥" },
        { 50, "\\" }, { 49, "\"" }, { 119, "$" }, { 114, "ø" }, { 98, ";" },
        { 70, "æ" }, { 69, "œ" }, { 68, "ç" }, { 67, "_" }, { 66, "+" },
        { 65, "ñ" }, { 82, "µ" }, { 83, "¿" }
    };

    public void Start(string instanceId) {
        string normalized = instanceId.Replace('\\', '#').ToLowerInvariant();
        string[] candidateGuids = new string[] {
            "{f72fe0d4-cbcb-407d-8814-9ed673d0dd6b}", // ADB Device (winusb.inf)
            "{a5dcbf10-6530-11d2-901f-00c04fb951ed}"  // GUID_DEVINTERFACE_USB_DEVICE
        };

        foreach (string guid in candidateGuids) {
            string path = "\\\\?\\" + normalized + "#" + guid;
            SafeFileHandle h = CreateFileW(path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, IntPtr.Zero);
            if (!h.IsInvalid) {
                IntPtr winUsb;
                if (WinUsb_Initialize(h, out winUsb)) {
                    _deviceFileHandle = h;
                    _rootWinUsbHandle = winUsb;
                    Console.WriteLine("[OK] Opened WinUSB receiver handle at " + path);
                    break;
                } else {
                    h.Close();
                }
            }
        }

        if (_rootWinUsbHandle == IntPtr.Zero) {
            throw new Exception("Could not open WinUSB handle for " + instanceId + ". Ensure the WinUSB driver is installed.");
        }

        List<IntPtr> allInterfaces = new List<IntPtr>() { _rootWinUsbHandle };
        for (byte i = 0; i < 8; i++) {
            IntPtr assoc;
            if (WinUsb_GetAssociatedInterface(_rootWinUsbHandle, i, out assoc)) {
                _assocHandles.Add(assoc);
                allInterfaces.Add(assoc);
            }
        }

        foreach (IntPtr intf in allInterfaces) {
            USB_INTERFACE_DESCRIPTOR desc;
            if (WinUsb_QueryInterfaceSettings(intf, 0, out desc)) {
                byte inPipe = 0;
                byte outPipe = 0;
                for (byte p = 0; p < desc.bNumEndpoints; p++) {
                    WINUSB_PIPE_INFORMATION pipeInfo;
                    if (WinUsb_QueryPipe(intf, 0, p, out pipeInfo)) {
                        if ((pipeInfo.PipeId & 0x80) != 0) inPipe = pipeInfo.PipeId;
                        else outPipe = pipeInfo.PipeId;
                    }
                }
                int slotIdx = -1;
                if (inPipe == 0x81 || outPipe == 0x01) slotIdx = 0;
                else if (inPipe == 0x83 || outPipe == 0x03) slotIdx = 1;
                else if (inPipe == 0x85 || outPipe == 0x05) slotIdx = 2;
                else if (inPipe == 0x87 || outPipe == 0x07) slotIdx = 3;

                if (slotIdx >= 0 && _slots[slotIdx] == null) {
                    uint readTimeout = 100;
                    uint writeTimeout = 500;
                    WinUsb_SetPipePolicy(intf, inPipe, PIPE_TRANSFER_TIMEOUT, 4, ref readTimeout);
                    WinUsb_SetPipePolicy(intf, outPipe, PIPE_TRANSFER_TIMEOUT, 4, ref writeTimeout);

                    _slots[slotIdx] = new ControllerSlot() {
                        SlotIndex = slotIdx,
                        InterfaceHandle = intf,
                        InPipe = inPipe,
                        OutPipe = outPipe
                    };
                    Console.WriteLine(string.Format("[OK] Bound Controller Slot {0} (IN=0x{1:X2}, OUT=0x{2:X2})", slotIdx + 1, inPipe, outPipe));
                }
            }
        }

        _vigemClient = vigem_alloc();
        uint vRes = vigem_connect(_vigemClient);
        if (vRes != 0x20000000) {
            throw new Exception(string.Format("vigem_connect failed with 0x{0:X8}. Ensure Nefarius ViGEmBus is installed.", vRes));
        }
        Console.WriteLine("[OK] Connected to Nefarius ViGEmBus!");

        _running = true;

        for (int i = 0; i < 4; i++) {
            if (_slots[i] != null) {
                ControllerSlot slot = _slots[i];
                Thread readThread = new Thread(() => ReadLoop(slot)) { IsBackground = true, Name = "Reader_" + i };
                Thread keepAliveThread = new Thread(() => KeepAliveLoop(slot)) { IsBackground = true, Name = "KeepAlive_" + i };
                _threads.Add(readThread);
                _threads.Add(keepAliveThread);
                readThread.Start();
                keepAliveThread.Start();

                SendCommand(slot, new byte[] { 0x08, 0x00, 0x00, 0x00 });
                SendCommand(slot, new byte[] { 0x08, 0x00, 0x00, 0x00 });
            }
        }
    }

    private void SendCommand(ControllerSlot slot, byte[] cmd) {
        lock (slot.WriteLock) {
            uint written;
            WinUsb_WritePipe(slot.InterfaceHandle, slot.OutPipe, cmd, (uint)cmd.Length, out written, IntPtr.Zero);
        }
    }

    private void EnsureControllerConnected(ControllerSlot slot) {
        if (!slot.Connected) {
            slot.Connected = true;
            slot.ChatpadInitNeeded = true;

            IntPtr target = vigem_target_x360_alloc();
            vigem_target_add(_vigemClient, target);
            slot.ViGEmTarget = target;
            slot.NotificationDelegate = (client, tgt, largeMotor, smallMotor, ledNumber, userData) => {
                byte[] rumble = new byte[] { 0x00, 0x01, 0x0F, 0xC0, 0x00, largeMotor, smallMotor, 0x00, 0x00, 0x00, 0x00, 0x00 };
                SendCommand(slot, rumble);
            };
            vigem_target_x360_register_notification(_vigemClient, target, slot.NotificationDelegate, IntPtr.Zero);

            // Set LED ring quadrant (0x42 = Player 1 .. 0x45 = Player 4)
            SendCommand(slot, new byte[] { 0x00, 0x00, 0x08, (byte)(0x42 + slot.SlotIndex) });
            // Send immediate Chatpad wake + keepalive
            SendCommand(slot, new byte[] { 0x00, 0x00, 0x0C, 0x1F });
            SendCommand(slot, new byte[] { 0x00, 0x00, 0x0C, 0x1B });
            Console.WriteLine(string.Format("[CONNECTED] Wireless Controller {0} + Chatpad ready!", slot.SlotIndex + 1));
        }
    }

    private void DisconnectController(ControllerSlot slot) {
        if (slot.Connected) {
            slot.Connected = false;
            if (slot.ViGEmTarget != IntPtr.Zero) {
                try {
                    vigem_target_remove(_vigemClient, slot.ViGEmTarget);
                    vigem_target_free(slot.ViGEmTarget);
                } catch { }
                slot.ViGEmTarget = IntPtr.Zero;
            }
            Console.WriteLine(string.Format("[DISCONNECTED] Wireless Controller {0}", slot.SlotIndex + 1));
        }
    }

    private void KeepAliveLoop(ControllerSlot slot) {
        while (_running) {
            try {
                if (slot.Connected) {
                    if (slot.KeepAliveToggle) {
                        SendCommand(slot, new byte[] { 0x00, 0x00, 0x0C, 0x1F });
                    } else {
                        SendCommand(slot, new byte[] { 0x00, 0x00, 0x0C, 0x1E });
                    }
                    slot.KeepAliveToggle = !slot.KeepAliveToggle;

                    if (slot.ChatpadInitNeeded) {
                        SendCommand(slot, new byte[] { 0x00, 0x00, 0x0C, 0x1B });
                        slot.ChatpadInitNeeded = false;
                    }
                }
            } catch { }
            Thread.Sleep(900);
        }
    }

    private void ReadLoop(ControllerSlot slot) {
        byte[] buf = new byte[32];
        while (_running) {
            uint transferred = 0;
            bool ok = WinUsb_ReadPipe(slot.InterfaceHandle, slot.InPipe, buf, (uint)buf.Length, out transferred, IntPtr.Zero);
            if (!ok || transferred == 0) {
                continue;
            }

            if (buf[0] == 0x08 && transferred >= 2) {
                bool isConn = (buf[1] & 0x80) != 0;
                if (isConn) {
                    EnsureControllerConnected(slot);
                } else {
                    DisconnectController(slot);
                }
            } else if (buf[0] == 0x00 && transferred >= 28 && buf[2] == 0x00 && buf[3] == 0xF0) {
                EnsureControllerConnected(slot);

                if ((buf[1] & 0x01) != 0) {
                    ProcessGamepadReport(slot, buf);
                }
                if ((buf[1] & 0x02) != 0) {
                    ProcessChatpadReport(slot, buf);
                }
            }
        }
    }

    private void ProcessGamepadReport(ControllerSlot slot, byte[] buf) {
        if (slot.ViGEmTarget == IntPtr.Zero) return;

        XUSB_REPORT report = new XUSB_REPORT();
        report.wButtons = (ushort)(buf[6] | (buf[7] << 8));
        report.bLeftTrigger = buf[8];
        report.bRightTrigger = buf[9];
        report.sThumbLX = (short)(buf[10] | (buf[11] << 8));
        report.sThumbLY = (short)(buf[12] | (buf[13] << 8));
        report.sThumbRX = (short)(buf[14] | (buf[15] << 8));
        report.sThumbRY = (short)(buf[16] | (buf[17] << 8));

        vigem_target_x360_update(_vigemClient, slot.ViGEmTarget, report);
    }

    private void ProcessChatpadReport(ControllerSlot slot, byte[] buf) {
        if (buf[24] == 0xF0) {
            if (buf[25] == 0x03) {
                slot.ChatpadInitNeeded = true;
                SendCommand(slot, new byte[] { 0x00, 0x00, 0x0C, 0x1B });
                Console.WriteLine(string.Format("[CHATPAD] Controller {0} Chatpad handshake complete!", slot.SlotIndex + 1));
            }
            return;
        }

        if (buf[24] != 0x00) return;

        byte mod = buf[25];
        byte k1 = buf[26];
        byte k2 = buf[27];

        if (slot.LastChatpadBytes[0] == mod && slot.LastChatpadBytes[1] == k1 && slot.LastChatpadBytes[2] == k2) {
            return;
        }
        slot.LastChatpadBytes[0] = mod;
        slot.LastChatpadBytes[1] = k1;
        slot.LastChatpadBytes[2] = k2;

        bool prevMessenger = slot.ModMessenger;
        slot.ModShift = (mod & 0x01) != 0;
        slot.ModGreen = (mod & 0x02) != 0;
        slot.ModOrange = (mod & 0x04) != 0;
        slot.ModMessenger = (mod & 0x08) != 0;

        if (slot.ModOrange && slot.ModShift) {
            slot.CapsLock = !slot.CapsLock;
        }

        if (slot.ModGreen != slot.LedGreen) {
            SendCommand(slot, new byte[] { 0x00, 0x00, 0x0C, (byte)(slot.ModGreen ? 0x09 : 0x01) });
            slot.LedGreen = slot.ModGreen;
        }
        if (slot.ModOrange != slot.LedOrange) {
            SendCommand(slot, new byte[] { 0x00, 0x00, 0x0C, (byte)(slot.ModOrange ? 0x0A : 0x02) });
            slot.LedOrange = slot.ModOrange;
        }
        if (slot.ModMessenger != slot.LedMessenger) {
            SendCommand(slot, new byte[] { 0x00, 0x00, 0x0C, (byte)(slot.ModMessenger ? 0x0B : 0x03) });
            slot.LedMessenger = slot.ModMessenger;
        }
        if (slot.CapsLock != slot.LedCapsLock) {
            SendCommand(slot, new byte[] { 0x00, 0x00, 0x0C, (byte)(slot.CapsLock ? 0x08 : 0x00) });
            slot.LedCapsLock = slot.CapsLock;
        }

        if (slot.ModMessenger && !prevMessenger) {
            SendVirtualKey(0x09, false);
        } else if (!slot.ModMessenger && prevMessenger) {
            SendVirtualKey(0x09, true);
        }

        bool upperCase = slot.ModShift ^ slot.CapsLock;
        if (!slot.ModGreen && !slot.ModOrange) {
            if (upperCase && !slot.ShiftSentDown) {
                SendVirtualKey(0xA0, false);
                slot.ShiftSentDown = true;
            } else if (!upperCase && slot.ShiftSentDown) {
                SendVirtualKey(0xA0, true);
                slot.ShiftSentDown = false;
            }
        } else if (slot.ShiftSentDown) {
            SendVirtualKey(0xA0, true);
            slot.ShiftSentDown = false;
        }

        HandleKeyDown(slot, k1, upperCase);
        HandleKeyDown(slot, k2, upperCase);

        List<byte> toRemove = new List<byte>();
        foreach (byte held in slot.HeldChatpadKeys) {
            if (held != k1 && held != k2) {
                toRemove.Add(held);
            }
        }
        foreach (byte released in toRemove) {
            slot.HeldChatpadKeys.Remove(released);
            if (KeyMap.ContainsKey(released)) {
                ushort vk = KeyMap[released];
                if (slot.HeldVirtualKeys.Contains(vk)) {
                    slot.HeldVirtualKeys.Remove(vk);
                    SendVirtualKey(vk, true);
                }
            }
        }
    }

    private void HandleKeyDown(ControllerSlot slot, byte key, bool upperCase) {
        if (key == 0 || slot.HeldChatpadKeys.Contains(key)) return;
        slot.HeldChatpadKeys.Add(key);

        if (slot.ModOrange && OrangeMap.ContainsKey(key)) {
            string s = OrangeMap[key];
            if (upperCase) s = s.ToUpperInvariant();
            SendUnicodeString(s);
        } else if (slot.ModGreen && GreenMap.ContainsKey(key)) {
            string s = GreenMap[key];
            if (upperCase) s = s.ToUpperInvariant();
            SendUnicodeString(s);
        } else if (KeyMap.ContainsKey(key)) {
            ushort vk = KeyMap[key];
            slot.HeldVirtualKeys.Add(vk);
            SendVirtualKey(vk, false);
        }
    }

    public void Dispose() {
        _running = false;
        Thread.Sleep(250);
        for (int i = 0; i < 4; i++) {
            if (_slots[i] != null && _slots[i].ViGEmTarget != IntPtr.Zero) {
                try {
                    vigem_target_remove(_vigemClient, _slots[i].ViGEmTarget);
                    vigem_target_free(_slots[i].ViGEmTarget);
                } catch { }
                _slots[i].ViGEmTarget = IntPtr.Zero;
            }
        }
        if (_vigemClient != IntPtr.Zero) {
            try {
                vigem_disconnect(_vigemClient);
                vigem_free(_vigemClient);
            } catch { }
            _vigemClient = IntPtr.Zero;
        }
        foreach (IntPtr h in _assocHandles) {
            WinUsb_Free(h);
        }
        if (_rootWinUsbHandle != IntPtr.Zero) {
            WinUsb_Free(_rootWinUsbHandle);
        }
        if (_deviceFileHandle != null && !_deviceFileHandle.IsInvalid) {
            _deviceFileHandle.Close();
        }
    }
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

if ($RestoreMicrosoftDriver) {
    $infFile = (Get-ChildItem "C:\Windows\INF\xusb*.inf" | Sort-Object Name -Descending | Select-Object -First 1).FullName
    Write-Host "Restoring standard Microsoft Xbox 360 Wireless Receiver driver ($infFile)..." -ForegroundColor Cyan
    [ReceiverDriverSwitcher]::InstallInfDriver($deviceId, $infFile, "Xbox 360 Wireless Receiver for Windows")
    & pnputil.exe /restart-device "$deviceId" | Out-Null
    Write-Host "Restored standard Microsoft driver successfully!" -ForegroundColor Green
    exit 0
}

$service = (Get-PnpDeviceProperty -InstanceId $deviceId -KeyName 'DEVPKEY_Device_Service').Data
if ($service -ne 'WINUSB') {
    Write-Host "Switching receiver $deviceId from '$service' to WinUSB (C:\Windows\INF\winusb.inf)..." -ForegroundColor Cyan
    [ReceiverDriverSwitcher]::InstallInfDriver($deviceId, "C:\Windows\INF\winusb.inf", "ADB Device")
    Start-Sleep -Seconds 1
}

$stack = (Get-PnpDeviceProperty -InstanceId $deviceId -KeyName 'DEVPKEY_Device_Stack' -ErrorAction SilentlyContinue).Data
if ($stack -contains '\Driver\xusb22' -or $stack -contains '\Driver\xusb21') {
    Write-Host "Unloading active xusb child nodes and restarting USB receiver..." -ForegroundColor Yellow
    Get-PnpDevice | Where-Object { $_.InstanceId -like 'USB\VID_045E&PID_02A1*' -and $_.Present } | ForEach-Object {
        & pnputil.exe /remove-device "$($_.InstanceId)" | Out-Null
    }
    & pnputil.exe /restart-device "$deviceId" | Out-Null
    Start-Sleep -Seconds 2
    $stack = (Get-PnpDeviceProperty -InstanceId $deviceId -KeyName 'DEVPKEY_Device_Stack' -ErrorAction SilentlyContinue).Data
}

if ($stack -contains '\Driver\xusb22' -or $stack -contains '\Driver\xusb21') {
    Write-Host ""
    Write-Host ">>> ACTION NEEDED: Unplug the Xbox 360 USB receiver for 2 seconds and plug it back in <<<" -ForegroundColor Yellow
    Write-Host "Waiting for USB receiver to reconnect with WinUSB driver..." -ForegroundColor Cyan
    while ($true) {
        Start-Sleep -Milliseconds 800
        $dev = Get-PnpDevice | Where-Object { $_.InstanceId -match '^USB\\VID_045E&PID_(02A9|0291|0719)\\' -and $_.Present } | Select-Object -First 1
        if ($dev) {
            $deviceId = $dev.InstanceId
            $curStack = (Get-PnpDeviceProperty -InstanceId $deviceId -KeyName 'DEVPKEY_Device_Stack' -ErrorAction SilentlyContinue).Data
            if ($curStack -and ($curStack -notcontains '\Driver\xusb22') -and ($curStack -notcontains '\Driver\xusb21')) {
                Write-Host "Receiver reconnected with WinUSB driver stack ($($curStack -join ', '))!" -ForegroundColor Green
                Start-Sleep -Seconds 1
                break
            }
        }
    }
}

if ($InstallWinUsbOnly) {
    exit 0
}

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " Xbox 360 Wireless Controller + DOBE TYX-517 Chatpad Bridge" -ForegroundColor Cyan
Write-Host " Press Ctrl+C to stop (or run with -RestoreMicrosoftDriver)" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

$bridge = New-Object XboxWirelessChatpadBridge
try {
    $bridge.Start($deviceId)
    while ($true) {
        Start-Sleep -Seconds 1
    }
} finally {
    $bridge.Dispose()
}
