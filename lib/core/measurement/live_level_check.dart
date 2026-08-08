// ── TUNAI PRO — Measurement Setup Live Level Check ──────────────────────────
//
// Pure types/logic only. No I/O, no recorder/player, no Riverpod. Turns a
// live dBFS reading into TOO LOW / GOOD / TOO HIGH using the SAME thresholds
// [MeasurementQualityPolicy] already uses for the WAV-based level check
// (minimumSignalRmsDbFs / maximumSignalRmsDbFs) — no new arbitrary numbers.
//
// Deliberately does NOT classify a live "clipping" state. record_darwin
// 1.2.2's Amplitude.max is a running maximum of AVCaptureAudioChannel's
// averagePowerLevel (an average-power / RMS-like metering value) that is
// NEVER reset per recording session — it accumulates across the entire
// lifetime of the underlying AudioRecorder object. It is not a true
// instantaneous peak-sample reading and cannot be meaningfully compared
// against the linear clippingAmplitudeThreshold (0.98) used by the
// WAV-based MeasurementPcmQualityAnalyzer. Final clipping verification is
// and remains the job of that real, sample-level analyzer — never faked
// here from a live meter reading.
library;

import 'measurement_quality_policy.dart';

/// TOO LOW / GOOD / TOO HIGH only — see this file's header comment for why
/// there is no live "clipping" status.
enum LiveLevelStatus { tooLow, good, tooHigh }

/// One live-meter tick.
class LiveLevelReading {
  final double currentDbFs;
  final LiveLevelStatus status;
  final DateTime at;

  const LiveLevelReading({
    required this.currentDbFs,
    required this.status,
    required this.at,
  });
}

/// Classifies [currentDbFs] against [policy]'s existing WAV-based-check
/// thresholds — the exact same [MeasurementQualityPolicy.minimumSignalRmsDbFs]
/// / [MeasurementQualityPolicy.maximumSignalRmsDbFs] boundaries, reused
/// verbatim rather than duplicated as new constants.
LiveLevelStatus classifyLiveLevel(
  double currentDbFs,
  MeasurementQualityPolicy policy,
) {
  if (currentDbFs < policy.minimumSignalRmsDbFs) return LiveLevelStatus.tooLow;
  if (currentDbFs > policy.maximumSignalRmsDbFs) return LiveLevelStatus.tooHigh;
  return LiveLevelStatus.good;
}

/// Tracks whether the live meter has been GOOD for a sustained window,
/// so a single transient tick can never trigger a PASS on its own. This is
/// a plain counter/window over incoming ticks — not a smoothing/DSP engine.
///
/// [stabilityWindow] (default 1s) is the span that must be covered by
/// consecutive GOOD ticks. [minimumTicks] guards against a single tick that
/// happens to span the whole window on its own (e.g. a slow poll interval)
/// being treated as "sustained" — at least this many GOOD ticks must have
/// been seen within the window.
class LiveLevelStabilityTracker {
  final Duration stabilityWindow;
  final int minimumTicks;

  LiveLevelStabilityTracker({
    this.stabilityWindow = const Duration(seconds: 1),
    this.minimumTicks = 2,
  });

  final List<LiveLevelReading> _recent = [];

  /// Feeds one new tick. Any tick that is not [LiveLevelStatus.good] clears
  /// the tracked history — stability must be CONTINUOUS, not cumulative.
  ///
  /// P0 real-hardware root cause (confirmed via [LIVE-LEVEL-P0] trace, not
  /// a guess): this used to also trim [_recent] down to a rolling
  /// [stabilityWindow]-wide tail here (`removeWhere` against
  /// `reading.at.subtract(stabilityWindow)`). That trim is structurally
  /// self-defeating: after trimming, the oldest retained tick's timestamp
  /// is by construction >= (latest - stabilityWindow), which caps
  /// `span = last.at - first.at` at <= stabilityWindow FOREVER — it can
  /// only ever equal stabilityWindow if a tick's timestamp lands on the
  /// exact millisecond of the cutoff, which real (jittery, ~160-200ms
  /// interval) polling essentially never does. The real trace showed
  /// exactly this: trackedDuration climbing to 999ms repeatedly and never
  /// reaching 1000ms, so isStableGood (`span >= stabilityWindow`) was
  /// permanently unreachable. No trimming is needed here at all: [_recent]
  /// is already cleared entirely the instant a non-good tick arrives, so
  /// it only ever spans one continuous GOOD run — which is short-lived in
  /// practice since [_confirmLiveLevelPass] (dialog) stops the session
  /// once stability is reached.
  void addTick(LiveLevelReading reading) {
    if (reading.status != LiveLevelStatus.good) {
      _recent.clear();
      return;
    }
    _recent.add(reading);
  }

  /// True once the tracked GOOD run spans at least [stabilityWindow] and
  /// contains at least [minimumTicks] ticks. Resets to false the instant a
  /// non-good tick arrives (enforced via [addTick] clearing history).
  bool get isStableGood {
    if (_recent.length < minimumTicks) return false;
    final span = _recent.last.at.difference(_recent.first.at);
    return span >= stabilityWindow;
  }

  /// Number of ticks currently tracked in the GOOD run — debug/trace use.
  int get trackedTickCount => _recent.length;

  /// The actual wall-clock span covered by the currently-tracked GOOD run —
  /// zero if empty. Read-only summary for evidence-building, not used by
  /// [isStableGood] itself (which compares against [stabilityWindow]
  /// directly).
  Duration get trackedDuration => _recent.isEmpty
      ? Duration.zero
      : _recent.last.at.difference(_recent.first.at);

  /// The most recent tracked reading's own dBFS — used as the representative
  /// ("RMS-like") value for live-sourced evidence. Null if nothing tracked.
  double? get latestDbFs => _recent.isEmpty ? null : _recent.last.currentDbFs;

  /// The highest dBFS observed across the tracked GOOD run — used as the
  /// representative "peak-like" value for live-sourced evidence. This is
  /// NOT a true sample peak (see this file's header comment on
  /// Amplitude.max) — just the max of the same average-power readings
  /// classifyLiveLevel already uses. Null if nothing tracked.
  double? get peakDbFsInWindow {
    if (_recent.isEmpty) return null;
    var peak = _recent.first.currentDbFs;
    for (final r in _recent) {
      if (r.currentDbFs > peak) peak = r.currentDbFs;
    }
    return peak;
  }

  void reset() => _recent.clear();
}
