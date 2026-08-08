// Phase 2 — Room Auto PEQ.
//
// A separate, deterministic-only correction path for the Stereo Room
// Measurement flow. Reuses the EXACT SAME acoustic engine primitives the
// Factory Guided AI path uses — AcousticProblemClassifier, CorrectionPlanner,
// CandidateGenerator, CandidateScorer, CandidateOptimizer,
// AcousticSelectionValidator (CandidateSafetyPolicy), AcousticApplyEngine —
// called directly rather than through ProLocalOrchestrator's cloud/plan
// machinery, which is hardwired to
// ProGuidedAiController.requiredFullSystemChannelIds (the 4 Factory driver
// channels). No independent parallel PEQ engine is created; every step below
// is an existing, already-tested pure function.
//
// Scope, per Phase 2 spec:
//   - cut-only (CandidatePolicy.adau1701Icp5(): maxCutDb=6.0, never boosts)
//   - correction restricted to the verified low-end range only (20-300 Hz)
//   - Left System candidates -> ch_wf_l PEQ only; Right -> ch_wf_r PEQ only
//   - Tweeter PEQ, XO, phase, delay are never touched
//   - zero hardware writes before explicit user approval
//
// Deliberately Left-only / Right-only, never simultaneous L+R: playing both
// sides together introduces position/distance/phase-dependent comb filtering
// at the mic, and a comb-filtered capture cannot attribute a given notch to
// the Left system, the Right system, or their interaction — unusable as an
// Auto PEQ correction basis. Do not change this to a 4-channel or per-band
// (Tweeter L+R / Mid L+R / Woofer L+R) simultaneous capture scheme.
//
// ── P2 (not implemented here): Stereo Final Verification ──────────────────
// A DISTINCT, future, evaluation-only capability, explicitly out of scope
// for this file and for the P0/P1 safety work it belongs to:
//   - captured with Left+Right both playing together, AFTER Room correction
//     has already been deployed
//   - purpose: center image, combined low-end, overall tonal balance, and a
//     final Before/After report — human-facing evaluation only
//   - NEVER an input to Auto PEQ candidate generation and NEVER a source for
//     any DSP write — the comb-filtering problem above applies to it just
//     as much as it would to using L+R-together as a correction basis
//   - has no data model, controller, or UI yet; do not build ad hoc pieces
//     of it while working on adjacent Room code — track it as one deliberate
//     future addition instead

import '../acoustic/acoustic_classification_policy.dart';
import '../acoustic/acoustic_problem_classifier.dart';
import '../acoustic/acoustic_apply_engine.dart';
import '../acoustic/candidate_optimizer.dart';
import '../acoustic/candidate_safety.dart';
import '../acoustic/candidate_scoring.dart';
import '../acoustic/candidate_set.dart';
import '../acoustic/correction_plan.dart';
import '../acoustic/correction_policy.dart';
import '../acoustic/measurement_confidence.dart';
import '../acoustic/measurement_evidence.dart'
    show MeasurementDomain, MeasurementSource;
import '../deploy/pro_hardware_capability.dart';
import '../deploy/pro_hardware_write_plan.dart';
import '../pro_export_data.dart';
import '../pro_tuning_data.dart';
import '../room_measurement_data.dart';

/// Verified low-end correction band for v1 Room bass correction. Chosen to
/// cover typical woofer passband below a 2-way crossover point without
/// reaching into the tweeter's range.
const double roomAutoPeqMinHz = 20.0;
const double roomAutoPeqMaxHz = 300.0;

String roomWooferChannelId(RoomSystemSide side) =>
    side == RoomSystemSide.left ? 'ch_wf_l' : 'ch_wf_r';

/// One side's full candidate-to-apply-result pipeline output. Not yet
/// written anywhere — the caller decides whether to present it for approval.
class RoomAutoPeqCandidate {
  final RoomSystemSide side;
  final String channelId;
  final AcousticClassificationResult classification;
  final CandidateSafetyResult safety;
  final TuningApplyResult applyResult;

  const RoomAutoPeqCandidate({
    required this.side,
    required this.channelId,
    required this.classification,
    required this.safety,
    required this.applyResult,
  });

  /// True when this side actually produced an appliable, safety-verified
  /// change (i.e. not blocked, not empty).
  bool get hasChange =>
      safety.applyPermitted &&
      applyResult.status == TuningApplyStatus.ok &&
      applyResult.applied.isNotEmpty;
}

abstract final class RoomAutoPeq {
  /// Readiness mirrors ProGuidedAiController.frdReadiness()'s contract for
  /// the Factory path: readiness is Before Left+Right = 2/2, entirely
  /// independent of driverChannels[i].hasParsedFrd.
  static bool isReady(RoomMeasurementSnapshot before) => before.isComplete;

