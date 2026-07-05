import '../features/dsp/dsp_state.dart';

/// 읽기 전용 Factory 프리셋 — User 프리셋과 저장공간/수정권한이 완전히 분리된
/// 별도 계층(AOS 항목 C). `const` 리스트 + setter 없는 불변 클래스라 런타임에
/// 덮어쓰거나 삭제할 수 없다. SharedPreferences 등 어떤 저장소에도 쓰지 않고
/// 코드에 직접 내장돼 있다 — User가 아무리 저장을 실수해도 항상 이 값으로
/// 복귀할 수 있는 "진짜" 안전한 기준점.
class FactoryPreset {
  final String id;
  final String name;
  final String description;

  /// 채널 수(maxPeqBands)에 맞춰 매번 새 DspState를 생성 — 프로파일이 바뀌어도
  /// 항상 유효한 상태를 돌려준다.
  final DspState Function(int maxPeqBands) build;

  const FactoryPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.build,
  });
}

/// 실제 공장 캘리브레이션 데이터가 없어(HANDOFF.md 기존 기록 참고) "보정 없는 평탄
/// 기준값"을 Factory로 채택 — 이미 DspState.initial()이 만드는 크로스오버 기본값
/// (TWE 2500Hz HPF, MID 200~2500Hz, WOO 200Hz LPF) 그대로를 사용한다. 이 값 자체를
/// 여기서 새로 만들지 않고 DspState.initial을 그대로 위임해서, resetAll()과 Factory
/// 로드가 항상 같은 소스를 가리키도록 보장한다(따로 유지되며 드리프트할 여지 없음).
final kFactoryPresetFlat = FactoryPreset(
  id: 'factory_flat',
  name: 'Factory',
  description: '보정 없는 평탄 기준값 — 언제든 복귀 가능한 안전한 기본 상태',
  build: (maxPeqBands) => DspState.initial(maxPeqBands: maxPeqBands),
);

final kFactoryPresets = <FactoryPreset>[kFactoryPresetFlat];

/// 예약된 이름 집합(소문자 비교) — User가 이 이름으로 저장을 시도하면 거부한다.
bool isReservedPresetName(String name) =>
    kFactoryPresets.any((p) => p.name.toLowerCase() == name.trim().toLowerCase());
