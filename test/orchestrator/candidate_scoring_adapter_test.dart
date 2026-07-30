import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/candidate_scoring.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_plan.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_types.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/acoustic_classify_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/candidate_generation_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/candidate_scoring_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/correction_plan_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/measurement_analyze_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_artifact_store.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_execution.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_reference_resolver.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_registry.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';

// ── FRD fixtures ──────────────────────────────────────────────────────────────

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

/// 3 points — insufficientEvidence propagates all the way to scoring.
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
        String toolId, List<String> inputRefs, String outputRef) =>
    ProOrchestratorStep(
      stepId: 'step-$toolId',
      toolId: ProOrchestratorToolId.values.firstWhere((e) => e.name == toolId),
      objective: 'test $toolId',
      inputRefs: inputRefs,
      outputRef: outputRef,
      requiresUserConfirmation: false,
    );

/// Full chain through to scoring. Returns store for artifact inspection.
ProToolArtifactStore _chain(String frdContent, String scoredRef) {
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

  const MeasurementAnalyzeAdapter()
      .run(ctx, _step('measurementAnalyze', ['src:frd'], 'meas:1'));
  const AcousticClassifyAdapter()
      .run(ctx, _step('acousticClassify', ['meas:1'], 'class:1'));
  const CorrectionPlanAdapter()
      .run(ctx, _step('acousticPlan', ['class:1'], 'plan:1'));
  const CandidateGenerationAdapter().run(ctx,
      _step('acousticGenerateCandidates', ['plan:1', 'class:1'], 'cands:1'));
  const CandidateScoringAdapter().run(
      ctx, _step('acousticScoreCandidates', ['cands:1', 'class:1'], scoredRef));

  return store;
}

