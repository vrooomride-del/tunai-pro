// ── TUNAI PRO Phase T4A — USBi Temporary Executor ────────────────────────────
// Strictly controlled executor for ADAU1466 Master Volume L/R via USBi.
// Injectable platform check and backend for testability.
//
// GUARD CHAIN (all must pass before any packet is sent):
//   D1 — Platform must be Windows (injectable for tests)
//   D2 — Transport must be usbiWindowsTemporary
//   D3 — Envelope must be isMasterVolumeCommand (0x0067 or 0x0064)
//   D4 — Envelope address must be verified Master Volume address
//   D5 — Envelope value must be in [0.0, 1.0]
//   D6 — User confirmation must be explicit (userConfirmed = true)
//   D7 — Native backend must be available (isAvailable = true)
//
// ABSOLUTE RESTRICTIONS:
//   - Do NOT bypass Guard D2 (transport check).
//   - wasActualWrite = true ONLY if native write call confirmed success.
//   - No PEQ / XO / Gain / Mute / Delay / SafeLoad / EEPROM / Selfboot.
//   - USBi is TEMPORARY. ICP5 is the final target.
//   - AI suggests. Expert verifies. AOS protects. DSP executes.

import 'dart:math' show Random;
import 'pro_usbi_executor_data.dart';
import 'pro_usbi_packet_builder.dart';
import 'pro_usbi_native_backend.dart';
import 'pro_transport_command_data.dart';
import 'pro_hardware_transport.dart';

class ProUsbiTemporaryExecutor {
  final bool Function() isWindowsPlatform;
  final ProUsbiNativeBackend backend;

  const ProUsbiTemporaryExecutor({
    required this.isWindowsPlatform,
    required this.backend,
  });

  /// Convenience factory for production builds (native backend disabled).
  factory ProUsbiTemporaryExecutor.disabled() => ProUsbiTemporaryExecutor(
    isWindowsPlatform: () => false,
    backend: const ProUsbiNativeBackendDisabled(),
  );

  String _newId(String prefix) =>
      '${prefix}_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

  // ── Guard helpers ───────────────────────────────────────────────────────────

  UsbiExecutionGuardResult _guard(
    bool passed,
    UsbiExecutionGuardCode code,
    String message, {
    String severity = 'block',
  }) =>
      UsbiExecutionGuardResult(
          passed: passed, code: code, message: message, severity: severity);

  // ── execute ─────────────────────────────────────────────────────────────────

