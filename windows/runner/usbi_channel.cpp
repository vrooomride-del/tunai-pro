// ── TUNAI PRO Phase T4C — USBi WinUSB MethodChannel Implementation ───────────
// Real Windows WinUSB backend for ADI USBi temporary engineering transport.
//
// Channel: "tunai/usbi"
// ADI USBi VID: 0x0456. PID may vary.
//
// ABSOLUTE RESTRICTIONS:
//   - No auto-write. send_setup / send_body only execute when explicitly called.
//   - Do NOT fake success. Return {success: false, error: "..."} on any failure.
//   - USBi is TEMPORARY. ICP5 is the final target.
//   - Do NOT hardcode a single PID. Enumerate and select by VID 0x0456 only.

#include "usbi_channel.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winusb.h>
#include <setupapi.h>
#include <usbiodef.h>
#include <devpkey.h>

#pragma comment(lib, "winusb.lib")
#pragma comment(lib, "setupapi.lib")

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <sstream>
#include <iomanip>
#include <algorithm>
#include <memory>
#include <stdexcept>

// ── Static registration ───────────────────────────────────────────────────────

void UsbiChannel::Register(flutter::BinaryMessenger* messenger) {
    // Heap-allocated; lives for the duration of the app.
    new UsbiChannel(messenger);
}

UsbiChannel::UsbiChannel(flutter::BinaryMessenger* messenger) {
    channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        messenger,
        "tunai/usbi",
        &flutter::StandardMethodCodec::GetInstance());

    channel_->SetMethodCallHandler(
        [this](const flutter::MethodCall<flutter::EncodableValue>& call,
               std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
            HandleMethod(call, std::move(result));
        });
}

// ── Dispatch ─────────────────────────────────────────────────────────────────

