import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/candidate_set.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_plan.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_types.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/acoustic_classify_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/candidate_generation_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/correction_plan_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/frd_grid_aligner.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/measurement_analyze_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_artifact_store.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_execution.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_reference_resolver.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_registry.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';

// ── FRD fixtures ──────────────────────────────────────────────────────────────

/// 10 points — classifies ok → plan ok → candidates generated.
const _frd10 = '100 -5.0 0\n'
    '200 -3.0 0\n'
    '400 -8.0 0\n'
    '800 -1.5 0\n'
    '1000 -1.0 0\n'
    '2000 -0.5 0\n'
    '4000 -2.0 0\n'
    '8000 -3.0 0\n'
    '12000 -4.0 0\n'
    '16000 -5.0 0';

/// 3 points — insufficientEvidence propagates through to CandidateSetStatus.
const _frd3 = '100 -3.0 0\n200 -2.0 0\n400 -1.0 0';

// ── Helpers ───────────────────────────────────────────────────────────────────

const _project = 'p1';

ProToolExecutionContext _ctx(
        ProToolReferenceResolver resolver, ProToolArtifactStore store) =>
    ProToolExecutionContext(
      projectId: _project,
      contextRef: 'ctx:1',
      resolver: resolver,
      store: store,
    );

ProOrchestratorStep _step(
  String toolId,
  List<String> inputRefs,
  String outputRef,
) =>
    ProOrchestratorStep(
      stepId: 'step-$toolId',
      toolId: ProOrchestratorToolId.values.firstWhere((e) => e.name == toolId),
      objective: 'test $toolId',
      inputRefs: inputRefs,
      outputRef: outputRef,
      requiresUserConfirmation: false,
    );

/// Full chain: measurementAnalyze → acousticClassify → acousticPlan →
/// acousticGenerateCandidates.
///
/// Returns the store for artifact inspection.
/// The classification artifact is stored at `class:1` so callers can pass
/// it as second inputRef to the generation step.
ProToolArtifactStore _chain(String frdContent, String candsRef) {
  final resolver = InMemoryProToolReferenceResolver();
  final store = ProToolArtifactStore();
  final ctx = _ctx(resolver, store);

  resolver.put(
    _project,
    'src:frd',
    ProMeasurementSource(
      fileName: 'test.frd',
      content: frdContent,
      format: AcousticFileType.frd,
    ),
  );

  const MeasurementAnalyzeAdapter()
      .run(ctx, _step('measurementAnalyze', ['src:frd'], 'meas:1'));
  const AcousticClassifyAdapter()
      .run(ctx, _step('acousticClassify', ['meas:1'], 'class:1'));
  const CorrectionPlanAdapter()
      .run(ctx, _step('acousticPlan', ['class:1'], 'plan:1'));
  const CandidateGenerationAdapter().run(ctx,
      _step('acousticGenerateCandidates', ['plan:1', 'class:1'], candsRef));

  return store;
}

