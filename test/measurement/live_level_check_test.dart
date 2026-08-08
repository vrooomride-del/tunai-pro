// Measurement Setup Live Level Check — pure classifier + stability tracker.
// No recorder/player involved; see mic_measurement_live_level_check_test.dart
// for the controller-level lifecycle/exclusivity tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/measurement/live_level_check.dart';
import 'package:tunai_pro/core/measurement/measurement_quality_policy.dart';

void main() {
  final policy = MeasurementQualityPolicy.proProvisional();
  // proProvisional(): minimumSignalRmsDbFs = -40.0, maximumSignalRmsDbFs = -6.0

  group('classifyLiveLevel — reuses existing WAV-based-check thresholds', () {
    test('well below minimum -> tooLow', () {
      expect(classifyLiveLevel(-60.0, policy), LiveLevelStatus.tooLow);
    });

    test('exactly at the minimum boundary -> good (not tooLow)', () {
      expect(classifyLiveLevel(-40.0, policy), LiveLevelStatus.good);
    });

    test('just below the minimum boundary -> tooLow', () {
      expect(classifyLiveLevel(-40.01, policy), LiveLevelStatus.tooLow);
    });

    test('a normal mid-range value -> good', () {
      expect(classifyLiveLevel(-20.0, policy), LiveLevelStatus.good);
    });

    test('exactly at the maximum boundary -> good (not tooHigh)', () {
      expect(classifyLiveLevel(-6.0, policy), LiveLevelStatus.good);
    });

    test('just above the maximum boundary -> tooHigh', () {
      expect(classifyLiveLevel(-5.99, policy), LiveLevelStatus.tooHigh);
    });

    test('well above maximum -> tooHigh', () {
      expect(classifyLiveLevel(0.0, policy), LiveLevelStatus.tooHigh);
    });

    test('uses the policy instance passed in, not a hardcoded constant', () {
      const custom = MeasurementQualityPolicy(
        expectedSampleRate: 48000,
        expectedChannelCount: 1,
        minimumCaptureDuration: Duration(seconds: 1),
        clippingAmplitudeThreshold: 0.98,
        clippingSampleCountThreshold: 10,
        clippingRatioThreshold: 0.0001,
        minimumSignalRmsDbFs: -30.0,
        maximumSignalRmsDbFs: -10.0,
        maximumNoiseFloorDbFs: -50.0,
        minimumSignalToNoiseDb: 20.0,
        silenceCaptureDuration: Duration(seconds: 3),
        levelCheckDuration: Duration(seconds: 3),
        setupCheckValidity: Duration(minutes: 30),
        version: 'test-custom',
      );
      // -35dBFS is tooLow under the custom policy's -30 floor even though
      // it would be "good" under proProvisional()'s -40 floor.
      expect(classifyLiveLevel(-35.0, custom), LiveLevelStatus.tooLow);
      expect(classifyLiveLevel(-35.0, policy), LiveLevelStatus.good);
    });
  });

  group('LiveLevelStabilityTracker — sustained-GOOD-only PASS gate', () {
    LiveLevelReading reading(LiveLevelStatus status, DateTime at) =>
        LiveLevelReading(currentDbFs: -20.0, status: status, at: at);

    test('a single GOOD tick is never stable (below minimumTicks)', () {
      final tracker = LiveLevelStabilityTracker();
      final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);
      tracker.addTick(reading(LiveLevelStatus.good, t0));
      expect(tracker.isStableGood, isFalse);
    });

    test(
        'two GOOD ticks spanning less than the stability window are not '
        'stable yet', () {
      final tracker = LiveLevelStabilityTracker(
          stabilityWindow: const Duration(seconds: 1));
      final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);
      tracker.addTick(reading(LiveLevelStatus.good, t0));
      tracker.addTick(
          reading(LiveLevelStatus.good, t0.add(const Duration(milliseconds: 400))));
      expect(tracker.isStableGood, isFalse);
    });

    test(
        'a sustained GOOD run spanning the full stability window with '
        'enough ticks IS stable', () {
      final tracker = LiveLevelStabilityTracker(
          stabilityWindow: const Duration(seconds: 1), minimumTicks: 2);
      final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);
      tracker.addTick(reading(LiveLevelStatus.good, t0));
      tracker.addTick(
          reading(LiveLevelStatus.good, t0.add(const Duration(milliseconds: 500))));
      tracker.addTick(
          reading(LiveLevelStatus.good, t0.add(const Duration(milliseconds: 1000))));
      expect(tracker.isStableGood, isTrue);
    });

    test(
        'GOOD followed by a single TOO HIGH tick resets stability — never '
        'stable immediately after', () {
      final tracker = LiveLevelStabilityTracker(
          stabilityWindow: const Duration(seconds: 1), minimumTicks: 2);
      final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);
      tracker.addTick(reading(LiveLevelStatus.good, t0));
      tracker.addTick(
          reading(LiveLevelStatus.good, t0.add(const Duration(milliseconds: 500))));
      tracker.addTick(
          reading(LiveLevelStatus.good, t0.add(const Duration(milliseconds: 1000))));
      expect(tracker.isStableGood, isTrue, reason: 'sanity: it was stable');

      tracker.addTick(
          reading(LiveLevelStatus.tooHigh, t0.add(const Duration(milliseconds: 1100))));
      expect(tracker.isStableGood, isFalse,
          reason: 'a single non-good tick must reset the run entirely');
    });

    test('after a reset, a fresh sustained GOOD run becomes stable again',
        () {
      final tracker = LiveLevelStabilityTracker(
          stabilityWindow: const Duration(seconds: 1), minimumTicks: 2);
      final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);
      tracker.addTick(reading(LiveLevelStatus.tooLow, t0));
      expect(tracker.isStableGood, isFalse);

      final t1 = t0.add(const Duration(seconds: 2));
      tracker.addTick(reading(LiveLevelStatus.good, t1));
      tracker.addTick(
          reading(LiveLevelStatus.good, t1.add(const Duration(milliseconds: 500))));
      tracker.addTick(
          reading(LiveLevelStatus.good, t1.add(const Duration(milliseconds: 1000))));
      expect(tracker.isStableGood, isTrue);
    });

    test(
        'P0 REGRESSION — real-hardware jittery ~165ms polling intervals '
        '(never landing exactly on a window boundary) DOES reach '
        'isStableGood, and trackedDuration can exceed stabilityWindow',
        () {
      // Reproduces the exact real UMIK-1 trace: [LIVE-LEVEL-P0] showed
      // goodRunTicks oscillating 5-6 and goodRunDurationMs climbing to 999
      // but NEVER reaching 1000, so isStableGood was permanently false. Root
      // cause: addTick used to trim _recent down to a rolling
      // stabilityWindow-wide tail, which structurally capped
      // span = last.at - first.at at <= stabilityWindow forever (the
      // trimmed oldest tick's timestamp is always >= latest - window by
      // construction) — real jittery timestamps essentially never land
      // exactly on the cutoff, so the >= comparison in isStableGood was
      // unreachable. This test uses the SAME ~165ms interval pattern the
      // real trace showed and asserts stability IS now reached.
      final tracker = LiveLevelStabilityTracker(
          stabilityWindow: const Duration(seconds: 1), minimumTicks: 2);
      final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);
      const intervalMs = 165;
      var lastStable = false;
      for (var i = 0; i < 7; i++) {
        final at = t0.add(Duration(milliseconds: intervalMs * i));
        tracker.addTick(reading(LiveLevelStatus.good, at));
        lastStable = tracker.isStableGood;
      }
      // 7 ticks at 165ms apart span 990ms — one more tick crosses 1000ms.
      expect(lastStable, isFalse,
          reason: 'sanity: 990ms span should not yet be stable');

      tracker.addTick(
          reading(LiveLevelStatus.good, t0.add(const Duration(milliseconds: 165 * 7))));
      expect(tracker.isStableGood, isTrue,
          reason: 'span is now 1155ms (>= 1000ms stabilityWindow) — this '
              'MUST become stable. Before the fix, the old trim logic made '
              'this permanently false.');
      expect(tracker.trackedDuration.inMilliseconds, greaterThanOrEqualTo(1000));
    });

    test('reset() clears tracked history explicitly', () {
      final tracker = LiveLevelStabilityTracker(
          stabilityWindow: const Duration(seconds: 1), minimumTicks: 2);
      final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);
      tracker.addTick(reading(LiveLevelStatus.good, t0));
      tracker.addTick(
          reading(LiveLevelStatus.good, t0.add(const Duration(seconds: 1))));
      expect(tracker.isStableGood, isTrue);

      tracker.reset();
      expect(tracker.isStableGood, isFalse);
    });
  });

  group('LiveLevelStabilityTracker — evidence-building accessors', () {
    LiveLevelReading readingAt(double dbFs, DateTime at) => LiveLevelReading(
        currentDbFs: dbFs, status: LiveLevelStatus.good, at: at);

    test('latestDbFs / peakDbFsInWindow / trackedDuration are null/zero '
        'before anything is tracked', () {
      final tracker = LiveLevelStabilityTracker();
      expect(tracker.latestDbFs, isNull);
      expect(tracker.peakDbFsInWindow, isNull);
      expect(tracker.trackedDuration, Duration.zero);
    });

    test('latestDbFs is the most recent tick, peakDbFsInWindow is the max '
        'observed, trackedDuration spans first-to-last', () {
      final tracker = LiveLevelStabilityTracker(
          stabilityWindow: const Duration(seconds: 1), minimumTicks: 2);
      final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);
      tracker.addTick(readingAt(-25.0, t0));
      tracker.addTick(readingAt(-15.0, t0.add(const Duration(milliseconds: 500))));
      tracker.addTick(readingAt(-30.0, t0.add(const Duration(milliseconds: 1000))));

      expect(tracker.isStableGood, isTrue);
      expect(tracker.latestDbFs, -30.0,
          reason: 'representative value is the most recent tick');
      expect(tracker.peakDbFsInWindow, -15.0,
          reason: 'peak-like value is the max observed in the window');
      expect(tracker.trackedDuration, const Duration(milliseconds: 1000));
    });

    test('a non-good tick clears these accessors too (same reset as '
        'isStableGood)', () {
      final tracker = LiveLevelStabilityTracker();
      final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);
      tracker.addTick(readingAt(-20.0, t0));
      expect(tracker.latestDbFs, isNotNull);

      tracker.addTick(LiveLevelReading(
          currentDbFs: -20.0,
          status: LiveLevelStatus.tooHigh,
          at: t0.add(const Duration(milliseconds: 100))));
      expect(tracker.latestDbFs, isNull);
      expect(tracker.peakDbFsInWindow, isNull);
      expect(tracker.trackedDuration, Duration.zero);
    });
  });
}
