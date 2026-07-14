class Adau1466MappedDelayAudit {
  final String channel;
  final String sigmaCell;
  final String sigmaSymbol;
  final int address;
  final int exportedBaselineWord;
  final String sigmaOutput;
  final String physicalOutput;
  final int? configuredMaxSamples;

  const Adau1466MappedDelayAudit(
      {required this.channel,
      required this.sigmaCell,
      required this.sigmaSymbol,
      required this.address,
      required this.exportedBaselineWord,
      required this.sigmaOutput,
      required this.physicalOutput,
      required this.configuredMaxSamples});

  String get parameterFormat => 'unsigned 32-bit integer sample count';
  String get validRawRange => configuredMaxSamples == null
      ? 'BLOCKED — configured Max unproven'
      : '0–$configuredMaxSamples samples';
  String get engineeringUnit => 'samples';
  String get sampleRateDependency =>
      'sample count; time conversion depends on sample rate';
  String get writeType => 'direct 6-byte parameter write; no SafeLoad';
  bool get writeEnabled => configuredMaxSamples != null;
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
        physicalOutput: 'OUT3',
        configuredMaxSamples: 4),
    Adau1466MappedDelayAudit(
        channel: 'MID_L',
        sigmaCell: 'Delay2_2',
        sigmaSymbol: 'DelaySigma300PMAlg1delay',
        address: 0x0408,
        exportedBaselineWord: 0x00000000,
        sigmaOutput: 'Output2',
        physicalOutput: 'OUT2',
        configuredMaxSamples: null),
    Adau1466MappedDelayAudit(
        channel: 'TWL',
        sigmaCell: 'Delay2_3',
        sigmaSymbol: 'DelaySigma300PMAlg4delay',
        address: 0x0405,
        exportedBaselineWord: 0x00000000,
        sigmaOutput: 'Output3',
        physicalOutput: 'OUT1',
        configuredMaxSamples: null),
    Adau1466MappedDelayAudit(
        channel: 'WFR',
        sigmaCell: 'Delay2_5',
        sigmaSymbol: 'DelaySigma300PMAlg6delay',
        address: 0x03C2,
        exportedBaselineWord: 0x00000000,
        sigmaOutput: 'Output4',
        physicalOutput: 'OUT8',
        configuredMaxSamples: null),
    Adau1466MappedDelayAudit(
        channel: 'MID_R',
        sigmaCell: 'Delay2_6',
        sigmaSymbol: 'DelaySigma300PMAlg7delay',
        address: 0x0406,
        exportedBaselineWord: 0x00000000,
        sigmaOutput: 'Output5',
        physicalOutput: 'OUT7',
        configuredMaxSamples: null),
    Adau1466MappedDelayAudit(
        channel: 'TWR',
        sigmaCell: 'Delay2_4',
        sigmaSymbol: 'DelaySigma300PMAlg5delay',
        address: 0x0407,
        exportedBaselineWord: 0x00000000,
        sigmaOutput: 'Output6',
        physicalOutput: 'OUT4',
        configuredMaxSamples: null),
  ];

  static const mappedAddressAllowlist = <int>{
    0x03C1,
    0x0408,
    0x0405,
    0x03C2,
    0x0406,
    0x0407,
  };
  static const writeEnabledAddresses = <int>{0x03C1};
  static Adau1466MappedDelayAudit? find(String channel) {
    for (final entry in channels) {
      if (entry.channel == channel) return entry;
    }
    return null;
  }

  static bool acceptsWrite(int address, num samples) {
    Adau1466MappedDelayAudit? match;
    for (final entry in channels) {
      if (entry.address == address) match = entry;
    }
    if (match == null ||
        !match.writeEnabled ||
        !samples.isFinite ||
        samples != samples.roundToDouble()) {
      return false;
    }
    return samples >= 0 && samples <= match.configuredMaxSamples!;
  }

  const ProAdau1466DelayAuditRegistry._();
}
