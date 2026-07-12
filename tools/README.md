# TUNAI DSP Address Tester

**Lab-only tool. Not for production use.**

Tests ADAU1466 DSP parameter writes through ADI USBi via WinUSB.

---

## Safety Warning

This tool writes only to verified addresses:
- `0x0067` Master Volume L
- `0x0064` Master Volume R

All writes are **volatile** (RAM only). Power cycle restores DSP defaults.

**Do not** connect EEPROM-enabled firmware. This tool does not use SafeLoad, EEPROM, or selfboot.

---

## Transport note

USBi is a **temporary Windows engineering transport**.  
The intended final transport is **ICP5**.  
DSP addresses (`0x0067`, `0x0064`) are transport-independent and will be reused on ICP5.

---

## Requirements

- Windows 10/11 x64
- Visual Studio 2019 or 2022 with C++ Desktop workload
- CMake 3.16+
- ADI USBi hardware connected via USB
- WinUSB driver installed for the USBi device (see Zadig section)

---

## Zadig / WinUSB Driver Setup

The ADI USBi ships with a proprietary driver (ADI-provided).  
If the device is already working with SigmaStudio, **do not replace the driver**.

If you see "Access Denied" or "No device found" errors:

1. Download [Zadig](https://zadig.akeo.ie/)
2. Options → List All Devices
3. Select the USBi device (VID 0x0456)
4. Choose **WinUSB** from the driver drop-down
5. Click "Replace Driver"
6. Re-run the tester

> **Warning**: Replacing the driver will break SigmaStudio USB communication.  
> To restore: Device Manager → Update Driver → Search automatically.

---

## Build

```cmd
cd tunai_dsp_address_tester

cmake -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release
```

Output: `bin\tunai_dsp_address_tester.exe`

### Alternative: Visual Studio

```cmd
cmake -B build -G "Visual Studio 17 2022" -A x64
start build\tunai_dsp_address_tester.sln
```

Build in Visual Studio with **Release / x64** configuration.

---

## How to Run

```cmd
bin\tunai_dsp_address_tester.exe
```

The program opens a console menu:

```
 1. List USB devices
 2. Open ADI USBi
 3. Write Master Volume L = 1.0
 4. Write Master Volume L = 0.5
 5. Write Master Volume L = 0.0
 6. Write Master Volume R = 1.0
 7. Write Master Volume R = 0.5
 8. Write Master Volume R = 0.0
 9. Restore L/R to 1.0
10. Manual address dry-run preview
11. Exit
```

---

## Test Procedure (with multimeter)

### Setup
1. Connect ADAU1466 evaluation board power.
2. Connect ADI USBi USB to PC.
3. If DAC output pins are accessible, connect multimeter to DAC output.
4. Run tester. Select **1** to list devices — confirm VID 0x0456 appears.
5. Select **2** to open device — confirm "Device opened."

### Volume write test
1. Select **3** (Master Volume L = 1.0) — type `YES` to confirm.
2. Measure DAC output level. Note value as "full scale".
3. Select **4** (Master Volume L = 0.5).
4. Measure DAC output. Should be ~6 dB lower than step 2.
5. Select **5** (Master Volume L = 0.0).
6. Measure DAC output. Should be silence / rail-to-rail noise floor.

### Restore
- Select **9** to restore both L and R to 1.0.
- Power cycle also restores DSP defaults (volatile-only writes).

---

## Packet reference

### Setup packet (8 bytes)
```
40 B2 00 00 01 01 06 00
```

### Write body (6 bytes): [addr 2B BE] + [data 4B BE]
| Target | Address | Value | Body |
|--------|---------|-------|------|
| Master Volume L | 0x0067 | 0.5 | `00 67 00 80 00 00` |
| Master Volume R | 0x0064 | 1.0 | `00 64 01 00 00 00` |
| Master Volume R | 0x0064 | 0.0 | `00 64 00 00 00 00` |

### ACK read request (8 bytes)
```
C0 B5 00 00 00 00 01 00
```

### ACK success condition
Response byte index 6 == `0x01`

---

## Log file

Every write operation is appended to:
```
tunai_dsp_address_test_log.txt
```
(written in the current working directory)

---

## What this tool does NOT do

- PEQ write
- Crossover write
- Gain / Mute / Delay write
- SafeLoad
- EEPROM write
- Selfboot
- Write All
- Automatic write on startup
- Address range inference

---

## Restore procedure

Either:
- Select menu option **9** (Restore L/R to 1.0)
- Or power cycle the ADAU1466 board (all writes are volatile)
