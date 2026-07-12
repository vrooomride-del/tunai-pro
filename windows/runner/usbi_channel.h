#pragma once
// ── TUNAI PRO Phase T4C — USBi WinUSB MethodChannel Handler ─────────────────
// Registers "tunai/usbi" MethodChannel and handles all USBi native calls.
//
// ABSOLUTE RESTRICTIONS:
//   - No auto-write on startup or registration.
//   - send_setup / send_body / read_ack only execute when explicitly called.
//   - Do NOT fake success. Return structured errors.
//   - ADI USBi VID = 0x0456. PID may vary — do not assume single PID.
//   - USBi is TEMPORARY. ICP5 remains the final target.

#ifndef USBI_CHANNEL_H_
#define USBI_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <winusb.h>
#include <setupapi.h>
#include <memory>
#include <string>
#include <vector>
#include <cstdint>

static constexpr uint16_t kAdiUsbiVid = 0x0456;

// Represents one open USBi device session.
struct UsbiSession {
    HANDLE                  fileHandle   = INVALID_HANDLE_VALUE;
    WINUSB_INTERFACE_HANDLE winusbHandle = nullptr;
    uint16_t                pid          = 0;
    std::wstring            devicePath;
    bool                    isOpen       = false;
};

class UsbiChannel {
public:
    // Register the "tunai/usbi" MethodChannel on the given messenger.
    static void Register(flutter::BinaryMessenger* messenger);

private:
    explicit UsbiChannel(flutter::BinaryMessenger* messenger);

    void HandleMethod(
        const flutter::MethodCall<flutter::EncodableValue>& call,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

    // ── Channel methods ──────────────────────────────────────────────────────

    // usbi_is_available → bool
    // Returns true: WinUSB APIs are accessible on this Windows build.
    void IsAvailable(
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

    // usbi_list_devices → List<Map>
    // Lists USB devices with VID/PID/product/manufacturer/likelyUsbi fields.
    void ListDevices(
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

    // usbi_open_device → Map {success, pid, path, error}
    // Opens the first ADI USBi device (VID 0x0456) via WinUSB.
    void OpenDevice(
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

    // usbi_send_setup → Map {success, transferred, error}
    // Sends the 8-byte setup packet as a vendor control OUT transfer.
    // args: {setup: List<int> (8 bytes), body_length: int}
    void SendSetup(
        const flutter::EncodableMap& args,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

    // usbi_send_body → Map {success, transferred, error}
    // Sends the 6-byte write body as the data phase of the control transfer.
    // args: {body: List<int> (6 bytes)}
    void SendBody(
        const flutter::EncodableMap& args,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

    // usbi_read_ack → Map {success, ack: List<int>, error}
    // Sends ACK read request and returns raw response bytes.
    // args: {ack_request: List<int> (8 bytes)}
    void ReadAck(
        const flutter::EncodableMap& args,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

    // usbi_close → Map {success}
    void CloseDevice(
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

    // ── WinUSB helpers ───────────────────────────────────────────────────────

    struct DeviceInfo {
        uint16_t    vid;
        uint16_t    pid;
        std::string product;
        std::string manufacturer;
        std::string instanceId;
        bool        likelyUsbi;
    };

    std::vector<DeviceInfo> EnumerateDevices();
    std::string FindUsbiDevicePath(std::string& errorOut);

    static WINUSB_SETUP_PACKET BuildControlSetup(
        uint8_t  requestType,
        uint8_t  request,
        uint16_t value,
        uint16_t index,
        uint16_t length);

    static std::string WinErrorToString(DWORD err);
    static std::string WideToUtf8(const wchar_t* ws);

    // ── State ────────────────────────────────────────────────────────────────
    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
    UsbiSession session_;
};

#endif  // USBI_CHANNEL_H_
