import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/candidate_set.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_plan.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_types.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/acoustic_classify_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/candidate_generation_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/correction_plan_adapter.dart';
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
