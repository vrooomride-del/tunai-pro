#include "usbi_device.h"
#include <iostream>
#include <sstream>
#include <iomanip>
#include <algorithm>

// ── Windows-only section ────────────────────────────────────────────────────
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <setupapi.h>
#include <winusb.h>
#include <usbiodef.h>
#pragma comment(lib, "setupapi.lib")
#pragma comment(lib, "winusb.lib")

// USBi uses control transfers on a WinUSB device.
// Endpoint 0 (control) is addressed via WinUsb_ControlTransfer.
// Setup stage:  bmRequestType=0x40  bRequest=0xB2  wValue=0x0000
//               wIndex=0x0001  wLength=0x0001 (or 0x0006 for data phase)
// The full 8-byte "setup packet" in the spec is actually a vendor control
// request followed by the 6-byte body, then an IN to read the ACK.

// Translate the 8-byte "setup" buffer to a WINUSB_SETUP_PACKET
static WINUSB_SETUP_PACKET toWinUsbSetup(const std::vector<uint8_t>& pkt) {
    WINUSB_SETUP_PACKET sp{};
    if (pkt.size() >= 8) {
        sp.RequestType = pkt[0];
        sp.Request     = pkt[1];
        sp.Value       = static_cast<USHORT>(pkt[2] | (pkt[3] << 8));
        sp.Index       = static_cast<USHORT>(pkt[4] | (pkt[5] << 8));
        sp.Length      = static_cast<USHORT>(pkt[6] | (pkt[7] << 8));
    }
    return sp;
}

struct UsbiHandle {
    HANDLE    fileHandle  = INVALID_HANDLE_VALUE;
    WINUSB_INTERFACE_HANDLE winusbHandle = nullptr;
};

// ── Device enumeration ───────────────────────────────────────────────────────

static std::string wideToUtf8(const wchar_t* ws) {
    if (!ws) return "";
    int len = WideCharToMultiByte(CP_UTF8, 0, ws, -1, nullptr, 0, nullptr, nullptr);
    if (len <= 0) return "";
    std::string s(len - 1, '\0');
    WideCharToMultiByte(CP_UTF8, 0, ws, -1, s.data(), len, nullptr, nullptr);
    return s;
}

std::vector<UsbDeviceInfo> listUsbDevices() {
    std::vector<UsbDeviceInfo> result;

    HDEVINFO devInfo = SetupDiGetClassDevsW(
        nullptr, L"USB", nullptr,
        DIGCF_PRESENT | DIGCF_ALLCLASSES);
    if (devInfo == INVALID_HANDLE_VALUE) return result;

    SP_DEVINFO_DATA devData{};
    devData.cbSize = sizeof(devData);

    for (DWORD idx = 0; SetupDiEnumDeviceInfo(devInfo, idx, &devData); ++idx) {
        UsbDeviceInfo info{};
        info.winusbAccessible = false;

        // Instance ID (contains VID/PID)
        wchar_t instanceId[512]{};
        SetupDiGetDeviceInstanceIdW(devInfo, &devData, instanceId, 512, nullptr);
        info.instanceId = wideToUtf8(instanceId);

        // Parse VID/PID from instance string e.g. "USB\VID_0456&PID_B62B\..."
        std::string& iid = info.instanceId;
        auto parseHex16 = [&](const std::string& prefix) -> uint16_t {
            auto pos = iid.find(prefix);
            if (pos == std::string::npos) return 0;
            pos += prefix.size();
            auto end = iid.find_first_not_of("0123456789ABCDEFabcdef", pos);
            std::string hex = iid.substr(pos, end == std::string::npos ? 4 : end - pos);
            return static_cast<uint16_t>(std::stoul(hex, nullptr, 16));
        };
        info.vid = parseHex16("VID_");
        info.pid = parseHex16("PID_");
        info.likelyUsbi = (info.vid == ADI_USBI_VID);

        // Friendly name as "product"
        wchar_t desc[256]{};
        if (SetupDiGetDeviceRegistryPropertyW(devInfo, &devData,
                SPDRP_DEVICEDESC, nullptr,
                reinterpret_cast<PBYTE>(desc), sizeof(desc), nullptr)) {
            info.product = wideToUtf8(desc);
        }

        // Manufacturer
        wchar_t mfr[256]{};
        if (SetupDiGetDeviceRegistryPropertyW(devInfo, &devData,
                SPDRP_MFG, nullptr,
                reinterpret_cast<PBYTE>(mfr), sizeof(mfr), nullptr)) {
            info.manufacturer = wideToUtf8(mfr);
        }

        if (info.vid != 0)
            result.push_back(std::move(info));
    }

    SetupDiDestroyDeviceInfoList(devInfo);
    return result;
}

