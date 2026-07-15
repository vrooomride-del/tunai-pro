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
  final String? usbProductIdentity;
  final int? baudRate;
  final int? dataBits;
  final String? parity;
  final int? stopBits;
  final List<int>? identificationRequest;
  final String? expectedProfile;
  final int? framingStartByte;
  final int? directWriteCommand;
  final int? ackCommand;
  final String? valueEncoding;
  final int? masterVolumeParameterId;
  final List<double>? capturedMasterVolumeValues;
  final int? masterMuteParameterId;
  final List<int>? masterMutePayloadPrefix;
  final List<int>? capturedMasterMuteStates;
  final String? masterMuteValueEncoding;
  final int? masterMuteAckParameterId;
  final int? masterMuteSuccessStatus;
  final bool? masterMutePolarityProven;
  final int? outputDac1GainParameterId;
  final List<int>? outputDac1GainPayloadPrefix;
  final List<double>? capturedOutputDac1GainValues;
  final String? outputDac1GainValueEncoding;
  final int? outputDac1GainAckParameterId;
  final int? outputDac1GainSuccessStatus;
  final bool? outputDac1GainRangeProven;
  final Map<int, List<double>>? outputGainPairsByChannel;
  final int? delayCandidateParameterId;
  final List<int>? delayCandidateChannels;
  final List<double>? delayCandidateValues;
  final int? filterCutoffParameterId;
  final Map<int, List<int>>? filterCutoffPairsByChannel;
  final int? peqBandGainParameterId;
  final Map<int, List<double>>? peqBand1GainPairsByChannel;

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
    this.usbProductIdentity,
    this.baudRate,
    this.dataBits,
    this.parity,
    this.stopBits,
    this.identificationRequest,
    this.expectedProfile,
    this.framingStartByte,
    this.directWriteCommand,
    this.ackCommand,
    this.valueEncoding,
    this.masterVolumeParameterId,
    this.capturedMasterVolumeValues,
    this.masterMuteParameterId,
    this.masterMutePayloadPrefix,
    this.capturedMasterMuteStates,
    this.masterMuteValueEncoding,
    this.masterMuteAckParameterId,
    this.masterMuteSuccessStatus,
    this.masterMutePolarityProven,
    this.outputDac1GainParameterId,
    this.outputDac1GainPayloadPrefix,
    this.capturedOutputDac1GainValues,
    this.outputDac1GainValueEncoding,
    this.outputDac1GainAckParameterId,
    this.outputDac1GainSuccessStatus,
    this.outputDac1GainRangeProven,
    this.outputGainPairsByChannel,
    this.delayCandidateParameterId,
    this.delayCandidateChannels,
    this.delayCandidateValues,
    this.filterCutoffParameterId,
    this.filterCutoffPairsByChannel,
    this.peqBandGainParameterId,
    this.peqBand1GainPairsByChannel,
  });

  bool get isProtocolProven =>
      usbVendorId != null &&
      usbProductId != null &&
      identificationRequest != null &&
      expectedProfile != null;
}

abstract final class Icp5ProtocolEvidenceRegistry {
  static const usb = Icp5ProtocolEvidence(
    usbVendorId: 0x1A86,
    usbProductId: 0x55D6,
    usbProductIdentity: 'USB-BLE-SERIAL CH9143',
    baudRate: 115200,
    dataBits: 8,
    parity: 'none',
    stopBits: 1,
    identificationRequest: [0x55, 0x07, 0x1A, 0, 0, 0, 0, 0, 0x76],
    expectedProfile: 'DSP1701.100.00.01',
    framingStartByte: 0x55,
    framing: '0x55 + declared length + command + payload + modulo-256 checksum',
    ackFormat: '0xE1 + echoed parameter ID + status 0x00',
    checksum: 'sum of every preceding frame byte modulo 256',
    directWriteSequence: '0x1C + parameter ID + little-endian float32',
    directWriteCommand: 0x1C,
    ackCommand: 0xE1,
    valueEncoding: 'IEEE-754 float32 little-endian',
    masterVolumeParameterId: 0x00000010,
    capturedMasterVolumeValues: [5.9, 6.0],
    masterMuteParameterId: 0x00000012,
    masterMutePayloadPrefix: [0x01, 0x00],
    capturedMasterMuteStates: [0x00, 0x01],
    masterMuteValueEncoding:
        'three-byte payload 01 00 + state byte 00/01; polarity unproven',
    masterMuteAckParameterId: 0x00000012,
    masterMuteSuccessStatus: 0x00,
    masterMutePolarityProven: false,
    outputDac1GainParameterId: 0x00000014,
    outputDac1GainPayloadPrefix: [0x01, 0x00],
    capturedOutputDac1GainValues: [-4.9, -4.8],
    outputDac1GainValueEncoding: 'IEEE-754 float32 little-endian',
    outputDac1GainAckParameterId: 0x00000014,
    outputDac1GainSuccessStatus: 0x00,
    outputDac1GainRangeProven: false,
    outputGainPairsByChannel: {
      0: [-4.9, -4.8],
    },
    delayCandidateParameterId: 0x00000017,
    delayCandidateChannels: [0, 1, 2, 3],
    delayCandidateValues: [1.0, 0.04],
    filterCutoffParameterId: 0x00000015,
    filterCutoffPairsByChannel: {
      0: [2001, 2000],
      2: [21, 20],
    },
    peqBandGainParameterId: 0x00000018,
    peqBand1GainPairsByChannel: {
      0: [-0.9, -1.0],
      2: [-1.0, -2.0],
    },
  );
  static const bluetooth = Icp5ProtocolEvidence();
}