  /// Runs the full classify -> plan -> generate -> score -> optimize ->
  /// validate -> apply pipeline for one side's Before measurement, targeting
  /// that side's Woofer PEQ channel only. Returns null when classification
  /// itself could not run (invalid measurement) — never a fabricated result.
  static RoomAutoPeqCandidate? generateForSide({
    required RoomSystemSide side,
    required RoomSystemMeasurement beforeMeasurement,
    required PeqChannelState currentWooferChannel,
  }) {
    final points = beforeMeasurement.frd.points;
    final freqs = [for (final p in points) p.frequencyHz];
    final mags = [for (final p in points) p.magnitudeDb ?? double.nan];
    if (freqs.isEmpty) return null;

    final target = List<double>.filled(freqs.length, 0.0);

    final confidencePolicy = MeasurementConfidencePolicy.proProvisional();
    final confidence = MeasurementConfidenceEngine.evaluate(
      MeasurementConfidenceMetrics(
        frequencies: freqs,
        spectraDb: [mags],
        minBandHz: 20.0,
        maxBandHz: 20000.0,
      ),
      confidencePolicy,
    );
    if (confidence.status == ConfidenceStatus.invalid) return null;

    final classification = AcousticProblemClassifier.classify(
      AcousticClassificationInput(
        frequenciesHz: freqs,
        measuredMagnitudeDb: mags,
        targetMagnitudeDb: target,
        measurementConfidence: confidence,
        measurementSource: MeasurementSource.liveMicrophone,
        measurementDomain: MeasurementDomain.acousticResponse,
        evidenceRefs: [beforeMeasurement.frd.id],
      ),
      AcousticClassificationPolicy.proProvisional(),
    );
    if (classification.status ==
        AcousticClassificationStatus.invalidMeasurement) {
      return null;
    }

    final channelId = roomWooferChannelId(side);
    final plan = CorrectionPlanner.plan(
      classification,
      CorrectionPolicy.proProvisional(),
    );
    final candidateSet = CandidateGenerator.generate(
      plan,
      classification,
      CandidatePolicy.adau1701Icp5(),
      correctionRange: CandidateCorrectionRange(
        channelId: channelId,
        minFrequencyHz: roomAutoPeqMinHz,
        maxFrequencyHz: roomAutoPeqMaxHz,
      ),
    );
    final scored = CandidateScorer.score(
      candidateSet,
      classification,
      ScoringPolicy.proProvisional(),
    );
    final selection = CandidateOptimizer.select(
      scored,
      OptimizerPolicy.proProvisional(),
    );
    final safety = AcousticSelectionValidator.validate(
      selection,
      CandidateSafetyPolicy.adau1701Icp5(),
    );
    // Room Auto PEQ is ADAU1701-only (see module header) — new automatic
    // candidates must never land on Band 9/10, which have no write-verified
    // hardware evidence. Pre-existing project bands there are left untouched.
    final applyResult = AcousticApplyEngine.apply(
      safety,
      currentWooferChannel,
      maxSlotCount: HardwareDeviceProfiles.adau1701Icp5
          .maxWriteVerifiedPeqBandCount(HardwareParamKind.peqGain),
    );

    return RoomAutoPeqCandidate(
      side: side,
      channelId: channelId,
      classification: classification,
      safety: safety,
      applyResult: applyResult,
    );
  }

  /// Builds a single [DspExportPackage] (and derived [HardwareWritePlan])
  /// covering every side in [candidates] that actually has a change — PEQ
  /// blocks only, one per side's Woofer channel. Never includes XO/gain/
  /// delay/tweeter blocks. Returns null when no side has an applicable
  /// change (nothing to write).
  ///
  /// [packageId] must be unique per approval (the caller mints a fresh id
  /// each time — see RoomAutoPeqController.approve()), never a fixed
  /// per-project constant: the After-mode hardware gate (RoomAfterGate)
  /// matches on this exact id to reject a stale result from an earlier,
  /// superseded Room correction — a fixed id would make every generation
  /// indistinguishable from the last.
  ///
  /// Zero hardware writes happen here — this only builds the plan object;
  /// the caller is responsible for routing it through the same
  /// approve-then-apply flow (HardwareApplyFlow / HardwareWriteExecutor)
  /// Deploy tab already uses for the Factory path.
  static (DspExportPackage, HardwareWritePlan)? buildWritePlan({
    required String projectId,
    required String packageId,
    required List<RoomAutoPeqCandidate> candidates,
  }) {
    final blocks = <ExportParameterBlock>[];
    for (final candidate in candidates) {
      if (!candidate.hasChange) continue;
      final bands = <String, dynamic>{};
      final normalized = candidate.applyResult.updatedChannel.normalized();
      for (var i = 0; i < normalized.bands.length; i++) {
        final band = normalized.bands[i];
        if (!band.enabled) continue;
        bands['band_$i'] = {
          'freq_hz': band.frequencyHz,
          'gain_db': band.gainDb,
          'q': band.q,
          'type': band.type.name,
        };
      }
      if (bands.isEmpty) continue;
      blocks.add(ExportParameterBlock(
        id: 'room-${candidate.channelId}-peq',
        type: ExportBlockType.peq,
        channelId: candidate.channelId,
        title: 'Room Auto PEQ ${candidate.side.label} Woofer',
        summary: 'Stereo Room bass correction (cut-only, '
            '${roomAutoPeqMinHz.toStringAsFixed(0)}-'
            '${roomAutoPeqMaxHz.toStringAsFixed(0)} Hz)',
        parameters: {'bands': bands},
      ));
    }
    if (blocks.isEmpty) return null;

    final package = DspExportPackage(
      id: packageId,
      targetPlatform: DspTargetPlatform.adau1701,
      format: ExportFormat.hardwareWritePlanPlaceholder,
      status: ExportStatus.draftReady,
      projectName: projectId,
      parameterBlocks: blocks,
      notes: 'Generated from confirmed Stereo Room Auto PEQ (Left/Right '
          'Woofer, bass-only, cut-only).',
    );
    return (
      package,
      buildHardwareWritePlan(package, HardwareDeviceProfiles.adau1701Icp5)
    );
  }