// ── Open device ─────────────────────────────────────────────────────────────

// Find device path for the ADI USBi via WinUSB GUID
static std::string findUsbiDevicePath(std::string& errorOut) {
    const GUID winusbGuid = GUID_DEVINTERFACE_USB_DEVICE;

    HDEVINFO devInfo = SetupDiGetClassDevsW(
        &winusbGuid, nullptr, nullptr,
        DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
    if (devInfo == INVALID_HANDLE_VALUE) {
        errorOut = "SetupDiGetClassDevs failed";
        return "";
    }

    SP_DEVICE_INTERFACE_DATA ifaceData{};
    ifaceData.cbSize = sizeof(ifaceData);

    std::string found;
    for (DWORD idx = 0;
         SetupDiEnumDeviceInterfaces(devInfo, nullptr, &winusbGuid, idx, &ifaceData);
         ++idx)
    {
        DWORD needed = 0;
        SetupDiGetDeviceInterfaceDetailW(devInfo, &ifaceData, nullptr, 0, &needed, nullptr);
        if (needed == 0) continue;

        std::vector<BYTE> buf(needed);
        auto* detail = reinterpret_cast<SP_DEVICE_INTERFACE_DETAIL_DATA_W*>(buf.data());
        detail->cbSize = sizeof(SP_DEVICE_INTERFACE_DETAIL_DATA_W);

        SP_DEVINFO_DATA devData{};
        devData.cbSize = sizeof(devData);
        if (!SetupDiGetDeviceInterfaceDetailW(
                devInfo, &ifaceData, detail, needed, nullptr, &devData))
            continue;

        // Check VID in instance ID
        wchar_t instanceId[512]{};
        SetupDiGetDeviceInstanceIdW(devInfo, &devData, instanceId, 512, nullptr);
        std::wstring iid(instanceId);
        std::wstring vidStr = L"VID_0456";
        // Case-insensitive search
        std::wstring iidUpper = iid;
        std::transform(iidUpper.begin(), iidUpper.end(), iidUpper.begin(), ::towupper);
        if (iidUpper.find(L"VID_0456") != std::wstring::npos) {
            // Convert path to narrow string
            int len = WideCharToMultiByte(CP_UTF8, 0, detail->DevicePath, -1,
                                          nullptr, 0, nullptr, nullptr);
            if (len > 0) {
                found.resize(len - 1);
                WideCharToMultiByte(CP_UTF8, 0, detail->DevicePath, -1,
                                    found.data(), len, nullptr, nullptr);
            }
            break;
        }
    }

    SetupDiDestroyDeviceInfoList(devInfo);

    if (found.empty())
        errorOut = "No ADI USBi device found (VID 0x0456). Is it connected?";
    return found;
}

UsbiHandle* openUsbiDevice(std::string& errorOut) {
    std::string path = findUsbiDevicePath(errorOut);
    if (path.empty()) return nullptr;

    // Convert path back to wide for CreateFile
    int wlen = MultiByteToWideChar(CP_UTF8, 0, path.c_str(), -1, nullptr, 0);
    std::wstring wpath(wlen, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, path.c_str(), -1, wpath.data(), wlen);

    HANDLE fh = CreateFileW(
        wpath.c_str(),
        GENERIC_READ | GENERIC_WRITE,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        nullptr,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OVERLAPPED,
        nullptr);

    if (fh == INVALID_HANDLE_VALUE) {
        DWORD err = GetLastError();
        std::ostringstream ss;
        ss << "CreateFile failed (error " << err << "). "
           << "Check WinUSB driver / Zadig.";
        errorOut = ss.str();
        return nullptr;
    }

    WINUSB_INTERFACE_HANDLE wh = nullptr;
    if (!WinUsb_Initialize(fh, &wh)) {
        DWORD err = GetLastError();
        CloseHandle(fh);
        std::ostringstream ss;
        ss << "WinUsb_Initialize failed (error " << err << "). "
           << "Check WinUSB driver / Zadig.";
        errorOut = ss.str();
        return nullptr;
    }

    auto* handle = new UsbiHandle();
    handle->fileHandle   = fh;
    handle->winusbHandle = wh;
    return handle;
}

void closeUsbiDevice(UsbiHandle* handle) {
    if (!handle) return;
    if (handle->winusbHandle) WinUsb_Free(handle->winusbHandle);
    if (handle->fileHandle != INVALID_HANDLE_VALUE) CloseHandle(handle->fileHandle);
    delete handle;
}

bool isDeviceOpen(const UsbiHandle* handle) {
    return handle &&
           handle->winusbHandle != nullptr &&
           handle->fileHandle != INVALID_HANDLE_VALUE;
}

// ── Write transaction ────────────────────────────────────────────────────────

bool sendWriteTransaction(
    UsbiHandle*                  handle,
    const std::vector<uint8_t>&  setupPacket,
    const std::vector<uint8_t>&  writeBody,
    const std::vector<uint8_t>&  ackRequest,
    std::vector<uint8_t>&        rawAckOut,
    std::string&                 errorOut)
{
    if (!isDeviceOpen(handle)) {
        errorOut = "Device not open.";
        return false;
    }

    // Phase 1: Control OUT — setup header
    {
        WINUSB_SETUP_PACKET sp = toWinUsbSetup(setupPacket);
        // wLength in the setup packet describes the data phase length (writeBody)
        sp.Length = static_cast<USHORT>(writeBody.size());

        std::vector<uint8_t> body = writeBody; // mutable copy for WinUSB
        ULONG transferred = 0;
        if (!WinUsb_ControlTransfer(handle->winusbHandle, sp,
                body.data(), static_cast<ULONG>(body.size()),
                &transferred, nullptr)) {
            DWORD err = GetLastError();
            std::ostringstream ss;
            ss << "WinUsb_ControlTransfer (write) failed (error " << err << ").";
            errorOut = ss.str();
            return false;
        }
    }

    // Phase 2: Control IN — ACK read
    {
        WINUSB_SETUP_PACKET sp = toWinUsbSetup(ackRequest);
        rawAckOut.resize(8, 0x00);
        ULONG transferred = 0;
        if (!WinUsb_ControlTransfer(handle->winusbHandle, sp,
                rawAckOut.data(), static_cast<ULONG>(rawAckOut.size()),
                &transferred, nullptr)) {
            DWORD err = GetLastError();
            rawAckOut.clear();
            std::ostringstream ss;
            ss << "WinUsb_ControlTransfer (ACK) failed (error " << err << ").";
            errorOut = ss.str();
            return false;
        }
        rawAckOut.resize(transferred);
    }

    return isAckSuccess(rawAckOut);
}

// ── Non-Windows stub ─────────────────────────────────────────────────────────
#else

std::vector<UsbDeviceInfo> listUsbDevices() { return {}; }

UsbiHandle* openUsbiDevice(std::string& errorOut) {
    errorOut = "Windows only.";
    return nullptr;
}
void closeUsbiDevice(UsbiHandle*) {}
bool isDeviceOpen(const UsbiHandle*) { return false; }

bool sendWriteTransaction(UsbiHandle*, const std::vector<uint8_t>&,
    const std::vector<uint8_t>&, const std::vector<uint8_t>&,
    std::vector<uint8_t>&, std::string& errorOut)
{
    errorOut = "Windows only.";
    return false;
}
#endif

// ── Print helpers (cross-platform) ──────────────────────────────────────────

void printDeviceList(const std::vector<UsbDeviceInfo>& devices) {
    if (devices.empty()) {
        std::cout << "  (no USB devices found)\n";
        return;
    }
    std::cout << "\n";
    std::cout << std::left
              << std::setw(6)  << "VID"
              << std::setw(6)  << "PID"
              << std::setw(8)  << "ADI?"
              << std::setw(30) << "Product"
              << "Manufacturer\n";
    std::cout << std::string(70, '-') << "\n";

    for (const auto& d : devices) {
        std::cout << "0x" << std::uppercase << std::hex << std::setw(4) << std::setfill('0') << d.vid << "  "
                  << "0x" << std::setw(4) << d.pid << std::setfill(' ') << "  "
                  << std::left << std::setw(6) << (d.likelyUsbi ? "YES" : "")
                  << std::setw(30) << d.product.substr(0, 28)
                  << d.manufacturer << "\n";
    }
    std::cout << "\n";
}