  /// Attempts to execute [request] via the USBi temporary executor.
  ///
  /// All guards D1–D7 must pass before any packet is sent.
  /// Returns a [UsbiExecutionResult] with wasActualWrite = false on any guard
  /// failure, and wasActualWrite = true only if native write confirmed success.
  Future<UsbiExecutionResult> execute(UsbiExecutionRequest request) async {
    final resultId  = _newId('res');
    final now       = DateTime.now();
    final guards    = <UsbiExecutionGuardResult>[];

    // D1 — Platform check
    final isWindows = isWindowsPlatform();
    guards.add(_guard(
      isWindows,
      UsbiExecutionGuardCode.platformNotWindows,
      isWindows
          ? 'Platform is Windows. USBi write path available.'
          : 'Platform is not Windows. '
            'USBi temporary executor requires Windows. '
            'Use simulation or wait for ICP5 on other platforms.',
    ));

    // D2 — Transport check
    final isUsbi = request.transportBackend ==
        HardwareTransportBackend.usbiWindowsTemporary;
    guards.add(_guard(
      isUsbi,
      UsbiExecutionGuardCode.transportNotUsbiTemporary,
      isUsbi
          ? 'Transport is usbiWindowsTemporary.'
          : 'Transport is "${request.transportBackend.name}". '
            'Only usbiWindowsTemporary is allowed for this executor.',
    ));

    // D3 — Master Volume address check
    final isMasterVol = isMasterVolumeAddress(request.addressInt);
    guards.add(_guard(
      isMasterVol,
      UsbiExecutionGuardCode.commandNotMasterVolume,
      isMasterVol
          ? 'Address ${request.addressHex} is a verified Master Volume address.'
          : 'Address ${request.addressHex} is not a Master Volume address. '
            'Only 0x0067 (L) and 0x0064 (R) are in scope for Phase T4A.',
    ));

    // D4 — Verified Master Volume address (must be exactly L or R)
    final knownAddr = request.addressInt == kMasterVolumeLAddr ||
        request.addressInt == kMasterVolumeRAddr;
    guards.add(_guard(
      knownAddr,
      UsbiExecutionGuardCode.addressNotVerifiedMasterVolume,
      knownAddr
          ? 'Address is a verified ADAU1466 Master Volume register.'
          : 'Address ${request.addressHex} is not the known Master Volume L '
            '(0x0067) or R (0x0064). Execution blocked.',
    ));

    // D5 — Value range check
    final valueOk =
        request.valueFloat >= 0.0 && request.valueFloat <= 1.0;
    guards.add(_guard(
      valueOk,
      UsbiExecutionGuardCode.valueOutOfRange,
      valueOk
          ? 'Value ${request.valueFloat} is within [0.0, 1.0].'
          : 'Value ${request.valueFloat} is outside [0.0, 1.0]. Blocked.',
    ));

    // D6 — User confirmation
    guards.add(_guard(
      request.userConfirmed,
      UsbiExecutionGuardCode.userConfirmationMissing,
      request.userConfirmed
          ? 'User confirmation present.'
          : 'User confirmation required before USBi write can proceed.',
    ));

    // D7 — Backend availability
    final backendOk = backend.isAvailable;
    guards.add(_guard(
      backendOk,
      UsbiExecutionGuardCode.writeBackendDisabled,
      backendOk
          ? 'USBi native write backend is available.'
          : 'USBi native write backend pending. '
            'Execution blocked until native backend is implemented. '
            'This executor is a controlled placeholder for Phase T4A.',
    ));

    // Check all guards
    final allPassed = guards.every((g) => g.passed);

    if (!allPassed) {
      final failedCode = guards.firstWhere((g) => !g.passed).code;
      final failedMsg  = guards.firstWhere((g) => !g.passed).message;

      // Determine status
      final status = switch (failedCode) {
        UsbiExecutionGuardCode.platformNotWindows        =>
            UsbiExecutionStatus.unsupportedPlatform,
        UsbiExecutionGuardCode.transportNotUsbiTemporary ||
        UsbiExecutionGuardCode.transportNotConnected     =>
            UsbiExecutionStatus.transportUnavailable,
        UsbiExecutionGuardCode.userConfirmationMissing   =>
            UsbiExecutionStatus.awaitingUserConfirmation,
        _ => UsbiExecutionStatus.blocked,
      };

      return UsbiExecutionResult(
        id:            resultId,
        requestId:     request.id,
        status:        status,
        wasActualWrite: false, // never true on guard failure
        ackReceived:    false,
        error:         failedMsg,
        guardResults:  guards,
        executedAt:    now,
        notes:         'Guard "${failedCode.label}" failed. '
                       'No USBi packet sent.',
      );
    }

    // All guards passed — build packets
    List<int> setupPacket;
    List<int> bodyPacket;
    try {
      setupPacket = buildParameterWriteSetup();
      bodyPacket  = buildParameterWriteBody(
        addressInt:    request.addressInt,
        fixedPointInt: request.fixedPointInt,
      );
    } catch (e) {
      guards.add(_guard(
        false,
        UsbiExecutionGuardCode.packetBuildFailed,
        'Packet build failed: $e',
      ));
      return UsbiExecutionResult(
        id:            resultId,
        requestId:     request.id,
        status:        UsbiExecutionStatus.failed,
        wasActualWrite: false,
        ackReceived:    false,
        error:         'Packet build failed: $e',
        guardResults:  guards,
        executedAt:    now,
      );
    }

    // Send packets and read ACK
    List<int>? ackPayload;
    try {
      ackPayload = await backend.sendPacketsAndReadAck(
        setupPacket:   setupPacket,
        bodyPacket:    bodyPacket,
        ackReadRequest: buildAckReadRequest(),
      );
    } catch (e) {
      return UsbiExecutionResult(
        id:            resultId,
        requestId:     request.id,
        status:        UsbiExecutionStatus.failed,
        wasActualWrite: false,
        ackReceived:    false,
        error:         'Native backend threw: $e',
        guardResults:  guards,
        executedAt:    now,
      );
    }

    if (ackPayload == null) {
      return UsbiExecutionResult(
        id:            resultId,
        requestId:     request.id,
        status:        UsbiExecutionStatus.failed,
        wasActualWrite: false,
        ackReceived:    false,
        error:         'No ACK payload returned. Transport error.',
        guardResults:  guards,
        executedAt:    now,
      );
    }

    final ackOk = isAckSuccess(ackPayload);
    final ackHex = bytesToHex(ackPayload);

    if (!ackOk) {
      guards.add(_guard(
        false,
        UsbiExecutionGuardCode.ackFailed,
        'ACK payload [$ackHex] does not contain expected 0x01 at byte 6.',
      ));
      return UsbiExecutionResult(
        id:            resultId,
        requestId:     request.id,
        status:        UsbiExecutionStatus.ackFailed,
        wasActualWrite: true, // write was sent; ACK was unexpected
        ackReceived:    false,
        ackByteHex:    ackHex,
        error:         'ACK failed. Expected 0x01 at byte 6. Got: [$ackHex].',
        guardResults:  guards,
        executedAt:    now,
        notes:         'Packet was sent. ACK failed. '
                       'Verify DSP state manually.',
      );
    }

    // Success
    return UsbiExecutionResult(
      id:            resultId,
      requestId:     request.id,
      status:        UsbiExecutionStatus.ackReceived,
      wasActualWrite: true, // confirmed — native write call succeeded
      ackReceived:    true,
      ackByteHex:    ackHex,
      guardResults:  guards,
      executedAt:    now,
      notes:         'USBi write confirmed. ACK 0x01 received. '
                     'Volatile write only — no EEPROM, no Selfboot.',
    );
  }

