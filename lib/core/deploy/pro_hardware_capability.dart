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
  /// ADAU1701 over ICP5. PEQ gain/frequency/Q are capture-proven for bands
  /// 0–7 (Band 1–8, real-hardware deploy confirmed); bands 8–9 (Band 9–10)
  /// are unavailable (confirmed failing on real hardware). Everything else
  /// is unverified or unavailable — see the PEQ capability entries below.
  static const HardwareDeviceProfile adau1701Icp5 = HardwareDeviceProfile(
    deviceId: 'adau1701-icp5',
    deviceName: 'ADAU1701 (ICP5)',
    transport: HardwareTransportType.icp5,
    capabilities: [
      // Band 1 (index 0): peqGain and peqFrequency are both operational.
      // peqGain: PRO-capture-proven — param 0x18 property 0x01 → offset 21.
      // peqFrequency: Consumer-production-proven — param 0x18 property 0x02 →
      //   offset 19:20 (uint16 LE Hz). Evidence:
      //   tunai_codex/lib/features/ble/icp5_peq_command_builder.dart
      //     (_peqParameter=0x18, _frequencyProperty=0x02)
      //   tunai_codex/test/consumer_dsp_physical_qa_fixture_test.dart
      //     (hardware ACK + readback confirmed at 1800 Hz on Consumer BLE device)
      //   PRO hardware readback (offset 19:20 change after write) pending; param
      //   0x15 is the crossover cutoff path — a different DSP block.
      // PEQ band capability correction (real-hardware deploy evidence):
      // bands 0–7 (Band 1–8) deploy successfully on real ADAU1701 hardware;
      // bands 8–9 (Band 9–10) fail on real hardware deploy. frame builder,
      // ACK parser, and channel mapping apply zero band-8/9-specific
      // handling (audited — see icp5_frame_codec.dart), so this is not a
      // protocol bug: the currently-compiled ADAU1701 DSP profile does not
      // support bands 9–10. The previous band-agnostic (bandIndex: null)
      // fallback claimed captureProven for bands 0–9 uniformly, based only
      // on the Consumer command-builder (tunai_codex/icp5_peq_command_builder.dart)
      // accepting any band byte 0–255 — a wire-frame constructor
      // permissiveness, not a device-level confirmation. Replaced below with
      // explicit per-band entries so no band silently inherits captureProven
      // without being individually accounted for.
      //
      // Band 0 (Band 1): peqGain PRO-capture-proven (param 0x18 property
      // 0x01 → offset 21); peqFrequency Consumer-production-proven (param
      // 0x18 property 0x02 → offset 19:20, uint16 LE Hz). Evidence:
      //   tunai_codex/lib/features/ble/icp5_peq_command_builder.dart
      //     (_peqParameter=0x18, _frequencyProperty=0x02)
      //   tunai_codex/test/consumer_dsp_physical_qa_fixture_test.dart
      //     (hardware ACK + readback confirmed at 1800 Hz on Consumer BLE device)
      // Bands 1–7 (Band 2–8): real-hardware deploy confirmed passing;
      // ACK-only (no PRO readback available for non-band-0), same as before.
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqGain,
          bandIndex: 0,
          verification: HardwareParamVerification.captureProven),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqGain,
          bandIndex: 1,
          verification: HardwareParamVerification.captureProven),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqGain,
          bandIndex: 2,
          verification: HardwareParamVerification.captureProven),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqGain,
          bandIndex: 3,
          verification: HardwareParamVerification.captureProven),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqGain,
          bandIndex: 4,
          verification: HardwareParamVerification.captureProven),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqGain,
          bandIndex: 5,
          verification: HardwareParamVerification.captureProven),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqGain,
          bandIndex: 6,
          verification: HardwareParamVerification.captureProven),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqGain,
          bandIndex: 7,
          verification: HardwareParamVerification.captureProven),
      // Bands 8–9 (Band 9–10): confirmed FAILING on real hardware deploy —
      // `unavailable`, not `unverified` (this is a negative confirmation,
      // not an absence of evidence).
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqGain,
          bandIndex: 8,
          verification: HardwareParamVerification.unavailable),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqGain,
          bandIndex: 9,
          verification: HardwareParamVerification.unavailable),

      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqFrequency,
          bandIndex: 0,
          verification: HardwareParamVerification.captureProven),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqFrequency,
          bandIndex: 1,
          verification: HardwareParamVerification.captureProven),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqFrequency,
          bandIndex: 2,
          verification: HardwareParamVerification.captureProven),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqFrequency,
          bandIndex: 3,
          verification: HardwareParamVerification.captureProven),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqFrequency,
          bandIndex: 4,
          verification: HardwareParamVerification.captureProven),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqFrequency,
          bandIndex: 5,
          verification: HardwareParamVerification.captureProven),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqFrequency,
          bandIndex: 6,
          verification: HardwareParamVerification.captureProven),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqFrequency,
          bandIndex: 7,
          verification: HardwareParamVerification.captureProven),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqFrequency,
          bandIndex: 8,
          verification: HardwareParamVerification.unavailable),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqFrequency,
          bandIndex: 9,
          verification: HardwareParamVerification.unavailable),

      // peqQ has no band-0-specific PRO capture (unchanged from before this
      // fix); same 0–7 captureProven / 8–9 unavailable split applies.
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqQ,
          bandIndex: 0,
          verification: HardwareParamVerification.captureProven),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqQ,
          bandIndex: 1,
          verification: HardwareParamVerification.captureProven),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqQ,
          bandIndex: 2,
          verification: HardwareParamVerification.captureProven),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqQ,
          bandIndex: 3,
          verification: HardwareParamVerification.captureProven),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqQ,
          bandIndex: 4,
          verification: HardwareParamVerification.captureProven),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqQ,
          bandIndex: 5,
          verification: HardwareParamVerification.captureProven),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqQ,
          bandIndex: 6,
          verification: HardwareParamVerification.captureProven),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqQ,
          bandIndex: 7,
          verification: HardwareParamVerification.captureProven),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqQ,
          bandIndex: 8,
          verification: HardwareParamVerification.unavailable),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.peqQ,
          bandIndex: 9,
          verification: HardwareParamVerification.unavailable),
      // Channel gain: parameter-ID 0x14 + float32 LE dB + channel byte 0–3
      // are capture-confirmed. Arbitrary dB values are hardware-unverified at
      // the value level; ACK-only (no readback service yet).
      HardwareCapabilityEntry(
          kind: HardwareParamKind.channelGain,
          verification: HardwareParamVerification.captureProven),
      // crossoverHighPass / crossoverLowPass: RESTORED to captureProven —
      // Phase 7-4A (ADAU1701 XO Deploy Restore, diff-based safe apply).
      //
      // History: P0 forensic fix ("XO Deploy Parameter Corruption") found a
      // real-hardware incident where a single 3 kHz LR24 edit corrupted
      // HPF/LPF and PEQ state across unrelated channels, root-caused to
      // buildAdau1701PeqXoExportBlocks() being a full-state resend — it
      // built an XO block for EVERY configured channel on every deploy, not
      // a diff against what was last applied (unlike gain's
      // appliedGainsByChannel). That function downgraded this entry to
      // `unavailable` and was fail-closed until fixed.
      //
      // This entry is safe to re-enable ONLY because the export path
      // changed, not because new hardware evidence was captured for
      // multi-channel or type/slope writes:
      //   - buildAdau1701PeqXoExportBlocks() no longer exists. XO now has
      //     its own builder, buildAdau1701XoExportBlocks() (see
      //     adau1701_engineering_export.dart), which is diff-only: it
      //     compares each channel's current HPF/LPF frequency against
      //     DeployProjectState.appliedXoByChannel (AppliedXoChannelState)
      //     and emits a block ONLY for a channel with an actually-changed
      //     side — an untouched channel produces no block, and therefore no
      //     op, regardless of what else is in tuningState.
      //   - PEQ is now built by the fully separate buildAdau1701PeqExportBlocks()
      //     — an XO-only edit's export package cannot contain a PEQ block
      //     that XO caused; the two builders share no state.
      //   - The frequency-only frame (param 0x15, band 0, 16-bit LE Hz) and
      //     channel mapping are UNCHANGED from the original TEST/RESTORE
      //     capture evidence on channels 0–3 — no new mapping is claimed
      //     proven here.
      //   - CrossoverFilter.type / .slope (e.g. "LR24") are still never
      //     transmitted — still no capture-proven mapping for them. This is
      //     tracked, not silently dropped: AppliedXoChannelState records
      //     type/slope for audit, but only a frequency change can produce a
      //     write operation.
      // Do NOT reintroduce a full-state XO export path (or any other caller
      // that skips the appliedXoByChannel diff) while this entry is
      // captureProven — that reopens the exact incident this fixes.
      HardwareCapabilityEntry(
          kind: HardwareParamKind.crossoverHighPass,
          verification: HardwareParamVerification.captureProven),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.crossoverLowPass,
          verification: HardwareParamVerification.captureProven),
      // channelMute: parameter-ID 0x12, payload 01 00 + state byte.
      // Polarity confirmed: State 0=MUTED, State 1=UNMUTED.
      // ACK-only (no mute readback service). Write is capture-proven.
      HardwareCapabilityEntry(
          kind: HardwareParamKind.channelMute,
          verification: HardwareParamVerification.captureProven),
      HardwareCapabilityEntry(
          kind: HardwareParamKind.channelDelay,
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
