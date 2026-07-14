import 'dsp_command.dart';
import 'dsp_transport.dart';
import 'icp5_protocol_evidence.dart';

abstract class _BlockedIcp5Transport implements DspTransport {
  final Icp5ProtocolEvidence evidence;
  const _BlockedIcp5Transport(this.evidence);

  @override
  bool get isAvailable => false;
  @override
  DspConnectionState get connectionState => DspConnectionState.unavailable;
  @override
  DspTransportCapabilities get capabilities =>
      DspTransportCapabilities.unproven;
  @override
  String get missingEvidence => 'PROTOCOL EVIDENCE REQUIRED — WRITES BLOCKED';

  DspTransportResult get _blocked => const DspTransportResult(
        success: false,
        failure: DspTransportFailure.protocolEvidenceMissing,
        message: 'PROTOCOL EVIDENCE REQUIRED — WRITES BLOCKED',
        wasActualWrite: false,
      );

  @override
  Future<DspTransportResult> open() async => _blocked;
  @override
  Future<void> close() async {}
  @override
  Future<DspTransportResult> execute(DspCommand command) async => _blocked;
}

class Icp5UsbTransport extends _BlockedIcp5Transport {
  const Icp5UsbTransport() : super(Icp5ProtocolEvidenceRegistry.usb);
  @override
  DspTransportIdentity get identity => DspTransportIdentity.icp5Usb;
  @override
  String get displayName => 'ICP5 USB';
}

class Icp5BluetoothTransport extends _BlockedIcp5Transport {
  const Icp5BluetoothTransport()
      : super(Icp5ProtocolEvidenceRegistry.bluetooth);
  @override
  DspTransportIdentity get identity => DspTransportIdentity.icp5Bluetooth;
  @override
  String get displayName => 'ICP5 Bluetooth';
}
