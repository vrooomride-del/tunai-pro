#include <iostream>
#include <string>
#include <vector>
#include <sstream>
#include <iomanip>
#include <algorithm>

#include "packet_builder.h"
#include "usbi_device.h"
#include "logger.h"

// ── Global state ─────────────────────────────────────────────────────────────

static UsbiHandle* g_device = nullptr;

// ── Helpers ──────────────────────────────────────────────────────────────────

static void printHeader() {
    std::cout << "\n";
    std::cout << "====================================================\n";
    std::cout << "  TUNAI DSP Address Tester  —  ADAU1466 / ADI USBi\n";
    std::cout << "  LAB USE ONLY. Volatile writes. No EEPROM/SafeLoad.\n";
    std::cout << "====================================================\n";
    std::cout << "  Device: " << (isDeviceOpen(g_device) ? "OPEN" : "NOT OPEN") << "\n";
    std::cout << "====================================================\n\n";
}

static void printMenu() {
    std::cout << " 1. List USB devices\n";
    std::cout << " 2. Open ADI USBi\n";
    std::cout << " 3. Write Master Volume L = 1.0\n";
    std::cout << " 4. Write Master Volume L = 0.5\n";
    std::cout << " 5. Write Master Volume L = 0.0\n";
    std::cout << " 6. Write Master Volume R = 1.0\n";
    std::cout << " 7. Write Master Volume R = 0.5\n";
    std::cout << " 8. Write Master Volume R = 0.0\n";
    std::cout << " 9. Restore L/R to 1.0\n";
    std::cout << "10. Manual address dry-run preview\n";
    std::cout << "11. Exit\n";
    std::cout << "\nSelect: ";
}

// ── Write guard + execute ────────────────────────────────────────────────────

static void doWrite(DspAddress address, DspValue value) {
    // Guard: device must be open
    if (!isDeviceOpen(g_device)) {
        std::cout << "[ERROR] Device not open. Select option 2 first.\n";
        return;
    }

    // Guard: address must be one of the two verified addresses
    if (address != DspAddress::MasterVolumeL &&
        address != DspAddress::MasterVolumeR) {
        std::cout << "[ERROR] Address not in verified set. Aborting.\n";
        return;
    }

    // Guard: value must be 1.0, 0.5, or 0.0
    if (value != DspValue::Full &&
        value != DspValue::Half &&
        value != DspValue::Zero) {
        std::cout << "[ERROR] Value not in allowed set. Aborting.\n";
        return;
    }

    // Build packets and show preview
    auto setup      = buildSetupPacket();
    auto body       = buildWriteBody(address, value);
    auto ackReq     = buildAckReadRequest();

    std::cout << "\n--- Write Preview ---\n";
    std::cout << "  Target  : " << dspAddressToString(address) << "\n";
    std::cout << "  Value   : " << dspValueToString(value) << "\n";
    std::cout << "  Fixed   : 0x" << std::uppercase << std::hex
              << std::setw(8) << std::setfill('0')
              << static_cast<uint32_t>(value) << "\n";
    std::cout << "  Setup   : " << bytesToHex(setup)  << "\n";
    std::cout << "  Body    : " << bytesToHex(body)   << "\n";
    std::cout << "  AckReq  : " << bytesToHex(ackReq) << "\n";
    std::cout << "\n  Type YES to confirm volatile write: ";

    std::string confirm;
    std::getline(std::cin, confirm);
    if (confirm != "YES") {
        std::cout << "[CANCELLED] Write aborted.\n";
        logInfo("Write cancelled by user: " + dspAddressToString(address)
                + " = " + dspValueToString(value));
        return;
    }

    // Execute
    std::vector<uint8_t> ackResponse;
    std::string errorMsg;
    bool ok = sendWriteTransaction(g_device, setup, body, ackReq, ackResponse, errorMsg);

    WriteLogEntry entry;
    entry.timestamp       = currentTimestamp();
    entry.address         = dspAddressToString(address);
    entry.valueFloat      = dspValueToString(value);
    entry.fixedPointHex   = bytesToHex({
        static_cast<uint8_t>((static_cast<uint32_t>(value) >> 24) & 0xFF),
        static_cast<uint8_t>((static_cast<uint32_t>(value) >> 16) & 0xFF),
        static_cast<uint8_t>((static_cast<uint32_t>(value) >>  8) & 0xFF),
        static_cast<uint8_t>( static_cast<uint32_t>(value)        & 0xFF),
    });
    entry.setupBytes      = bytesToHex(setup);
    entry.bodyBytes       = bytesToHex(body);
    entry.ackRequestBytes = bytesToHex(ackReq);
    entry.ackResponseBytes= ackResponse.empty() ? "(none)" : bytesToHex(ackResponse);
    entry.success         = ok;
    entry.errorMessage    = errorMsg;

    logWrite(entry);

    if (ok)
        std::cout << "[OK] Write successful. ACK: " << bytesToHex(ackResponse) << "\n";
    else
        std::cout << "[FAIL] Write failed. " << errorMsg << "\n";
}

// ── Manual dry-run ───────────────────────────────────────────────────────────

