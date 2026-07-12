#pragma once
#include <cstdint>
#include <vector>
#include <string>

// ADAU1466 8.24 fixed-point values (big-endian, 4 bytes)
enum class DspValue : uint32_t {
    Full  = 0x01000000,  // 1.0
    Half  = 0x00800000,  // 0.5
    Zero  = 0x00000000,  // 0.0
};

// Verified ADAU1466 Master Volume addresses
enum class DspAddress : uint16_t {
    MasterVolumeL = 0x0067,
    MasterVolumeR = 0x0064,
};

// USBi packet: 8-byte setup header
// 40 B2 00 00 01 01 06 00
std::vector<uint8_t> buildSetupPacket();

// USBi write body: [addr 2B BE] + [data 4B BE] = 6 bytes
// e.g. 0x0067 + 0.5 -> 00 67 00 80 00 00
std::vector<uint8_t> buildWriteBody(DspAddress address, DspValue value);

// USBi ACK read request: C0 B5 00 00 00 00 01 00
std::vector<uint8_t> buildAckReadRequest();

// Check ACK response: byte[6] == 0x01 means success
bool isAckSuccess(const std::vector<uint8_t>& response);

// Format bytes as "XX XX XX ..." for display/logging
std::string bytesToHex(const std::vector<uint8_t>& bytes);

// Convert DspValue to float string
std::string dspValueToString(DspValue v);

// Convert DspAddress to string
std::string dspAddressToString(DspAddress addr);
