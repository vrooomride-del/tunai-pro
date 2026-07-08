import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'spectrum_snapshot.dart';

class SoundScoreResult {
  final int total;         // 0–100
  final int flatness;      // 0–40
  final int bassExt;       // 0–20
  final int trebleRolloff; // 0–20
  final int channelMatch;  // 0–20 (stereo 측정 필요; 현재 15 고정)
  final String explanation;

  const SoundScoreResult({
    required this.total,
    required this.flatness,
    required this.bassExt,
    required this.trebleRolloff,
    required this.channelMatch,
    required this.explanation,
  });
}

class SoundScoreCalculator {
  SoundScoreCalculator._();

  static SoundScoreResult? compute(List<FrequencyBin>? bins) {
    if (bins == null || bins.length < 5) return null;
    final sorted = List<FrequencyBin>.from(bins)
      ..sort((a, b) => a.frequency.compareTo(b.frequency));

    final flatness = _flatnessScore(sorted);
    final bass = _bassScore(sorted);
    final treble = _trebleScore(sorted);
    const channelMatch = 15;
    final total = (flatness + bass + treble + channelMatch).clamp(0, 100);

    return SoundScoreResult(
      total: total,
      flatness: flatness,
      bassExt: bass,
      trebleRolloff: treble,
      channelMatch: channelMatch,
      explanation: _explain(flatness, bass, treble),
    );
  }

  static int _flatnessScore(List<FrequencyBin> bins) {
    final mags = bins
        .where((b) => b.frequency >= 200 && b.frequency <= 8000)
        .map((b) => b.magnitude)
        .toList();
    if (mags.isEmpty) return 20;
    final mean = mags.reduce((a, b) => a + b) / mags.length;
    final variance = mags
            .map((m) => (m - mean) * (m - mean))
            .reduce((a, b) => a + b) /
        mags.length;
    final std = math.sqrt(variance);
    return (40.0 * (1.0 - (std - 3.0).clamp(0.0, 12.0) / 12.0))
        .round()
        .clamp(0, 40);
  }

  static int _bassScore(List<FrequencyBin> bins) {
    final refMags = bins
        .where((b) => b.frequency >= 200 && b.frequency <= 2000)
        .map((b) => b.magnitude)
        .toList();
    if (refMags.isEmpty) return 10;
    final refMean = refMags.reduce((a, b) => a + b) / refMags.length;
    final at40 = _interpMag(bins, 40);
    if (at40 == null) return 10;
    final delta = at40 - refMean;
    return (20.0 * (delta + 20.0).clamp(0.0, 17.0) / 17.0)
        .round()
        .clamp(0, 20);
  }

  static int _trebleScore(List<FrequencyBin> bins) {
    final at10k = _interpMag(bins, 10000);
    final at20k = _interpMag(bins, 20000);
    if (at10k == null || at20k == null) return 15;
    final drop = at10k - at20k;
    if (drop >= 2 && drop <= 8) return 20;
    if (drop < 0) return (20 + drop * 2).round().clamp(0, 20);
    if (drop > 8) return (20 - (drop - 8) * 2).round().clamp(0, 20);
    return (drop / 2 * 20).round().clamp(0, 20);
  }

  static double? _interpMag(List<FrequencyBin> bins, double freq) {
    FrequencyBin? lo, hi;
    for (final b in bins) {
      if (b.frequency <= freq) {
        lo = b;
      } else {
        hi ??= b;
      }
    }
    if (lo == null && hi == null) return null;
    if (lo == null) return hi!.magnitude;
    if (hi == null) return lo.magnitude;
    if (hi.frequency == lo.frequency) return lo.magnitude;
    final t = (freq - lo.frequency) / (hi.frequency - lo.frequency);
    return lo.magnitude + t * (hi.magnitude - lo.magnitude);
  }

  static String _explain(int flatness, int bass, int treble) {
    final parts = <String>[];
    if (flatness >= 35) {
      parts.add('주파수 응답이 매우 평탄합니다');
    } else if (flatness >= 25) {
      parts.add('주파수 응답이 양호합니다');
    } else if (flatness >= 15) {
      parts.add('중역대 피크/딥이 감지됩니다');
    } else {
      parts.add('주파수 응답에 큰 불규칙성이 있습니다');
    }

    if (bass >= 18) {
      parts.add('저역 확장이 우수합니다');
    } else if (bass >= 12) {
      parts.add('저역이 다소 제한적입니다');
    } else {
      parts.add('저역 확장이 부족합니다');
    }

    if (treble >= 18) {
      parts.add('고역 롤오프가 자연스럽습니다');
    } else if (treble >= 12) {
      parts.add('고역이 다소 감쇠되어 있습니다');
    } else {
      parts.add('고역 손실이 큽니다');
    }

    return '${parts.join('. ')}.';
  }
}

final soundScoreProvider = Provider<SoundScoreResult?>((ref) {
  final snap = ref.watch(spectrumSnapshotProvider);
  return SoundScoreCalculator.compute(snap.before);
});