static void doDryRun() {
    std::cout << "\n--- Manual Address Dry-Run (preview only, NO send) ---\n";
    std::cout << "  Enter address (hex, e.g. 0067): ";
    std::string addrStr;
    std::getline(std::cin, addrStr);

    std::cout << "  Enter fixed-point value (hex, e.g. 00800000): ";
    std::string valStr;
    std::getline(std::cin, valStr);

    uint16_t addr = 0;
    uint32_t val  = 0;
    try {
        addr = static_cast<uint16_t>(std::stoul(addrStr, nullptr, 16));
        val  = static_cast<uint32_t>(std::stoul(valStr,  nullptr, 16));
    } catch (...) {
        std::cout << "[ERROR] Invalid hex input.\n";
        return;
    }

    std::vector<uint8_t> body = {
        static_cast<uint8_t>((addr >> 8) & 0xFF),
        static_cast<uint8_t>( addr       & 0xFF),
        static_cast<uint8_t>((val >> 24) & 0xFF),
        static_cast<uint8_t>((val >> 16) & 0xFF),
        static_cast<uint8_t>((val >>  8) & 0xFF),
        static_cast<uint8_t>( val        & 0xFF),
    };
    auto setup  = buildSetupPacket();
    auto ackReq = buildAckReadRequest();

    std::cout << "\n  [DRY-RUN — packet bytes only, nothing is sent]\n";
    std::cout << "  Address : 0x" << std::uppercase << std::hex
              << std::setw(4) << std::setfill('0') << addr << "\n";
    std::cout << "  Value   : 0x" << std::setw(8) << val << "\n";
    std::cout << "  Setup   : " << bytesToHex(setup)  << "\n";
    std::cout << "  Body    : " << bytesToHex(body)   << "\n";
    std::cout << "  AckReq  : " << bytesToHex(ackReq) << "\n";

    logInfo("DRY-RUN addr=0x" + addrStr + " val=0x" + valStr
            + " body=" + bytesToHex(body));
}

// ── Menu handlers ─────────────────────────────────────────────────────────────

static void handleListDevices() {
    std::cout << "\n--- USB Device List ---\n";
    auto devices = listUsbDevices();
    printDeviceList(devices);

    bool anyAdi = false;
    for (const auto& d : devices) {
        if (d.likelyUsbi) { anyAdi = true; break; }
    }
    if (anyAdi)
        std::cout << "[INFO] ADI USBi candidate found (VID 0x0456). "
                  << "Select option 2 to open.\n";
    else
        std::cout << "[INFO] No ADI USBi (VID 0x0456) detected.\n";
}

static void handleOpenDevice() {
    if (isDeviceOpen(g_device)) {
        std::cout << "[INFO] Device already open. Close and reopen? (YES/no): ";
        std::string ans;
        std::getline(std::cin, ans);
        if (ans != "YES") return;
        closeUsbiDevice(g_device);
        g_device = nullptr;
    }

    std::cout << "[INFO] Opening ADI USBi (VID 0x0456)...\n";
    std::string err;
    g_device = openUsbiDevice(err);
    if (g_device)
        std::cout << "[OK] Device opened.\n";
    else
        std::cout << "[FAIL] " << err << "\n";

    logInfo(g_device ? "Device opened." : "Device open failed: " + err);
}

static void handleRestore() {
    std::cout << "\n[INFO] Restore: Write Master Volume L=1.0 then R=1.0\n";
    doWrite(DspAddress::MasterVolumeL, DspValue::Full);
    doWrite(DspAddress::MasterVolumeR, DspValue::Full);
}

// ── Main ──────────────────────────────────────────────────────────────────────

int main() {
    logInfo("=== TUNAI DSP Address Tester started ===");

    while (true) {
        printHeader();
        printMenu();

        std::string line;
        if (!std::getline(std::cin, line)) break;

        int choice = 0;
        try { choice = std::stoi(line); } catch (...) { choice = 0; }

        switch (choice) {
            case 1:  handleListDevices(); break;
            case 2:  handleOpenDevice();  break;
            case 3:  doWrite(DspAddress::MasterVolumeL, DspValue::Full); break;
            case 4:  doWrite(DspAddress::MasterVolumeL, DspValue::Half); break;
            case 5:  doWrite(DspAddress::MasterVolumeL, DspValue::Zero); break;
            case 6:  doWrite(DspAddress::MasterVolumeR, DspValue::Full); break;
            case 7:  doWrite(DspAddress::MasterVolumeR, DspValue::Half); break;
            case 8:  doWrite(DspAddress::MasterVolumeR, DspValue::Zero); break;
            case 9:  handleRestore();     break;
            case 10: doDryRun();          break;
            case 11:
                closeUsbiDevice(g_device);
                logInfo("=== Tester exited ===");
                std::cout << "[INFO] Exiting.\n";
                return 0;
            default:
                std::cout << "[ERROR] Invalid selection.\n";
        }

        std::cout << "\nPress Enter to continue...";
        std::string dummy;
        std::getline(std::cin, dummy);
    }

    closeUsbiDevice(g_device);
    return 0;
}
