import '../dsp/dsp_adapter.dart';
import '../dsp/adau1701_adapter.dart';
import '../dsp/adau1466_adapter.dart';

enum SystemProfileId {
  tunaiOne,       // JAB4(ADAU1701) 2웨이
  isobarik,       // 파란보드(ADAU1466) 3웨이 Linn Isobarik
  tunaiReference, // 파란보드(ADAU1466) 동축 2웨이
}

enum ChannelType { woofer, mid, tweeter, fullRange, subwoofer }

class ChannelConfig {
  final String name;
  final ChannelType type;
  final (double, double) freqRange;
  const ChannelConfig({required this.name, required this.type, required this.freqRange});
}

class SystemProfile {
  final SystemProfileId id;
  final String displayName;
  final String description;
  final String chipLabel;
  final DspAdapter Function(RawWriteFn send) adapterFactory;
  final List<ChannelConfig> channels;
  final int crossoverPoints;

  const SystemProfile({
    required this.id,
    required this.displayName,
    required this.description,
    required this.chipLabel,
    required this.adapterFactory,
    required this.channels,
    required this.crossoverPoints,
  });

  int get channelCount => channels.length;
  bool get isAdau1466 => id == SystemProfileId.isobarik || id == SystemProfileId.tunaiReference;
}

// ── 사전 정의 프로파일 ─────────────────────────────────────────

final kTunaiOneSystemProfile = SystemProfile(
  id: SystemProfileId.tunaiOne,
  displayName: 'TUNAI ONE',
  description: '5.25" 우퍼 + 1" 트위터 2웨이 · JAB4(ADAU1701)',
  chipLabel: 'ADAU1701',
  adapterFactory: (send) => Adau1701Adapter(send: send),
  channels: const [
    ChannelConfig(name: 'Woofer',  type: ChannelType.woofer,  freqRange: (40,   2200)),
    ChannelConfig(name: 'Tweeter', type: ChannelType.tweeter, freqRange: (2200, 20000)),
  ],
  crossoverPoints: 1,
);

final kIsobarikSystemProfile = SystemProfile(
  id: SystemProfileId.isobarik,
  displayName: 'Isobarik 거실',
  description: 'Linn Isobarik 3웨이 · 파란보드(ADAU1466 + CS42448)',
  chipLabel: 'ADAU1466',
  adapterFactory: (send) => Adau1466Adapter(send: send),
  channels: const [
    ChannelConfig(name: 'Woofer',  type: ChannelType.woofer,  freqRange: (20,   280)),
    ChannelConfig(name: 'Mid',     type: ChannelType.mid,     freqRange: (280,  2500)),
    ChannelConfig(name: 'Tweeter', type: ChannelType.tweeter, freqRange: (2500, 20000)),
  ],
  crossoverPoints: 2,
);

final kTunaiReferenceSystemProfile = SystemProfile(
  id: SystemProfileId.tunaiReference,
  displayName: 'TUNAI REFERENCE',
  description: '5.25" 동축 2웨이 · 파란보드(ADAU1466 + CS42448) + TPA3255 + QCC5125',
  chipLabel: 'ADAU1466',
  adapterFactory: (send) => Adau1466Adapter(send: send),
  channels: const [
    ChannelConfig(name: 'Coaxial Woofer',  type: ChannelType.woofer,  freqRange: (40,   2000)),
    ChannelConfig(name: 'Coaxial Tweeter', type: ChannelType.tweeter, freqRange: (2000, 20000)),
  ],
  crossoverPoints: 1,
);

final kAllSystemProfiles = [
  kTunaiOneSystemProfile,
  kIsobarikSystemProfile,
  kTunaiReferenceSystemProfile,
];