void main() {
  const scorer = CandidateScoringAdapter();

  // ── Tool identity ─────────────────────────────────────────────────────────

  test('toolId is acousticScoreCandidates', () {
    expect(scorer.toolId, ProOrchestratorToolId.acousticScoreCandidates);
  });

  test(
      'acousticScoreCandidates can be registered in ProDeterministicToolRegistry',
      () {
    expect(
      () => ProDeterministicToolRegistry([scorer]),
      returnsNormally,
    );
  });

  // ── Full chain ────────────────────────────────────────────────────────────

  group('full chain', () {
    test('10-point FRD → ScoredCandidateSetArtifact stored', () {
      final store = _chain(_frd10, 'scored:1');
      expect(store.has(_project, 'scored:1'), isTrue);
      expect(
        () => store.getTyped<ScoredCandidateSetArtifact>(_project, 'scored:1'),
        returnsNormally,
      );
    });

    test('10-point FRD → status in {ok, allRejected, noCorrectableDirectives}',
        () {
      final store = _chain(_frd10, 'scored:1');
      final art =
          store.getTyped<ScoredCandidateSetArtifact>(_project, 'scored:1');
      expect(
        [
          ScoredCandidateSetStatus.ok,
          ScoredCandidateSetStatus.allRejected,
          ScoredCandidateSetStatus.noCorrectableDirectives,
        ],
        contains(art.value.status),
      );
    });

    test('3-point FRD → status = insufficientEvidence', () {
      final store = _chain(_frd3, 'scored:1');
      final art =
          store.getTyped<ScoredCandidateSetArtifact>(_project, 'scored:1');
      expect(art.value.status, ScoredCandidateSetStatus.insufficientEvidence);
    });

    test('3-point FRD → scoredCandidates is empty', () {
      final store = _chain(_frd3, 'scored:1');
      final art =
          store.getTyped<ScoredCandidateSetArtifact>(_project, 'scored:1');
      expect(art.value.scoredCandidates, isEmpty);
    });

    test('policyId is pro_provisional_v2', () {
      final store = _chain(_frd10, 'scored:1');
      final art =
          store.getTyped<ScoredCandidateSetArtifact>(_project, 'scored:1');
      expect(art.value.policyId, 'pro_provisional_v2');
    });

    test('evidenceRefs propagated from candidateSet', () {
      final store = _chain(_frd10, 'scored:1');
      final art =
          store.getTyped<ScoredCandidateSetArtifact>(_project, 'scored:1');
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
      const CandidateGenerationAdapter().run(
          ctx,
          _step(
              'acousticGenerateCandidates', ['plan:1', 'class:1'], 'cands:1'));

      final result = scorer.run(
          ctx,
          _step(
              'acousticScoreCandidates', ['cands:1', 'class:1'], 'scored:out'));
      expect(result.toolId, ProOrchestratorToolId.acousticScoreCandidates);
      expect(result.outputRef, 'scored:out');
    });

    test('result summary contains scored count and status', () {
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
      const CandidateGenerationAdapter().run(
          ctx,
          _step(
              'acousticGenerateCandidates', ['plan:1', 'class:1'], 'cands:1'));

      final result = scorer.run(ctx,
          _step('acousticScoreCandidates', ['cands:1', 'class:1'], 'scored:1'));
      expect(result.summary, contains('status='));
      expect(result.summary, contains('v2'));
    });
  });

  // ── Ranking invariant ─────────────────────────────────────────────────────

  test('scoredCandidates rank values are 1..n (contiguous, 1-based)', () {
    final store = _chain(_frd10, 'scored:1');
    final scored =
        store.getTyped<ScoredCandidateSetArtifact>(_project, 'scored:1').value;
    for (var i = 0; i < scored.scoredCandidates.length; i++) {
      expect(scored.scoredCandidates[i].rank, i + 1);
    }
  });

  test('compositeScore descending in rank order', () {
    final store = _chain(_frd10, 'scored:1');
    final cands = store
        .getTyped<ScoredCandidateSetArtifact>(_project, 'scored:1')
        .value
        .scoredCandidates;
    for (var i = 1; i < cands.length; i++) {
      expect(cands[i - 1].compositeScore >= cands[i].compositeScore, isTrue);
    }
  });

  // ── Tool confidence ───────────────────────────────────────────────────────

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
    const CandidateGenerationAdapter().run(ctx,
        _step('acousticGenerateCandidates', ['plan:1', 'class:1'], 'cands:1'));

    final result = scorer.run(ctx,
        _step('acousticScoreCandidates', ['cands:1', 'class:1'], 'scored:1'));
    expect(result.confidence, ProConfidence.low);
  });

  // ── Input count validation ────────────────────────────────────────────────

  test('single inputRef → missingReference', () {
    final resolver = InMemoryProToolReferenceResolver();
    final store = ProToolArtifactStore();
    final ctx = _ctx(resolver, store);

    expect(
      () => scorer.run(
          ctx, _step('acousticScoreCandidates', ['cands:1'], 'scored:1')),
      throwsA(predicate<ProToolException>(
          (e) => e.code == ProToolFailureCode.missingReference)),
    );
  });

  test('zero inputRefs → missingReference', () {
    final resolver = InMemoryProToolReferenceResolver();
    final store = ProToolArtifactStore();
    final ctx = _ctx(resolver, store);

    expect(
      () => scorer.run(ctx, _step('acousticScoreCandidates', [], 'scored:1')),
      throwsA(predicate<ProToolException>(
          (e) => e.code == ProToolFailureCode.missingReference)),
    );
  });

  // ── Input type validation ─────────────────────────────────────────────────

  test('wrong type as first input → typeMismatch', () {
    final resolver = InMemoryProToolReferenceResolver();
    final store = ProToolArtifactStore();
    final ctx = _ctx(resolver, store);
    store.put(_project, 'sim:1', SimulationArtifact([1.0, 2.0]));

    expect(
      () => scorer.run(ctx,
          _step('acousticScoreCandidates', ['sim:1', 'class:1'], 'scored:1')),
      throwsA(predicate<ProToolException>(
          (e) => e.code == ProToolFailureCode.typeMismatch)),
    );
  });

  test('missing refs → missingReference', () {
    final resolver = InMemoryProToolReferenceResolver();
    final store = ProToolArtifactStore();
    final ctx = _ctx(resolver, store);

    expect(
      () => scorer.run(
          ctx,
          _step(
              'acousticScoreCandidates', ['no-cands', 'no-class'], 'scored:1')),
      throwsA(predicate<ProToolException>(
          (e) => e.code == ProToolFailureCode.missingReference)),
    );
  });

  // ── JSON / no DSP fields ──────────────────────────────────────────────────

  group('JSON', () {
    test('ScoredCandidateSet.toJson has no DSP forbidden fields', () {
      final store = _chain(_frd10, 'scored:1');
      final j = store
          .getTyped<ScoredCandidateSetArtifact>(_project, 'scored:1')
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

    test(
        'ScoredCandidateSet.toJson contains status, scoredCandidates, policyId',
        () {
      final store = _chain(_frd10, 'scored:1');
      final j = store
          .getTyped<ScoredCandidateSetArtifact>(_project, 'scored:1')
          .value
          .toJson();

      expect(j.containsKey('status'), isTrue);
      expect(j.containsKey('scoredCandidates'), isTrue);
      expect(j.containsKey('policyId'), isTrue);
    });

    test('ScoredCandidate.toJson has no DSP forbidden fields', () {
      final store = _chain(_frd10, 'scored:1');
      final cands = store
          .getTyped<ScoredCandidateSetArtifact>(_project, 'scored:1')
          .value
          .scoredCandidates;
      for (final c in cands) {
        final j = c.toJson();
        expect(j.containsKey('biquad'), isFalse);
        expect(j.containsKey('address'), isFalse);
        expect(j.containsKey('register'), isFalse);
      }
    });

    test('ScoredCandidate.toJson contains rank, grade, compositeScore', () {
      final store = _chain(_frd10, 'scored:1');
      final cands = store
          .getTyped<ScoredCandidateSetArtifact>(_project, 'scored:1')
          .value
          .scoredCandidates;
      for (final c in cands) {
        final j = c.toJson();
        expect(j.containsKey('rank'), isTrue);
        expect(j.containsKey('grade'), isTrue);
        expect(j.containsKey('compositeScore'), isTrue);
      }
    });
  });

  // ── Determinism ───────────────────────────────────────────────────────────

  test('same FRD → same scored status and count', () {
    final store1 = _chain(_frd10, 'scored:1');
    final store2 = _chain(_frd10, 'scored:1');
    final s1 =
        store1.getTyped<ScoredCandidateSetArtifact>(_project, 'scored:1').value;
    final s2 =
        store2.getTyped<ScoredCandidateSetArtifact>(_project, 'scored:1').value;

    expect(s1.status, s2.status);
    expect(s1.scoredCandidates.length, s2.scoredCandidates.length);
    expect(s1.policyId, s2.policyId);
  });

  test('same FRD → same rank order and compositeScores', () {
    final store1 = _chain(_frd10, 'scored:1');
    final store2 = _chain(_frd10, 'scored:1');
    final c1 = store1
        .getTyped<ScoredCandidateSetArtifact>(_project, 'scored:1')
        .value
        .scoredCandidates;
    final c2 = store2
        .getTyped<ScoredCandidateSetArtifact>(_project, 'scored:1')
        .value
        .scoredCandidates;

    for (var i = 0; i < c1.length; i++) {
      expect(c1[i].rank, c2[i].rank);
      expect(c1[i].compositeScore, c2[i].compositeScore);
      expect(c1[i].grade, c2[i].grade);
    }
  });
}
