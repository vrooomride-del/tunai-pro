#include "packet_builder.h"
#include <sstream>
#include <iomanip>

std::vector<uint8_t> buildSetupPacket() {
    return { 0x40, 0xB2, 0x00, 0x00, 0x01, 0x01, 0x06, 0x00 };
}

std::vector<uint8_t> buildWriteBody(DspAddress address, DspValue value) {
    uint16_t addr = static_cast<uint16_t>(address);
    uint32_t val  = static_cast<uint32_t>(value);
    return {
        static_cast<uint8_t>((addr >> 8) & 0xFF),
        static_cast<uint8_t>( addr       & 0xFF),
        static_cast<uint8_t>((val >> 24) & 0xFF),
        static_cast<uint8_t>((val >> 16) & 0xFF),
        static_cast<uint8_t>((val >>  8) & 0xFF),
        static_cast<uint8_t>( val        & 0xFF),
    };
}

std::vector<uint8_t> buildAckReadRequest() {
    return { 0xC0, 0xB5, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00 };
}

bool isAckSuccess(const std::vector<uint8_t>& response) {
    return response.size() > 6 && response[6] == 0x01;
}

std::string bytesToHex(const std::vector<uint8_t>& bytes) {
    std::ostringstream ss;
    for (size_t i = 0; i < bytes.size(); ++i) {
        if (i) ss << ' ';
        ss << std::uppercase << std::hex << std::setw(2) << std::setfill('0')
           << static_cast<int>(bytes[i]);
    }
    return ss.str();
}

std::string dspValueToString(DspValue v) {
    switch (v) {
        case DspValue::Full: return "1.0";
        case DspValue::Half: return "0.5";
        case DspValue::Zero: return "0.0";
        default: return "?";
    }
}

std::string dspAddressToString(DspAddress addr) {
    switch (addr) {
        case DspAddress::MasterVolumeL: return "Master Volume L (0x0067)";
        case DspAddress::MasterVolumeR: return "Master Volume R (0x0064)";
        default: return "Unknown";
    }
}
