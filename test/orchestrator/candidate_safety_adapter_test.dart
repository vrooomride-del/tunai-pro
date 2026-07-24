import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/acoustic_problem_classifier.dart'
    show AcousticFeatureType;
import 'package:tunai_pro/core/acoustic/candidate_optimizer.dart';
import 'package:tunai_pro/core/acoustic/candidate_safety.dart';
import 'package:tunai_pro/core/acoustic/candidate_scoring.dart'
    show CandidateScoreGrade, ScoredCandidate;
import 'package:tunai_pro/core/acoustic/candidate_set.dart' show PeqCandidate;
import 'package:tunai_pro/core/acoustic/correction_plan.dart'
    show CorrectionIntent;
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_plan.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_types.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/acoustic_classify_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/candidate_generation_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/candidate_optimizer_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/candidate_safety_adapter.dart';
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

/// 3 points → insufficientEvidence → optimizer propagated → safety block.
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

/// Full chain through to safety validation. Returns store for inspection.
ProToolArtifactStore _chain(String frdContent, String safetyRef) {
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
      .run(ctx, _step('acousticOptimizeSelection', ['scored:1'], 'optim:1'));
  const CandidateSafetyAdapter()
      .run(ctx, _step('acousticValidateSafety', ['optim:1'], safetyRef));

  return store;
}

/// Builds a synthetic [OptimizedSelectionArtifact] with a known status and
/// stores it at [ref]. Used to test propagation paths without a full FRD chain.
void _putOptimArtifact(
    ProToolArtifactStore store, String ref, OptimizationStatus status) {
  store.put(
    _project,
    ref,
    OptimizedSelectionArtifact(OptimizedSelection(
      status: status,
      selected: const [],
      rejected: const [],
      reasons: ['synthetic fixture'],
      policyId: 'test',
      policyVersion: 1,
      evidenceRefs: const ['ev:1'],
    )),
  );
}

/// Builds a [SelectedCandidate] with controllable [featureType] and [gainDb].
SelectedCandidate _selectedCandidate({
  String featureId = 'f1',
  AcousticFeatureType featureType = AcousticFeatureType.narrowPeak,
  double gainDb = -3.0,
  double frequencyHz = 1000.0,
  int applicationOrder = 1,
}) {
  final peq = PeqCandidate(
    candidateId: 'candidate:$featureId',
    featureId: featureId,
    featureType: featureType,
    frequencyHz: frequencyHz,
    gainDb: gainDb,
    q: 2.0,
    intent: CorrectionIntent.cut,
    reason: 'synthetic',
  );
  final scored = ScoredCandidate(
    candidate: peq,
    prominenceDb: gainDb.abs(),
    prominenceScore: 20.0,
    magnitudeConsistencyScore: 15.0,
    qualityFactor: 1.0,
    compositeScore: 50.0,
    rank: applicationOrder,
    grade: CandidateScoreGrade.good,
    reasons: const ['synthetic'],
  );
  return SelectedCandidate(
    scoredCandidate: scored,
    applicationOrder: applicationOrder,
    selectionReason: 'synthetic',
  );
}

/// Builds an [OptimizedSelectionArtifact] with status=ok and given [selected].
void _putOkOptimWithCandidates(
    ProToolArtifactStore store, String ref, List<SelectedCandidate> selected) {
  store.put(
    _project,
    ref,
    OptimizedSelectionArtifact(OptimizedSelection(
      status: OptimizationStatus.ok,
      selected: selected,
      rejected: const [],
      reasons: ['synthetic'],
      policyId: 'test',
      policyVersion: 1,
      evidenceRefs: const ['ev:1'],
    )),
  );
}

