import 'pro_adau1466_xo_audit_registry.dart';
import 'pro_usbi_native_backend.dart';
import 'pro_usbi_packet_builder.dart';

class ProAdau1466WflLpf2SafeLoadExecutor {
  static const minimumAudioFrameWait = Duration(milliseconds: 1);
  static const slewAddress = 0x01FA;
  static const coefficientStartAddress = 0x618D;
  static const enabledCoefficientAddresses = {
    0x618D,
    0x618E,
    0x618F,
    0x6190,
    0x6191,
  };

  final ProUsbiNativeBackend backend;
  final bool Function() isWindowsPlatform;
  final Future<void> Function(Duration) wait;
  bool _hasTriggered = false;

  ProAdau1466WflLpf2SafeLoadExecutor(
      {required this.backend,
      required this.isWindowsPlatform,
      Future<void> Function(Duration)? wait})
      : wait = wait ?? Future<void>.delayed;

  bool get isRealExecutorAvailable =>
      isWindowsPlatform() && backend.isAvailable && !backend.isFake;

  static List<WflLpf2SafeLoadStage> testStages() =>
      _stages('TEST', ProAdau1466WflLpf2DiagnosticEvidence.testPayload);
  static List<WflLpf2SafeLoadStage> restoreStages() =>
      _stages('RESTORE', ProAdau1466WflLpf2DiagnosticEvidence.baselinePayload);

  static List<WflLpf2SafeLoadStage> _stages(String phase, List<int> payload) {
    final bodies = <List<int>>[
      [0x01, 0xFA, 0x00, 0x00, 0x20, 0x8A],
      [0x60, 0x00, ...payload],
      [
        0x60,
        0x05,
        0x00,
        0x00,
        0x61,
        0x8D,
        0x00,
        0x00,
        0x00,
        0x05,
        0x00,
        0x00,
        0x00,
        0x00,
      ],
    ];
    return List.generate(
        bodies.length,
        (index) => WflLpf2SafeLoadStage(
              label: '$phase stage ${index + 1}',
              setupPacket:
                  buildParameterWriteSetup(bodyLength: bodies[index].length),
              bodyPacket: bodies[index],
            ));
  }

  Future<WflLpf2DiagnosticResult> runTest({required bool deviceOpen}) async {
    final blocked = _guard(deviceOpen);
    if (blocked != null) return blocked;
    final test = await _executeTransaction(testStages());
    if (test.every((stage) => stage.ackOk)) {
      return WflLpf2DiagnosticResult(
          testStages: test, confirmedState: '281 Hz TEST · PASS_ACK');
    }
    final restore = await _executeTransaction(restoreStages());
    return WflLpf2DiagnosticResult(
        testStages: test,
        restoreStages: restore,
        confirmedState: restore.every((stage) => stage.ackOk)
            ? '280 Hz BASELINE · PASS_ACK'
            : 'UNCONFIRMED',
        error: 'TEST failed; complete RESTORE attempted.');
  }

  Future<WflLpf2DiagnosticResult> runRestore({required bool deviceOpen}) async {
    final blocked = _guard(deviceOpen);
    if (blocked != null) return blocked;
    final restore = await _executeTransaction(restoreStages());
    return WflLpf2DiagnosticResult(
        restoreStages: restore,
        confirmedState: restore.every((stage) => stage.ackOk)
            ? '280 Hz BASELINE · PASS_ACK'
            : 'UNCONFIRMED',
        error:
            restore.every((stage) => stage.ackOk) ? null : 'RESTORE failed.');
  }

  WflLpf2DiagnosticResult? _guard(bool deviceOpen) {
    if (!isWindowsPlatform()) {
      return const WflLpf2DiagnosticResult(
          blocked: true, error: 'Platform is not Windows.');
    }
    if (!deviceOpen) {
      return const WflLpf2DiagnosticResult(
          blocked: true, error: 'USBi device is not open.');
    }
    if (!backend.isAvailable || backend.isFake) {
      return const WflLpf2DiagnosticResult(
          blocked: true, error: 'Real USBi executor is unavailable.');
    }
    return null;
  }

  Future<List<WflLpf2SafeLoadStageResult>> _executeTransaction(
      List<WflLpf2SafeLoadStage> stages) async {
    if (_hasTriggered) await wait(minimumAudioFrameWait);
    final results = <WflLpf2SafeLoadStageResult>[];
    for (final stage in stages) {
      try {
        final ack = await backend.sendPacketsAndReadAck(
          setupPacket: List.of(stage.setupPacket),
          bodyPacket: List.of(stage.bodyPacket),
          ackReadRequest: buildAckReadRequest(),
        );
        final ackOk = ack != null && ack.length == 1 && ack.single == 0x01;
        results.add(WflLpf2SafeLoadStageResult(
            stage: stage,
            ackOk: ackOk,
            ackBytes: ack == null ? null : List.of(ack)));
      } catch (error) {
        results.add(WflLpf2SafeLoadStageResult(
            stage: stage, ackOk: false, error: '$error'));
      }
    }
    _hasTriggered = true;
    return results;
  }
}

class WflLpf2SafeLoadStage {
  final String label;
  final List<int> setupPacket;
  final List<int> bodyPacket;
  const WflLpf2SafeLoadStage(
      {required this.label,
      required this.setupPacket,
      required this.bodyPacket});
}

class WflLpf2SafeLoadStageResult {
  final WflLpf2SafeLoadStage stage;
  final bool ackOk;
  final List<int>? ackBytes;
  final String? error;
  const WflLpf2SafeLoadStageResult(
      {required this.stage, required this.ackOk, this.ackBytes, this.error});
  String get status => ackOk ? 'PASS_ACK' : 'FAIL';
}

class WflLpf2DiagnosticResult {
  final bool blocked;
  final List<WflLpf2SafeLoadStageResult> testStages;
  final List<WflLpf2SafeLoadStageResult> restoreStages;
  final String confirmedState;
  final String? error;
  const WflLpf2DiagnosticResult(
      {this.blocked = false,
      this.testStages = const [],
      this.restoreStages = const [],
      this.confirmedState = '280 Hz BASELINE · not written',
      this.error});
  bool get restoreFailed =>
      restoreStages.isNotEmpty && !restoreStages.every((stage) => stage.ackOk);
}
