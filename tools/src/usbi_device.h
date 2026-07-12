#pragma once
#include <string>
#include <vector>
#include <cstdint>

// ADI USBi VID
static constexpr uint16_t ADI_USBI_VID = 0x0456;

struct UsbDeviceInfo {
    uint16_t    vid;
    uint16_t    pid;
    std::string manufacturer;
    std::string product;
    std::string instanceId;
    bool        likelyUsbi;     // VID matches ADI
    bool        winusbAccessible;
};

// List all USB devices visible via SetupDi
std::vector<UsbDeviceInfo> listUsbDevices();

// Print device table to stdout
void printDeviceList(const std::vector<UsbDeviceInfo>& devices);

// Opaque device handle (WinUSB)
struct UsbiHandle;

// Open first ADI USBi device found (VID 0x0456).
// Returns nullptr on failure; sets errorOut.
UsbiHandle* openUsbiDevice(std::string& errorOut);

// Close device handle
void closeUsbiDevice(UsbiHandle* handle);

bool isDeviceOpen(const UsbiHandle* handle);

// Send setup packet then write body; read ACK.
// Returns true if ACK byte[6]==0x01.
// rawAckOut receives the raw ACK bytes (may be empty on error).
bool sendWriteTransaction(
    UsbiHandle*                    handle,
    const std::vector<uint8_t>&    setupPacket,
    const std::vector<uint8_t>&    writeBody,
    const std::vector<uint8_t>&    ackRequest,
    std::vector<uint8_t>&          rawAckOut,
    std::string&                   errorOut
);
