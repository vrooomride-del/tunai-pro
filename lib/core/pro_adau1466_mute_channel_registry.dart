class Adau1466MappedMuteChannel {
  final String channel;
  final String sigmaCell;
  final String sigmaSymbol;
  final int address;
  final int exportedState;
  final String sigmaOutput;
  final String physicalOutput;
  const Adau1466MappedMuteChannel(
      {required this.channel,
      required this.sigmaCell,
      required this.sigmaSymbol,
      required this.address,
      required this.exportedState,
      required this.sigmaOutput,
      required this.physicalOutput});
}

class ProAdau1466MuteChannelRegistry {
  static const channels = <Adau1466MappedMuteChannel>[
    Adau1466MappedMuteChannel(
        channel: 'WFL',
        sigmaCell: 'Mute1_3',
        sigmaSymbol: 'MuteNoSlewADAU145XAlg3mute',
        address: 0x060E,
        exportedState: 1,
        sigmaOutput: 'Output1',
        physicalOutput: 'OUT3'),
    Adau1466MappedMuteChannel(
        channel: 'MID_L',
        sigmaCell: 'Mute1',
        sigmaSymbol: 'MuteNoSlewADAU145XAlg1mute',
        address: 0x0613,
        exportedState: 1,
        sigmaOutput: 'Output2',
        physicalOutput: 'OUT2'),
    Adau1466MappedMuteChannel(
        channel: 'TWL',
        sigmaCell: 'Mute1_4',
        sigmaSymbol: 'MuteNoSlewADAU145XAlg4mute',
        address: 0x0610,
        exportedState: 0,
        sigmaOutput: 'Output3',
        physicalOutput: 'OUT1'),
    Adau1466MappedMuteChannel(
        channel: 'WFR',
        sigmaCell: 'Mute1_2',
        sigmaSymbol: 'MuteNoSlewADAU145XAlg2mute',
        address: 0x060F,
        exportedState: 1,
        sigmaOutput: 'Output4',
        physicalOutput: 'OUT8'),
    Adau1466MappedMuteChannel(
        channel: 'MID_R',
        sigmaCell: 'Mute1_8',
        sigmaSymbol: 'MuteNoSlewADAU145XAlg8mute',
        address: 0x0612,
        exportedState: 1,
        sigmaOutput: 'Output5',
        physicalOutput: 'OUT7'),
    Adau1466MappedMuteChannel(
        channel: 'TWR',
        sigmaCell: 'Mute1_7',
        sigmaSymbol: 'MuteNoSlewADAU145XAlg7mute',
        address: 0x0611,
        exportedState: 0,
        sigmaOutput: 'Output6',
        physicalOutput: 'OUT4'),
  ];
  const ProAdau1466MuteChannelRegistry._();
  static Adau1466MappedMuteChannel? find(String name) {
    for (final c in channels) {
      if (c.channel == name) return c;
    }
    return null;
  }
}