void main() {
  const safety = CandidateSafetyAdapter();

  // ── Tool identity ─────────────────────────────────────────────────────────

  test('toolId is acousticValidateSafety', () {
    expect(safety.toolId, ProOrchestratorToolId.acousticValidateSafety);
  });

  test(
      'acousticValidateSafety can be registered in ProDeterministicToolRegistry',
      () {
    expect(
      () => ProDeterministicToolRegistry([safety]),
      returnsNormally,
    );
  });

  // ── Full chain ────────────────────────────────────────────────────────────

  group('full chain', () {
    test('10-point FRD → CandidateSafetyArtifact stored', () {
      final store = _chain(_frd10, 'safety:1');
      expect(store.has(_project, 'safety:1'), isTrue);
      expect(
        () => store.getTyped<CandidateSafetyArtifact>(_project, 'safety:1'),
        returnsNormally,
      );
    });

    test('10-point FRD → applyPermitted is a bool (not null)', () {
      final store = _chain(_frd10, 'safety:1');
      final art = store.getTyped<CandidateSafetyArtifact>(_project, 'safety:1');
      // applyPermitted is bool — just assert it's accessible and typed.
      expect(art.value.applyPermitted, isA<bool>());
    });

    test('3-point FRD → applyPermitted = false (propagated upstream block)',
        () {
      final store = _chain(_frd3, 'safety:1');
      final art = store.getTyped<CandidateSafetyArtifact>(_project, 'safety:1');
      expect(art.value.applyPermitted, isFalse);
    });

    test('3-point FRD → verifiedCandidates is empty', () {
      final store = _chain(_frd3, 'safety:1');
      final art = store.getTyped<CandidateSafetyArtifact>(_project, 'safety:1');
      expect(art.value.verifiedCandidates, isEmpty);
    });

    test('3-point FRD → at least one issue present (propagatedStatus)', () {
      final store = _chain(_frd3, 'safety:1');
      final art = store.getTyped<CandidateSafetyArtifact>(_project, 'safety:1');
      expect(art.value.issues, isNotEmpty);
    });

    test('policyId is pro_provisional', () {
      final store = _chain(_frd10, 'safety:1');
      final art = store.getTyped<CandidateSafetyArtifact>(_project, 'safety:1');
      expect(art.value.policyId, 'pro_provisional');
    });

    test('evidenceRefs propagated', () {
      final store = _chain(_frd10, 'safety:1');
      final art = store.getTyped<CandidateSafetyArtifact>(_project, 'safety:1');
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
      const CandidateOptimizerAdapter().run(
          ctx, _step('acousticOptimizeSelection', ['scored:1'], 'optim:1'));

      final result = safety.run(
          ctx, _step('acousticValidateSafety', ['optim:1'], 'safety:out'));
      expect(result.toolId, ProOrchestratorToolId.acousticValidateSafety);
      expect(result.outputRef, 'safety:out');
    });

    test('result summary contains applyPermitted and issue count', () {
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
      const CandidateOptimizerAdapter().run(
          ctx, _step('acousticOptimizeSelection', ['scored:1'], 'optim:1'));

      final result = safety.run(
          ctx, _step('acousticValidateSafety', ['optim:1'], 'safety:1'));
      expect(result.summary, contains('applyPermitted='));
    });
  });

  // ── Propagation paths (via synthetic fixtures) ────────────────────────────

  group('propagation', () {
    test('optimizer nothingSelected → applyPermitted = false', () {
      final store = ProToolArtifactStore();
      final ctx = _ctx(InMemoryProToolReferenceResolver(), store);
      _putOptimArtifact(store, 'optim:1', OptimizationStatus.nothingSelected);

      safety.run(ctx, _step('acousticValidateSafety', ['optim:1'], 'safety:1'));

      final art = store.getTyped<CandidateSafetyArtifact>(_project, 'safety:1');
      expect(art.value.applyPermitted, isFalse);
    });

    test('optimizer propagated → applyPermitted = false', () {
      final store = ProToolArtifactStore();
      final ctx = _ctx(InMemoryProToolReferenceResolver(), store);
      _putOptimArtifact(store, 'optim:1', OptimizationStatus.propagated);

      safety.run(ctx, _step('acousticValidateSafety', ['optim:1'], 'safety:1'));

      final art = store.getTyped<CandidateSafetyArtifact>(_project, 'safety:1');
      expect(art.value.applyPermitted, isFalse);
    });

    test('non-ok optimizer status → issues contain propagatedStatus code', () {
      final store = ProToolArtifactStore();
      final ctx = _ctx(InMemoryProToolReferenceResolver(), store);
      _putOptimArtifact(store, 'optim:1', OptimizationStatus.propagated);

      safety.run(ctx, _step('acousticValidateSafety', ['optim:1'], 'safety:1'));

      final art = store.getTyped<CandidateSafetyArtifact>(_project, 'safety:1');
      expect(
        art.value.issues.any(
            (i) => i.code == CandidateSafetyViolationCode.propagatedStatus),
        isTrue,
      );
    });
  });

  // ── Violation checks (synthetic fixtures) ────────────────────────────────

  group('violation checks', () {
    test('valid cut candidate → applyPermitted = true, verifiedCandidates = 1',
        () {
      final store = ProToolArtifactStore();
      final ctx = _ctx(InMemoryProToolReferenceResolver(), store);
      _putOkOptimWithCandidates(store, 'optim:1', [_selectedCandidate()]);

      safety.run(ctx, _step('acousticValidateSafety', ['optim:1'], 'safety:1'));

      final art = store.getTyped<CandidateSafetyArtifact>(_project, 'safety:1');
      expect(art.value.applyPermitted, isTrue);
      expect(art.value.verifiedCandidates.length, 1);
    });

    test('deepNull candidate → deepNullGuard violation, applyPermitted = false',
        () {
      final store = ProToolArtifactStore();
      final ctx = _ctx(InMemoryProToolReferenceResolver(), store);
      _putOkOptimWithCandidates(store, 'optim:1',
          [_selectedCandidate(featureType: AcousticFeatureType.deepNull)]);

      safety.run(ctx, _step('acousticValidateSafety', ['optim:1'], 'safety:1'));

      final art = store.getTyped<CandidateSafetyArtifact>(_project, 'safety:1');
      expect(art.value.applyPermitted, isFalse);
      expect(
        art.value.issues
            .any((i) => i.code == CandidateSafetyViolationCode.deepNullGuard),
        isTrue,
      );
    });

    test('positive gainDb → noBoostGuard violation, applyPermitted = false',
        () {
      final store = ProToolArtifactStore();
      final ctx = _ctx(InMemoryProToolReferenceResolver(), store);
      _putOkOptimWithCandidates(
          store, 'optim:1', [_selectedCandidate(gainDb: 1.0)]);

      safety.run(ctx, _step('acousticValidateSafety', ['optim:1'], 'safety:1'));

      final art = store.getTyped<CandidateSafetyArtifact>(_project, 'safety:1');
      expect(art.value.applyPermitted, isFalse);
      expect(
        art.value.issues
            .any((i) => i.code == CandidateSafetyViolationCode.noBoostGuard),
        isTrue,
      );
    });

    test(
        '11 candidates (availableSlots=10) → bandBudgetExceeded, '
        'applyPermitted = false', () {
      final store = ProToolArtifactStore();
      final ctx = _ctx(InMemoryProToolReferenceResolver(), store);
      final candidates = [
        for (var i = 0; i < 11; i++)
          _selectedCandidate(
            featureId: 'f$i',
            frequencyHz: 100.0 * (i + 1),
            applicationOrder: i + 1,
          )
      ];
      _putOkOptimWithCandidates(store, 'optim:1', candidates);

      safety.run(ctx, _step('acousticValidateSafety', ['optim:1'], 'safety:1'));

      final art = store.getTyped<CandidateSafetyArtifact>(_project, 'safety:1');
      expect(art.value.applyPermitted, isFalse);
      expect(
        art.value.issues.any(
            (i) => i.code == CandidateSafetyViolationCode.bandBudgetExceeded),
        isTrue,
      );
    });
  });

  // ── Tool confidence ───────────────────────────────────────────────────────

  test('applyPermitted=false → low confidence', () {
    final store = ProToolArtifactStore();
    final ctx = _ctx(InMemoryProToolReferenceResolver(), store);
    _putOptimArtifact(store, 'optim:1', OptimizationStatus.propagated);

    final result = safety.run(
        ctx, _step('acousticValidateSafety', ['optim:1'], 'safety:1'));
    expect(result.confidence, ProConfidence.low);
  });

  // ── Input count validation ────────────────────────────────────────────────

  test('two inputRefs (expects one) → missingReference', () {
    final resolver = InMemoryProToolReferenceResolver();
    final store = ProToolArtifactStore();
    final ctx = _ctx(resolver, store);

    expect(
      () => safety.run(ctx,
          _step('acousticValidateSafety', ['optim:1', 'extra:1'], 'safety:1')),
      throwsA(predicate<ProToolException>(
          (e) => e.code == ProToolFailureCode.missingReference)),
    );
  });

  test('zero inputRefs → missingReference', () {
    final resolver = InMemoryProToolReferenceResolver();
    final store = ProToolArtifactStore();
    final ctx = _ctx(resolver, store);

    expect(
      () => safety.run(ctx, _step('acousticValidateSafety', [], 'safety:1')),
      throwsA(predicate<ProToolException>(
          (e) => e.code == ProToolFailureCode.missingReference)),
    );
  });

  // ── Input type validation ─────────────────────────────────────────────────

  test('wrong artifact type as input → typeMismatch', () {
    final resolver = InMemoryProToolReferenceResolver();
    final store = ProToolArtifactStore();
    final ctx = _ctx(resolver, store);
    store.put(_project, 'sim:1', SimulationArtifact([1.0, 2.0]));

    expect(
      () => safety.run(
          ctx, _step('acousticValidateSafety', ['sim:1'], 'safety:1')),
      throwsA(predicate<ProToolException>(
          (e) => e.code == ProToolFailureCode.typeMismatch)),
    );
  });

  test('missing ref → missingReference', () {
    final resolver = InMemoryProToolReferenceResolver();
    final store = ProToolArtifactStore();
    final ctx = _ctx(resolver, store);

    expect(
      () => safety.run(
          ctx, _step('acousticValidateSafety', ['no-optim'], 'safety:1')),
      throwsA(predicate<ProToolException>(
          (e) => e.code == ProToolFailureCode.missingReference)),
    );
  });

  // ── JSON / no DSP fields ──────────────────────────────────────────────────

  group('JSON', () {
    test('CandidateSafetyResult.toJson has no DSP forbidden fields', () {
      final store = _chain(_frd10, 'safety:1');
      final j = store
          .getTyped<CandidateSafetyArtifact>(_project, 'safety:1')
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
        'CandidateSafetyResult.toJson contains applyPermitted, issues, '
        'verifiedCandidates, policyId', () {
      final store = _chain(_frd10, 'safety:1');
      final j = store
          .getTyped<CandidateSafetyArtifact>(_project, 'safety:1')
          .value
          .toJson();

      expect(j.containsKey('applyPermitted'), isTrue);
      expect(j.containsKey('issues'), isTrue);
      expect(j.containsKey('verifiedCandidates'), isTrue);
      expect(j.containsKey('policyId'), isTrue);
    });

    test('issues toJson has no DSP forbidden fields', () {
      final store = _chain(_frd3, 'safety:1');
      final issues = store
          .getTyped<CandidateSafetyArtifact>(_project, 'safety:1')
          .value
          .issues;
      for (final issue in issues) {
        final j = issue.toJson();
        expect(j.containsKey('biquad'), isFalse);
        expect(j.containsKey('address'), isFalse);
        expect(j.containsKey('register'), isFalse);
        expect(j.containsKey('code'), isTrue);
      }
    });
  });

  // ── Determinism ───────────────────────────────────────────────────────────

  test('same FRD → same applyPermitted and issue count', () {
    final store1 = _chain(_frd10, 'safety:1');
    final store2 = _chain(_frd10, 'safety:1');
    final r1 =
        store1.getTyped<CandidateSafetyArtifact>(_project, 'safety:1').value;
    final r2 =
        store2.getTyped<CandidateSafetyArtifact>(_project, 'safety:1').value;

    expect(r1.applyPermitted, r2.applyPermitted);
    expect(r1.issues.length, r2.issues.length);
    expect(r1.verifiedCandidates.length, r2.verifiedCandidates.length);
    expect(r1.policyId, r2.policyId);
  });
}
