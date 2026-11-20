# Xbox 360 Wireless Controller & Chatpad Bridge for Windows 10/11

Bring your **Xbox 360 Wireless Controllers**, **Xbox 360 Console RF Module USB Receivers (`PID_02A9`)**, third-party receivers (`PID_0291`), and clip-on **Xbox 360 Chatpads** (both the official Microsoft Chatpad and the **DOBE TYX-517**) back to life on modern Windows 10 and Windows 11 — **without Zadig, `libusb-win32`, `vJoy`, or disabling Secure Boot / Core Isolation (HVCI)**.

---

## Why This Exists

Microsoft's official Windows driver for the Xbox 360 Wireless Receiver (`xusb22.sys`) has two longstanding gaps:
1. **Unrecognized Receiver Hardware IDs (Code 28)**: Official Xbox 360 Console RF boards wired to USB (`VID_045E&PID_02A9`) and third-party wireless receivers (`VID_045E&PID_0291`) fail automatic driver installation because `xusb22.inf` only lists `PID_0719`.
2. **No Wireless Chatpad Support**: Even when `xusb22.sys` is bound, Microsoft never implemented the Chatpad wake/keepalive heartbeat or serial packet parser in the Windows wireless driver — so a clipped-on Xbox 360 Chatpad or **DOBE TYX-517** stays completely dead on PC.

Older 2012–2013 community tools (`xbox360wirelesschatpad`) required replacing the driver with unsigned `libusb-win32` via Zadig, routing controller input through `vJoy` (which only creates a legacy DirectInput joystick instead of an XInput Xbox 360 controller), lacked `PID_02A9` support, and suffered from a 3-second keep-alive inhibit bug that froze typing after a few characters.

### What This Project Does Differently
* **100% Built-in Microsoft-Signed Drivers**: Uses Windows SetupAPI (`SetupDiSetSelectedDriver` + `DiInstallDevice`) to bind either:
  * `C:\Windows\INF\xusb22.inf` (**Mode 1: Controllers Only**), or
  * `C:\Windows\INF\winusb.inf` (**Mode 2: Controllers + Wireless Chatpad Bridge**).
* **True XInput Gamepads via Nefarius ViGEmBus**: Forwards all 4 wireless controller slots (buttons, triggers, thumbsticks, LED quadrant ring, and dual-motor rumble) directly to `ViGEmBus` as raw 12-byte `XUSB_REPORT` frames — every modern game sees native Xbox 360 XInput controllers.
* **Full Wireless Chatpad Keyboard (`SendInput`)**: Wakes and maintains the 1-second heartbeat (`00 00 0C 1F` / `1E` + `1B` handshake) for the official Xbox 360 Chatpad and **DOBE TYX-517**, controls the Chatpad modifier LEDs, and injects hardware scan codes + Unicode symbol layers (`Green` and `Orange` modifiers) directly into Windows.
* **Single-File PowerShell + Embedded C#**: No Visual Studio build required; runs directly in Windows PowerShell 5.1 or PowerShell 7.

---

## Supported Hardware

### USB Wireless Receivers
| Hardware Variant | Vendor ID | Product ID | Hardware ID | Supported |
| :--- | :--- | :--- | :--- | :---: |
| **Official Xbox 360 Wireless Gaming Receiver for Windows** | `045E` | `0719` | `USB\VID_045E&PID_0719` | Yes |
| **Xbox 360 Console Internal RF Module (USB Adapter Mod)** | `045E` | `02A9` | `USB\VID_045E&PID_02A9` | Yes |
| **Third-Party / Generic Xbox 360 Wireless Receiver** | `045E` | `0291` | `USB\VID_045E&PID_0291` | Yes |

### Controllers & Chatpads
* **Original Microsoft Xbox 360 Wireless Controller** (up to 4 controllers per receiver)
* **Official Microsoft Xbox 360 Chatpad** (clips into the bottom 4-pin serial expansion port + 2.5mm headset jack)
* **DOBE Fomis Electronics TYX-517** Xbox 360 Mini Keyboard / Chatpad

---

## Quick Start

