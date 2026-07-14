import 'pro_adau1466_delay_audit_registry.dart';
import 'pro_usbi_native_backend.dart';
import 'pro_usbi_packet_builder.dart';

class ProAdau1466OperationalDelayExecutor {
  final ProUsbiNativeBackend backend;
  final bool Function() isWindowsPlatform;
  const ProAdau1466OperationalDelayExecutor(
      {required this.backend, required this.isWindowsPlatform});

  bool get isRealExecutorAvailable =>
      isWindowsPlatform() && backend.isAvailable && !backend.isFake;

  Future<OperationalDelayWriteResult> writeOnce({
    required Adau1466MappedDelayAudit channel,
    required num samples,
    required bool deviceOpen,
  }) async {
    if (!isRealExecutorAvailable ||
        !deviceOpen ||
        !identical(
            ProAdau1466DelayAuditRegistry.find(channel.channel), channel) ||
        !ProAdau1466DelayAuditRegistry.acceptsWrite(channel.address, samples)) {
      return const OperationalDelayWriteResult(blocked: true);
    }
    try {
      final rawAck = await backend.sendPacketsAndReadAck(
        setupPacket: buildParameterWriteSetup(),
        bodyPacket: buildParameterWriteBody(
            addressInt: channel.address, fixedPointInt: samples.toInt()),
        ackReadRequest: buildAckReadRequest(),
      );
      final success =
          rawAck != null && rawAck.length == 1 && rawAck.single == 1;
      return OperationalDelayWriteResult(
          success: success, confirmedSamples: success ? samples.toInt() : null);
    } catch (_) {
      return const OperationalDelayWriteResult();
    }
  }
}

class OperationalDelayWriteResult {
  final bool blocked;
  final bool success;
  final int? confirmedSamples;
  const OperationalDelayWriteResult(
      {this.blocked = false, this.success = false, this.confirmedSamples});
  String get ackStatus => blocked
      ? 'BLOCKED'
      : success
          ? 'PASS_ACK'
          : 'FAIL';
}
