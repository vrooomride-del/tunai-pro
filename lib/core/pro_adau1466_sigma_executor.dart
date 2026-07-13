// ── TUNAI PRO — ADAU1466 Sigma Verification Executor ─────────────────────────
// Controlled write+restore path for hardware address verification.
// Uses the same packet builder and backend as the confirmed MV executor.
//
// ABSOLUTE RESTRICTIONS:
//   - No EEPROM. No Selfboot. No WriteAll. No SafeLoad (until validated).
//   - testWasActualWrite = true ONLY when backend.sendPacketsAndReadAck() was called.
//   - G1: Windows only. G2: user confirmed. G3: restore value confirmed.
//   - G4: backend available. G5: address < 0x8000 or safeload area.
//   - USBi is TEMPORARY. ICP5 is the final target.
//   - AI suggests. Expert verifies. AOS protects. DSP executes.

import 'pro_usbi_native_backend.dart';
import 'pro_usbi_packet_builder.dart';
import 'pro_adau1466_sigma_candidate.dart';

// ── Request / Result models ───────────────────────────────────────────────────

class SigmaVerificationWriteRequest {
  final String id;
  final int addressInt;
  final String addressHex;
  final String label;
  final int testValue32;
  final int restoreValue32;
  final bool userConfirmed;
  final bool restoreValueConfirmed;

  const SigmaVerificationWriteRequest({
    required this.id,
    required this.addressInt,
    required this.addressHex,
    required this.label,
    required this.testValue32,
    required this.restoreValue32,
    required this.userConfirmed,
    required this.restoreValueConfirmed,
  });
}

class SigmaVerificationWriteResult {
  final String id;
  final bool testWasActualWrite;
  final bool restoreWasActualWrite;
  final bool testAckOk;
  final bool restoreAckOk;
  final String testBodyHex;
  final String restoreBodyHex;
  final String? testAckBytes;
  final String? restoreAckBytes;
  final String? error;
  final String backendName;
  final CandidateValidationStatus resultStatus;
  final DateTime executedAt;

  const SigmaVerificationWriteResult({
    required this.id,
    required this.testWasActualWrite,
    required this.restoreWasActualWrite,
    required this.testAckOk,
    required this.restoreAckOk,
    required this.testBodyHex,
    required this.restoreBodyHex,
    this.testAckBytes,
    this.restoreAckBytes,
    this.error,
    required this.backendName,
    required this.resultStatus,
    required this.executedAt,
  });
}

// ── Executor ──────────────────────────────────────────────────────────────────

class ProUsbiSigmaVerificationExecutor {
  static const Set<int> writeEnabledAddresses = {0x0067, 0x0064};

  final ProUsbiNativeBackend backend;
  final bool Function() isWindowsPlatform;

  const ProUsbiSigmaVerificationExecutor({
    required this.backend,
    required this.isWindowsPlatform,
  });