### Mode 1: Controllers Only (Bind Official Microsoft `xusb22.inf` Driver)

If you just want your `PID_02A9` or `PID_0291` USB receiver to work as a standard plug-and-play Xbox 360 Wireless Receiver in Windows without clicking through Device Manager:

1. Open **PowerShell as Administrator**.
2. Run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install_xbox_receiver.ps1
   ```

Your receiver will immediately appear under **Xbox 360 Peripherals** as **Xbox 360 Wireless Receiver for Windows**, and up to 4 wireless controllers will work natively.

---

### Mode 2: Controllers + Wireless Chatpad (`WinUSB` + `ViGEmBus` Bridge)

If you have an **Xbox 360 Chatpad** or **DOBE TYX-517** clipped onto your wireless controller and want both the **controller (XInput)** and the **mini-keyboard** to work simultaneously:

#### Prerequisite
* Install [**Nefarius ViGEmBus Driver**](https://github.com/nefarius/ViGEmBus/releases) (if you use DS4Windows, Sunshine, Parsec, or Steam virtual gamepads, you likely already have it installed).

#### First Run (Switches Driver to WinUSB & Starts Bridge)
1. Open **PowerShell as Administrator** (only required the first time to switch the driver from `xusb22.inf` to `winusb.inf`).
2. Run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\start_chatpad_bridge.ps1
   ```
   * On first run, the script automatically downloads `vigemclient.dll` from the official `Nefarius.ViGEm.Client` NuGet package, binds your receiver to Windows's built-in `winusb.inf`, unloads any active `xusb22` child nodes, and starts the bridge.
   * *(Note: After the driver is switched to `WinUSB` once, future runs of `start_chatpad_bridge.ps1` do **not** require Administrator privileges.)*

#### Reverting Back to the Standalone Microsoft Driver
Whenever you want to return the receiver to the standalone Microsoft `xusb22.inf` driver without running the bridge, run this in an **Administrator PowerShell**:
```powershell
powershell -ExecutionPolicy Bypass -File .\start_chatpad_bridge.ps1 -RestoreMicrosoftDriver
```

---

## Chatpad Key & Modifier Layout (Official & DOBE TYX-517)

| Key / Combo | Windows Action |
| :--- | :--- |
| **Letters (`A`–`Z`) & Numbers (`1`–`0`)** | Standard keystrokes via Win32 `SendInput` scan codes |
| **Shift** | Upper-case next/held letter |
| **Orange + Shift** | Toggles **Caps Lock** (and illuminates the Caps Lock LED) |
| **Green Square Modifier + Key** | Types the green symbol printed on the keycap: `! @ € # % ^ & * ( ) ~ { } / ' [ ] : ` - \| < > ?` |
| **Orange Circle Modifier + Key** | Types the orange symbol/character printed on the keycap: `¡ å é $ Þ ý ú í ó = á ß ð £ ¥ \ " ø ; æ œ ç _ + ñ µ ¿` |
| **Messenger Key (Person Icon)** | Acts as `Tab` |
| **Enter / Backspace / Space / Left / Right** | Native `Enter`, `Backspace`, `Space`, `Left Arrow`, `Right Arrow` |

---

## Technical Reference: Xbox 360 Wireless Receiver & Chatpad USB Protocol

### 1. USB Endpoints (`VID_045E`, `PID_0719` / `0291` / `02A9`)
A single Xbox 360 Wireless Receiver exposes 8 USB interfaces (4 controller data interfaces + 4 voice headset audio interfaces):

| Controller Slot | USB Interface | Interrupt IN Pipe (Device → Host) | Interrupt OUT Pipe (Host → Device) |
| :---: | :---: | :---: | :---: |
| **Player 1** | Interface 0 | `0x81` (32B max, 29B payload) | `0x01` (4B / 12B commands) |
| **Player 2** | Interface 2 | `0x83` (32B max, 29B payload) | `0x03` (4B / 12B commands) |
| **Player 3** | Interface 4 | `0x85` (32B max, 29B payload) | `0x05` (4B / 12B commands) |
| **Player 4** | Interface 6 | `0x87` (32B max, 29B payload) | `0x07` (4B / 12B commands) |

