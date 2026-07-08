import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 주파수 + SPL 크기 (mobile의 FrequencyBin과 동일 구조)
class FrequencyBin {
  final double frequency;
  final double magnitude;
  const FrequencyBin({required this.frequency, required this.magnitude});
}

class SpectrumSnapshot {
  final List<FrequencyBin>? before;
  final List<FrequencyBin>? afterAi;

  const SpectrumSnapshot({this.before, this.afterAi});
}

final spectrumSnapshotProvider =
    StateNotifierProvider<SpectrumSnapshotController, SpectrumSnapshot>(
  (ref) => SpectrumSnapshotController(),
);

class SpectrumSnapshotController extends StateNotifier<SpectrumSnapshot> {
  SpectrumSnapshotController() : super(const SpectrumSnapshot());

  void setBefore(List<FrequencyBin> bins) =>
      state = SpectrumSnapshot(before: bins, afterAi: state.afterAi);

  void setAfterAi(List<FrequencyBin> bins) =>
      state = SpectrumSnapshot(before: state.before, afterAi: bins);

  void reset() => state = const SpectrumSnapshot();

  /// PEQ 보정 밴드를 before 곡선에 합성 (Gaussian 근사) → afterAi 계산
  static List<FrequencyBin> applyCorrections(
    List<FrequencyBin> before,
    List<({double freq, double gain, double q})> corrections,
  ) {
    return before.map((b) {
      double delta = 0;
      for (final c in corrections) {
        if (b.frequency <= 0 || c.freq <= 0) continue;
        final octaves = (math.log(b.frequency / c.freq) / math.ln2).abs();
        final width = 1 / c.q.clamp(0.3, 16.0);
        delta += c.gain * math.exp(-0.5 * math.pow(octaves / width, 2));
      }
      return FrequencyBin(frequency: b.frequency, magnitude: b.magnitude + delta);
    }).toList();
  }

  /// 모의 룸 응답 생성 — 실측 연동 전까지 사용 (100포인트, 20Hz~20kHz 로그 분할)
  static List<FrequencyBin> generateMockResponse() {
    const logMin = 1.30103; // log10(20)
    const logMax = 4.30103; // log10(20000)
    return List.generate(100, (i) {
      final logF = logMin + i * (logMax - logMin) / 99;
      final freq = math.pow(10, logF).toDouble();
      double mag = 0;
      // 60Hz 이하 저역 롤오프
      if (freq < 60) mag -= 10 * (1 - freq / 60).clamp(0.0, 1.0);
      // 130Hz 부근 룸 모드 (+4dB)
      final rm = (math.log(freq / 130) / math.ln2).abs();
      mag += 4.0 * math.exp(-0.5 * math.pow(rm / 0.5, 2));
      // 8kHz 이상 고역 롤오프
      if (freq > 8000) {
        mag -= 5 * (math.log(freq / 8000) / math.ln2).clamp(0.0, 3.0);
      }
      // 실내 반사 효과 (미세 undulation)
      mag += 1.5 * math.sin(math.log(freq) * 3);
      return FrequencyBin(frequency: freq, magnitude: mag);
    });
  }
}
