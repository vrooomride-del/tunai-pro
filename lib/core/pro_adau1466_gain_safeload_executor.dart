import 'pro_adau1466_sigma_candidate.dart';
import 'pro_adau1466_gain_channel_registry.dart';
import 'pro_usbi_native_backend.dart';
import 'pro_usbi_packet_builder.dart';

/// Capture-locked, one-shot diagnostic for the six mapped ADAU1466 HWGain cells.
///
/// This is intentionally not a general SafeLoad implementation. It accepts
/// a registry channel, and emits only its locked test/restore packet bodies.
/// It has no EEPROM, Selfboot, arbitrary-address/value,
/// or legacy transport entry point.
class ProAdau1466GainSafeLoadExecutor {
  static const int targetAddress = 0x03B8;
  static const int slewAddress = 0x03B9;
  static const int slewValue = 0x0000208A;
  static const int testGainValue = 0x00000840;
  static const int restoreGainValue = 0x0000068E;
  static const Set<int> writeEnabledTargets = {
    0x03B8,
    0x03C4,
    0x03C7,
    0x03BB,
    0x03CA,
    0x03CD,
  };

  final ProUsbiNativeBackend backend;
  final bool Function() isWindowsPlatform;

  const ProAdau1466GainSafeLoadExecutor({
    required this.backend,
    required this.isWindowsPlatform,
  });

  bool get isRealExecutorAvailable =>
      isWindowsPlatform() && backend.isAvailable && !backend.isFake;

  static List<Adau1466GainSafeLoadStage> testStages(
          Adau1466MappedGainChannel channel) =>
      _stagesFor(channel: channel, restore: false, phase: 'TEST');

  static List<Adau1466GainSafeLoadStage> restoreStages(
          Adau1466MappedGainChannel channel) =>
      _stagesFor(channel: channel, restore: true, phase: 'RESTORE');

  static List<Adau1466GainSafeLoadStage> _stagesFor({
    required Adau1466MappedGainChannel channel,
    required bool restore,
    required String phase,
  }) {
    final plan = restore
        ? ProAdau1466GainChannelRegistry.buildRestorePlan(channel)
        : ProAdau1466GainChannelRegistry.buildTestPlan(channel);
    return List.generate(plan.stages.length, (index) {
      final stage = plan.stages[index];
      return Adau1466GainSafeLoadStage(
        label: '$phase stage ${index + 1}',
        setupPacket: stage.setupPacket,
        bodyPacket: stage.bodyPacket,
      );
    });
  }

  Future<Adau1466GainSafeLoadResult> runDiagnostic({
    required Adau1466MappedGainChannel channel,
    required bool deviceOpen,
  }) async {
    Adau1466GainSafeLoadResult blocked(String error) =>
        Adau1466GainSafeLoadResult(
          requestedTargetAddress: channel.targetAddress,
          error: error,
          resultStatus: CandidateValidationStatus.blocked,
        );

    if (!isWindowsPlatform()) return blocked('Platform is not Windows.');
    if (!deviceOpen) return blocked('USBi device is not open.');
    if (!backend.isAvailable) return blocked('USBi backend is unavailable.');
    if (backend.isFake) {
      return blocked('Gain diagnostic requires a real executor.');
    }
    if (!ProAdau1466GainChannelRegistry.channels.contains(channel) ||
        !writeEnabledTargets.contains(channel.targetAddress)) {
      return blocked('Only the six fixed mapped Gain channels are enabled.');
    }

    final testResults = <Adau1466GainSafeLoadStageResult>[];
    final restoreResults = <Adau1466GainSafeLoadStageResult>[];
    for (final stage in testStages(channel)) {
      testResults.add(await _executeStage(stage));
    }
    // Restore is unconditional once execution starts. Every restore stage is
    // attempted independently, even if any test or earlier restore stage fails.
    for (final stage in restoreStages(channel)) {
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
      requestedTargetAddress: channel.targetAddress,
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
