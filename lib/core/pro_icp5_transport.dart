// ── TUNAI PRO Phase T2 — ICP5 Transport Placeholder ─────────────────────────
// ICP5 is the final intended hardware programming/transport path.
// Phase T2: backend not implemented. Placeholder only.
//
// ABSOLUTE RESTRICTIONS:
//   - Do NOT send ICP5 packets.
//   - Do NOT write to hardware.
//   - Do NOT assume packet format — TBD by hardware team.
//   - Do NOT invent addresses or register ranges.
//   - wasActualWrite must remain false.
//   - AI suggests. Expert verifies. AOS protects. DSP executes.

import 'pro_hardware_transport.dart';

class ProIcp5Transport {
  static const bool isPlaceholder = true;
  static const bool isDetectionOnly = true;
  static const bool isWriteEnabled = false; // NEVER true in Phase T2

  static const String placeholderNote =
      'ICP5 final transport target. Backend pending.';

  static const String packetNote =
      'No ICP5 packet format is assumed or implemented. '
      'Packet structure, address mapping, and protocol are TBD by hardware team.';

  HardwareTransportInfo get transportInfo => HardwareTransportInfo.defaultIcp5;

  /// Phase T2: Returns placeholder info. No ICP5 communication occurs.
  Future<HardwareTransportInfo> checkReadiness() async =>
      HardwareTransportInfo.defaultIcp5.copyWith(
        lastCheckedAt: DateTime.now(),
        notes: placeholderNote,
      );

  Map<String, dynamic> toStatusJson() => {
    'isPlaceholder':   isPlaceholder,
    'isDetectionOnly': isDetectionOnly,
    'isWriteEnabled':  isWriteEnabled,
    'note':            placeholderNote,
    'packetNote':      packetNote,
    'safetyNote':      'No ICP5 packet is sent. Backend not implemented.',
  };
}
