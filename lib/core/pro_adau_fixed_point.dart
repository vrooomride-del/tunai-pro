// ── TUNAI PRO Phase P — ADAU Fixed-Point Conversion (Draft) ──────────────────
// Converts floating-point DSP coefficients to ADAU fixed-point format drafts.
// DRAFT ONLY — values are NOT linked to hardware addresses.
// DO NOT write to hardware. DO NOT attach to unverified DSP addresses.
// DO NOT claim final ADAU binary compatibility.
// AI suggests. Expert verifies. AOS protects. DSP executes.

import 'dart:math' as math;

// ── Enums ─────────────────────────────────────────────────────────────────────

enum AdauFixedPointFormat {
  format824,   // 8.24 signed fixed-point (standard ADAU coefficient format)
  format528,   // 5.28 signed fixed-point (extended precision)
  format1616,  // 16.16 signed fixed-point
  unknown;

  String toJson() => name;
  static AdauFixedPointFormat fromJson(String s) =>
      AdauFixedPointFormat.values.firstWhere((e) => e.name == s,
          orElse: () => AdauFixedPointFormat.unknown);

  String get label => switch (this) {
    AdauFixedPointFormat.format824  => '8.24',
    AdauFixedPointFormat.format528  => '5.28',
    AdauFixedPointFormat.format1616 => '16.16',
    AdauFixedPointFormat.unknown    => 'Unknown',
  };
}

enum AdauCoefficientStatus {
  notConverted,
  convertedDraft,
  requiresVerification,
  unsupported;

  String toJson() => name;
  static AdauCoefficientStatus fromJson(String s) =>
      AdauCoefficientStatus.values.firstWhere((e) => e.name == s,
          orElse: () => AdauCoefficientStatus.notConverted);

  String get label => switch (this) {
    AdauCoefficientStatus.notConverted        => 'Not Converted',
    AdauCoefficientStatus.convertedDraft      => 'Converted (Draft)',
    AdauCoefficientStatus.requiresVerification => 'Requires Verification',
    AdauCoefficientStatus.unsupported         => 'Unsupported',
  };
}

// ── AdauFixedPointValue ───────────────────────────────────────────────────────

class AdauFixedPointValue {
  final AdauFixedPointFormat format;
  final double sourceDouble;
  final int rawInt;
  final String hex;
  final AdauCoefficientStatus status;
  final String? warning;

  const AdauFixedPointValue({
    required this.format,
    required this.sourceDouble,
    required this.rawInt,
    required this.hex,
    required this.status,
    this.warning,
  });

  Map<String, dynamic> toJson() => {
    'format': format.toJson(),
    'sourceDouble': sourceDouble,
    'rawInt': rawInt,
    'hex': hex,
    'status': status.toJson(),
    if (warning != null) 'warning': warning,
  };

  factory AdauFixedPointValue.fromJson(Map<String, dynamic> j) =>
      AdauFixedPointValue(
        format: AdauFixedPointFormat.fromJson(j['format'] as String? ?? 'unknown'),
        sourceDouble: (j['sourceDouble'] as num? ?? 0).toDouble(),
        rawInt: j['rawInt'] as int? ?? 0,
        hex: j['hex'] as String? ?? '0x00000000',
        status: AdauCoefficientStatus.fromJson(j['status'] as String? ?? 'notConverted'),
        warning: j['warning'] as String?,
      );
}

// ── AdauFixedPointConverter ───────────────────────────────────────────────────

class AdauFixedPointConverter {
  static const String _draftWarning =
      'Draft ADAU 8.24 conversion. Requires SigmaStudio/hardware verification. '
      'Not linked to any hardware address. Not for direct register write.';

  /// Convert [value] to signed 8.24 fixed-point draft.
  /// rawInt = round(value × 2^24).
  /// Clamps to signed 32-bit range.
  static AdauFixedPointValue to824(double value) {
    if (!value.isFinite) {
      return AdauFixedPointValue(
        format: AdauFixedPointFormat.format824,
        sourceDouble: value,
        rawInt: 0,
        hex: '0x00000000',
        status: AdauCoefficientStatus.requiresVerification,
        warning: 'Non-finite input value — conversion skipped. $_draftWarning',
      );
    }

    final scale = math.pow(2, 24).toDouble();
    final raw = (value * scale).round();
    // Clamp to signed 32-bit range
    const minVal = -2147483648; // -(2^31)
    const maxVal =  2147483647; //  (2^31 - 1)
    final clamped = raw.clamp(minVal, maxVal);

    final overflowed = clamped != raw;
    final hex = _toHex32(clamped);

    return AdauFixedPointValue(
      format: AdauFixedPointFormat.format824,
      sourceDouble: value,
      rawInt: clamped,
      hex: hex,
      status: overflowed
          ? AdauCoefficientStatus.requiresVerification
          : AdauCoefficientStatus.convertedDraft,
      warning: overflowed
          ? 'Value overflowed signed 32-bit 8.24 range — clamped. $_draftWarning'
          : _draftWarning,
    );
  }

  /// 5.28 fixed-point — not yet implemented for Phase P.
  static AdauFixedPointValue to528(double value) => AdauFixedPointValue(
    format: AdauFixedPointFormat.format528,
    sourceDouble: value,
    rawInt: 0,
    hex: '0x00000000',
    status: AdauCoefficientStatus.unsupported,
    warning: '5.28 conversion not implemented in Phase P. Requires SigmaStudio verification.',
  );

  /// 16.16 fixed-point — not yet implemented for Phase P.
  static AdauFixedPointValue to1616(double value) => AdauFixedPointValue(
    format: AdauFixedPointFormat.format1616,
    sourceDouble: value,
    rawInt: 0,
    hex: '0x00000000',
    status: AdauCoefficientStatus.unsupported,
    warning: '16.16 conversion not implemented in Phase P. Requires SigmaStudio verification.',
  );

  /// Convert a list of biquad coefficients [b0,b1,b2,a1,a2] to 8.24 drafts.
  static List<AdauFixedPointValue> biquadCoefficients824(List<double> coeffs) =>
      coeffs.map(to824).toList();

  static String _toHex32(int value) {
    // Represent as unsigned 32-bit hex for readability
    final unsigned = value & 0xFFFFFFFF;
    return '0x${unsigned.toRadixString(16).toUpperCase().padLeft(8, '0')}';
  }
}
