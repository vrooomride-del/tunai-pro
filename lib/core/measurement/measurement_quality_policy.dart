// ── TUNAI PRO Phase 3-D1 — measurement quality policy ───────────────────────
//
// Every quality-related threshold used across setup-check/noise-floor/
// level-check lives here, not scattered as magic numbers in a controller or
// widget. All values below are PROVISIONAL ENGINEERING DEFAULTS — chosen
// from general digital-audio-measurement conventions, not from bench testing
// against this app's actual hardware chain. They are namespaced behind this
// one immutable policy object specifically so they can be revised after real
// Mac hardware testing without touching call sites — see each field's doc
// comment for the specific rationale and expected revision trigger.
library;

class MeasurementQualityPolicy {
  /// The sample rate every capture in this app requests today
  /// (MicMeasurementController.sampleRate). A mismatch between this and a
  /// recording's actual WAV metadata means the OS silently used a different
  /// rate than requested.
  final int expectedSampleRate;

  /// Mono (1) for Factory single-channel capture. Room's stereo captures
  /// use their own generator/consumer pair and are not evaluated through
  /// this single expected value at the setup-check level.
  final int expectedChannelCount;

  /// Below this, a capture is rejected outright as too short to produce a
  /// meaningful RMS/peak read — provisional: 1 second is comfortably more
  /// than one full pink-noise cycle's statistical settling time at any
  /// reasonable sample rate, but has not been tuned against real capture
  /// jitter.
  final Duration minimumCaptureDuration;

  /// Passed straight through to MeasurementPcmQualityAnalyzer — see
  /// kMeasurementClippingAmplitudeThreshold's own doc comment for why 0.98
  /// rather than exactly 1.0.
  final double clippingAmplitudeThreshold;

  /// A capture is flagged "clipping" if EITHER this many samples clip...
  final int clippingSampleCountThreshold;

  /// ...OR this fraction of all samples clip, whichever is more sensitive
  /// for the given capture length. Provisional: even a handful of true
  /// full-scale samples indicates a level problem worth flagging before any
  /// ratio would cross a percentage threshold on a multi-second capture.
  final double clippingRatioThreshold;

  /// Signal RMS below this during a level-check test signal likely means
  /// the mic/interface gain is too low for a usable SNR against typical
  /// room noise floors. Provisional: -40 dBFS RMS leaves ~15-20 dB of
  /// headroom below a typical -20 to -25 dBFS "good" pink-noise capture
  /// level, generous enough not to false-positive on a slightly quiet
  /// setup while still catching a clearly under-driven input.
  final double minimumSignalRmsDbFs;

  /// Signal RMS above this during a level-check likely means the input is
  /// overdriven even without hard full-scale clipping (soft clipping,
  /// analog front-end distortion). Provisional: -6 dBFS RMS is close
  /// enough to full scale that sustained pink noise at that level is
  /// almost certainly too hot for a clean capture.
  final double maximumSignalRmsDbFs;

  /// Noise-floor RMS above this means the room/input chain is too noisy
  /// for the eventual FRD capture to be trustworthy at low levels.
  /// Provisional: -50 dBFS is a generously permissive "quiet enough" bar
  /// for a live room (not a treated/anechoic space) — likely to be
  /// tightened after bench comparison against real room recordings.
  final double maximumNoiseFloorDbFs;

  /// Minimum acceptable (signal RMS − noise-floor RMS) in dB. Provisional:
  /// 20 dB SNR is a conservative floor below which small-signal frequency
  /// response detail becomes noise-dominated.
  final double minimumSignalToNoiseDb;

  /// How long the noise-floor (silence) capture runs.
  final Duration silenceCaptureDuration;

  /// How long the level-check (test-signal) capture runs — deliberately
  /// shorter than a full FRD capture (10s) since this only needs enough
  /// data for a stable RMS/peak read, not full frequency resolution.
  final Duration levelCheckDuration;

  /// How long a successful Guided Setup check remains usable before it must
  /// be re-run. Provisional: 30 minutes is long enough to cover a full
  /// Factory 4-channel or Room 2-side session without re-checking between
  /// every capture, short enough that a stale environment (mic unplugged
  /// and replugged, room conditions changed) doesn't stay silently trusted
  /// for an entire work session.
  final Duration setupCheckValidity;

  /// Identifies which version of this policy's thresholds produced a given
  /// readiness snapshot — bumping this whenever thresholds change lets
  /// MeasurementSetupReadinessIdentity invalidate old snapshots computed
  /// under different (now-stale) rules.
  final String version;

  const MeasurementQualityPolicy({
    required this.expectedSampleRate,
    required this.expectedChannelCount,
    required this.minimumCaptureDuration,
    required this.clippingAmplitudeThreshold,
    required this.clippingSampleCountThreshold,
    required this.clippingRatioThreshold,
    required this.minimumSignalRmsDbFs,
    required this.maximumSignalRmsDbFs,
    required this.maximumNoiseFloorDbFs,
    required this.minimumSignalToNoiseDb,
    required this.silenceCaptureDuration,
    required this.levelCheckDuration,
    required this.setupCheckValidity,
    required this.version,
  });

  /// The provisional defaults described above. Named `proProvisional()` to
  /// match the existing convention in
  /// core/acoustic/measurement_confidence.dart
  /// (MeasurementConfidencePolicy.proProvisional()) — the same "not yet
  /// bench-validated" signal.
  factory MeasurementQualityPolicy.proProvisional() =>
      const MeasurementQualityPolicy(
        expectedSampleRate: 48000,
        expectedChannelCount: 1,
        minimumCaptureDuration: Duration(seconds: 1),
        clippingAmplitudeThreshold: 0.98,
        clippingSampleCountThreshold: 10,
        clippingRatioThreshold: 0.0001,
        minimumSignalRmsDbFs: -40.0,
        maximumSignalRmsDbFs: -6.0,
        maximumNoiseFloorDbFs: -50.0,
        minimumSignalToNoiseDb: 20.0,
        silenceCaptureDuration: Duration(seconds: 3),
        levelCheckDuration: Duration(seconds: 3),
        setupCheckValidity: Duration(minutes: 30),
        version: 'provisional-1',
      );
}
