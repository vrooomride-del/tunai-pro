class Adau1466MappedDelayAudit {
  final String channel;
  final String sigmaCell;
  final String sigmaSymbol;
  final int address;
  final int exportedBaselineWord;
  final String sigmaOutput;
  final String physicalOutput;

  const Adau1466MappedDelayAudit(
      {required this.channel,
      required this.sigmaCell,
      required this.sigmaSymbol,
      required this.address,
      required this.exportedBaselineWord,
      required this.sigmaOutput,
      required this.physicalOutput});

  String get parameterFormat => 'UNPROVEN — export says 8.24 or Sigma integer';
  String get validRawRange => 'UNPROVEN';
  String get engineeringUnit => 'UNPROVEN';
  String get sampleRateDependency => 'UNPROVEN';
  String get writeType => 'direct_candidate only — capture required';
  bool get writeEnabled => false;
}

class ProAdau1466DelayAuditRegistry {
  static const channels = <Adau1466MappedDelayAudit>[
    Adau1466MappedDelayAudit(
        channel: 'WFL',
        sigmaCell: 'Delay2',
        sigmaSymbol: 'DelaySigma300PMAlg2delay',
        address: 0x03C1,
        exportedBaselineWord: 0x00000004,
        sigmaOutput: 'Output1',
        physicalOutput: 'OUT3'),
    Adau1466MappedDelayAudit(
        channel: 'MID_L',
        sigmaCell: 'Delay2_2',
        sigmaSymbol: 'DelaySigma300PMAlg1delay',
        address: 0x0408,
        exportedBaselineWord: 0x00000000,
        sigmaOutput: 'Output2',
        physicalOutput: 'OUT2'),
    Adau1466MappedDelayAudit(
        channel: 'TWL',
        sigmaCell: 'Delay2_3',
        sigmaSymbol: 'DelaySigma300PMAlg4delay',
        address: 0x0405,
        exportedBaselineWord: 0x00000000,
        sigmaOutput: 'Output3',
        physicalOutput: 'OUT1'),
    Adau1466MappedDelayAudit(
        channel: 'WFR',
        sigmaCell: 'Delay2_5',
        sigmaSymbol: 'DelaySigma300PMAlg6delay',
        address: 0x03C2,
        exportedBaselineWord: 0x00000000,
        sigmaOutput: 'Output4',
        physicalOutput: 'OUT8'),
    Adau1466MappedDelayAudit(
        channel: 'MID_R',
        sigmaCell: 'Delay2_6',
        sigmaSymbol: 'DelaySigma300PMAlg7delay',
        address: 0x0406,
        exportedBaselineWord: 0x00000000,
        sigmaOutput: 'Output5',
        physicalOutput: 'OUT7'),
    Adau1466MappedDelayAudit(
        channel: 'TWR',
        sigmaCell: 'Delay2_4',
        sigmaSymbol: 'DelaySigma300PMAlg5delay',
        address: 0x0407,
        exportedBaselineWord: 0x00000000,
        sigmaOutput: 'Output6',
        physicalOutput: 'OUT4'),
  ];

  static const writeEnabledAddresses = <int>{};
  static bool acceptsWrite(int address, int rawWord) => false;
  const ProAdau1466DelayAuditRegistry._();
}
