// ── TUNAI PRO Phase T — Controlled Write Engine ───────────────────────────────
// Generates and (placeholder-)executes controlled ADAU1466 Master Volume writes.
//
// ABSOLUTE RESTRICTIONS — do not loosen without expert hardware sign-off:
//   - Only ADAU1466 Master Volume L (0x67) and R (0x64) are allowed.
//   - Values must be in the range 0.0–1.0. No boost above 1.0. No negatives.
//   - Transport must be connected (non-placeholder) before any write is attempted.
//   - User confirmation is required for every write session.
//   - Permission must be controlledMasterVolumeOnly.
//   - No EEPROM write. No Selfboot write. No SafeLoad. No Write-All.
//   - Log every attempt regardless of outcome.
//   - AI suggests. Expert verifies. AOS protects. DSP executes.

import 'dart:math' show Random;
import 'pro_hardware_write_data.dart';
import 'pro_usbi_transport.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

// Verified ADAU1466 Master Volume addresses.
// These are the ONLY addresses this engine will ever touch.
const int _kAddrMasterVolumeL = 0x67;
const int _kAddrMasterVolumeR = 0x64;

// ADAU1466 uses 5.23 fixed-point for volume parameters.
// Full scale (1.0) = 0x00800000 in 5.23.
// The engine encodes value * 2^23 as a 4-byte big-endian integer.
const int _kFixedPointScale = 1 << 23; // 2^23 = 8388608

// ── Fixed-point encoding ──────────────────────────────────────────────────────

/// Encodes a 0.0–1.0 linear gain into ADAU1466 5.23 fixed-point 4-byte MSB-first.
/// Returns [b0, b1, b2, b3] where b0 is the most significant byte.
List<int> _encodeFixedPoint(double value) {
  // Clamp defensively — callers must already validate, but we double-guard.
  final clamped = value.clamp(0.0, 1.0);
  final fixed = (clamped * _kFixedPointScale).round().clamp(0, 0x7FFFFFFF);
  return [
    (fixed >> 24) & 0xFF,
    (fixed >> 16) & 0xFF,
    (fixed >>  8) & 0xFF,
     fixed        & 0xFF,
  ];
}