### 2. Incoming Packets (29 Bytes on `EP 0x81 / 0x83 / 0x85 / 0x87`)

* **Connection Status Frame (`buf[0] == 0x08`)**:
  * `(buf[1] & 0x80) != 0`: Controller connected (`0x80` = controller, `0xC0` = controller + accessory/headset).
  * `buf[1] == 0x00`: Controller disconnected.
* **Controller / Chatpad Data Frame (`buf[0] == 0x00 && buf[2] == 0x00 && buf[3] == 0xF0`)**:
  * `buf[1]` is a bitmask of active sub-reports in the 29-byte frame:
    * **Bit 0 (`(buf[1] & 0x01) != 0`) — Gamepad State (`buf[6..17]`)**:
      Bytes `6..17` are a verbatim 12-byte little-endian `XUSB_REPORT` struct:
      * `uint16 wButtons` (`buf[6..7]`): D-Pad (`0x0001..0x0008`), Start (`0x0010`), Back (`0x0020`), L3/R3 (`0x0040`/`0x0080`), LB/RB (`0x0100`/`0x0200`), Guide (`0x0400`), A/B/X/Y (`0x1000..0x8000`)
      * `uint8 bLeftTrigger` (`buf[8]`), `uint8 bRightTrigger` (`buf[9]`)
      * `int16 sThumbLX` (`buf[10..11]`), `int16 sThumbLY` (`buf[12..13]`)
      * `int16 sThumbRX` (`buf[14..15]`), `int16 sThumbRY` (`buf[16..17]`)
    * **Bit 1 (`(buf[1] & 0x02) != 0`) — Chatpad Report (`buf[24..27]`)**:
      * `buf[24] == 0xF0 && buf[25] == 0x03`: Chatpad handshake request (host must reply with `00 00 0C 1B`).
      * `buf[24] == 0x00`: Keystroke state report:
        * `buf[25]`: Modifier bitmask (`0x01` = Shift, `0x02` = Green, `0x04` = Orange, `0x08` = Messenger)
        * `buf[26]`: Primary held key code (`0x00` if none)
        * `buf[27]`: Secondary held key code (`0x00` if none; Chatpad hardware supports 2 simultaneous non-modifier keys)

### 3. Outgoing Commands (to `EP 0x01 / 0x03 / 0x05 / 0x07`)

| Command | Hex Bytes | Purpose |
| :--- | :--- | :--- |
| **Query Presence** | `08 00 00 00` | Requests immediate `0x08` connection status packet from the receiver |
| **Set Player 1..4 LED** | `00 00 08 42` .. `45` | Illuminates quadrant 1..4 on the Xbox Guide ring |
| **Chatpad Keep-Alive 1** | `00 00 0C 1F` | Sent on alternating ~900ms ticks to keep the Chatpad awake |
| **Chatpad Keep-Alive 2** | `00 00 0C 1E` | Sent on alternating ~900ms ticks to keep the Chatpad awake |
| **Chatpad Handshake Init** | `00 00 0C 1B` | Sent on initial connect and whenever `buf[24..25] == F0 03` is received |
| **Chatpad LEDs On/Off** | `00 00 0C <cmd>` | Green (`09`/`01`), Orange (`0A`/`02`), Messenger (`0B`/`03`), CapsLock (`08`/`00`) |
| **Rumble Feedback** | `00 01 0F C0 00 <L> <R> 00 00 00 00 00` | 12-byte dual-motor vibration packet (`L` = large motor, `R` = small motor) |

> **Why Older Drivers Froze After Typing 3–4 Letters**:
> Legacy implementations set an `inhibitKeepAlive = true` flag for 3 ticks (3 seconds) every time a key state changed. While typing normal letters or numbers continuously, the `1F`/`1E` keep-alive heartbeat was suppressed long enough for the Chatpad's internal ~3-second watchdog timer to expire and drop back to sleep. Synchronizing `WinUsb_WritePipe` with a lock and keeping the 900ms `1F`/`1E` heartbeat continuous completely eliminates typing freezes.

---

## License
MIT License — see [LICENSE](LICENSE).
