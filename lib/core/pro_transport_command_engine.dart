// ── TUNAI PRO Phase T3 — Transport Command Engine ────────────────────────────
// Creates transport-independent DSP write command envelopes for dry-run preview.
// Only ADAU1466 Master Volume L (0x0067) and R (0x0064) are supported.
// No hardware packet bytes are generated. No transport write methods are called.
//
// ABSOLUTE RESTRICTIONS:
//   - Do NOT write to hardware.
//   - Do NOT send USB, BLE, or ICP5 packets.
//   - Do NOT call transport.writeParameter().
//   - actualWriteAllowed must remain false.
//   - isExecutableNow must remain false.
//   - Only Master Volume L/R addresses are in scope.
//   - AI suggests. Expert verifies. AOS protects. DSP executes.

import 'dart:math' show Random;
import 'pro_transport_command_data.dart';
import 'pro_hardware_transport.dart';
import 'pro_dsp_address_registry.dart';
import 'pro_export_data.dart'; // DspTargetPlatform

// ── 8.24 fixed-point encoding ─────────────────────────────────────────────────
//
// ADAU1466 uses 8.24 fixed-point for volume parameters (as stated in the
// address map CSV column "data_type = 8.24 fixed-point").
// Full scale: 1.0 = 0x01000000 (1 * 2^24 = 16777216)
// Half scale: 0.5 = 0x00800000 (0.5 * 2^24 = 8388608)

const int _k824Scale = 1 << 24; // 2^24 = 16777216

/// Encodes 0.0–1.0 linear gain into ADAU1466 8.24 fixed-point (4-byte big-endian).
/// 1.0 → 0x01000000, 0.5 → 0x00800000, 0.0 → 0x00000000.
int _encode824(double value) {
  final clamped = value.clamp(0.0, 1.0);
  return (clamped * _k824Scale).round().clamp(0, 0x7FFFFFFF);
}

String _to824Hex(double value) {
  final fixed = _encode824(value);
  return '0x${fixed.toRadixString(16).padLeft(8, '0').toUpperCase()}';
}

String _newId() =>
    'tcmd_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

// ── createMasterVolumeCommand ──────────────────────────────────────────────────

