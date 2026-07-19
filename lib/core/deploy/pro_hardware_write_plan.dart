// ── TUNAI PRO — Hardware Write Plan builder (translation only) ────────────────
// Translates a DspExportPackage's typed parameterBlocks into a device-annotated
// HardwareWritePlan, tagging each parameter with its capability/verification
// level. This is a DESCRIPTION of intended writes — it performs no writes,
// makes no transport/executor calls, and touches no DSP codec or address map.
//
// Fail-closed: any parameter without a capture-proven capability entry is
// marked not-writable.

import '../pro_export_data.dart';
import 'pro_hardware_capability.dart';

// ── Operation ─────────────────────────────────────────────────────────────────

class HardwareWriteOp {
  final String channelId;
  final HardwareParamKind parameterKind;

  /// 0-based band index (0 = Band 1) for PEQ parameters; null otherwise.
  final int? bandIndex;

  /// Intended value. Booleans (polarity/mute) are encoded as 1.
  final num targetValue;

  final HardwareParamVerification verification;

  /// True only when [verification] is capture-proven for the device.
  final bool writable;

  /// Human-readable rationale for the writable flag.
  final String reason;

  const HardwareWriteOp({
    required this.channelId,
    required this.parameterKind,
    required this.bandIndex,
    required this.targetValue,
    required this.verification,
    required this.writable,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {
        'channelId': channelId,
        'parameterKind': parameterKind.toJson(),
        if (bandIndex != null) 'bandIndex': bandIndex,
        'targetValue': targetValue,
        'verification': verification.toJson(),
        'writable': writable,
        'reason': reason,
      };
}

// ── Summary ───────────────────────────────────────────────────────────────────

class HardwareWritePlanSummary {
  final int totalOps;
  final int writableOps;
  final int captureProvenCount;
  final int unverifiedCount;
  final int unavailableCount;

  const HardwareWritePlanSummary({
    required this.totalOps,
    required this.writableOps,
    required this.captureProvenCount,
    required this.unverifiedCount,
    required this.unavailableCount,
  });

  bool get hasWritableOps => writableOps > 0;

  Map<String, dynamic> toJson() => {
        'totalOps': totalOps,
        'writableOps': writableOps,
        'captureProvenCount': captureProvenCount,
        'unverifiedCount': unverifiedCount,
        'unavailableCount': unavailableCount,
      };
}

// ── Plan ──────────────────────────────────────────────────────────────────────

class HardwareWritePlan {
  final String sourceExportPackageId;
  final HardwareDeviceProfile deviceProfile;
  final DateTime generatedAt;
  final List<HardwareWriteOp> operations;
  final HardwareWritePlanSummary summary;

  const HardwareWritePlan({
    required this.sourceExportPackageId,
    required this.deviceProfile,
    required this.generatedAt,
    required this.operations,
    required this.summary,
  });

  /// The subset of operations eligible for an actual write (capture-proven).
  List<HardwareWriteOp> get writableOperations =>
      operations.where((o) => o.writable).toList();

  Map<String, dynamic> toJson() => {
        'sourceExportPackageId': sourceExportPackageId,
        'deviceId': deviceProfile.deviceId,
        'generatedAt': generatedAt.toIso8601String(),
        'operations': operations.map((o) => o.toJson()).toList(),
        'summary': summary.toJson(),
      };
}

// ── Builder ───────────────────────────────────────────────────────────────────

/// Builds a [HardwareWritePlan] from [exportPackage]'s parameterBlocks, tagging
/// each parameter with [profile]'s capability/verification level.
///
/// Read-only translation: no transport, executor, or DSP write occurs. Unknown
/// or unmapped parameters fail closed (not writable).
HardwareWritePlan buildHardwareWritePlan(
  DspExportPackage exportPackage,
  HardwareDeviceProfile profile, {
  DateTime? generatedAt,
}) {
  final ops = <HardwareWriteOp>[];

  for (final block in exportPackage.parameterBlocks) {
    switch (block.type) {
      case ExportBlockType.peq:
        final bands = block.parameters['bands'];
        if (bands is Map) {
          for (final entry in bands.entries) {
            final idx = _bandIndex('${entry.key}');
            final band = entry.value;
            if (band is! Map) continue;
            _addOp(ops, profile, block.channelId,
                HardwareParamKind.peqFrequency, idx, band['freq_hz']);
            _addOp(ops, profile, block.channelId, HardwareParamKind.peqGain,
                idx, band['gain_db']);
            _addOp(ops, profile, block.channelId, HardwareParamKind.peqQ, idx,
                band['q']);
          }
        }

      case ExportBlockType.crossover:
        final hp = block.parameters['highPass'];
        if (hp is Map) {
          _addOp(ops, profile, block.channelId,
              HardwareParamKind.crossoverHighPass, null, hp['freq_hz']);
        }
        final lp = block.parameters['lowPass'];
        if (lp is Map) {
          _addOp(ops, profile, block.channelId,
              HardwareParamKind.crossoverLowPass, null, lp['freq_hz']);
        }
        if (block.parameters['polarityInverted'] == true) {
          _addOp(ops, profile, block.channelId,
              HardwareParamKind.channelPolarity, null, 1);
        }

      case ExportBlockType.gain:
      case ExportBlockType.delay:
      case ExportBlockType.phase:
        final p = block.parameters;
        if (p['gainDb'] is num) {
          _addOp(ops, profile, block.channelId, HardwareParamKind.channelGain,
              null, p['gainDb'] as num);
        }
        if (p['delayMs'] is num) {
          _addOp(ops, profile, block.channelId, HardwareParamKind.channelDelay,
              null, p['delayMs'] as num);
        }
        if (p['muted'] == true) {
          _addOp(ops, profile, block.channelId, HardwareParamKind.channelMute,
              null, 1);
        }

      case ExportBlockType.protection:
        // Protection is a summary block — no directly writable parameters.
        break;
    }
  }

  return HardwareWritePlan(
    sourceExportPackageId: exportPackage.id,
    deviceProfile: profile,
    generatedAt: generatedAt ?? DateTime.now(),
    operations: ops,
    summary: _summarize(ops),
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

void _addOp(
  List<HardwareWriteOp> ops,
  HardwareDeviceProfile profile,
  String channelId,
  HardwareParamKind kind,
  int? bandIndex,
  Object? rawValue,
) {
  if (rawValue == null) return;
  final num value;
  if (rawValue is num) {
    value = rawValue;
  } else if (rawValue is bool) {
    value = rawValue ? 1 : 0;
  } else {
    return; // non-numeric, non-bool → not a writable parameter value.
  }

  final verification = profile.verificationFor(kind, bandIndex: bandIndex);
  ops.add(HardwareWriteOp(
    channelId: channelId,
    parameterKind: kind,
    bandIndex: bandIndex,
    targetValue: value,
    verification: verification,
    writable: verification.isWriteEligible,
    reason: _reasonFor(verification, profile),
  ));
}

String _reasonFor(
    HardwareParamVerification v, HardwareDeviceProfile profile) {
  switch (v) {
    case HardwareParamVerification.captureProven:
      return 'Capture-proven write path on ${profile.deviceName}.';
    case HardwareParamVerification.unverified:
      return 'Write path exists on ${profile.deviceName} but is not '
          'capture-proven; capture evidence required before writing.';
    case HardwareParamVerification.unavailable:
      return 'No confirmed write path on ${profile.deviceName}.';
  }
}

/// Parses the trailing integer of a `band_N` key. Returns null if not present.
int? _bandIndex(String key) {
  final i = key.lastIndexOf('_');
  if (i < 0 || i + 1 >= key.length) return null;
  return int.tryParse(key.substring(i + 1));
}

HardwareWritePlanSummary _summarize(List<HardwareWriteOp> ops) {
  var proven = 0;
  var unverified = 0;
  var unavailable = 0;
  for (final o in ops) {
    switch (o.verification) {
      case HardwareParamVerification.captureProven:
        proven++;
      case HardwareParamVerification.unverified:
        unverified++;
      case HardwareParamVerification.unavailable:
        unavailable++;
    }
  }
  return HardwareWritePlanSummary(
    totalOps: ops.length,
    writableOps: proven,
    captureProvenCount: proven,
    unverifiedCount: unverified,
    unavailableCount: unavailable,
  );
}
