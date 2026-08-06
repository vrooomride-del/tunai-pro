// Result of a hardware DSP parameter readback comparison.
//
// Produced after a raw state read is decoded and the actual value is compared
// to the expected (written) value. Attach to HardwareWriteOpOutcome when the
// operation reaches HardwareWriteOpStatus.written to carry the evidence that
// elevated the status from ack-only to readback-verified.
//
// Phase 3 audit note (V3-8A): HardwareWriteOpOutcome currently carries no
// per-operation readback detail — only a status enum. Wire readbackResult
// into HardwareWriteOpOutcome once BLE hardware capture confirms the Band0
// gain readback round-trip and the binding in pro_icp5_peq_write_port.dart
// is updated to perform the post-write read. UI surface (Phase 4) follows
// that step, not this one.

enum HardwareReadbackStatus {
  /// actualValue matches expectedValue within tolerance.
  verified,

  /// actualValue differs from expectedValue beyond tolerance.
  mismatch,

  /// No readback implementation is available for this parameter.
  unavailable,

  /// The raw state read or decode step failed; values are not meaningful.
  readError,
}

class HardwareReadbackResult {
  final String parameter;
  final double expectedValue;
  final double actualValue;

  /// |actualValue − expectedValue|. NaN when status is unavailable/readError.
  final double difference;

  final HardwareReadbackStatus status;

  /// Human-readable context for unavailable/readError outcomes; null on success.
  final String? message;

  const HardwareReadbackResult({
    required this.parameter,
    required this.expectedValue,
    required this.actualValue,
    required this.difference,
    required this.status,
    this.message,
  });

  /// Compares [actualValue] to [expectedValue] within [tolerance] and returns
  /// a verified or mismatch result. Default tolerance is 0.1 (one-tenth of a
  /// dB for gain parameters encoded at ×10 int8 resolution).
  factory HardwareReadbackResult.verify({
    required String parameter,
    required double expectedValue,
    required double actualValue,
    double tolerance = 0.1,
  }) {
    final difference = (actualValue - expectedValue).abs();
    return HardwareReadbackResult(
      parameter: parameter,
      expectedValue: expectedValue,
      actualValue: actualValue,
      difference: difference,
      status: difference <= tolerance
          ? HardwareReadbackStatus.verified
          : HardwareReadbackStatus.mismatch,
    );
  }

  factory HardwareReadbackResult.unavailable(String parameter) =>
      HardwareReadbackResult(
        parameter: parameter,
        expectedValue: double.nan,
        actualValue: double.nan,
        difference: double.nan,
        status: HardwareReadbackStatus.unavailable,
      );

  factory HardwareReadbackResult.readError(String parameter, String reason) =>
      HardwareReadbackResult(
        parameter: parameter,
        expectedValue: double.nan,
        actualValue: double.nan,
        difference: double.nan,
        status: HardwareReadbackStatus.readError,
        message: reason,
      );

  bool get isVerified => status == HardwareReadbackStatus.verified;

  Map<String, dynamic> toJson() => {
        'parameter': parameter,
        if (status == HardwareReadbackStatus.verified ||
            status == HardwareReadbackStatus.mismatch) ...{
          'expectedValue': expectedValue,
          'actualValue': actualValue,
          'difference': difference,
        },
        'status': status.name,
        if (message != null) 'message': message,
      };
}
