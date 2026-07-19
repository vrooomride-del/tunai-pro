// ── TUNAI PRO — Hardware Capability Layer (data + lookup only) ────────────────
// Declares WHAT parameters a device can accept as a hardware write and WHAT
// evidence level backs each one. This is a capability *description*; it performs
// no writes and touches no transport, executor, codec, or address mapping.
//
// Fail-closed by design: any parameter without an explicit, proven capability
// entry resolves to `unavailable`.

/// Evidence level backing a hardware parameter write.
enum HardwareParamVerification {
  /// Device- and capture-confirmed write AND readback. The only level eligible
  /// for an actual hardware write.
  captureProven,

  /// A write path exists but is not capture-proven. Never auto-written;
  /// requires explicit override + fresh capture evidence before promotion.
  unverified,

  /// No confirmed write path. Export/preset/simulation only — never written.
  unavailable;

  String get label => switch (this) {
        HardwareParamVerification.captureProven => 'Capture Proven',
        HardwareParamVerification.unverified => 'Unverified',
        HardwareParamVerification.unavailable => 'Unavailable',
      };

  /// Only capture-proven parameters may be written to hardware.
  bool get isWriteEligible => this == HardwareParamVerification.captureProven;

  String toJson() => name;

  static HardwareParamVerification fromJson(String s) =>
      HardwareParamVerification.values.firstWhere(
        (e) => e.name == s,
        orElse: () => HardwareParamVerification.unavailable,
      );
}

/// Transport a device profile is reached over. Descriptive only — no transport
/// code is referenced or invoked here.
enum HardwareTransportType {
  icp5,
  usbiDeveloper,
  none;

  String get label => switch (this) {
        HardwareTransportType.icp5 => 'ICP5',
        HardwareTransportType.usbiDeveloper => 'USBi (developer)',
        HardwareTransportType.none => 'None',
      };

  String toJson() => name;

  static HardwareTransportType fromJson(String s) =>
      HardwareTransportType.values.firstWhere(
        (e) => e.name == s,
        orElse: () => HardwareTransportType.none,
      );
}

/// Kinds of tunable parameter the capability layer can describe.
enum HardwareParamKind {
  peqGain,
  peqFrequency,
  peqQ,
  crossoverHighPass,
  crossoverLowPass,
  channelGain,
  channelDelay,
  channelMute,
  channelPolarity;

  String toJson() => name;

  static HardwareParamKind? fromJson(String s) {
    for (final k in HardwareParamKind.values) {
      if (k.name == s) return k;
    }
    return null;
  }
}

/// One capability declaration. [bandIndex] is 0-based (0 = Band 1); `null` means
/// the entry applies to every band / a non-banded parameter. A band-specific
/// entry wins over a band-agnostic one for the same [kind].
class HardwareCapabilityEntry {
  final HardwareParamKind kind;
  final int? bandIndex;
  final HardwareParamVerification verification;

  const HardwareCapabilityEntry({
    required this.kind,
    this.bandIndex,
    required this.verification,
  });

  Map<String, dynamic> toJson() => {
        'kind': kind.toJson(),
        if (bandIndex != null) 'bandIndex': bandIndex,
        'verification': verification.toJson(),
      };
}

/// A device's declared write capabilities. Immutable data + a fail-closed
/// lookup. No behaviour that touches hardware.
class HardwareDeviceProfile {
  final String deviceId;
  final String deviceName;
  final HardwareTransportType transport;
  final List<HardwareCapabilityEntry> capabilities;

  const HardwareDeviceProfile({
    required this.deviceId,
    required this.deviceName,
    required this.transport,
    required this.capabilities,
  });

  /// Verification level for [kind] (optionally at [bandIndex]).
  ///
  /// Fail-closed: with no matching entry the result is
  /// [HardwareParamVerification.unavailable]. A band-specific entry takes
  /// precedence over a band-agnostic (`bandIndex == null`) entry.
  HardwareParamVerification verificationFor(
    HardwareParamKind kind, {
    int? bandIndex,
  }) {
    HardwareCapabilityEntry? banded;
    HardwareCapabilityEntry? general;
    for (final e in capabilities) {
      if (e.kind != kind) continue;
      if (e.bandIndex != null) {
        if (bandIndex != null && e.bandIndex == bandIndex) banded = e;
      } else {
        general = e;
      }
    }
    return (banded ?? general)?.verification ??
        HardwareParamVerification.unavailable;
  }

  /// True only when the parameter is capture-proven for this device.
  bool isWriteEligible(HardwareParamKind kind, {int? bandIndex}) =>
      verificationFor(kind, bandIndex: bandIndex).isWriteEligible;

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'transport': transport.toJson(),
        'capabilities': capabilities.map((c) => c.toJson()).toList(),
      };
}

/// Built-in device profiles. Additive data only.
abstract final class HardwareDeviceProfiles {
  /// ADAU1701 over ICP5. Only Band 1 (index 0) gain + frequency are
  /// capture-proven; everything else is unverified or unavailable.
  static const HardwareDeviceProfile adau1701Icp5 = HardwareDeviceProfile(
    deviceId: 'adau1701-icp5',
    deviceName: 'ADAU1701 (ICP5)',
    transport: HardwareTransportType.icp5,
    capabilities: [
      // Band 1 (index 0): the only capture-proven writes.
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqGain,
          bandIndex: 0,
          verification: HardwareParamVerification.captureProven),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqFrequency,
          bandIndex: 0,
          verification: HardwareParamVerification.captureProven),
      // All other PEQ bands' gain/frequency: write path exists, not proven.
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqGain,
          verification: HardwareParamVerification.unverified),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqFrequency,
          verification: HardwareParamVerification.unverified),
      // Q: unverified across all bands.
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqQ,
          verification: HardwareParamVerification.unverified),
      // No confirmed write path.
      HardwareCapabilityEntry(
          kind: HardwareParamKind.crossoverHighPass,
          verification: HardwareParamVerification.unavailable),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.crossoverLowPass,
          verification: HardwareParamVerification.unavailable),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.channelDelay,
          verification: HardwareParamVerification.unavailable),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.channelGain,
          verification: HardwareParamVerification.unavailable),
    ],
  );

  /// ADAU1466 developer profile. Kept separate and intentionally empty: no
  /// writable mappings are assumed, so every lookup fails closed to
  /// `unavailable` until a mapping is capture-proven.
  static const HardwareDeviceProfile adau1466Developer = HardwareDeviceProfile(
    deviceId: 'adau1466-developer',
    deviceName: 'ADAU1466 (developer)',
    transport: HardwareTransportType.usbiDeveloper,
    capabilities: [],
  );

  static const List<HardwareDeviceProfile> all = [
    adau1701Icp5,
    adau1466Developer,
  ];

  /// Profile by id, or null if unknown.
  static HardwareDeviceProfile? byId(String deviceId) {
    for (final p in all) {
      if (p.deviceId == deviceId) return p;
    }
    return null;
  }
}
