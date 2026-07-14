import 'pro_adau1466_gain_channel_registry.dart';
import 'pro_usbi_native_backend.dart';
import 'pro_usbi_packet_builder.dart';

class ProAdau1466OperationalGainExecutor {
  final ProUsbiNativeBackend backend;
  final bool Function() isWindowsPlatform;

  const ProAdau1466OperationalGainExecutor({
    required this.backend,
    required this.isWindowsPlatform,
  });

  bool get isRealExecutorAvailable =>
      isWindowsPlatform() && backend.isAvailable && !backend.isFake;

  Future<OperationalGainWriteResult> writeWithRollback({
    required Adau1466MappedGainChannel channel,
    required int requestedWord,
    required int previousConfirmedWord,
    required bool deviceOpen,
  }) async {
    if (!isRealExecutorAvailable ||
        !deviceOpen ||
        !ProAdau1466GainChannelRegistry.channels.contains(channel)) {
      return const OperationalGainWriteResult(blocked: true);
    }
    final write = await _runPlan(
        ProAdau1466GainChannelRegistry.buildOperationalPlan(
            channel, requestedWord));
    if (write.success) {
      return OperationalGainWriteResult(
          writeStages: write.stages, confirmedWord: requestedWord);
    }
    final restore = await _runPlan(
        ProAdau1466GainChannelRegistry.buildOperationalPlan(
            channel, previousConfirmedWord));
    return OperationalGainWriteResult(
      writeStages: write.stages,
      restoreStages: restore.stages,
      confirmedWord: previousConfirmedWord,
      restoreFailed: !restore.success,
    );
  }

  Future<_PlanResult> _runPlan(Adau1466GainSafeLoadPacketPlan plan) async {
    final results = <bool>[];
    for (final stage in plan.stages) {
      try {
        final ack = await backend.sendPacketsAndReadAck(
          setupPacket: stage.setupPacket,
          bodyPacket: stage.bodyPacket,
          ackReadRequest: buildAckReadRequest(),
        );
        results.add(ack != null && ack.length == 1 && ack.single == 0x01);
      } catch (_) {
        results.add(false);
      }
    }
    return _PlanResult(results);
  }
}

class OperationalGainWriteResult {
  final bool blocked;
  final List<bool> writeStages;
  final List<bool> restoreStages;
  final int? confirmedWord;
  final bool restoreFailed;

  const OperationalGainWriteResult({
    this.blocked = false,
    this.writeStages = const [],
    this.restoreStages = const [],
    this.confirmedWord,
    this.restoreFailed = false,
  });

  bool get success => writeStages.length == 3 && writeStages.every((v) => v);
  String get ackStatus => blocked
      ? 'BLOCKED'
      : success
          ? 'PASS_ACK'
          : 'FAIL';
}

class _PlanResult {
  final List<bool> stages;
  const _PlanResult(this.stages);
  bool get success => stages.length == 3 && stages.every((v) => v);
}