String _toHexString(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();

String _toHex32(double value) {
  final bytes = _encodeFixedPoint(value);
  return '0x${_toHexString(bytes)}';
}

String _uniqueId() =>
    'wreq_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

// ── Guard result ──────────────────────────────────────────────────────────────

class ControlledWriteGuardResult {
  final bool allowed;
  final String? blockedReason;
  final List<String> warnings;

  const ControlledWriteGuardResult({
    required this.allowed,
    this.blockedReason,
    this.warnings = const [],
  });
}

// ── Guard checks ──────────────────────────────────────────────────────────────

ControlledWriteGuardResult _runGuards({
  required double leftVolume,
  required double rightVolume,
  required bool userConfirmed,
  required bool transportConnected,
  required HardwareWritePermission permission,
}) {
  final warnings = <String>[];

  // Guard 1: values must be in valid range
  if (leftVolume < 0.0 || leftVolume > 1.0) {
    return ControlledWriteGuardResult(
      allowed: false,
      blockedReason: 'Left volume $leftVolume is out of range [0.0–1.0]. '
                     'Values above 1.0 or below 0.0 are blocked.',
    );
  }
  if (rightVolume < 0.0 || rightVolume > 1.0) {
    return ControlledWriteGuardResult(
      allowed: false,
      blockedReason: 'Right volume $rightVolume is out of range [0.0–1.0]. '
                     'Values above 1.0 or below 0.0 are blocked.',
    );
  }

  // Guard 2: permission must be controlledMasterVolumeOnly
  if (permission != HardwareWritePermission.controlledMasterVolumeOnly) {
    return ControlledWriteGuardResult(
      allowed: false,
      blockedReason: 'Permission is "${permission.label}". '
                     'Only controlledMasterVolumeOnly permission allows writes.',
    );
  }

  // Guard 3: user must have confirmed
  if (!userConfirmed) {
    return const ControlledWriteGuardResult(
      allowed: false,
      blockedReason: 'User confirmation is required before any write.',
    );
  }

  // Guard 4: transport must be connected (non-placeholder)
  if (!transportConnected) {
    return const ControlledWriteGuardResult(
      allowed: false,
      blockedReason: 'USBi transport is not connected. '
                     'Phase T transport is a placeholder — no real hardware write.',
    );
  }

  // Warnings (non-blocking)
  if (leftVolume == 1.0 || rightVolume == 1.0) {
    warnings.add('Volume at maximum (1.0). Verify speaker protection is active.');
  }
  if ((leftVolume - rightVolume).abs() > 0.3) {
    warnings.add('Left/Right volume difference exceeds 0.3. Verify stereo balance.');
  }

  return ControlledWriteGuardResult(allowed: true, warnings: warnings);
}

// ── Request builder ───────────────────────────────────────────────────────────

/// Creates the two write requests (L and R) for a master volume pair.
/// Does NOT touch any transport. This is pure data construction.
///
/// [leftVolume] and [rightVolume] must be in [0.0, 1.0].
/// Throws [ArgumentError] if values are out of range.
List<HardwareWriteRequest> createMasterVolumeWriteRequests({
  required double leftVolume,
  required double rightVolume,
  HardwareWritePermission permission =
      HardwareWritePermission.controlledMasterVolumeOnly,
}) {
  if (leftVolume < 0.0 || leftVolume > 1.0) {
    throw ArgumentError.value(
        leftVolume, 'leftVolume', 'Must be in range [0.0, 1.0]');
  }
  if (rightVolume < 0.0 || rightVolume > 1.0) {
    throw ArgumentError.value(
        rightVolume, 'rightVolume', 'Must be in range [0.0, 1.0]');
  }

  final now = DateTime.now();

  final lBytes = _encodeFixedPoint(leftVolume);
  final rBytes = _encodeFixedPoint(rightVolume);

  final reqL = HardwareWriteRequest(
    id:            _uniqueId(),
    target:        HardwareWriteTarget.adau1466MasterVolumeL,
    addressInt:    _kAddrMasterVolumeL,
    addressHex:    '0x${_kAddrMasterVolumeL.toRadixString(16).toUpperCase()}',
    valueDouble:   leftVolume,
    fixedPointHex: _toHex32(leftVolume),
    rawBytes:      lBytes,
    createdAt:     now,
    permission:    permission,
    dryRunOnly:    true,
    warning:       'Volatile write only — ADAU1466 Master Volume L (0x67). '
                   'Verified address. No EEPROM. No Selfboot. No SafeLoad.',
  );

  final reqR = HardwareWriteRequest(
    id:            _uniqueId(),
    target:        HardwareWriteTarget.adau1466MasterVolumeR,
    addressInt:    _kAddrMasterVolumeR,
    addressHex:    '0x${_kAddrMasterVolumeR.toRadixString(16).toUpperCase()}',
    valueDouble:   rightVolume,
    fixedPointHex: _toHex32(rightVolume),
    rawBytes:      rBytes,
    createdAt:     now,
    permission:    permission,
    dryRunOnly:    true,
    warning:       'Volatile write only — ADAU1466 Master Volume R (0x64). '
                   'Verified address. No EEPROM. No Selfboot. No SafeLoad.',
  );

  return [reqL, reqR];
}

// ── Write executor ────────────────────────────────────────────────────────────

/// Attempts to perform the controlled master volume write via [transport].
/// Returns a [HardwareWriteLog] recording every request and the final result.
///
/// In Phase T, transport is always a placeholder — this will always return a
/// blocked/failed result. The log will clearly indicate wasActualWrite: false.
Future<HardwareWriteLog> performControlledMasterVolumeWrite({
  required double leftVolume,
  required double rightVolume,
  required bool userConfirmed,
  required ProUsbiTransport transport,
  HardwareWritePermission permission =
      HardwareWritePermission.controlledMasterVolumeOnly,
}) async {
  final now = DateTime.now();
  final logId = 'wlog_${now.millisecondsSinceEpoch}';

  // Run guards first — fail fast, log always
  final guard = _runGuards(
    leftVolume:        leftVolume,
    rightVolume:       rightVolume,
    userConfirmed:     userConfirmed,
    transportConnected: transport.isConnected,
    permission:        permission,
  );

  // Build requests (for logging) regardless of guard outcome
  HardwareWriteResult result;
  List<HardwareWriteRequest> requests;

  if (!guard.allowed) {
    // Guard blocked — construct minimal requests for the log, mark dry-run
    requests = _safeRequestsOrEmpty(leftVolume, rightVolume, permission);
    result = HardwareWriteResult(
      requestId:      logId,
      status:         HardwareWriteStatus.blocked,
      attemptedAt:    now,
      errorMessage:   guard.blockedReason,
      wasActualWrite: false,
      safetyNote:     'Blocked by guard. No write occurred. '
                      'Volatile write only — ADAU1466 Master Volume L/R only.',
    );
  } else {
    // Guards passed — attempt transport write for each request
    try {
      requests = createMasterVolumeWriteRequests(
        leftVolume:  leftVolume,
        rightVolume: rightVolume,
        permission:  permission,
      );

      // Verify addresses before touching transport — extra safety layer
      for (final req in requests) {
        if (!_isVerifiedAddress(req.addressInt)) {
          result = HardwareWriteResult(
            requestId:      logId,
            status:         HardwareWriteStatus.blocked,
            attemptedAt:    now,
            errorMessage:   'Address 0x${req.addressInt.toRadixString(16)} is not a '
                            'verified master volume address. Write aborted.',
            wasActualWrite: false,
            safetyNote:     'Unverified address blocked. No write occurred.',
          );
          return HardwareWriteLog(
            id:            logId,
            requests:      requests,
            result:        result,
            createdAt:     now,
            userConfirmed: userConfirmed,
            sessionNote:   'BLOCKED — unverified address.',
          );
        }
      }

      // Attempt write via transport (Phase T: always returns failure)
      var anyFailed = false;
      String? firstError;
      for (final req in requests) {
        final outcome = await transport.writeParameter(req.addressInt, req.rawBytes);
        if (!outcome.success) {
          anyFailed = true;
          firstError ??= outcome.errorMessage;
          break;
        }
      }

      result = HardwareWriteResult(
        requestId:      logId,
        status:         anyFailed
                        ? HardwareWriteStatus.failed
                        : HardwareWriteStatus.success,
        attemptedAt:    now,
        errorMessage:   firstError,
        wasActualWrite: false, // always false in Phase T
        safetyNote:     'Volatile write only — ADAU1466 Master Volume L/R. '
                        'No EEPROM. No Selfboot. No SafeLoad.',
      );
    } catch (e) {
      requests = _safeRequestsOrEmpty(leftVolume, rightVolume, permission);
      result = HardwareWriteResult(
        requestId:      logId,
        status:         HardwareWriteStatus.failed,
        attemptedAt:    now,
        errorMessage:   'Unexpected error: $e',
        wasActualWrite: false,
        safetyNote:     'Error during write. No hardware state was changed.',
      );
    }
  }

  return HardwareWriteLog(
    id:            logId,
    requests:      requests,
    result:        result,
    createdAt:     now,
    userConfirmed: userConfirmed,
    sessionNote:   guard.allowed
                   ? (guard.warnings.isNotEmpty
                       ? 'Warnings: ${guard.warnings.join("; ")}'
                       : 'Write attempted.')
                   : 'Blocked: ${guard.blockedReason}',
  );
}

// ── Internal helpers ──────────────────────────────────────────────────────────

bool _isVerifiedAddress(int addr) =>
    addr == _kAddrMasterVolumeL || addr == _kAddrMasterVolumeR;

List<HardwareWriteRequest> _safeRequestsOrEmpty(
  double left, double right, HardwareWritePermission permission) {
  try {
    final cL = left.clamp(0.0, 1.0);
    final cR = right.clamp(0.0, 1.0);
    return createMasterVolumeWriteRequests(
        leftVolume: cL, rightVolume: cR, permission: permission);
  } catch (_) {
    return [];
  }
}
