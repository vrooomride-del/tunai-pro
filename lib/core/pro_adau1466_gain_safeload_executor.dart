import 'pro_adau1466_sigma_candidate.dart';
import 'pro_usbi_native_backend.dart';
import 'pro_usbi_packet_builder.dart';

/// Capture-locked, one-shot diagnostic for ADAU1466 Sigma cell Single 1.
///
/// This is intentionally not a general SafeLoad implementation. It accepts
/// one target and one test/restore pair, and emits only the six packet bodies
/// captured from SigmaStudio. It has no EEPROM, Selfboot, arbitrary-address,
/// or legacy transport entry point.
class ProAdau1466GainSafeLoadExecutor {
  static const int targetAddress = 0x03B8;
  static const int slewAddress = 0x03B9;
  static const int slewValue = 0x0000208A;
  static const int testGainValue = 0x00000840;
  static const int restoreGainValue = 0x0000068E;
  static const Set<int> writeEnabledTargets = {targetAddress};

  static const List<int> _slewBody = [0x03, 0xB9, 0x00, 0x00, 0x20, 0x8A];
  static const List<int> _testDataBody = [0x60, 0x00, 0x00, 0x00, 0x08, 0x40];
  static const List<int> _restoreDataBody = [
    0x60,
    0x00,
    0x00,
    0x00,
    0x06,
    0x8E
  ];
  static const List<int> _targetCountBody = [
    0x60,
    0x05,
    0x00,
    0x00,
    0x03,
    0xB8,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x00,
  ];

  final ProUsbiNativeBackend backend;
  final bool Function() isWindowsPlatform;

  const ProAdau1466GainSafeLoadExecutor({
    required this.backend,
    required this.isWindowsPlatform,
  });

  bool get isRealExecutorAvailable =>
      isWindowsPlatform() && backend.isAvailable && !backend.isFake;

  static List<Adau1466GainSafeLoadStage> testStages() => [
        const Adau1466GainSafeLoadStage(
          label: 'TEST stage 1',
          setupPacket: [0x40, 0xB2, 0x00, 0x00, 0x01, 0x01, 0x06, 0x00],
          bodyPacket: _slewBody,
        ),
        const Adau1466GainSafeLoadStage(
          label: 'TEST stage 2',
          setupPacket: [0x40, 0xB2, 0x00, 0x00, 0x01, 0x01, 0x06, 0x00],
          bodyPacket: _testDataBody,
        ),
        const Adau1466GainSafeLoadStage(
          label: 'TEST stage 3',
          setupPacket: [0x40, 0xB2, 0x00, 0x00, 0x01, 0x01, 0x0E, 0x00],
          bodyPacket: _targetCountBody,
        ),
      ];

  static List<Adau1466GainSafeLoadStage> restoreStages() => [
        const Adau1466GainSafeLoadStage(
          label: 'RESTORE stage 1',
          setupPacket: [0x40, 0xB2, 0x00, 0x00, 0x01, 0x01, 0x06, 0x00],
          bodyPacket: _slewBody,
        ),
        const Adau1466GainSafeLoadStage(
          label: 'RESTORE stage 2',
          setupPacket: [0x40, 0xB2, 0x00, 0x00, 0x01, 0x01, 0x06, 0x00],
          bodyPacket: _restoreDataBody,
        ),
        const Adau1466GainSafeLoadStage(
          label: 'RESTORE stage 3',
          setupPacket: [0x40, 0xB2, 0x00, 0x00, 0x01, 0x01, 0x0E, 0x00],
          bodyPacket: _targetCountBody,
        ),
      ];