/// Creates a dry-run command envelope for ADAU1466 Master Volume L or R.
///
/// [side] must be 'L' (→ 0x0067) or 'R' (→ 0x0064).
/// [linearValue] must be in [0.0, 1.0].
/// [registry] is used to verify the address exists and is write-eligible.
///
/// Phase T3: actualWriteAllowed = false. isExecutableNow = false.
/// No transport write methods are called. No packet bytes are produced.
TransportCommandEnvelope createMasterVolumeCommand({
  required HardwareTransportBackend backend,
  required String side,
  required double linearValue,
  required DspAddressRegistry registry,
}) {
  final id = _newId();
  final now = DateTime.now();

  // Validate side
  if (side != 'L' && side != 'R') {
    return TransportCommandEnvelope(
      id:             id,
      commandType:    TransportCommandType.writeParameter,
      status:         TransportCommandStatus.blocked,
      transportBackend: backend,
      targetPlatform: DspTargetPlatform.adau1466,
      parameterId:    'unknown_side',
      logicalName:    'Master Volume (unknown side)',
      addressHex:     '0x0000',
      addressInt:     0,
      byteOrder:      'big-endian',
      writeMode:      TransportWriteMode.volatileOnly,
      requiresUserConfirmation: true,
      blockedReason:  'Side must be "L" or "R". Got: "$side".',
      createdAt:      now,
    );
  }

  final addressInt  = side == 'L' ? kMasterVolumeLAddr : kMasterVolumeRAddr;
  final addressHex  = '0x${addressInt.toRadixString(16).padLeft(4, '0').toUpperCase()}';
  final parameterId = side == 'L' ? 'master_volume_l' : 'master_volume_r';
  final logicalName = 'Master Volume ${side == "L" ? "Left" : "Right"}';

  // Validate value range
  if (linearValue < 0.0 || linearValue > 1.0) {
    return TransportCommandEnvelope(
      id:              id,
      commandType:     TransportCommandType.writeParameter,
      status:          TransportCommandStatus.blocked,
      transportBackend: backend,
      targetPlatform:  DspTargetPlatform.adau1466,
      parameterId:     parameterId,
      logicalName:     logicalName,
      addressHex:      addressHex,
      addressInt:      addressInt,
      valueFloat:      linearValue,
      byteOrder:       'big-endian',
      writeMode:       TransportWriteMode.volatileOnly,
      requiresUserConfirmation: true,
      blockedReason:   'Value $linearValue is out of range [0.0–1.0]. '
                       'Values above 1.0 or below 0.0 are blocked.',
      createdAt:       now,
    );
  }

  // Verify address is in registry
  final regEntry = registry.findByAddressInt(addressInt);
  if (regEntry == null) {
    return TransportCommandEnvelope(
      id:              id,
      commandType:     TransportCommandType.writeParameter,
      status:          TransportCommandStatus.blocked,
      transportBackend: backend,
      targetPlatform:  DspTargetPlatform.adau1466,
      parameterId:     parameterId,
      logicalName:     logicalName,
      addressHex:      addressHex,
      addressInt:      addressInt,
      valueFloat:      linearValue,
      byteOrder:       'big-endian',
      writeMode:       TransportWriteMode.volatileOnly,
      requiresUserConfirmation: true,
      blockedReason:   'Address $addressHex not found in registry. '
                       'Expert verification required before command can proceed.',
      createdAt:       now,
    );
  }

  // Check address is write-eligible
  if (!registry.isActualWriteEligible(regEntry)) {
    return TransportCommandEnvelope(
      id:              id,
      commandType:     TransportCommandType.writeParameter,
      status:          TransportCommandStatus.blocked,
      transportBackend: backend,
      targetPlatform:  DspTargetPlatform.adau1466,
      parameterId:     parameterId,
      logicalName:     logicalName,
      addressHex:      addressHex,
      addressInt:      addressInt,
      valueFloat:      linearValue,
      byteOrder:       'big-endian',
      writeMode:       TransportWriteMode.volatileOnly,
      requiresUserConfirmation: true,
      blockedReason:   'Address $addressHex has status '
                       '"${regEntry.verificationStatus.label}". '
                       'Only verified addresses are write-eligible.',
      createdAt:       now,
      notes:           'Registry entry found but not write-eligible. '
                       'Expert sign-off required.',
    );
  }

  // All guards passed — create dry-run ready envelope.
  // Phase T3: actualWriteAllowed = false. isExecutableNow = false.
  // No packet bytes are produced. No transport is touched.
  final fixedInt = _encode824(linearValue);
  final fixedHex = _to824Hex(linearValue);

  return TransportCommandEnvelope(
    id:              id,
    commandType:     TransportCommandType.writeParameter,
    status:          TransportCommandStatus.dryRunReady,
    transportBackend: backend,
    targetPlatform:  DspTargetPlatform.adau1466,
    parameterId:     parameterId,
    logicalName:     logicalName,
    addressHex:      addressHex,
    addressInt:      addressInt,
    valueFloat:      linearValue,
    fixedPointHex:   fixedHex,
    fixedPointInt:   fixedInt,
    byteOrder:       'big-endian',
    writeMode:       TransportWriteMode.volatileOnly,
    requiresUserConfirmation: true,
    createdAt:       now,
    notes:           'ADAU1466 8.24 fixed-point. Volatile write only. '
                     'No EEPROM. No Selfboot. No SafeLoad. '
                     'Dry-run envelope — no hardware packet generated.',
  );
}

// ── createBlockedCommandForUnsupportedParameter ───────────────────────────────

/// Returns a blocked envelope for any parameter that is not Master Volume L/R.
/// Used to clearly reject PEQ / XO / Gain / Mute / Delay / SafeLoad requests.
TransportCommandEnvelope createBlockedCommandForUnsupportedParameter({
  required HardwareTransportBackend backend,
  required String parameterId,
  required String logicalName,
  required String addressHex,
  required int addressInt,
}) => TransportCommandEnvelope(
  id:              _newId(),
  commandType:     TransportCommandType.unsupported,
  status:          TransportCommandStatus.blocked,
  transportBackend: backend,
  targetPlatform:  DspTargetPlatform.adau1466,
  parameterId:     parameterId,
  logicalName:     logicalName,
  addressHex:      addressHex,
  addressInt:      addressInt,
  byteOrder:       'big-endian',
  writeMode:       TransportWriteMode.volatileOnly,
  requiresUserConfirmation: true,
  blockedReason:
      'Only Master Volume L/R dry-run commands are supported in Phase T3. '
      '"$logicalName" ($addressHex) is outside the allowed parameter scope.',
  notes:
      'PEQ, XO, Gain, Mute, Delay, SafeLoad, EEPROM, and Selfboot are '
      'blocked until live validation is complete and expert sign-off is given.',
);
