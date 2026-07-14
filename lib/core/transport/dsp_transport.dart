import 'dsp_command.dart';

enum DspTransportIdentity { usbi, icp5Usb, icp5Bluetooth }

enum DspConnectionState {
  unavailable,
  disconnected,
  connecting,
  connected,
  error
}

enum DspTransportFailure {
  none,
  unavailable,
  notConnected,
  unsupportedCapability,
  protocolEvidenceMissing,
  transferFailed,
  ackFailed,
  exception,
}

class DspTransportCapabilities {
  final bool directParameterWrite;
  final bool oneWordSafeLoad;
  final bool fiveWordSafeLoad;
  final bool ackSupport;
  final bool readbackSupport;
  final bool reconnectSupport;
  final int? maximumPayloadSize;
  final bool boardDetectionSupport;

  const DspTransportCapabilities({
    required this.directParameterWrite,
    required this.oneWordSafeLoad,
    required this.fiveWordSafeLoad,
    required this.ackSupport,
    required this.readbackSupport,
    required this.reconnectSupport,
    required this.maximumPayloadSize,
    required this.boardDetectionSupport,
  });

  static const unproven = DspTransportCapabilities(
    directParameterWrite: false,
    oneWordSafeLoad: false,
    fiveWordSafeLoad: false,
    ackSupport: false,
    readbackSupport: false,
    reconnectSupport: false,
    maximumPayloadSize: null,
    boardDetectionSupport: false,
  );

  bool supports(DspCommandKind kind) => switch (kind) {
        DspCommandKind.directParameterWrite => directParameterWrite,
        DspCommandKind.oneWordSafeLoad => oneWordSafeLoad,
        DspCommandKind.fiveWordSafeLoad => fiveWordSafeLoad,
      };
}

class DspTransportResult {
  final bool success;
  final DspTransportFailure failure;
  final String message;
  final List<List<int>> acknowledgements;
  final bool wasActualWrite;

  const DspTransportResult({
    required this.success,
    required this.failure,
    required this.message,
    this.acknowledgements = const [],
    this.wasActualWrite = false,
  });
}

abstract interface class DspTransport {
  DspTransportIdentity get identity;
  String get displayName;
  bool get isAvailable;
  DspConnectionState get connectionState;
  DspTransportCapabilities get capabilities;
  String? get missingEvidence;

  Future<DspTransportResult> open();
  Future<void> close();
  Future<DspTransportResult> execute(DspCommand command);
}

/// Routes a command only to the explicitly selected transport. It intentionally
/// has no fallback transport, so a rejected/failed active transaction cannot
/// silently escape to another backend.
class DspTransportRouter {
  final DspTransport selected;
  const DspTransportRouter(this.selected);

  Future<DspTransportResult> execute(DspCommand command) =>
      selected.execute(command);
}
