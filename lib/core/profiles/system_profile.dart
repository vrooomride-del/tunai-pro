import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../dsp/dsp_adapter.dart';
import '../dsp/adau1701_adapter.dart';
import '../dsp/adau1466_adapter.dart';
import '../dsp/validating_dsp_adapter.dart';

/// 선택된 시스템 프로파일 전역 상태 — core에 선언 (circular import 방지)
final systemProfileProvider = StateProvider<SystemProfile>(
  (ref) => kTunaiOneSystemProfile,
);

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
  // ADAU1701(비-1466) 펌웨어에는 PEQ 모듈이 없음 — Adau1701Adapter.writeBiquad는
  // no-op이라 PEQ 탭에서 밴드를 편집해도 실기기에 전송되지 않는다. UI는 아직
  // 그대로 노출돼 있음 — 실사용 전 숨기거나, 펌웨어에 PEQ 블록을 추가해 재컴파일할 것.
  int get maxPeqBands => isAdau1466 ? 20 : 10;
}

// ── 사전 정의 프로파일 ─────────────────────────────────────────
//
// adapterFactory는 항상 ValidatingDspAdapter로 감싸서 반환한다 — Safety Validation
// Layer(AOS 항목 D)를 우회할 방법을 없애기 위함. 채널 리스트를 top-level const로
// 먼저 선언해 adapterFactory 클로저와 channels 필드가 동일한 리스트를 참조하게 함.

const _tunaiOneChannels = [
  ChannelConfig(name: 'Woofer',  type: ChannelType.woofer,  freqRange: (40,   2200)),
  ChannelConfig(name: 'Tweeter', type: ChannelType.tweeter, freqRange: (2200, 20000)),
];

final kTunaiOneSystemProfile = SystemProfile(
  id: SystemProfileId.tunaiOne,
  displayName: 'TUNAI ONE',
  description: '5.25" 우퍼 + 1" 트위터 2웨이 · JAB4(ADAU1701)',
  chipLabel: 'ADAU1701',
  adapterFactory: (send) =>
      ValidatingDspAdapter(Adau1701Adapter(send: send), _tunaiOneChannels),
  channels: _tunaiOneChannels,
  crossoverPoints: 1,
);

const _isobarikChannels = [
  ChannelConfig(name: 'Woofer',  type: ChannelType.woofer,  freqRange: (20,   280)),
  ChannelConfig(name: 'Mid',     type: ChannelType.mid,     freqRange: (280,  2500)),
  ChannelConfig(name: 'Tweeter', type: ChannelType.tweeter, freqRange: (2500, 20000)),
];

final kIsobarikSystemProfile = SystemProfile(
  id: SystemProfileId.isobarik,
  displayName: 'Isobarik 거실',
  description: 'Linn Isobarik 3웨이 · 파란보드(ADAU1466 + CS42448)',
  chipLabel: 'ADAU1466',
  adapterFactory: (send) =>
      ValidatingDspAdapter(Adau1466Adapter(send: send), _isobarikChannels),
  channels: _isobarikChannels,
  crossoverPoints: 2,
);

const _tunaiReferenceChannels = [
  ChannelConfig(name: 'Coaxial Woofer',  type: ChannelType.woofer,  freqRange: (40,   2000)),
  ChannelConfig(name: 'Coaxial Tweeter', type: ChannelType.tweeter, freqRange: (2000, 20000)),
];

final kTunaiReferenceSystemProfile = SystemProfile(
  id: SystemProfileId.tunaiReference,
  displayName: 'TUNAI REFERENCE',
  description: '5.25" 동축 2웨이 · 파란보드(ADAU1466 + CS42448) + TPA3255 + QCC5125',
  chipLabel: 'ADAU1466',
  adapterFactory: (send) =>
      ValidatingDspAdapter(Adau1466Adapter(send: send), _tunaiReferenceChannels),
  channels: _tunaiReferenceChannels,
  crossoverPoints: 1,
);

final kAllSystemProfiles = [
  kTunaiOneSystemProfile,
  kIsobarikSystemProfile,
  kTunaiReferenceSystemProfile,
];