  Future<Adau1466GainSafeLoadResult> runDiagnostic({
    required int requestedTargetAddress,
    required int requestedTestValue,
    required int requestedRestoreValue,
    required bool deviceOpen,
  }) async {
    Adau1466GainSafeLoadResult blocked(String error) =>
        Adau1466GainSafeLoadResult(
          requestedTargetAddress: requestedTargetAddress,
          error: error,
          resultStatus: CandidateValidationStatus.blocked,
        );

    if (!isWindowsPlatform()) return blocked('Platform is not Windows.');
    if (!deviceOpen) return blocked('USBi device is not open.');
    if (!backend.isAvailable) return blocked('USBi backend is unavailable.');
    if (backend.isFake) {
      return blocked('Gain diagnostic requires a real executor.');
    }
    if (!writeEnabledTargets.contains(requestedTargetAddress)) {
      return blocked('Only Gain Single 1 target 0x03B8 is enabled.');
    }
    if (requestedTestValue != testGainValue ||
        requestedRestoreValue != restoreGainValue) {
      return blocked(
          'Only test 0x00000840 and restore 0x0000068E are enabled.');
    }

    final testResults = <Adau1466GainSafeLoadStageResult>[];
    final restoreResults = <Adau1466GainSafeLoadStageResult>[];
    for (final stage in testStages()) {
      testResults.add(await _executeStage(stage));
    }
    // Restore is unconditional once execution starts. Every restore stage is
    // attempted independently, even if any test or earlier restore stage fails.
    for (final stage in restoreStages()) {
      restoreResults.add(await _executeStage(stage));
    }

    final allTestAck = testResults.every((stage) => stage.ackOk);
    final allRestoreAck =
        restoreResults.every((stage) => stage.rawAckIsExactly01);
    final failures = [...testResults, ...restoreResults]
        .where((stage) => !stage.ackOk)
        .map((stage) =>
            '${stage.stage.label}: ${stage.error ?? "raw ACK was not 01"}')
        .join(' ');
    return Adau1466GainSafeLoadResult(
      requestedTargetAddress: requestedTargetAddress,
      testStages: testResults,
      restoreStages: restoreResults,
      error: failures.isEmpty ? null : failures,
      resultStatus: allTestAck && allRestoreAck
          ? CandidateValidationStatus.passAck
          : CandidateValidationStatus.fail,
    );
  }

  Future<Adau1466GainSafeLoadStageResult> _executeStage(
      Adau1466GainSafeLoadStage stage) async {
    UsbiNativeTransactionDiagnostics? diagnostics;
    try {
      final ack = await backend.sendPacketsAndReadAck(
        setupPacket: List<int>.from(stage.setupPacket),
        bodyPacket: List<int>.from(stage.bodyPacket),
        ackReadRequest: buildAckReadRequest(),
      );
      diagnostics = _captureDiagnostics();
      final exactAck = ack != null && ack.length == 1 && ack.single == 0x01;
      return Adau1466GainSafeLoadStageResult(
        stage: stage,
        wasActualWrite: true,
        ackBytes: ack == null ? null : List<int>.from(ack),
        ackOk: exactAck,
        diagnostics: diagnostics,
        error: exactAck ? null : 'Stage did not return raw ACK 01.',
      );
    } catch (error) {
      diagnostics = _captureDiagnostics();
      return Adau1466GainSafeLoadStageResult(
        stage: stage,
        wasActualWrite: true,
        ackOk: false,
        diagnostics: diagnostics,
        error: 'Native write failed: $error',
      );
    }
  }

  UsbiNativeTransactionDiagnostics? _captureDiagnostics() {
    final currentBackend = backend;
    return currentBackend is ProUsbiTransactionDiagnosticsProvider
        ? (currentBackend as ProUsbiTransactionDiagnosticsProvider)
            .lastTransactionDiagnostics
        : null;
  }
}

class Adau1466GainSafeLoadStage {
  final String label;
  final List<int> setupPacket;
  final List<int> bodyPacket;

  const Adau1466GainSafeLoadStage({
    required this.label,
    required this.setupPacket,
    required this.bodyPacket,
  });
}

class Adau1466GainSafeLoadStageResult {
  final Adau1466GainSafeLoadStage stage;
  final bool wasActualWrite;
  final List<int>? ackBytes;
  final bool ackOk;
  final UsbiNativeTransactionDiagnostics? diagnostics;
  final String? error;

  const Adau1466GainSafeLoadStageResult({
    required this.stage,
    required this.wasActualWrite,
    this.ackBytes,
    required this.ackOk,
    this.diagnostics,
    this.error,
  });

  bool get rawAckIsExactly01 =>
      ackBytes != null && ackBytes!.length == 1 && ackBytes!.single == 0x01;
}

class Adau1466GainSafeLoadResult {
  final int requestedTargetAddress;
  final List<Adau1466GainSafeLoadStageResult> testStages;
  final List<Adau1466GainSafeLoadStageResult> restoreStages;
  final String? error;
  final CandidateValidationStatus resultStatus;

  const Adau1466GainSafeLoadResult({
    required this.requestedTargetAddress,
    this.testStages = const [],
    this.restoreStages = const [],
    this.error,
    required this.resultStatus,
  });

  bool get wasActualWrite =>
      [...testStages, ...restoreStages].any((stage) => stage.wasActualWrite);
  bool get allTestStagesPassAck =>
      testStages.length == 3 && testStages.every((stage) => stage.ackOk);
  bool get allRestoreStagesReturnedRawAck01 =>
      restoreStages.length == 3 &&
      restoreStages.every((stage) => stage.rawAckIsExactly01);
  bool get restoreFailed => !allRestoreStagesReturnedRawAck01;
}
