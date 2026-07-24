import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/candidate_optimizer.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_plan.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_types.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/acoustic_classify_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/candidate_generation_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/candidate_optimizer_adapter.dart';
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

/// 3 points — insufficientEvidence propagates to OptimizationStatus.propagated.
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

/// Full chain through to optimizer. Returns store for artifact inspection.
ProToolArtifactStore _chain(String frdContent, String optimRef) {
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
  const CandidateScoringAdapter().run(ctx,
      _step('acousticScoreCandidates', ['cands:1', 'class:1'], 'scored:1'));
  const CandidateOptimizerAdapter()
      .run(ctx, _step('acousticOptimizeSelection', ['scored:1'], optimRef));

  return store;
}

void main() {
  const optim = CandidateOptimizerAdapter();

  // ── Tool identity ─────────────────────────────────────────────────────────

  test('toolId is acousticOptimizeSelection', () {
    expect(optim.toolId, ProOrchestratorToolId.acousticOptimizeSelection);
  });

  test(
      'acousticOptimizeSelection can be registered in ProDeterministicToolRegistry',
      () {
    expect(
      () => ProDeterministicToolRegistry([optim]),
      returnsNormally,
    );
  });

  // ── Full chain ────────────────────────────────────────────────────────────

  group('full chain', () {
    test('10-point FRD → OptimizedSelectionArtifact stored', () {
      final store = _chain(_frd10, 'optim:1');
      expect(store.has(_project, 'optim:1'), isTrue);
      expect(
        () => store.getTyped<OptimizedSelectionArtifact>(_project, 'optim:1'),
        returnsNormally,
      );
    });

    test('10-point FRD → status in {ok, nothingSelected, propagated}', () {
      final store = _chain(_frd10, 'optim:1');
      final art =
          store.getTyped<OptimizedSelectionArtifact>(_project, 'optim:1');
      expect(
        [
          OptimizationStatus.ok,
          OptimizationStatus.nothingSelected,
          OptimizationStatus.propagated,
        ],
        contains(art.value.status),
      );
    });

    test('3-point FRD → status = propagated', () {
      final store = _chain(_frd3, 'optim:1');
      final art =
          store.getTyped<OptimizedSelectionArtifact>(_project, 'optim:1');
      expect(art.value.status, OptimizationStatus.propagated);
    });

    test('3-point FRD → selected list is empty', () {
      final store = _chain(_frd3, 'optim:1');
      final art =
          store.getTyped<OptimizedSelectionArtifact>(_project, 'optim:1');
      expect(art.value.selected, isEmpty);
    });

    test('policyId is pro_provisional', () {
      final store = _chain(_frd10, 'optim:1');
      final art =
          store.getTyped<OptimizedSelectionArtifact>(_project, 'optim:1');
      expect(art.value.policyId, 'pro_provisional');
    });

    test('evidenceRefs propagated from scored set', () {
      final store = _chain(_frd10, 'optim:1');
      final art =
          store.getTyped<OptimizedSelectionArtifact>(_project, 'optim:1');
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
      const CandidateScoringAdapter().run(ctx,
          _step('acousticScoreCandidates', ['cands:1', 'class:1'], 'scored:1'));

      final result = optim.run(
          ctx, _step('acousticOptimizeSelection', ['scored:1'], 'optim:out'));
      expect(result.toolId, ProOrchestratorToolId.acousticOptimizeSelection);
      expect(result.outputRef, 'optim:out');
    });

    test('result summary contains selected count and status', () {
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
      const CandidateScoringAdapter().run(ctx,
          _step('acousticScoreCandidates', ['cands:1', 'class:1'], 'scored:1'));

      final result = optim.run(
          ctx, _step('acousticOptimizeSelection', ['scored:1'], 'optim:1'));
      expect(result.summary, contains('status='));
    });
  });

  // ── applicationOrder invariant ────────────────────────────────────────────

  test('selected candidates have applicationOrder 1..n (contiguous, 1-based)',
      () {
    final store = _chain(_frd10, 'optim:1');
    final sel = store
        .getTyped<OptimizedSelectionArtifact>(_project, 'optim:1')
        .value
        .selected;
    for (var i = 0; i < sel.length; i++) {
      expect(sel[i].applicationOrder, i + 1);
    }
  });

  test('selected count does not exceed proProvisional maxNewBands (4)', () {
    final store = _chain(_frd10, 'optim:1');
    final sel = store
        .getTyped<OptimizedSelectionArtifact>(_project, 'optim:1')
        .value
        .selected;
    expect(sel.length, lessThanOrEqualTo(4));
  });

  // ── Tool confidence ───────────────────────────────────────────────────────

  test('propagated status → low confidence', () {
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
    const CandidateScoringAdapter().run(ctx,
        _step('acousticScoreCandidates', ['cands:1', 'class:1'], 'scored:1'));

    final result = optim.run(
        ctx, _step('acousticOptimizeSelection', ['scored:1'], 'optim:1'));
    expect(result.confidence, ProConfidence.low);
  });

  // ── Input count validation ────────────────────────────────────────────────

  test('two inputRefs (expects one) → missingReference', () {
    final resolver = InMemoryProToolReferenceResolver();
    final store = ProToolArtifactStore();
    final ctx = _ctx(resolver, store);

    expect(
      () => optim.run(
          ctx,
          _step(
              'acousticOptimizeSelection', ['scored:1', 'extra:1'], 'optim:1')),
      throwsA(predicate<ProToolException>(
          (e) => e.code == ProToolFailureCode.missingReference)),
    );
  });

  test('zero inputRefs → missingReference', () {
    final resolver = InMemoryProToolReferenceResolver();
    final store = ProToolArtifactStore();
    final ctx = _ctx(resolver, store);

    expect(
      () => optim.run(ctx, _step('acousticOptimizeSelection', [], 'optim:1')),
      throwsA(predicate<ProToolException>(
          (e) => e.code == ProToolFailureCode.missingReference)),
    );
  });

  // ── Input type validation ─────────────────────────────────────────────────

  test('CandidateSetArtifact (wrong type) as input → typeMismatch', () {
    final resolver = InMemoryProToolReferenceResolver();
    final store = ProToolArtifactStore();
    final ctx = _ctx(resolver, store);
    store.put(_project, 'sim:1', SimulationArtifact([1.0, 2.0]));

    expect(
      () => optim.run(
          ctx, _step('acousticOptimizeSelection', ['sim:1'], 'optim:1')),
      throwsA(predicate<ProToolException>(
          (e) => e.code == ProToolFailureCode.typeMismatch)),
    );
  });

  test('missing ref → missingReference', () {
    final resolver = InMemoryProToolReferenceResolver();
    final store = ProToolArtifactStore();
    final ctx = _ctx(resolver, store);

    expect(
      () => optim.run(
          ctx, _step('acousticOptimizeSelection', ['no-scored'], 'optim:1')),
      throwsA(predicate<ProToolException>(
          (e) => e.code == ProToolFailureCode.missingReference)),
    );
  });

  // ── JSON / no DSP fields ──────────────────────────────────────────────────

  group('JSON', () {
    test('OptimizedSelection.toJson has no DSP forbidden fields', () {
      final store = _chain(_frd10, 'optim:1');
      final j = store
          .getTyped<OptimizedSelectionArtifact>(_project, 'optim:1')
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
        'OptimizedSelection.toJson contains status, selected, rejected, policyId',
        () {
      final store = _chain(_frd10, 'optim:1');
      final j = store
          .getTyped<OptimizedSelectionArtifact>(_project, 'optim:1')
          .value
          .toJson();

      expect(j.containsKey('status'), isTrue);
      expect(j.containsKey('selected'), isTrue);
      expect(j.containsKey('rejected'), isTrue);
      expect(j.containsKey('policyId'), isTrue);
    });

    test('SelectedCandidate.toJson has no DSP forbidden fields', () {
      final store = _chain(_frd10, 'optim:1');
      final sel = store
          .getTyped<OptimizedSelectionArtifact>(_project, 'optim:1')
          .value
          .selected;
      for (final s in sel) {
        final j = s.toJson();
        expect(j.containsKey('biquad'), isFalse);
        expect(j.containsKey('address'), isFalse);
        expect(j.containsKey('register'), isFalse);
      }
    });

    test(
        'SelectedCandidate.toJson contains applicationOrder and selectionReason',
        () {
      final store = _chain(_frd10, 'optim:1');
      final sel = store
          .getTyped<OptimizedSelectionArtifact>(_project, 'optim:1')
          .value
          .selected;
      for (final s in sel) {
        final j = s.toJson();
        expect(j.containsKey('applicationOrder'), isTrue);
        expect(j.containsKey('selectionReason'), isTrue);
      }
    });
  });

  // ── Determinism ───────────────────────────────────────────────────────────

  test('same FRD → same selection status and count', () {
    final store1 = _chain(_frd10, 'optim:1');
    final store2 = _chain(_frd10, 'optim:1');
    final s1 =
        store1.getTyped<OptimizedSelectionArtifact>(_project, 'optim:1').value;
    final s2 =
        store2.getTyped<OptimizedSelectionArtifact>(_project, 'optim:1').value;

    expect(s1.status, s2.status);
    expect(s1.selected.length, s2.selected.length);
    expect(s1.policyId, s2.policyId);
  });

  test('same FRD → same applicationOrder sequence', () {
    final store1 = _chain(_frd10, 'optim:1');
    final store2 = _chain(_frd10, 'optim:1');
    final c1 = store1
        .getTyped<OptimizedSelectionArtifact>(_project, 'optim:1')
        .value
        .selected;
    final c2 = store2
        .getTyped<OptimizedSelectionArtifact>(_project, 'optim:1')
        .value
        .selected;

    for (var i = 0; i < c1.length; i++) {
      expect(c1[i].applicationOrder, c2[i].applicationOrder);
      expect(c1[i].scoredCandidate.candidate.featureId,
          c2[i].scoredCandidate.candidate.featureId);
    }
  });
}