  /// Builds a rollback [DspExportPackage]/[HardwareWritePlan] that restores
  /// exactly the Woofer PEQ slots Room Auto PEQ newly filled back to their
  /// pre-apply state, from [preApplySnapshot] (the project's full
  /// [TuningProjectState] captured at approval time — see
  /// RoomAutoPeqController.approve()). No other tuning value (XO/gain/delay/
  /// mute/phase, or any other PEQ slot) is touched, because Room Auto PEQ
  /// never touched them either.
  ///
  /// This codebase's export-block format has no explicit "disable this
  /// slot" instruction (a PEQ block only ever declares bands to WRITE, never
  /// bands to clear — see buildHardwareWritePlan's ExportBlockType.peq
  /// handling, which just omits absent band indices). Since AcousticApplyEngine
  /// only ever fills a previously-FREE slot (fillNextFreeSlot), reverting
  /// means explicitly writing gainDb: 0 (acoustically flat — indistinguishable
  /// from "disabled") back to exactly the slot indices Room newly occupied.
  /// If a snapshot slot was already enabled with different values (defensive
  /// — not the current AcousticApplyEngine behavior, but not assumed away
  /// either), that slot's exact pre-apply freq/gain/Q is restored instead.
  ///
  /// Returns null when there is nothing to revert (no candidate actually
  /// wrote a new slot). Zero hardware writes happen here.
  static (DspExportPackage, HardwareWritePlan)? buildRollbackPlan({
    required String projectId,
    required String packageId,
    required List<RoomAutoPeqCandidate> approvedCandidates,
    required TuningProjectState preApplySnapshot,
  }) {
    final blocks = <ExportParameterBlock>[];
    for (final candidate in approvedCandidates) {
      if (!candidate.hasChange) continue;
      final channelId = candidate.channelId;
      final postApply = candidate.applyResult.updatedChannel.normalized();
      final preApply = (preApplySnapshot.peqChannels
                  .where((c) => c.channelId == channelId)
                  .firstOrNull ??
              PeqChannelState.fixed(channelId))
          .normalized();

      final bands = <String, dynamic>{};
      for (var i = 0; i < postApply.bands.length; i++) {
        final after = postApply.bands[i];
        if (!after.enabled) continue;
        final before = i < preApply.bands.length ? preApply.bands[i] : null;
        if (before == null || !before.enabled) {
          // Room newly filled this previously-free slot — revert to
          // acoustically flat (0 dB), the closest representable equivalent
          // to "this slot was disabled".
          bands['band_$i'] = {
            'freq_hz': after.frequencyHz,
            'gain_db': 0.0,
            'q': after.q,
            'type': after.type.name,
          };
        } else if (before.frequencyHz != after.frequencyHz ||
            before.gainDb != after.gainDb ||
            before.q != after.q) {
          // Defensive: slot was already occupied pre-apply with different
          // values. Restore its exact prior values.
          bands['band_$i'] = {
            'freq_hz': before.frequencyHz,
            'gain_db': before.gainDb,
            'q': before.q,
            'type': before.type.name,
          };
        }
      }
      if (bands.isEmpty) continue;
      blocks.add(ExportParameterBlock(
        id: 'room-rollback-$channelId',
        type: ExportBlockType.peq,
        channelId: channelId,
        title: 'Room Auto PEQ Rollback — ${candidate.side.label} Woofer',
        summary: 'Restore pre-apply PEQ state (worsened verdict)',
        parameters: {'bands': bands},
      ));
    }
    if (blocks.isEmpty) return null;

    final package = DspExportPackage(
      id: packageId,
      targetPlatform: DspTargetPlatform.adau1701,
      format: ExportFormat.hardwareWritePlanPlaceholder,
      status: ExportStatus.draftReady,
      projectName: projectId,
      parameterBlocks: blocks,
      notes: 'Room Auto PEQ rollback — restores Left/Right Woofer PEQ to the '
          'pre-apply snapshot; no other tuning value touched.',
    );
    return (
      package,
      buildHardwareWritePlan(package, HardwareDeviceProfiles.adau1701Icp5)
    );
  }
}
