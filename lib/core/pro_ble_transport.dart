// ── TUNAI PRO Phase T2 — BLE / macOS Transport Placeholder ───────────────────
// macOS Bluetooth / BLE is the intended write path on macOS.
// Phase T2: detection and write backend not implemented.
//
// ABSOLUTE RESTRICTIONS:
//   - Do NOT send BLE packets.
//   - Do NOT connect to any BLE peripheral.
//   - Do NOT write to hardware.
//   - wasActualWrite must remain false.
//   - AI suggests. Expert verifies. AOS protects. DSP executes.

import 'pro_hardware_transport.dart';

class ProBleTransport {
  static const bool isPlaceholder = true;
  static const bool isDetectionOnly = true;
  static const bool isWriteEnabled = false; // NEVER true in Phase T2

  static const String placeholderNote =
      'macOS BLE transport planned. Detection/write backend not enabled in this build.';

  static const String scanNote =
      'BLE scan not implemented. No peripheral is connected or claimed. '
      'No BLE advertisement packets are sent or received.';

  // Future BLE fields (for UI preview and JSON schema readiness):
  // - bluetoothId: device UUID from CoreBluetooth
  // - advertisedName: NSLocalizedName from CBPeripheral
  // - serviceUuid: DSP service UUID (TBD by hardware team)
  // - characteristicUuid: write characteristic UUID (TBD by hardware team)

  HardwareTransportInfo get transportInfo => HardwareTransportInfo.defaultBleMacos;

  /// Phase T2: No BLE scan is implemented. Returns placeholder info.
  /// No BLE advertisement or connection occurs.
  Future<HardwareTransportInfo> checkReadiness() async =>
      HardwareTransportInfo.defaultBleMacos.copyWith(
        lastCheckedAt: DateTime.now(),
        notes: placeholderNote,
      );

  Map<String, dynamic> toStatusJson() => {
    'isPlaceholder':   isPlaceholder,
    'isDetectionOnly': isDetectionOnly,
    'isWriteEnabled':  isWriteEnabled,
    'note':            placeholderNote,
    'scanNote':        scanNote,
    'safetyNote':      'No BLE packet is sent. Detection not implemented.',
  };
}