  // ── eligibility check ───────────────────────────────────────────────────────

  /// Returns true if the given [envelope] passes all static eligibility checks
  /// (address scope, status, value), WITHOUT requiring user confirmation.
  /// Used by UI to show/hide the executor section.
  bool isEnvelopeEligible(TransportCommandEnvelope envelope) =>
      envelope.isMasterVolumeCommand &&
      envelope.status == TransportCommandStatus.dryRunReady &&
      (envelope.valueFloat ?? -1.0) >= 0.0 &&
      (envelope.valueFloat ?? 2.0) <= 1.0;

  /// Builds a [UsbiExecutionRequest] from an eligible [envelope].
  UsbiExecutionRequest buildRequest({
    required TransportCommandEnvelope envelope,
    required bool userConfirmed,
  }) =>
      UsbiExecutionRequest(
        id:                _newId('req'),
        commandEnvelopeId: envelope.id,
        transportBackend:  envelope.transportBackend,
        parameterId:       envelope.parameterId,
        logicalName:       envelope.logicalName,
        addressHex:        envelope.addressHex,
        addressInt:        envelope.addressInt,
        fixedPointHex:     envelope.fixedPointHex ?? '0x00000000',
        fixedPointInt:     envelope.fixedPointInt ?? 0,
        valueFloat:        envelope.valueFloat ?? 0.0,
        userConfirmed:     userConfirmed,
      );
}
