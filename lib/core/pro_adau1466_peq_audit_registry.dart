class Adau1466PeqOutputAudit {
  final String channel;
  final String sigmaOutput;
  final String physicalOutput;

  const Adau1466PeqOutputAudit({
    required this.channel,
    required this.sigmaOutput,
    required this.physicalOutput,
  });

  String get status =>
      'WRITE BLOCKED — PEQ coefficient rows are not embedded; exact cell, band, slew, coefficients, baseline words, Frequency/Gain/Q are unavailable.';
}

/// Fail-closed audit of the PEQ evidence that is actually embedded in TUNAI PRO.
///
/// The source metadata records 875 PEQ rows, but
/// [kTunaiAdau1466ThreeWayAddressMapCsv] intentionally contains only the 118
/// non-PEQ rows. Consequently no individual PEQ address can be allowlisted.
class ProAdau1466PeqAuditRegistry {
  static const sourceFile =
      'TUNAI_ADAU1466_v0_8B_GLOBAL_DRIVER_160BAND_PEQ.params';
  static const fullOriginalExportFound = false;
  static const requiredExportArtifact =
      'TUNAI_ADAU1466_v0_8B_GLOBAL_DRIVER_160BAND_PEQ.params';
  static const requiredSigmaStudioOperation =
      'Open the matching TUNAI_ADAU1466_v0_8B_GLOBAL_DRIVER_160BAND_PEQ SigmaStudio project, compile/link it, then use SigmaStudio Export System Files and retain the complete generated .params parameter export without filtering PEQ rows.';
  static const sourcePeqRowCount = 875;
  static const embeddedPeqRowCount = 0;
  static const coefficientOrder = ['b2', 'b1', 'b0', 'a2', 'a1'];

  static const outputs = <Adau1466PeqOutputAudit>[
    Adau1466PeqOutputAudit(
        channel: 'WFL', sigmaOutput: 'Output1', physicalOutput: 'OUT3'),
    Adau1466PeqOutputAudit(
        channel: 'MID_L', sigmaOutput: 'Output2', physicalOutput: 'OUT2'),
    Adau1466PeqOutputAudit(
        channel: 'TWL', sigmaOutput: 'Output3', physicalOutput: 'OUT1'),
    Adau1466PeqOutputAudit(
        channel: 'WFR', sigmaOutput: 'Output4', physicalOutput: 'OUT8'),
    Adau1466PeqOutputAudit(
        channel: 'MID_R', sigmaOutput: 'Output5', physicalOutput: 'OUT7'),
    Adau1466PeqOutputAudit(
        channel: 'TWR', sigmaOutput: 'Output6', physicalOutput: 'OUT4'),
  ];

  static const selectedRepresentative = 'WFL · L_WOOFER_PEQ_20 · Band 1';
  static const baselineMetadataProven = false;
  static const writeEnabledAddresses = <int>{};

  static bool acceptsTransaction({
    required int slewAddress,
    required List<int> coefficientAddresses,
    required List<int> coefficientWords,
  }) => false;

  const ProAdau1466PeqAuditRegistry._();
}
