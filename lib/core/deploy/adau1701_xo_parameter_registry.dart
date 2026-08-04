// ── ADAU1701 XO Parameter Registry — Phase 7-5B ──────────────────────────────
// Explicit, single-source-of-truth mapping of ICP5 param 0x15 (XO/filter
// control) properties. Data only — this file performs no write, and is not
// wired into pro_hardware_capability.dart / pro_hardware_write_plan.dart /
// any export builder. It exists so the next phase (once real evidence for
// slope/type exists) has one place to update rather than scattered
// constants, matching this codebase's existing pattern
// (HardwareParamVerification / pro_hardware_capability.dart).
//
// Verification status is intentionally NOT uniform: frequency is
// captureProven (three independently checksum-verified real MiUMAX
// captures — see adau1701_xo_frequency_capture_evidence_test.dart). Slope
// and filter type are recorded here as claimed value maps, but kept
// `unavailable` — the evidence provided for them was a bare
// "property/value" list with no complete example frame to verify byte
// positions or checksum against, unlike frequency's three full captures.
// Treating them as proven without that would repeat exactly the mistake
// that caused the original P0 "XO Deploy Parameter Corruption" incident.

import 'pro_hardware_capability.dart' show HardwareParamVerification;

enum XoParameterProperty { frequency, slope, filterType }

/// One ICP5 param-0x15 property mapping. [valueMap] is null for frequency
/// (a continuous uint16 value, not an enum). [verification] gates whether
/// this mapping may ever be used to build a real write — see
/// [HardwareParamVerification] for the fail-closed contract.
class XoParameterMapping {
  final int parameterId;
  final XoParameterProperty property;
  final String encoding;
  final Map<String, int>? valueMap;
  final HardwareParamVerification verification;
  final String evidenceNote;

  const XoParameterMapping({
    required this.parameterId,
    required this.property,
    required this.encoding,
    this.valueMap,
    required this.verification,
    required this.evidenceNote,
  });
}

abstract final class Adau1701XoParameterRegistry {
  /// Frequency — capture-proven (Phase 7-5A/7-5B). Payload after the 0x15
  /// parameter ID: [channel, 0x02, side, freqLo, freqHi]. Side: 0x00 = HPF,
  /// 0x01 = LPF (frame index 9) — this is the byte Phase 7-5A initially
  /// mis-modeled as a fixed "frequency property" constant, corrected once an
  /// HPF capture was available to show it actually varies by side.
  static const frequency = XoParameterMapping(
    parameterId: 0x15,
    property: XoParameterProperty.frequency,
    encoding: 'payload = [channel, 0x02, side, freqLo, freqHi]; '
        'side: 0x00=HPF, 0x01=LPF; frequency = uint16 little-endian Hz',
    verification: HardwareParamVerification.captureProven,
    evidenceNote:
        'icp5_frame_codec.dart buildFilterFrequencyWriteArbitrary(). Three '
        'independently checksum-verified real MiUMAX captures: '
        'LPF 3000 Hz (55 0B 1C 00 00 00 15 03 02 01 B8 0B 5A), '
        'HPF 3100 Hz (55 0B 1C 00 00 00 15 03 02 00 1C 0C BE), '
        'LPF 3100 Hz (55 0B 1C 00 00 00 15 03 02 01 1C 0C BF).',
  );

  /// Slope — NOT wired to any write path. Values below are recorded exactly
  /// as claimed, for reference only; they are not deployable until a
  /// complete, checksum-verifiable captured frame exists for at least one
  /// slope change (the same rigor applied to [frequency]).
  static const slope = XoParameterMapping(
    parameterId: 0x15,
    property: XoParameterProperty.slope,
    encoding: 'UNCONFIRMED — no complete captured frame was provided; byte '
        'position within the payload is unknown',
    valueMap: {'6dB': 0x01, '12dB': 0x02, '24dB': 0x04},
    verification: HardwareParamVerification.unavailable,
    evidenceNote:
        'A property/value claim ("property 0x00", values 0x01/0x02/0x04) was '
        'given without a full example frame (channel + side + property + '
        'value + checksum) to independently verify, unlike frequency\'s three '
        'captures. Needs at least one complete captured frame per slope '
        'change before this can move to captureProven.',
  );

  /// Filter type — NOT wired to any write path. Same evidentiary gap as
  /// [slope].
  static const filterType = XoParameterMapping(
    parameterId: 0x15,
    property: XoParameterProperty.filterType,
    encoding: 'UNCONFIRMED — no complete captured frame was provided; byte '
        'position within the payload is unknown',
    valueMap: {'butterworth': 0x08, 'bessel': 0x0A},
    verification: HardwareParamVerification.unavailable,
    evidenceNote:
        'A property/value claim ("property 0x03", values 0x08/0x0A) was '
        'given without a full example frame to independently verify. Needs '
        'at least one complete captured frame per filter-type change before '
        'this can move to captureProven. Linkwitz-Riley is not in the '
        'claimed value set at all — no LR value exists here to invent one.',
  );

  static const all = [frequency, slope, filterType];
}