void main() {
  const gen = CandidateGenerationAdapter();

  // ── Tool identity ─────────────────────────────────────────────────────────

  test('toolId is acousticGenerateCandidates', () {
    expect(gen.toolId, ProOrchestratorToolId.acousticGenerateCandidates);
  });

  test(
      'acousticGenerateCandidates can be registered in ProDeterministicToolRegistry',
      () {
    expect(
      () => ProDeterministicToolRegistry([gen]),
      returnsNormally,
    );
  });

  // ── Full chain ────────────────────────────────────────────────────────────

  group('full chain', () {
    test('10-point FRD → CandidateSetArtifact stored', () {
      final store = _chain(_frd10, 'cands:1');
      expect(store.has(_project, 'cands:1'), isTrue);
      expect(
        () => store.getTyped<CandidateSetArtifact>(_project, 'cands:1'),
        returnsNormally,
      );
    });

    test('10-point FRD → status in {ok, noCorrectableDirectives}', () {
      final store = _chain(_frd10, 'cands:1');
      final art = store.getTyped<CandidateSetArtifact>(_project, 'cands:1');
      expect(
        [CandidateSetStatus.ok, CandidateSetStatus.noCorrectableDirectives],
        contains(art.value.status),
      );
    });

    test('3-point FRD → status = insufficientEvidence', () {
      final store = _chain(_frd3, 'cands:1');
      final art = store.getTyped<CandidateSetArtifact>(_project, 'cands:1');
      expect(art.value.status, CandidateSetStatus.insufficientEvidence);
    });

    test('3-point FRD → candidates list is empty', () {
      final store = _chain(_frd3, 'cands:1');
      final art = store.getTyped<CandidateSetArtifact>(_project, 'cands:1');
      expect(art.value.candidates, isEmpty);
    });

    test('policyId is pro_provisional', () {
      final store = _chain(_frd10, 'cands:1');
      final art = store.getTyped<CandidateSetArtifact>(_project, 'cands:1');
      expect(art.value.policyId, 'pro_provisional');
    });

    test('evidenceRefs propagated', () {
      final store = _chain(_frd10, 'cands:1');
      final art = store.getTyped<CandidateSetArtifact>(_project, 'cands:1');
      expect(art.value.evidenceRefs, isNotEmpty);
    });

    test('result reference carries correct toolId and outputRef', () {
      final resolver = InMemoryProToolReferenceResolver();
      final store = ProToolArtifactStore();
      final ctx = _ctx(resolver, store);
      resolver.put(
          _project,
          'src:frd',
          const ProMeasurementSource(
              fileName: 'f.frd',
              content: _frd10,
              format: AcousticFileType.frd));
      const MeasurementAnalyzeAdapter()
          .run(ctx, _step('measurementAnalyze', ['src:frd'], 'meas:1'));
      const AcousticClassifyAdapter()
          .run(ctx, _step('acousticClassify', ['meas:1'], 'class:1'));
      const CorrectionPlanAdapter()
          .run(ctx, _step('acousticPlan', ['class:1'], 'plan:1'));

      final result = gen.run(
          ctx,
          _step('acousticGenerateCandidates', ['plan:1', 'class:1'],
              'cands:out'));
      expect(result.toolId, ProOrchestratorToolId.acousticGenerateCandidates);
      expect(result.outputRef, 'cands:out');
    });

    test('result summary contains candidate count and status', () {
      final resolver = InMemoryProToolReferenceResolver();
      final store = ProToolArtifactStore();
      final ctx = _ctx(resolver, store);
      resolver.put(
          _project,
          'src:frd',
          const ProMeasurementSource(
              fileName: 'f.frd',
              content: _frd10,
              format: AcousticFileType.frd));
      const MeasurementAnalyzeAdapter()
          .run(ctx, _step('measurementAnalyze', ['src:frd'], 'meas:1'));
      const AcousticClassifyAdapter()
          .run(ctx, _step('acousticClassify', ['meas:1'], 'class:1'));
      const CorrectionPlanAdapter()
          .run(ctx, _step('acousticPlan', ['class:1'], 'plan:1'));

      final result = gen.run(
          ctx,
          _step(
              'acousticGenerateCandidates', ['plan:1', 'class:1'], 'cands:1'));
      expect(result.summary, contains('status='));
    });
  });

  // ── Tool confidence ───────────────────────────────────────────────────────

  group('tool confidence', () {
    test('insufficientEvidence → low confidence', () {
      final resolver = InMemoryProToolReferenceResolver();
      final store = ProToolArtifactStore();
      final ctx = _ctx(resolver, store);
      resolver.put(
          _project,
          'src:frd',
          const ProMeasurementSource(
              fileName: 'f.frd', content: _frd3, format: AcousticFileType.frd));
      const MeasurementAnalyzeAdapter()
          .run(ctx, _step('measurementAnalyze', ['src:frd'], 'meas:1'));
      const AcousticClassifyAdapter()
          .run(ctx, _step('acousticClassify', ['meas:1'], 'class:1'));
      const CorrectionPlanAdapter()
          .run(ctx, _step('acousticPlan', ['class:1'], 'plan:1'));

      final result = gen.run(
          ctx,
          _step(
              'acousticGenerateCandidates', ['plan:1', 'class:1'], 'cands:1'));
      expect(result.confidence, ProConfidence.low);
    });
  });

  // ── Input count validation ────────────────────────────────────────────────

  test('single inputRef → missingReference', () {
    final resolver = InMemoryProToolReferenceResolver();
    final store = ProToolArtifactStore();
    final ctx = _ctx(resolver, store);

    expect(
      () => gen.run(
          ctx, _step('acousticGenerateCandidates', ['plan:1'], 'cands:1')),
      throwsA(predicate<ProToolException>(
          (e) => e.code == ProToolFailureCode.missingReference)),
    );
  });

  test('zero inputRefs → missingReference', () {
    final resolver = InMemoryProToolReferenceResolver();
    final store = ProToolArtifactStore();
    final ctx = _ctx(resolver, store);

    expect(
      () => gen.run(ctx, _step('acousticGenerateCandidates', [], 'cands:1')),
      throwsA(predicate<ProToolException>(
          (e) => e.code == ProToolFailureCode.missingReference)),
    );
  });

  // ── Input type validation ─────────────────────────────────────────────────

  test('SimulationArtifact as first input → typeMismatch', () {
    final resolver = InMemoryProToolReferenceResolver();
    final store = ProToolArtifactStore();
    final ctx = _ctx(resolver, store);
    // First ref points to wrong type — typeMismatch before second ref is read.
    store.put(_project, 'sim:1', SimulationArtifact([1.0, 2.0, 3.0]));

    expect(
      () => gen.run(ctx,
          _step('acousticGenerateCandidates', ['sim:1', 'class:1'], 'cands:1')),
      throwsA(predicate<ProToolException>(
          (e) => e.code == ProToolFailureCode.typeMismatch)),
    );
  });

  test('missing plan ref → missingReference', () {
    final resolver = InMemoryProToolReferenceResolver();
    final store = ProToolArtifactStore();
    final ctx = _ctx(resolver, store);

    expect(
      () => gen.run(
          ctx,
          _step('acousticGenerateCandidates', ['no-plan', 'no-class'],
              'cands:1')),
      throwsA(predicate<ProToolException>(
          (e) => e.code == ProToolFailureCode.missingReference)),
    );
  });

  // ── JSON / no DSP fields ──────────────────────────────────────────────────

  group('JSON', () {
    test('CandidateSet.toJson has no DSP forbidden fields', () {
      final store = _chain(_frd10, 'cands:1');
      final j = store
          .getTyped<CandidateSetArtifact>(_project, 'cands:1')
          .value
          .toJson();

      for (final key in [
        'biquad',
        'address',
        'payload',
        'register',
        'coefficients'
      ]) {
        expect(j.containsKey(key), isFalse, reason: 'forbidden key: $key');
      }
    });

    test('CandidateSet.toJson contains status, candidates, policyId', () {
      final store = _chain(_frd10, 'cands:1');
      final j = store
          .getTyped<CandidateSetArtifact>(_project, 'cands:1')
          .value
          .toJson();

      expect(j.containsKey('status'), isTrue);
      expect(j.containsKey('candidates'), isTrue);
      expect(j.containsKey('policyId'), isTrue);
    });

    test(
        'PeqCandidate.toJson contains frequencyHz, gainDb, q (acoustic — not DSP addr)',
        () {
      final store = _chain(_frd10, 'cands:1');
      final cands = store
          .getTyped<CandidateSetArtifact>(_project, 'cands:1')
          .value
          .candidates;
      for (final c in cands) {
        final j = c.toJson();
        expect(j.containsKey('frequencyHz'), isTrue);
        expect(j.containsKey('gainDb'), isTrue);
        expect(j.containsKey('q'), isTrue);
        // No biquad or hardware commands
        expect(j.containsKey('biquad'), isFalse);
        expect(j.containsKey('address'), isFalse);
        expect(j.containsKey('register'), isFalse);
      }
    });
  });

  // ── Pipeline verification: 2-sweep evidence ──────────────────────────────

  // fallingTrend FRD: 11 bins at ~1-octave spacing, exactly -2 dB/oct from
  // 20 Hz to 20 kHz.  Trend features are ALWAYS quality=confident (no
  // minimumBinsPerFeature gate), so the pipeline produces a candidate when
  // measurement confidence is sufficient (≥2 sweeps for repeatability).
  const _frdTrend = '20 0.0 0\n'
      '40 -2.0 0\n'
      '80 -4.0 0\n'
      '160 -6.0 0\n'
      '315 -8.0 0\n'
      '630 -10.0 0\n'
      '1250 -12.0 0\n'
      '2500 -14.0 0\n'
      '5000 -16.0 0\n'
      '10000 -18.0 0\n'
      '20000 -20.0 0';

  group('verification: 2-sweep evidence', () {
    // Supplies spectraDb:[mags, mags] by setting sweepCount=2 on the adapter.
    // Two identical sweeps → repeatability.score=1.0 → grade=excellent →
    // correctableAllowed → fallingTrend (confident) → cautiousBroadCorrection
    // → correctable → candidate generated.
    // Proves the end-to-end pipeline is live; does NOT represent a real
    // multi-sweep session.
    ProToolArtifactStore _chain2(String frdContent, String candsRef) {
      final resolver = InMemoryProToolReferenceResolver();
      final store = ProToolArtifactStore();
      final ctx = _ctx(resolver, store);
      resolver.put(
        _project,
        'src:frd',
        ProMeasurementSource(
            fileName: 'test.frd',
            content: frdContent,
            format: AcousticFileType.frd),
      );
      const MeasurementAnalyzeAdapter(sweepCount: 2)
          .run(ctx, _step('measurementAnalyze', ['src:frd'], 'meas:1'));
      const AcousticClassifyAdapter()
          .run(ctx, _step('acousticClassify', ['meas:1'], 'class:1'));
      const CorrectionPlanAdapter()
          .run(ctx, _step('acousticPlan', ['class:1'], 'plan:1'));
      const CandidateGenerationAdapter().run(ctx,
          _step('acousticGenerateCandidates', ['plan:1', 'class:1'], candsRef));
      return store;
    }

    test('2-sweep trend FRD → CandidateSetStatus.ok', () {
      final store = _chain2(_frdTrend, 'cands:1');
      final cs = store.getTyped<CandidateSetArtifact>(_project, 'cands:1').value;
      expect(cs.status, CandidateSetStatus.ok);
    });

    test('2-sweep trend FRD → candidates non-empty', () {
      final store = _chain2(_frdTrend, 'cands:1');
      final cs = store.getTyped<CandidateSetArtifact>(_project, 'cands:1').value;
      expect(cs.candidates, isNotEmpty);
    });

    test('2-sweep → all candidates have negative gainDb (cut only)', () {
      final store = _chain2(_frdTrend, 'cands:1');
      final cs = store.getTyped<CandidateSetArtifact>(_project, 'cands:1').value;
      for (final c in cs.candidates) {
        expect(c.gainDb, isNegative,
            reason: 'candidate ${c.candidateId} must be a cut');
      }
    });

    test('2-sweep → no DSP-forbidden fields in candidate JSON', () {
      final store = _chain2(_frdTrend, 'cands:1');
      final cs = store.getTyped<CandidateSetArtifact>(_project, 'cands:1').value;
      for (final c in cs.candidates) {
        final j = c.toJson();
        expect(j.containsKey('biquad'), isFalse);
        expect(j.containsKey('address'), isFalse);
        expect(j.containsKey('register'), isFalse);
      }
    });

    test('1-sweep trend FRD → 0 candidates (policy gate); 2-sweep → candidates', () {
      // _chain uses default sweepCount=1 → repeatability unavailable → 0 cands.
      final store1 = _chain(_frdTrend, 'cands:1');
      final store2 = _chain2(_frdTrend, 'cands:1');
      final cs1 = store1.getTyped<CandidateSetArtifact>(_project, 'cands:1').value;
      final cs2 = store2.getTyped<CandidateSetArtifact>(_project, 'cands:1').value;
      expect(cs1.candidates, isEmpty,
          reason: 'single sweep must yield 0 candidates (policy gate)');
      expect(cs2.candidates, isNotEmpty,
          reason: '2-sweep must yield candidates (pipeline verification)');
    });
  });

  // ── Production multi-sweep evidence path (A-E) ───────────────────────────

  // _frdTrend2: same 11-point falling trend as _frdTrend but with ±0.1 dB
  // perturbation so the content hash differs — two independent sweeps.
  // Mean abs diff = 0.1 dB, ceiling = 6 dB → repeatability score ≈ 0.983 →
  // excellent → sufficient evidence → correctable → candidate generated.
  const _frdTrend2 = '20 0.1 0\n'
      '40 -1.9 0\n'
      '80 -3.9 0\n'
      '160 -5.9 0\n'
      '315 -7.9 0\n'
      '630 -9.9 0\n'
      '1250 -11.9 0\n'
      '2500 -13.9 0\n'
      '5000 -15.9 0\n'
      '10000 -17.9 0\n'
      '20000 -19.9 0';

  String _contentHash(String content) => sha256
      .convert(utf8.encode(
          '${MeasurementAnalyzeAdapter.contentHashPrefix}|$content'))
      .toString();

  ProToolArtifactStore _chainMulti(
      String primaryContent, List<FrdSweepEntry> additionalSweeps,
      String candsRef) {
    final resolver = InMemoryProToolReferenceResolver();
    final store = ProToolArtifactStore();
    final ctx = _ctx(resolver, store);
    resolver.put(
      _project,
      'src:frd',
      ProMeasurementSource(
        fileName: 'sweep1.frd',
        content: primaryContent,
        format: AcousticFileType.frd,
        additionalSweeps: additionalSweeps,
      ),
    );
    const MeasurementAnalyzeAdapter()
        .run(ctx, _step('measurementAnalyze', ['src:frd'], 'meas:1'));
    const AcousticClassifyAdapter()
        .run(ctx, _step('acousticClassify', ['meas:1'], 'class:1'));
    const CorrectionPlanAdapter()
        .run(ctx, _step('acousticPlan', ['class:1'], 'plan:1'));
    const CandidateGenerationAdapter().run(
        ctx, _step('acousticGenerateCandidates', ['plan:1', 'class:1'], candsRef));
    return store;
  }

  group('production multi-sweep evidence (A-E)', () {
    test('A: single FRD (empty additionalSweeps) → repeatability unavailable → 0 candidates', () {
      final store = _chainMulti(_frdTrend, const [], 'cands:1');
      final cs = store.getTyped<CandidateSetArtifact>(_project, 'cands:1').value;
      expect(cs.candidates, isEmpty,
          reason: 'single sweep → repeatability unavailable → analysis-only');
    });

    test('B: two different repeatable sweeps → CandidateSetStatus.ok', () {
      final store = _chainMulti(
        _frdTrend,
        [FrdSweepEntry(
          fileName: 'sweep2.frd',
          content: _frdTrend2,
          contentHash: _contentHash(_frdTrend2),
        )],
        'cands:1',
      );
      final cs = store.getTyped<CandidateSetArtifact>(_project, 'cands:1').value;
      expect(cs.status, CandidateSetStatus.ok);
      expect(cs.candidates, isNotEmpty,
          reason: 'two distinct repeatable sweeps → correctable candidate');
    });

    test('B: two-sweep candidate values are finite and deterministic', () {
      final sweep2 = FrdSweepEntry(
        fileName: 'sweep2.frd',
        content: _frdTrend2,
        contentHash: _contentHash(_frdTrend2),
      );
      final store1 = _chainMulti(_frdTrend, [sweep2], 'cands:1');
      final store2 = _chainMulti(_frdTrend, [sweep2], 'cands:1');
      final c1 = store1.getTyped<CandidateSetArtifact>(_project, 'cands:1').value.candidates;
      final c2 = store2.getTyped<CandidateSetArtifact>(_project, 'cands:1').value.candidates;
      expect(c1.length, c2.length);
      for (var i = 0; i < c1.length; i++) {
        expect(c1[i].frequencyHz.isFinite, isTrue);
        expect(c1[i].gainDb.isFinite, isTrue);
        expect(c1[i].q.isFinite, isTrue);
        expect(c1[i].frequencyHz, c2[i].frequencyHz);
        expect(c1[i].gainDb, c2[i].gainDb);
        expect(c1[i].q, c2[i].q);
      }
    });

    test('C: identical duplicate sweeps (same hash) → deduplicated → 0 candidates', () {
      final primaryHash = _contentHash(_frdTrend);
      final store = _chainMulti(
        _frdTrend,
        [FrdSweepEntry(
          fileName: 'sweep1_copy.frd',
          content: _frdTrend,
          contentHash: primaryHash,  // same as primary → not independent
        )],
        'cands:1',
      );
      final cs = store.getTyped<CandidateSetArtifact>(_project, 'cands:1').value;
      expect(cs.candidates, isEmpty,
          reason: 'identical sweeps are not independent evidence → 0 candidates');
    });

    test('D: FrdGridAligner — narrower sweep clips intersection, no extrapolation', () {
      // Primary: 20Hz–200Hz (4 points). Secondary: 50Hz–100Hz (5 points).
      // Intersection: [50Hz, 100Hz]. Secondary has more points there → secondary grid.
      final primary = (
        freqs: [20.0, 50.0, 100.0, 200.0],
        mags: [0.0, -3.0, -6.0, -12.0],
      );
      final secondary = (
        freqs: [50.0, 60.0, 70.0, 80.0, 100.0],
        mags: [-2.5, -3.5, -4.5, -5.5, -5.5],
      );
      final result = FrdGridAligner.align([primary, secondary])!;

      // All returned frequencies must lie within the intersection range.
      for (final f in result.frequencies) {
        expect(f, greaterThanOrEqualTo(50.0),
            reason: 'no extrapolation below intersection min');
        expect(f, lessThanOrEqualTo(100.0),
            reason: 'no extrapolation above intersection max');
      }
      // Secondary grid (5 points) is selected as the common grid.
      expect(result.frequencies, equals([50.0, 60.0, 70.0, 80.0, 100.0]));
      expect(result.spectraDb.length, 2);

      // Deterministic: same inputs → same output.
      final result2 = FrdGridAligner.align([primary, secondary])!;
      expect(result2.frequencies, result.frequencies);
      for (var si = 0; si < result.spectraDb.length; si++) {
        for (var fi = 0; fi < result.spectraDb[si].length; fi++) {
          expect(result2.spectraDb[si][fi],
              closeTo(result.spectraDb[si][fi], 1e-9));
        }
      }
    });

    test('D: FrdGridAligner — non-overlapping grids return null', () {
      final a = (freqs: [20.0, 50.0], mags: [0.0, -3.0]);
      final b = (freqs: [100.0, 200.0], mags: [-6.0, -12.0]);
      expect(FrdGridAligner.align([a, b]), isNull);
    });

    test('E: no deepNull candidates ever generated (hard policy invariant)', () {
      final sweep2 = FrdSweepEntry(
        fileName: 'sweep2.frd',
        content: _frdTrend2,
        contentHash: _contentHash(_frdTrend2),
      );
      final store = _chainMulti(_frdTrend, [sweep2], 'cands:1');
      final cs = store.getTyped<CandidateSetArtifact>(_project, 'cands:1').value;
      for (final c in cs.candidates) {
        expect(c.featureType.name, isNot(equals('deepNull')),
            reason: 'deepNull candidate generation is always prohibited by policy');
      }
    });
  });

  // ── Numeric duplicate detection (Blocker 2) ──────────────────────────────

  // _frdTrendFormatted: same numeric measurements as _frdTrend but with extra
  // decimal places and trailing zeros — different raw bytes, identical numbers.
  // The numeric fingerprint must match _frdTrend so it is deduplicated.
  const _frdTrendFormatted = '20.0 0.000 0.0\n'
      '40.0 -2.000 0.0\n'
      '80.0 -4.000 0.0\n'
      '160.0 -6.000 0.0\n'
      '315.0 -8.000 0.0\n'
      '630.0 -10.000 0.0\n'
      '1250.0 -12.000 0.0\n'
      '2500.0 -14.000 0.0\n'
      '5000.0 -16.000 0.0\n'
      '10000.0 -18.000 0.0\n'
      '20000.0 -20.000 0.0';

  group('numeric duplicate detection (Blocker 2)', () {
    test(
        '1: same numeric FRD, different whitespace/decimal formatting '
        '→ deduplicated → repeatability unavailable → 0 candidates', () {
      // _frdTrendFormatted has a different raw content hash than _frdTrend
      // but the parsed numeric values are identical — should be rejected as
      // not independent evidence.
      final store = _chainMulti(
        _frdTrend,
        [
          FrdSweepEntry(
            fileName: 'sweep_formatted.frd',
            content: _frdTrendFormatted,
            contentHash: _contentHash(_frdTrendFormatted), // different raw hash
          ),
        ],
        'cands:1',
      );
      final cs = store.getTyped<CandidateSetArtifact>(_project, 'cands:1').value;
      expect(cs.candidates, isEmpty,
          reason: 'numerically identical sweeps must not count as independent '
              'repeatability evidence → 0 candidates');
    });

    test(
        '2: two genuinely different repeatable FRDs → numeric fingerprints differ '
        '→ sufficient confidence → candidate generated', () {
      // _frdTrend2 differs from _frdTrend by ±0.1 dB per point — genuinely
      // different measurements.  Numeric fingerprints are distinct so both
      // sweeps are accepted as independent evidence.
      final store = _chainMulti(
        _frdTrend,
        [
          FrdSweepEntry(
            fileName: 'sweep2.frd',
            content: _frdTrend2,
            contentHash: _contentHash(_frdTrend2),
          ),
        ],
        'cands:1',
      );
      final cs = store.getTyped<CandidateSetArtifact>(_project, 'cands:1').value;
      expect(cs.status, CandidateSetStatus.ok);
      expect(cs.candidates, isNotEmpty,
          reason: 'two genuinely different sweeps must yield correctable candidate');
    });
  });

  // ── Determinism ───────────────────────────────────────────────────────────

  test('same FRD → same candidate status and count', () {
    final store1 = _chain(_frd10, 'cands:1');
    final store2 = _chain(_frd10, 'cands:1');
    final s1 = store1.getTyped<CandidateSetArtifact>(_project, 'cands:1').value;
    final s2 = store2.getTyped<CandidateSetArtifact>(_project, 'cands:1').value;

    expect(s1.status, s2.status);
    expect(s1.candidates.length, s2.candidates.length);
    expect(s1.policyId, s2.policyId);
  });

  test('same FRD → same candidate frequencyHz values', () {
    final store1 = _chain(_frd10, 'cands:1');
    final store2 = _chain(_frd10, 'cands:1');
    final c1 = store1
        .getTyped<CandidateSetArtifact>(_project, 'cands:1')
        .value
        .candidates;
    final c2 = store2
        .getTyped<CandidateSetArtifact>(_project, 'cands:1')
        .value
        .candidates;

    for (var i = 0; i < c1.length; i++) {
      expect(c1[i].frequencyHz, c2[i].frequencyHz);
      expect(c1[i].gainDb, c2[i].gainDb);
      expect(c1[i].q, c2[i].q);
    }
  });
}
