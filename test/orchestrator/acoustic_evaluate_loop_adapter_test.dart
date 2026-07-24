import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/closed_loop_evaluator.dart';
import 'package:tunai_pro/core/acoustic/measurement_confidence.dart'
    show ConfidenceStatus;
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_plan.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_types.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/acoustic_evaluate_loop_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_artifact_store.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_execution.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_reference_resolver.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_registry.dart';
import 'package:tunai_pro/core/pro_response_error.dart';

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

/// Builds a [LoopMeasurementSnapshot] with the given score and confidence.
LoopMeasurementSnapshot _snapshot(
  double score, {
  ConfidenceStatus confidenceStatus = ConfidenceStatus.valid,
  String measurementRef = 'meas:x',
}) =>
    LoopMeasurementSnapshot(
      measurementRef: measurementRef,
      scoreResult: ResponseErrorResult(
        rmsDb: 1.0,
        maxDeviationDb: 2.0,
        maxDeviationHz: 1000.0,
        weightedRmsDb: 1.0,
        score: score,
      ),
      confidenceStatus: confidenceStatus,
    );

/// Stores a [LoopSnapshotArtifact] at [ref].
void _putSnapshot(ProToolArtifactStore store, String ref,
        LoopMeasurementSnapshot snapshot) =>
    store.put(_project, ref, LoopSnapshotArtifact(snapshot));

