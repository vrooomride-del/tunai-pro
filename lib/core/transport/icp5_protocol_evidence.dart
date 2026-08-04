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
  final List<int>? peqReadRequest;
  final String? peqReadResponseFormat;

  // ── Crossover filter type / slope / coefficient evidence (Phase 7-P0) ──────
  // Deliberately ALL NULL below — no capture exists yet for any of these.
  // See lib/core/dsp/adau1701_crossover_filter_engine.dart for the
  // hardware-independent coefficient math prepared ahead of this evidence,
  // and the Phase 7-5/7-P0 capture checklist for exactly what fills these in.
  // No field here may ever be populated with a guessed/inferred value — only
  // from a real logged ICP5 frame or SigmaStudio-exported parameter map.

  /// Parameter ID for filter type (LR/Butterworth/Bessel), if runtime
  /// case (a). Null until captured — never assume it exists near 0x15/0x18.
  final int? filterTypeParameterId;
  final int? filterTypePropertyByte;
  final String? filterTypeEncoding;

  /// Captured raw values per filter-type label once known, e.g.
  /// {'LR': 0, 'BW': 1, 'Bessel': 2} — labels only, no assumed ordering.
  final Map<String, int>? capturedFilterTypeValuesByLabel;

  /// Parameter ID for slope/order (12/18/24/48 dB/oct), if runtime case (a).
  final int? filterSlopeParameterId;
  final int? filterSlopePropertyByte;
  final String? filterSlopeEncoding;
  final Map<String, int>? capturedFilterSlopeValuesByLabel;

  /// Parameter ID for raw biquad coefficients (b0,b1,b2,a1,a2 per section),
  /// if case (c) — generated/compiled coefficients rather than a type/slope
  /// selector. [filterCoefficientOrder] describes the byte layout once known
  /// (e.g. "b0,b1,b2,a1,a2 per section, low-frequency-pole section first").
  final int? filterCoefficientParameterId;
  final String? filterCoefficientOrder;
  final String? filterCoefficientEndian;
  final String? filterCoefficientValueEncoding;
  final Map<int, int>? filterCoefficientChannelMapping;

  /// True only once type/slope/coefficient evidence above has been
  /// independently confirmed over that specific transport. Both default
  /// false — matches [bluetooth] being entirely empty for every other
  /// parameter in this registry today (gain/mute/PEQ/XO-frequency were all
  /// captured over USB only; BLE has never been independently verified).
  final bool filterTypeSlopeCoefficientUsbVerified;
  final bool filterTypeSlopeCoefficientBleVerified;

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
    this.peqReadRequest,
    this.peqReadResponseFormat,
    this.filterTypeParameterId,
    this.filterTypePropertyByte,
    this.filterTypeEncoding,
    this.capturedFilterTypeValuesByLabel,
    this.filterSlopeParameterId,
    this.filterSlopePropertyByte,
    this.filterSlopeEncoding,
    this.capturedFilterSlopeValuesByLabel,
    this.filterCoefficientParameterId,
    this.filterCoefficientOrder,
    this.filterCoefficientEndian,
    this.filterCoefficientValueEncoding,
    this.filterCoefficientChannelMapping,
    this.filterTypeSlopeCoefficientUsbVerified = false,
    this.filterTypeSlopeCoefficientBleVerified = false,
  });

  bool get hasPeqReadEvidence =>
      peqReadRequest != null && peqReadResponseFormat != null;

  /// True only once at least one of filter type/slope/coefficient has a
  /// captured parameter ID AND has been verified over at least one
  /// transport. False for both [Icp5ProtocolEvidenceRegistry.usb] and
  /// [Icp5ProtocolEvidenceRegistry.bluetooth] today — this is the fail-closed
  /// marker the deploy/capability layer should gate on before ever treating
  /// filter type/slope/coefficient as writable.
  bool get hasFilterTypeSlopeCoefficientEvidence =>
      (filterTypeSlopeCoefficientUsbVerified || filterTypeSlopeCoefficientBleVerified) &&
      (filterTypeParameterId != null ||
          filterSlopeParameterId != null ||
          filterCoefficientParameterId != null);

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
        'three-byte payload 01 00 + state byte 00/01; State 0=MUTED, State 1=UNMUTED; polarity confirmed',
    masterMuteAckParameterId: 0x00000012,
    masterMuteSuccessStatus: 0x00,
    masterMutePolarityProven: true,
    outputDac1GainParameterId: 0x00000014,
    outputDac1GainPayloadPrefix: [0x01, 0x00],
    capturedOutputDac1GainValues: [-4.9, -4.8],
    outputDac1GainValueEncoding: 'IEEE-754 float32 little-endian',
    outputDac1GainAckParameterId: 0x00000014,
    outputDac1GainSuccessStatus: 0x00,
    outputDac1GainRangeProven: false,
    outputGainPairsByChannel: {
      0: [-4.9, -4.8],
      1: [-4.8, -4.7],
      2: [-0.16666946, -0.06666946],
      3: [-0.16666946, -0.06666946],
    },
    delayCandidateParameterId: 0x00000017,
    delayCandidateChannels: [0, 1, 2, 3],
    delayCandidateValues: [1.0, 0.04],
    filterCutoffParameterId: 0x00000015,
    filterCutoffPairsByChannel: {
      0: [2001, 2000],
      1: [2001, 2000],
      2: [21, 20],
      3: [21, 20],
    },
    peqBandGainParameterId: 0x00000018,
    peqBand1GainPairsByChannel: {
      0: [-0.9, -1.0],
      1: [4.2, 4.1],
      2: [-1.0, -2.0],
      3: [2.1, 2.0],
    },
  );
  static const bluetooth = Icp5ProtocolEvidence();
}
