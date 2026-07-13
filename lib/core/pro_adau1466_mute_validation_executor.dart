import 'pro_adau1466_sigma_candidate.dart';
import 'pro_usbi_native_backend.dart';
import 'pro_usbi_packet_builder.dart';

/// Evidence-bounded validation path for SigmaStudio cell Mute1_3 only.
///
/// This executor is deliberately separate from the operational Master Volume
/// path. It performs volatile direct parameter writes only; it has no SafeLoad,
/// EEPROM, Selfboot, or general-purpose address path.
class ProAdau1466MuteValidationExecutor {
  static const int mute1_3Address = 0x060E;
  static const int testUncheckedValue = 0x00000000;
  static const int restoreCheckedValue = 0x00000001;
  static const Set<int> writeEnabledAddresses = {mute1_3Address};

  final ProUsbiNativeBackend backend;
  final bool Function() isWindowsPlatform;

  const ProAdau1466MuteValidationExecutor({
    required this.backend,
    required this.isWindowsPlatform,
  });

  bool get isRealExecutorAvailable =>
      isWindowsPlatform() && backend.isAvailable && !backend.isFake;

  Future<Adau1466MuteValidationResult> runSmokeTest({
    required int addressInt,
    required bool deviceOpen,
  }) async {
    final testBody = buildParameterWriteBody(
      addressInt: addressInt,
      fixedPointInt: testUncheckedValue,
    );
    final restoreBody = buildParameterWriteBody(
      addressInt: addressInt,
      fixedPointInt: restoreCheckedValue,
    );

    Adau1466MuteValidationResult blocked(String error) =>
        Adau1466MuteValidationResult(
          addressInt: addressInt,
          testBodyHex: bytesToHex(testBody),
          restoreBodyHex: bytesToHex(restoreBody),
          error: error,
          resultStatus: CandidateValidationStatus.blocked,
        );

    if (!isWindowsPlatform()) return blocked('Platform is not Windows.');
    if (!deviceOpen) return blocked('USBi device is not open.');
    if (!backend.isAvailable) return blocked('USBi backend is unavailable.');
    if (backend.isFake) {
      return blocked('Mute validation requires a real executor.');
    }
    if (!writeEnabledAddresses.contains(addressInt)) {
      return blocked(
          'Only Mute1_3 at 0x060E is enabled. All other addresses remain blocked.');
    }

    final setup = buildParameterWriteSetup();
    final ackRequest = buildAckReadRequest();
    bool testWasActualWrite = false;
    bool restoreWasActualWrite = false;
    bool testAckOk = false;
    bool restoreAckOk = false;
    String? testAckBytes;
    String? restoreAckBytes;
    String? testError;
    String? restoreError;

    try {
      testWasActualWrite = true;
      final ack = await backend.sendPacketsAndReadAck(
        setupPacket: setup,
        bodyPacket: testBody,
        ackReadRequest: ackRequest,
      );
      if (ack != null) {
        testAckBytes = bytesToHex(ack);
        testAckOk = isAckSuccess(ack);
      }
      if (!testAckOk) testError = 'Test write did not return ACK 0x01.';
    } catch (e) {
      testError = 'Test write failed: $e';
    }

    // Restore is intentionally independent of test ACK/exception outcome.
    // Once the guarded test phase starts, always attempt the captured baseline.
    try {
      restoreWasActualWrite = true;
      final ack = await backend.sendPacketsAndReadAck(
        setupPacket: setup,
        bodyPacket: restoreBody,
        ackReadRequest: ackRequest,
      );
      if (ack != null) {
        restoreAckBytes = bytesToHex(ack);
        restoreAckOk = isAckSuccess(ack);
      }
      if (!restoreAckOk) {
        restoreError = 'RESTORE FAILURE: baseline 1 did not return ACK 0x01.';
      }
    } catch (e) {
      restoreError = 'RESTORE FAILURE: baseline write failed: $e';
    }

    final errorParts = [testError, restoreError].whereType<String>().toList();
    return Adau1466MuteValidationResult(
      addressInt: addressInt,
      testWasActualWrite: testWasActualWrite,
      restoreWasActualWrite: restoreWasActualWrite,
      testAckOk: testAckOk,
      restoreAckOk: restoreAckOk,
      testBodyHex: bytesToHex(testBody),
      restoreBodyHex: bytesToHex(restoreBody),
      testAckBytes: testAckBytes,
      restoreAckBytes: restoreAckBytes,
      error: errorParts.isEmpty ? null : errorParts.join(' '),
      resultStatus: testAckOk && restoreAckOk
          ? CandidateValidationStatus.passAck
          : CandidateValidationStatus.fail,
    );
  }
}

class Adau1466MuteValidationResult {
  final int addressInt;
  final bool testWasActualWrite;
  final bool restoreWasActualWrite;
  final bool testAckOk;
  final bool restoreAckOk;
  final String testBodyHex;
  final String restoreBodyHex;
  final String? testAckBytes;
  final String? restoreAckBytes;
  final String? error;
  final CandidateValidationStatus resultStatus;

  const Adau1466MuteValidationResult({
    required this.addressInt,
    this.testWasActualWrite = false,
    this.restoreWasActualWrite = false,
    this.testAckOk = false,
    this.restoreAckOk = false,
    required this.testBodyHex,
    required this.restoreBodyHex,
    this.testAckBytes,
    this.restoreAckBytes,
    this.error,
    required this.resultStatus,
  });

  bool get wasActualWrite => testWasActualWrite || restoreWasActualWrite;
  bool get restoreFailed => restoreWasActualWrite && !restoreAckOk;
}
