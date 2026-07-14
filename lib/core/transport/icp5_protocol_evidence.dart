class Icp5ProtocolEvidence {
  final int? usbVendorId;
  final int? usbProductId;
  final String? usbInterfaceClass;
  final int? usbOutEndpoint;
  final int? usbInEndpoint;
  final String? bluetoothServiceUuid;
  final String? bluetoothWriteCharacteristicUuid;
  final String? bluetoothAckCharacteristicUuid;
  final String? framing;
  final int? maximumPayload;
  final String? ackFormat;
  final String? fragmentation;
  final String? checksum;
  final String? dspTargetSelection;
  final String? directWriteSequence;
  final String? safeLoadSequence;

  const Icp5ProtocolEvidence({
    this.usbVendorId,
    this.usbProductId,
    this.usbInterfaceClass,
    this.usbOutEndpoint,
    this.usbInEndpoint,
    this.bluetoothServiceUuid,
    this.bluetoothWriteCharacteristicUuid,
    this.bluetoothAckCharacteristicUuid,
    this.framing,
    this.maximumPayload,
    this.ackFormat,
    this.fragmentation,
    this.checksum,
    this.dspTargetSelection,
    this.directWriteSequence,
    this.safeLoadSequence,
  });

  bool get isProtocolProven => false;
}

abstract final class Icp5ProtocolEvidenceRegistry {
  static const usb = Icp5ProtocolEvidence();
  static const bluetooth = Icp5ProtocolEvidence();
}
