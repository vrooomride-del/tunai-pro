import '../pro_usbi_native_backend.dart';
import '../pro_usbi_packet_builder.dart';
import '../pro_usbi_windows_native_backend.dart';
import 'dsp_command.dart';
import 'dsp_transport.dart';

/// Phase A adapter for the proven temporary engineering backend. Existing
/// hardware executors remain untouched; this adapter sends the same setup,
/// body, and ACK request bytes through sendPacketsAndReadAck().
class UsbiDspTransport implements DspTransport {
  final ProUsbiNativeBackend backend;
  final bool Function() deviceOpen;

  const UsbiDspTransport({required this.backend, required this.deviceOpen});

  @override
  DspTransportIdentity get identity => DspTransportIdentity.usbi;
  @override
  String get displayName => 'USBi — Windows Temporary Engineering';
  @override
  bool get isAvailable => backend.isAvailable;
  @override
  DspConnectionState get connectionState => !isAvailable
      ? DspConnectionState.unavailable
      : deviceOpen()
          ? DspConnectionState.connected
          : DspConnectionState.disconnected;
  @override
  DspTransportCapabilities get capabilities => const DspTransportCapabilities(
        directParameterWrite: true,
        oneWordSafeLoad: true,
        fiveWordSafeLoad: true,
        ackSupport: true,
        readbackSupport: false,
        reconnectSupport: true,
        maximumPayloadSize: 22,
        boardDetectionSupport: false,
      );
  @override
  String? get missingEvidence => null;

  @override
  Future<DspTransportResult> open() async {
    if (backend is! ProUsbiWindowsNativeBackend) {
      return const DspTransportResult(
        success: false,
        failure: DspTransportFailure.unavailable,
        message: 'Device lifecycle is owned by the Workbench USBi session.',
      );
    }
    final result = await (backend as ProUsbiWindowsNativeBackend).openDevice();
    return DspTransportResult(
      success: result.success,
      failure: result.success
          ? DspTransportFailure.none
          : DspTransportFailure.unavailable,
      message:
          result.success ? 'USBi connected.' : result.error ?? 'Open failed.',
    );
  }

  @override
  Future<void> close() async {
    if (backend is ProUsbiWindowsNativeBackend) {
      await (backend as ProUsbiWindowsNativeBackend).closeDevice();
    }
  }

  @override
  Future<DspTransportResult> execute(DspCommand command) async {
    if (!isAvailable) {
      return _failure(DspTransportFailure.unavailable, 'USBi unavailable.');
    }
    if (!deviceOpen()) {
      return _failure(
          DspTransportFailure.notConnected, 'USBi device is closed.');
    }
    if (!capabilities.supports(command.kind)) {
      return _failure(DspTransportFailure.unsupportedCapability,
          'Command capability is unsupported.');
    }
    final acknowledgements = <List<int>>[];
    for (final write in command.writes) {
      final body = write.addressAndData;
      if (body.length > capabilities.maximumPayloadSize!) {
        return _failure(DspTransportFailure.unsupportedCapability,
            'Payload exceeds proven USBi size.');
      }
      try {
        final ack = await backend.sendPacketsAndReadAck(
          setupPacket: buildParameterWriteSetup(bodyLength: body.length),
          bodyPacket: body,
          ackReadRequest: buildAckReadRequest(),
        );
        if (ack == null) {
          return _failure(
              DspTransportFailure.transferFailed, 'USBi transfer failed.',
              actual: true);
        }
        acknowledgements.add(List<int>.from(ack));
        if (!isAckSuccess(ack)) {
          return DspTransportResult(
            success: false,
            failure: DspTransportFailure.ackFailed,
            message: 'USBi ACK was not 01.',
            acknowledgements: acknowledgements,
            wasActualWrite: true,
          );
        }
      } catch (error) {
        return _failure(DspTransportFailure.exception, '$error', actual: true);
      }
    }
    return DspTransportResult(
      success: true,
      failure: DspTransportFailure.none,
      message: 'PASS_ACK',
      acknowledgements: acknowledgements,
      wasActualWrite: true,
    );
  }

  DspTransportResult _failure(DspTransportFailure failure, String message,
          {bool actual = false}) =>
      DspTransportResult(
          success: false,
          failure: failure,
          message: message,
          wasActualWrite: actual);
}
