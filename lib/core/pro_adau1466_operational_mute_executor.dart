import 'pro_adau1466_mute_channel_registry.dart';
import 'pro_usbi_native_backend.dart';
import 'pro_usbi_packet_builder.dart';

class ProAdau1466OperationalMuteExecutor {
  final ProUsbiNativeBackend backend;
  final bool Function() isWindowsPlatform;
  const ProAdau1466OperationalMuteExecutor(
      {required this.backend, required this.isWindowsPlatform});
  bool get isRealExecutorAvailable =>
      isWindowsPlatform() && backend.isAvailable && !backend.isFake;

  Future<OperationalMuteResult> writeWithRollback({
    required Adau1466MappedMuteChannel channel,
    required int requestedState,
    required int previousConfirmedState,
    required bool deviceOpen,
  }) async {
    if (!_isAllowed(channel, requestedState, deviceOpen) ||
        (previousConfirmedState != 0 && previousConfirmedState != 1)) {
      return const OperationalMuteResult(blocked: true);
    }
    final ack = await _write(channel, requestedState);
    if (ack) {
      return OperationalMuteResult(
          success: true, confirmedState: requestedState);
    }
    final restoreAck = await _write(channel, previousConfirmedState);
    return OperationalMuteResult(
        confirmedState: previousConfirmedState, restoreFailed: !restoreAck);
  }

  Future<OperationalMuteResult> restoreOnce({
    required Adau1466MappedMuteChannel channel,
    required int confirmedState,
    required bool deviceOpen,
  }) async {
    if (!_isAllowed(channel, confirmedState, deviceOpen)) {
      return const OperationalMuteResult(blocked: true);
    }
    final ack = await _write(channel, confirmedState);
    return OperationalMuteResult(
        success: ack, confirmedState: ack ? confirmedState : null);
  }

  bool _isAllowed(Adau1466MappedMuteChannel channel, int state,
          bool deviceOpen) =>
      isRealExecutorAvailable &&
      deviceOpen &&
      ProAdau1466MuteChannelRegistry.channels.contains(channel) &&
      (state == 0 || state == 1);

  Future<bool> _write(Adau1466MappedMuteChannel channel, int state) async {
    try {
      final ack = await backend.sendPacketsAndReadAck(
          setupPacket: buildParameterWriteSetup(),
          bodyPacket: buildParameterWriteBody(
              addressInt: channel.address, fixedPointInt: state),
          ackReadRequest: buildAckReadRequest());
      return ack != null && ack.length == 1 && ack.single == 0x01;
    } catch (_) {
      return false;
    }
  }
}

class OperationalMuteResult {
  final bool blocked;
  final bool success;
  final int? confirmedState;
  final bool restoreFailed;
  const OperationalMuteResult(
      {this.blocked = false,
      this.success = false,
      this.confirmedState,
      this.restoreFailed = false});
  String get ackStatus => blocked
      ? 'BLOCKED'
      : success
          ? 'PASS_ACK'
          : 'FAIL';
}
