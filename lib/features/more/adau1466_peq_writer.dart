import 'dart:math';
import '../../core/dsp/transport/dsp_transport.dart';
import 'dsp_unlock_flags.dart';

/// ADAU1466 biquad PEQ 係数 書き込み — SafeLoad 経由, 5.27 固定小数点.
///
/// ADAU1466 係数順序: B2 / B1 / B0 / A2 / A1 (5ワード).
/// 各係数は `buildSafeLoadWriteSequence` (usbi_protocol.dart) が処理する
/// SafeLoad 3단계로 writeParameter 를 통해 write.
///
/// [DspUnlockFlags.peqWriteUnlocked] = false 동안 실제 write는 차단된다.
/// UI는 표시되지만 DSP에 반영되지 않는다.
class Adau1466PeqWriter {
  final DspTransport transport;

  /// 샘플레이트 (ADAU1466 기본값)
  static const double kFs = 48000.0;

  Adau1466PeqWriter(this.transport);

  /// 단일 PEQ 밴드를 SafeLoad로 write.
  ///
  /// [baseAddr] : 채널의 PEQ 첫 밴드 기준 주소 (예: Global L = 0x69).
  /// [bandIndex] : 0~19 (밴드 번호).
  /// [gainDb]    : -24.0 ~ +24.0 dB.
  /// [freq]      : 20 ~ 20000 Hz.
  /// [q]         : Q 값 (0.1 ~ 16).
  ///
  /// [DspUnlockFlags.peqWriteUnlocked]가 false면 아무 일도 하지 않고 반환.
  Future<void> writePeqBand(
    int baseAddr,
    int bandIndex,
    double gainDb,
    double freq,
    double q,
  ) async {
    if (!DspUnlockFlags.peqWriteUnlocked) return;

    final coeffs = _calcPeakingBiquad(gainDb: gainDb, freq: freq, q: q);
    // 주소: baseAddr + bandIndex * 5 (5 coefficients per band)
    final startAddr = baseAddr + bandIndex * 5;

    // ADAU1466 순서: B2/B1/B0/A2/A1
    for (var i = 0; i < 5; i++) {
      final fixed = _toFixed527(coeffs[i]);
      await transport.writeParameter(startAddr + i, _toBytes4(fixed));
    }
  }

  /// Peaking EQ biquad 係数計算 (Audio EQ Cookbook 準拠).
  ///
  /// 반환 순서: [B2, B1, B0, A2, A1] — ADAU1466 기준.
  /// 모든 값은 a0으로 정규화.
  static List<double> _calcPeakingBiquad({
    required double gainDb,
    required double freq,
    required double q,
  }) {
    final w0 = 2.0 * pi * freq / kFs;
    final cosW0 = cos(w0);
    final sinW0 = sin(w0);
    final alpha = sinW0 / (2.0 * q);
    final A = pow(10.0, gainDb / 40.0).toDouble();

    final b0 = 1.0 + alpha * A;
    final b1 = -2.0 * cosW0;
    final b2 = 1.0 - alpha * A;
    final a0 = 1.0 + alpha / A;
    final a1 = -2.0 * cosW0;
    final a2 = 1.0 - alpha / A;

    // ADAU1466는 피드백 계수 a1/a2를 negated form으로 저장 — 부호 반전 불필요
    // (DSP 내부에서 자체 처리). a0 으로 정규화.
    return [
      b2 / a0,
      b1 / a0,
      b0 / a0,
      a2 / a0,
      a1 / a0,
    ];
  }

  /// double → 5.27 fixed-point int.
  /// dbToFixed824() 사용 금지 — Q8.24 ≠ 5.27.
  static int _toFixed527(double v) => (v * (1 << 27)).round();

  static List<int> _toBytes4(int v) => [
        (v >> 24) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 8) & 0xFF,
        v & 0xFF,
      ];
}