void main() {
  const adapter = AcousticEvaluateLoopAdapter();

  // ── Tool identity ─────────────────────────────────────────────────────────

  test('toolId is acousticEvaluateLoop', () {
    expect(adapter.toolId, ProOrchestratorToolId.acousticEvaluateLoop);
  });

  test('acousticEvaluateLoop can be registered in ProDeterministicToolRegistry',
      () {
    expect(
      () => ProDeterministicToolRegistry([adapter]),
      returnsNormally,
    );
  });

  // ── Verdict paths ─────────────────────────────────────────────────────────

  group('verdict', () {
    test('scoreDelta >= 2.0 → improved', () {
      final store = ProToolArtifactStore();
      final ctx = _ctx(InMemoryProToolReferenceResolver(), store);
      _putSnapshot(store, 'before:1', _snapshot(50.0));
      _putSnapshot(store, 'after:1', _snapshot(53.0));

      adapter.run(ctx,
          _step('acousticEvaluateLoop', ['before:1', 'after:1'], 'loop:1'));

      final art = store.getTyped<ClosedLoopResultArtifact>(_project, 'loop:1');
      expect(art.value.verdict, ImprovementVerdict.improved);
      expect(art.value.scoreDelta, closeTo(3.0, 0.001));
    });

    test('scoreDelta <= -2.0 → regressed', () {
      final store = ProToolArtifactStore();
      final ctx = _ctx(InMemoryProToolReferenceResolver(), store);
      _putSnapshot(store, 'before:1', _snapshot(50.0));
      _putSnapshot(store, 'after:1', _snapshot(45.0));

      adapter.run(ctx,
          _step('acousticEvaluateLoop', ['before:1', 'after:1'], 'loop:1'));

      final art = store.getTyped<ClosedLoopResultArtifact>(_project, 'loop:1');
      expect(art.value.verdict, ImprovementVerdict.regressed);
      expect(art.value.scoreDelta, closeTo(-5.0, 0.001));
    });

    test('scoreDelta within (-2.0, 2.0) → neutral', () {
      final store = ProToolArtifactStore();
      final ctx = _ctx(InMemoryProToolReferenceResolver(), store);
      _putSnapshot(store, 'before:1', _snapshot(50.0));
      _putSnapshot(store, 'after:1', _snapshot(51.0));

      adapter.run(ctx,
          _step('acousticEvaluateLoop', ['before:1', 'after:1'], 'loop:1'));

      final art = store.getTyped<ClosedLoopResultArtifact>(_project, 'loop:1');
      expect(art.value.verdict, ImprovementVerdict.neutral);
      expect(art.value.scoreDelta, closeTo(1.0, 0.001));
    });

    test('after confidence insufficientEvidence → inconclusive', () {
      final store = ProToolArtifactStore();
      final ctx = _ctx(InMemoryProToolReferenceResolver(), store);
      _putSnapshot(store, 'before:1', _snapshot(50.0));
      _putSnapshot(
          store,
          'after:1',
          _snapshot(55.0,
              confidenceStatus: ConfidenceStatus.insufficientEvidence));

      adapter.run(ctx,
          _step('acousticEvaluateLoop', ['before:1', 'after:1'], 'loop:1'));

      final art = store.getTyped<ClosedLoopResultArtifact>(_project, 'loop:1');
      expect(art.value.verdict, ImprovementVerdict.inconclusive);
      expect(art.value.scoreDelta, 0.0);
    });

    test('after confidence invalid → inconclusive', () {
      final store = ProToolArtifactStore();
      final ctx = _ctx(InMemoryProToolReferenceResolver(), store);
      _putSnapshot(store, 'before:1', _snapshot(50.0));
      _putSnapshot(store, 'after:1',
          _snapshot(55.0, confidenceStatus: ConfidenceStatus.invalid));

      adapter.run(ctx,
          _step('acousticEvaluateLoop', ['before:1', 'after:1'], 'loop:1'));

      final art = store.getTyped<ClosedLoopResultArtifact>(_project, 'loop:1');
      expect(art.value.verdict, ImprovementVerdict.inconclusive);
    });
  });

  // ── Evidence propagation ──────────────────────────────────────────────────

  group('evidence propagation', () {
    test('evidenceRefs contain both inputRefs', () {
      final store = ProToolArtifactStore();
      final ctx = _ctx(InMemoryProToolReferenceResolver(), store);
      _putSnapshot(store, 'before:1', _snapshot(50.0));
      _putSnapshot(store, 'after:1', _snapshot(53.0));

      adapter.run(ctx,
          _step('acousticEvaluateLoop', ['before:1', 'after:1'], 'loop:1'));

      final art = store.getTyped<ClosedLoopResultArtifact>(_project, 'loop:1');
      expect(art.value.evidenceRefs, containsAll(['before:1', 'after:1']));
    });

    test('policyId is pro_provisional', () {
      final store = ProToolArtifactStore();
      final ctx = _ctx(InMemoryProToolReferenceResolver(), store);
      _putSnapshot(store, 'before:1', _snapshot(50.0));
      _putSnapshot(store, 'after:1', _snapshot(53.0));

      adapter.run(ctx,
          _step('acousticEvaluateLoop', ['before:1', 'after:1'], 'loop:1'));

      final art = store.getTyped<ClosedLoopResultArtifact>(_project, 'loop:1');
      expect(art.value.policyId, 'pro_provisional');
    });

    test('before and after snapshots preserved in result', () {
      final store = ProToolArtifactStore();
      final ctx = _ctx(InMemoryProToolReferenceResolver(), store);
      _putSnapshot(
          store, 'before:1', _snapshot(40.0, measurementRef: 'meas:before'));
      _putSnapshot(
          store, 'after:1', _snapshot(45.0, measurementRef: 'meas:after'));

      adapter.run(ctx,
          _step('acousticEvaluateLoop', ['before:1', 'after:1'], 'loop:1'));

      final art = store.getTyped<ClosedLoopResultArtifact>(_project, 'loop:1');
      expect(art.value.before.measurementRef, 'meas:before');
      expect(art.value.after.measurementRef, 'meas:after');
    });
  });

  // ── Result reference ──────────────────────────────────────────────────────

  test('result carries correct toolId and outputRef', () {
    final store = ProToolArtifactStore();
    final ctx = _ctx(InMemoryProToolReferenceResolver(), store);
    _putSnapshot(store, 'before:1', _snapshot(50.0));
    _putSnapshot(store, 'after:1', _snapshot(53.0));

    final result = adapter.run(ctx,
        _step('acousticEvaluateLoop', ['before:1', 'after:1'], 'loop:out'));
    expect(result.toolId, ProOrchestratorToolId.acousticEvaluateLoop);
    expect(result.outputRef, 'loop:out');
  });

  test('result summary contains verdict and scoreDelta', () {
    final store = ProToolArtifactStore();
    final ctx = _ctx(InMemoryProToolReferenceResolver(), store);
    _putSnapshot(store, 'before:1', _snapshot(50.0));
    _putSnapshot(store, 'after:1', _snapshot(53.0));

    final result = adapter.run(
        ctx, _step('acousticEvaluateLoop', ['before:1', 'after:1'], 'loop:1'));
    expect(result.summary, contains('verdict='));
    expect(result.summary, contains('scoreDelta='));
  });

  // ── Confidence mapping ────────────────────────────────────────────────────

  test('improved verdict → high confidence', () {
    final store = ProToolArtifactStore();
    final ctx = _ctx(InMemoryProToolReferenceResolver(), store);
    _putSnapshot(store, 'before:1', _snapshot(50.0));
    _putSnapshot(store, 'after:1', _snapshot(53.0));

    final result = adapter.run(
        ctx, _step('acousticEvaluateLoop', ['before:1', 'after:1'], 'loop:1'));
    expect(result.confidence, ProConfidence.high);
  });

  test('neutral verdict → medium confidence', () {
    final store = ProToolArtifactStore();
    final ctx = _ctx(InMemoryProToolReferenceResolver(), store);
    _putSnapshot(store, 'before:1', _snapshot(50.0));
    _putSnapshot(store, 'after:1', _snapshot(51.0));

    final result = adapter.run(
        ctx, _step('acousticEvaluateLoop', ['before:1', 'after:1'], 'loop:1'));
    expect(result.confidence, ProConfidence.medium);
  });

  test('regressed verdict → low confidence', () {
    final store = ProToolArtifactStore();
    final ctx = _ctx(InMemoryProToolReferenceResolver(), store);
    _putSnapshot(store, 'before:1', _snapshot(50.0));
    _putSnapshot(store, 'after:1', _snapshot(45.0));

    final result = adapter.run(
        ctx, _step('acousticEvaluateLoop', ['before:1', 'after:1'], 'loop:1'));
    expect(result.confidence, ProConfidence.low);
  });

  test('inconclusive verdict → low confidence', () {
    final store = ProToolArtifactStore();
    final ctx = _ctx(InMemoryProToolReferenceResolver(), store);
    _putSnapshot(store, 'before:1', _snapshot(50.0));
    _putSnapshot(
        store,
        'after:1',
        _snapshot(55.0,
            confidenceStatus: ConfidenceStatus.insufficientEvidence));

    final result = adapter.run(
        ctx, _step('acousticEvaluateLoop', ['before:1', 'after:1'], 'loop:1'));
    expect(result.confidence, ProConfidence.low);
  });

  // ── Input count validation ────────────────────────────────────────────────

  test('one inputRef (expects two) → missingReference', () {
    final store = ProToolArtifactStore();
    final ctx = _ctx(InMemoryProToolReferenceResolver(), store);

    expect(
      () => adapter.run(
          ctx, _step('acousticEvaluateLoop', ['before:1'], 'loop:1')),
      throwsA(predicate<ProToolException>(
          (e) => e.code == ProToolFailureCode.missingReference)),
    );
  });

  test('zero inputRefs → missingReference', () {
    final store = ProToolArtifactStore();
    final ctx = _ctx(InMemoryProToolReferenceResolver(), store);

    expect(
      () => adapter.run(ctx, _step('acousticEvaluateLoop', [], 'loop:1')),
      throwsA(predicate<ProToolException>(
          (e) => e.code == ProToolFailureCode.missingReference)),
    );
  });

  test('three inputRefs → missingReference', () {
    final store = ProToolArtifactStore();
    final ctx = _ctx(InMemoryProToolReferenceResolver(), store);

    expect(
      () => adapter.run(
          ctx, _step('acousticEvaluateLoop', ['a', 'b', 'c'], 'loop:1')),
      throwsA(predicate<ProToolException>(
          (e) => e.code == ProToolFailureCode.missingReference)),
    );
  });

  // ── Input type validation ─────────────────────────────────────────────────

  test('wrong artifact type for before → typeMismatch', () {
    final store = ProToolArtifactStore();
    final ctx = _ctx(InMemoryProToolReferenceResolver(), store);
    store.put(_project, 'bad:1', SimulationArtifact([1.0, 2.0]));
    _putSnapshot(store, 'after:1', _snapshot(53.0));

    expect(
      () => adapter.run(
          ctx, _step('acousticEvaluateLoop', ['bad:1', 'after:1'], 'loop:1')),
      throwsA(predicate<ProToolException>(
          (e) => e.code == ProToolFailureCode.typeMismatch)),
    );
  });

  test('missing before ref → missingReference', () {
    final store = ProToolArtifactStore();
    final ctx = _ctx(InMemoryProToolReferenceResolver(), store);
    _putSnapshot(store, 'after:1', _snapshot(53.0));

    expect(
      () => adapter.run(ctx,
          _step('acousticEvaluateLoop', ['no-before', 'after:1'], 'loop:1')),
      throwsA(predicate<ProToolException>(
          (e) => e.code == ProToolFailureCode.missingReference)),
    );
  });

  // ── JSON / no DSP fields ──────────────────────────────────────────────────

  group('JSON', () {
    test('ClosedLoopResult.toJson has no DSP forbidden fields', () {
      final store = ProToolArtifactStore();
      final ctx = _ctx(InMemoryProToolReferenceResolver(), store);
      _putSnapshot(store, 'before:1', _snapshot(50.0));
      _putSnapshot(store, 'after:1', _snapshot(53.0));

      adapter.run(ctx,
          _step('acousticEvaluateLoop', ['before:1', 'after:1'], 'loop:1'));

      final j = store
          .getTyped<ClosedLoopResultArtifact>(_project, 'loop:1')
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

    test('ClosedLoopResult.toJson contains verdict, scoreDelta, policyId', () {
      final store = ProToolArtifactStore();
      final ctx = _ctx(InMemoryProToolReferenceResolver(), store);
      _putSnapshot(store, 'before:1', _snapshot(50.0));
      _putSnapshot(store, 'after:1', _snapshot(53.0));

      adapter.run(ctx,
          _step('acousticEvaluateLoop', ['before:1', 'after:1'], 'loop:1'));

      final j = store
          .getTyped<ClosedLoopResultArtifact>(_project, 'loop:1')
          .value
          .toJson();
      expect(j.containsKey('verdict'), isTrue);
      expect(j.containsKey('scoreDelta'), isTrue);
      expect(j.containsKey('policyId'), isTrue);
      expect(j.containsKey('evidenceRefs'), isTrue);
    });
  });

  // ── Determinism ───────────────────────────────────────────────────────────

  test('same snapshots → same verdict and scoreDelta', () {
    ProToolArtifactStore makeStore() {
      final store = ProToolArtifactStore();
      final ctx = _ctx(InMemoryProToolReferenceResolver(), store);
      _putSnapshot(store, 'before:1', _snapshot(50.0));
      _putSnapshot(store, 'after:1', _snapshot(53.0));
      adapter.run(ctx,
          _step('acousticEvaluateLoop', ['before:1', 'after:1'], 'loop:1'));
      return store;
    }

    final r1 = makeStore()
        .getTyped<ClosedLoopResultArtifact>(_project, 'loop:1')
        .value;
    final r2 = makeStore()
        .getTyped<ClosedLoopResultArtifact>(_project, 'loop:1')
        .value;

    expect(r1.verdict, r2.verdict);
    expect(r1.scoreDelta, r2.scoreDelta);
    expect(r1.policyId, r2.policyId);
    expect(r1.evidenceRefs, r2.evidenceRefs);
  });
}