void UsbiChannel::HandleMethod(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
{
    const auto& method = call.method_name();

    if (method == "usbi_is_available") {
        IsAvailable(std::move(result));
    } else if (method == "usbi_list_devices") {
        ListDevices(std::move(result));
    } else if (method == "usbi_open_device") {
        OpenDevice(std::move(result));
    } else if (method == "usbi_close") {
        CloseDevice(std::move(result));
    } else if (method == "usbi_send_setup" ||
               method == "usbi_send_body"  ||
               method == "usbi_read_ack")
    {
        const flutter::EncodableMap* args = nullptr;
        if (call.arguments()) {
            args = std::get_if<flutter::EncodableMap>(call.arguments());
        }
        if (!args) {
            result->Error("INVALID_ARGS", "Expected EncodableMap arguments.");
            return;
        }
        if (method == "usbi_send_setup") SendSetup(*args, std::move(result));
        else if (method == "usbi_send_body") SendBody(*args, std::move(result));
        else ReadAck(*args, std::move(result));
    } else {
        result->NotImplemented();
    }
}

// ── usbi_is_available ─────────────────────────────────────────────────────────

void UsbiChannel::IsAvailable(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
{
    // WinUSB is available on all supported Windows versions (≥ Vista).
    result->Success(flutter::EncodableValue(true));
}

// ── usbi_list_devices ─────────────────────────────────────────────────────────

void UsbiChannel::ListDevices(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
{
    auto devices = EnumerateDevices();
    flutter::EncodableList list;
    for (const auto& d : devices) {
        flutter::EncodableMap entry;
        entry[flutter::EncodableValue("vid")] =
            flutter::EncodableValue(static_cast<int>(d.vid));
        entry[flutter::EncodableValue("pid")] =
            flutter::EncodableValue(static_cast<int>(d.pid));
        entry[flutter::EncodableValue("product")] =
            flutter::EncodableValue(d.product);
        entry[flutter::EncodableValue("manufacturer")] =
            flutter::EncodableValue(d.manufacturer);
        entry[flutter::EncodableValue("instanceId")] =
            flutter::EncodableValue(d.instanceId);
        entry[flutter::EncodableValue("likelyUsbi")] =
            flutter::EncodableValue(d.likelyUsbi);
        list.push_back(flutter::EncodableValue(entry));
    }
    result->Success(flutter::EncodableValue(list));
}

// ── usbi_open_device ──────────────────────────────────────────────────────────

void UsbiChannel::OpenDevice(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
{
    // Close any existing session first.
    if (session_.isOpen) {
        if (session_.winusbHandle) WinUsb_Free(session_.winusbHandle);
        if (session_.fileHandle != INVALID_HANDLE_VALUE)
            CloseHandle(session_.fileHandle);
        session_ = UsbiSession{};
    }

    std::string errorOut;
    std::string path = FindUsbiDevicePath(errorOut);

    if (path.empty()) {
        flutter::EncodableMap res;
        res[flutter::EncodableValue("success")] =
            flutter::EncodableValue(false);
        res[flutter::EncodableValue("error")] =
            flutter::EncodableValue(errorOut);
        result->Success(flutter::EncodableValue(res));
        return;
    }

    // Convert path to wide string for CreateFileW.
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
        std::string msg = "CreateFile failed (error " +
            std::to_string(err) + "): " + WinErrorToString(err) +
            ". Check WinUSB driver / Zadig.";
        flutter::EncodableMap res;
        res[flutter::EncodableValue("success")] =
            flutter::EncodableValue(false);
        res[flutter::EncodableValue("error")] =
            flutter::EncodableValue(msg);
        result->Success(flutter::EncodableValue(res));
        return;
    }

    WINUSB_INTERFACE_HANDLE wh = nullptr;
    if (!WinUsb_Initialize(fh, &wh)) {
        DWORD err = GetLastError();
        CloseHandle(fh);
        std::string msg = "WinUsb_Initialize failed (error " +
            std::to_string(err) + "): " + WinErrorToString(err) +
            ". Check WinUSB driver / Zadig.";
        flutter::EncodableMap res;
        res[flutter::EncodableValue("success")] =
            flutter::EncodableValue(false);
        res[flutter::EncodableValue("error")] =
            flutter::EncodableValue(msg);
        result->Success(flutter::EncodableValue(res));
        return;
    }

    session_.fileHandle   = fh;
    session_.winusbHandle = wh;
    session_.devicePath   = wpath;
    session_.isOpen       = true;

    flutter::EncodableMap res;
    res[flutter::EncodableValue("success")] = flutter::EncodableValue(true);
    res[flutter::EncodableValue("path")]    =
        flutter::EncodableValue(path);
    result->Success(flutter::EncodableValue(res));
}

// ── usbi_send_setup ───────────────────────────────────────────────────────────
// Sends the 8-byte setup packet as a WinUSB vendor control OUT.
// The body bytes are sent as the data phase of the same control transfer.
// args: { setup: List<int> (8 bytes), body: List<int> (6 bytes) }

void UsbiChannel::SendSetup(
    const flutter::EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
{
    if (!session_.isOpen) {
        flutter::EncodableMap res;
        res[flutter::EncodableValue("success")] =
            flutter::EncodableValue(false);
        res[flutter::EncodableValue("error")] =
            flutter::EncodableValue("Device not open. Call usbi_open_device first.");
        result->Success(flutter::EncodableValue(res));
        return;
    }

    // Extract setup bytes
    auto setupIt = args.find(flutter::EncodableValue("setup"));
    auto bodyIt  = args.find(flutter::EncodableValue("body"));
    if (setupIt == args.end() || bodyIt == args.end()) {
        result->Error("INVALID_ARGS", "Missing 'setup' or 'body' argument.");
        return;
    }

    const auto* setupList =
        std::get_if<flutter::EncodableList>(&setupIt->second);
    const auto* bodyList =
        std::get_if<flutter::EncodableList>(&bodyIt->second);

    if (!setupList || setupList->size() != 8 || !bodyList) {
        result->Error("INVALID_ARGS",
            "setup must be List<int>[8], body must be List<int>.");
        return;
    }

    // Parse setup header into WINUSB_SETUP_PACKET
    // USBi format: [bmRequestType, bRequest, wValueL, wValueH,
    //               wIndexL, wIndexH, wLengthL, wLengthH]
    auto b = [&](int i) {
        return static_cast<uint8_t>(
            std::get<int32_t>((*setupList)[static_cast<size_t>(i)]));
    };

    WINUSB_SETUP_PACKET sp{};
    sp.RequestType = b(0);
    sp.Request     = b(1);
    sp.Value       = static_cast<USHORT>(b(2) | (b(3) << 8));
    sp.Index       = static_cast<USHORT>(b(4) | (b(5) << 8));
    // wLength = actual body byte count
    sp.Length      = static_cast<USHORT>(bodyList->size());

    // Build body buffer
    std::vector<BYTE> bodyBuf;
    bodyBuf.reserve(bodyList->size());
    for (const auto& v : *bodyList) {
        bodyBuf.push_back(static_cast<BYTE>(std::get<int32_t>(v)));
    }

    ULONG transferred = 0;
    BOOL ok = WinUsb_ControlTransfer(
        session_.winusbHandle,
        sp,
        bodyBuf.data(),
        static_cast<ULONG>(bodyBuf.size()),
        &transferred,
        nullptr);

    flutter::EncodableMap res;
    if (ok) {
        res[flutter::EncodableValue("success")] =
            flutter::EncodableValue(true);
        res[flutter::EncodableValue("transferred")] =
            flutter::EncodableValue(static_cast<int>(transferred));
    } else {
        DWORD err = GetLastError();
        res[flutter::EncodableValue("success")] =
            flutter::EncodableValue(false);
        res[flutter::EncodableValue("error")] =
            flutter::EncodableValue(
                "ControlTransfer (setup+body) failed (error " +
                std::to_string(err) + "): " + WinErrorToString(err));
    }
    result->Success(flutter::EncodableValue(res));
}

// ── usbi_send_body ────────────────────────────────────────────────────────────
// NOTE: In the USBi protocol the body is sent as the data phase of the same
// control transfer as the setup packet (handled in SendSetup above).
// This method exists as a no-op acknowledgement for protocol symmetry —
// the Dart executor calls send_setup (which already includes the body),
// then calls send_body which returns success without retransmitting.
// This avoids double-writes while preserving the 3-step API contract.

void UsbiChannel::SendBody(
    const flutter::EncodableMap& /*args*/,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
{
    if (!session_.isOpen) {
        flutter::EncodableMap res;
        res[flutter::EncodableValue("success")] =
            flutter::EncodableValue(false);
        res[flutter::EncodableValue("error")] =
            flutter::EncodableValue("Device not open.");
        result->Success(flutter::EncodableValue(res));
        return;
    }
    // Body was already sent as part of the control transfer in SendSetup.
    flutter::EncodableMap res;
    res[flutter::EncodableValue("success")] = flutter::EncodableValue(true);
    res[flutter::EncodableValue("note")] =
        flutter::EncodableValue("Body included in setup control transfer.");
    result->Success(flutter::EncodableValue(res));
}

// ── usbi_read_ack ─────────────────────────────────────────────────────────────
// Sends the ACK read request as a vendor control IN transfer.
// args: { ack_request: List<int> (8 bytes) }

void UsbiChannel::ReadAck(
    const flutter::EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
{
    if (!session_.isOpen) {
        flutter::EncodableMap res;
        res[flutter::EncodableValue("success")] =
            flutter::EncodableValue(false);
        res[flutter::EncodableValue("error")] =
            flutter::EncodableValue("Device not open.");
        result->Success(flutter::EncodableValue(res));
        return;
    }

    auto ackIt = args.find(flutter::EncodableValue("ack_request"));
    if (ackIt == args.end()) {
        result->Error("INVALID_ARGS", "Missing 'ack_request' argument.");
        return;
    }
    const auto* ackList =
        std::get_if<flutter::EncodableList>(&ackIt->second);
    if (!ackList || ackList->size() != 8) {
        result->Error("INVALID_ARGS", "ack_request must be List<int>[8].");
        return;
    }

    // Parse ACK read request header
    auto b = [&](int i) {
        return static_cast<uint8_t>(
            std::get<int32_t>((*ackList)[static_cast<size_t>(i)]));
    };

    WINUSB_SETUP_PACKET sp{};
    sp.RequestType = b(0);   // 0xC0 — vendor IN
    sp.Request     = b(1);   // 0xB5
    sp.Value       = static_cast<USHORT>(b(2) | (b(3) << 8));
    sp.Index       = static_cast<USHORT>(b(4) | (b(5) << 8));
    sp.Length      = static_cast<USHORT>(b(6) | (b(7) << 8));  // 0x0001

    // Read response — buffer up to 8 bytes
    constexpr ULONG kAckBufSize = 8;
    BYTE ackBuf[kAckBufSize]{};
    ULONG transferred = 0;
    BOOL ok = WinUsb_ControlTransfer(
        session_.winusbHandle,
        sp,
        ackBuf,
        kAckBufSize,
        &transferred,
        nullptr);

    flutter::EncodableMap res;
    if (ok) {
        flutter::EncodableList ackBytes;
        for (ULONG i = 0; i < transferred; ++i)
            ackBytes.push_back(flutter::EncodableValue(static_cast<int>(ackBuf[i])));
        res[flutter::EncodableValue("success")] =
            flutter::EncodableValue(true);
        res[flutter::EncodableValue("ack")] =
            flutter::EncodableValue(ackBytes);
    } else {
        DWORD err = GetLastError();
        res[flutter::EncodableValue("success")] =
            flutter::EncodableValue(false);
        res[flutter::EncodableValue("error")] =
            flutter::EncodableValue(
                "ACK ControlTransfer failed (error " +
                std::to_string(err) + "): " + WinErrorToString(err));
    }
    result->Success(flutter::EncodableValue(res));
}

// ── usbi_close ────────────────────────────────────────────────────────────────

void UsbiChannel::CloseDevice(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
{
    if (session_.isOpen) {
        if (session_.winusbHandle) WinUsb_Free(session_.winusbHandle);
        if (session_.fileHandle != INVALID_HANDLE_VALUE)
            CloseHandle(session_.fileHandle);
        session_ = UsbiSession{};
    }
    flutter::EncodableMap res;
    res[flutter::EncodableValue("success")] = flutter::EncodableValue(true);
    result->Success(flutter::EncodableValue(res));
}

// ── Device enumeration ────────────────────────────────────────────────────────

std::vector<UsbiChannel::DeviceInfo> UsbiChannel::EnumerateDevices() {
    std::vector<DeviceInfo> result;

    HDEVINFO devInfo = SetupDiGetClassDevsW(
        nullptr, L"USB", nullptr,
        DIGCF_PRESENT | DIGCF_ALLCLASSES);
    if (devInfo == INVALID_HANDLE_VALUE) return result;

    SP_DEVINFO_DATA devData{};
    devData.cbSize = sizeof(devData);

    for (DWORD idx = 0; SetupDiEnumDeviceInfo(devInfo, idx, &devData); ++idx) {
        DeviceInfo info{};

        wchar_t instanceId[512]{};
        SetupDiGetDeviceInstanceIdW(devInfo, &devData,
            instanceId, 512, nullptr);
        info.instanceId = WideToUtf8(instanceId);

        // Parse VID/PID from "USB\VID_XXXX&PID_YYYY\..."
        auto parseHex16 = [&](const std::string& prefix) -> uint16_t {
            auto pos = info.instanceId.find(prefix);
            if (pos == std::string::npos) return 0;
            pos += prefix.size();
            auto end = info.instanceId.find_first_not_of(
                "0123456789ABCDEFabcdef", pos);
            std::string hex = info.instanceId.substr(
                pos, end == std::string::npos ? 4 : end - pos);
            if (hex.empty()) return 0;
            return static_cast<uint16_t>(std::stoul(hex, nullptr, 16));
        };
        info.vid = parseHex16("VID_");
        info.pid = parseHex16("PID_");
        if (info.vid == 0) continue;  // skip non-USB entries

        info.likelyUsbi = (info.vid == kAdiUsbiVid);

        wchar_t desc[256]{};
        if (SetupDiGetDeviceRegistryPropertyW(devInfo, &devData,
                SPDRP_DEVICEDESC, nullptr,
                reinterpret_cast<PBYTE>(desc), sizeof(desc), nullptr))
            info.product = WideToUtf8(desc);

        wchar_t mfr[256]{};
        if (SetupDiGetDeviceRegistryPropertyW(devInfo, &devData,
                SPDRP_MFG, nullptr,
                reinterpret_cast<PBYTE>(mfr), sizeof(mfr), nullptr))
            info.manufacturer = WideToUtf8(mfr);

        result.push_back(std::move(info));
    }
    SetupDiDestroyDeviceInfoList(devInfo);
    return result;
}

// ── Find USBi device path ─────────────────────────────────────────────────────

std::string UsbiChannel::FindUsbiDevicePath(std::string& errorOut) {
    HDEVINFO devInfo = SetupDiGetClassDevsW(
        &GUID_DEVINTERFACE_USB_DEVICE, nullptr, nullptr,
        DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
    if (devInfo == INVALID_HANDLE_VALUE) {
        errorOut = "SetupDiGetClassDevs failed.";
        return "";
    }

    SP_DEVICE_INTERFACE_DATA ifaceData{};
    ifaceData.cbSize = sizeof(ifaceData);
    std::string found;

    for (DWORD idx = 0;
         SetupDiEnumDeviceInterfaces(devInfo, nullptr,
             &GUID_DEVINTERFACE_USB_DEVICE, idx, &ifaceData);
         ++idx)
    {
        DWORD needed = 0;
        SetupDiGetDeviceInterfaceDetailW(devInfo, &ifaceData,
            nullptr, 0, &needed, nullptr);
        if (needed == 0) continue;

        std::vector<BYTE> buf(needed);
        auto* detail =
            reinterpret_cast<SP_DEVICE_INTERFACE_DETAIL_DATA_W*>(buf.data());
        detail->cbSize = sizeof(SP_DEVICE_INTERFACE_DETAIL_DATA_W);

        SP_DEVINFO_DATA devData{};
        devData.cbSize = sizeof(devData);

        if (!SetupDiGetDeviceInterfaceDetailW(devInfo, &ifaceData,
                detail, needed, nullptr, &devData))
            continue;

        // Check VID in instance ID
        wchar_t instanceId[512]{};
        SetupDiGetDeviceInstanceIdW(devInfo, &devData,
            instanceId, 512, nullptr);
        std::wstring iid(instanceId);
        std::wstring iidUpper = iid;
        std::transform(iidUpper.begin(), iidUpper.end(),
            iidUpper.begin(), ::towupper);

        if (iidUpper.find(L"VID_0456") != std::wstring::npos) {
            int len = WideCharToMultiByte(CP_UTF8, 0,
                detail->DevicePath, -1, nullptr, 0, nullptr, nullptr);
            if (len > 0) {
                found.resize(static_cast<size_t>(len - 1));
                WideCharToMultiByte(CP_UTF8, 0,
                    detail->DevicePath, -1,
                    found.data(), len, nullptr, nullptr);
            }
            break;
        }
    }
    SetupDiDestroyDeviceInfoList(devInfo);

    if (found.empty())
        errorOut = "No ADI USBi device found (VID 0x0456). "
                   "Is the device connected? "
                   "Check WinUSB driver / Zadig.";
    return found;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

std::string UsbiChannel::WinErrorToString(DWORD err) {
    LPWSTR msgBuf = nullptr;
    FormatMessageW(
        FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
        FORMAT_MESSAGE_IGNORE_INSERTS,
        nullptr, err,
        MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
        reinterpret_cast<LPWSTR>(&msgBuf), 0, nullptr);
    std::string msg;
    if (msgBuf) {
        msg = WideToUtf8(msgBuf);
        LocalFree(msgBuf);
        // Trim trailing whitespace/newline
        while (!msg.empty() && (msg.back() == '\n' || msg.back() == '\r' ||
                                 msg.back() == ' '))
            msg.pop_back();
    }
    return msg.empty() ? "Unknown error" : msg;
}

std::string UsbiChannel::WideToUtf8(const wchar_t* ws) {
    if (!ws) return "";
    int len = WideCharToMultiByte(CP_UTF8, 0, ws, -1,
        nullptr, 0, nullptr, nullptr);
    if (len <= 0) return "";
    std::string s(static_cast<size_t>(len - 1), '\0');
    WideCharToMultiByte(CP_UTF8, 0, ws, -1,
        s.data(), len, nullptr, nullptr);
    return s;
}