  /// Writes [req.testValue32] then restores [req.restoreValue32].
  /// Guards are checked before any I/O.
  Future<SigmaVerificationWriteResult> writeWithRestore(
      SigmaVerificationWriteRequest req) async {
    final now = DateTime.now();
    final backendName = backend.runtimeType.toString();

    // Pre-compute body packets for logging (always done, even if blocked)
    final testBody = buildParameterWriteBody(
      addressInt:    req.addressInt,
      fixedPointInt: req.testValue32,
    );
    final restoreBody = buildParameterWriteBody(
      addressInt:    req.addressInt,
      fixedPointInt: req.restoreValue32,
    );
    final testBodyHex    = bytesToHex(testBody);
    final restoreBodyHex = bytesToHex(restoreBody);

    // G1: Windows only
    if (!isWindowsPlatform()) {
      return SigmaVerificationWriteResult(
        id:                   req.id,
        testWasActualWrite:   false,
        restoreWasActualWrite: false,
        testAckOk:            false,
        restoreAckOk:         false,
        testBodyHex:          testBodyHex,
        restoreBodyHex:       restoreBodyHex,
        error:                'G1: Platform is not Windows. Write blocked.',
        backendName:          backendName,
        resultStatus:         CandidateValidationStatus.blocked,
        executedAt:           now,
      );
    }

    // G2: User confirmed
    if (!req.userConfirmed) {
      return SigmaVerificationWriteResult(
        id:                   req.id,
        testWasActualWrite:   false,
        restoreWasActualWrite: false,
        testAckOk:            false,
        restoreAckOk:         false,
        testBodyHex:          testBodyHex,
        restoreBodyHex:       restoreBodyHex,
        error:                'G2: User confirmation missing.',
        backendName:          backendName,
        resultStatus:         CandidateValidationStatus.blocked,
        executedAt:           now,
      );
    }

    // G3: Restore value confirmed
    if (!req.restoreValueConfirmed) {
      return SigmaVerificationWriteResult(
        id:                   req.id,
        testWasActualWrite:   false,
        restoreWasActualWrite: false,
        testAckOk:            false,
        restoreAckOk:         false,
        testBodyHex:          testBodyHex,
        restoreBodyHex:       restoreBodyHex,
        error:                'G3: Restore value not confirmed.',
        backendName:          backendName,
        resultStatus:         CandidateValidationStatus.blocked,
        executedAt:           now,
      );
    }

    // G4: Backend available
    if (!backend.isAvailable) {
      return SigmaVerificationWriteResult(
        id:                   req.id,
        testWasActualWrite:   false,
        restoreWasActualWrite: false,
        testAckOk:            false,
        restoreAckOk:         false,
        testBodyHex:          testBodyHex,
        restoreBodyHex:       restoreBodyHex,
        error:                'G4: Backend not available (USBi not connected or not Windows).',
        backendName:          backendName,
        resultStatus:         CandidateValidationStatus.blocked,
        executedAt:           now,
      );
    }

    // The temporary engineering executor is an explicit allowlist, not a
    // general Sigma parameter writer. Classification or an ACK cannot widen it.
    if (!writeEnabledAddresses.contains(req.addressInt)) {
      return SigmaVerificationWriteResult(
        id:                   req.id,
        testWasActualWrite:   false,
        restoreWasActualWrite: false,
        testAckOk:            false,
        restoreAckOk:         false,
        testBodyHex:          testBodyHex,
        restoreBodyHex:       restoreBodyHex,
        error:                'G5: Address ${req.addressHex} is not in the Master Volume allowlist. Write blocked.',
        backendName:          backendName,
        resultStatus:         CandidateValidationStatus.blocked,
        executedAt:           now,
      );
    }

    // G6: Address safety — block EEPROM/Selfboot region (>= 0x8000, not safeload area)
    final isSafeloadArea = req.addressInt >= 0x6000 && req.addressInt <= 0x6007;
    if (req.addressInt >= 0x8000 && !isSafeloadArea) {
      return SigmaVerificationWriteResult(
        id:                   req.id,
        testWasActualWrite:   false,
        restoreWasActualWrite: false,
        testAckOk:            false,
        restoreAckOk:         false,
        testBodyHex:          testBodyHex,
        restoreBodyHex:       restoreBodyHex,
        error:                'G5: Address 0x${req.addressInt.toRadixString(16).toUpperCase()} '
                              'is in forbidden region (>= 0x8000). Write blocked.',
        backendName:          backendName,
        resultStatus:         CandidateValidationStatus.blocked,
        executedAt:           now,
      );
    }

    // All guards passed — perform writes
    final setup      = buildParameterWriteSetup();
    final ackRequest = buildAckReadRequest();

    // Test write
    bool testWasActualWrite   = false;
    bool restoreWasActualWrite = false;
    bool testAckOk   = false;
    bool restoreAckOk = false;
    String? testAckBytesStr;
    String? restoreAckBytesStr;
    String? error;

    try {
      final testAck = await backend.sendPacketsAndReadAck(
        setupPacket:    setup,
        bodyPacket:     testBody,
        ackReadRequest: ackRequest,
      );
      testWasActualWrite = true;
      if (testAck != null) {
        testAckBytesStr = bytesToHex(testAck);
        testAckOk = isAckSuccess(testAck);
      }

      // Restore write (always attempt even if test ACK failed)
      final restoreAck = await backend.sendPacketsAndReadAck(
        setupPacket:    setup,
        bodyPacket:     restoreBody,
        ackReadRequest: ackRequest,
      );
      restoreWasActualWrite = true;
      if (restoreAck != null) {
        restoreAckBytesStr = bytesToHex(restoreAck);
        restoreAckOk = isAckSuccess(restoreAck);
      }
    } catch (e) {
      error = 'Write exception: $e';
    }

    // Determine result status
    final CandidateValidationStatus resultStatus;
    if (error != null) {
      resultStatus = CandidateValidationStatus.fail;
    } else if (testWasActualWrite && testAckOk) {
      resultStatus = CandidateValidationStatus.passAck;
    } else if (testWasActualWrite && !testAckOk) {
      resultStatus = CandidateValidationStatus.fail;
    } else {
      resultStatus = CandidateValidationStatus.blocked;
    }

    return SigmaVerificationWriteResult(
      id:                   req.id,
      testWasActualWrite:   testWasActualWrite,
      restoreWasActualWrite: restoreWasActualWrite,
      testAckOk:            testAckOk,
      restoreAckOk:         restoreAckOk,
      testBodyHex:          testBodyHex,
      restoreBodyHex:       restoreBodyHex,
      testAckBytes:         testAckBytesStr,
      restoreAckBytes:      restoreAckBytesStr,
      error:                error,
      backendName:          backendName,
      resultStatus:         resultStatus,
      executedAt:           now,
    );
  }
}
