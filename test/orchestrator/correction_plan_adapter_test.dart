import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/correction_plan.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_plan.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_types.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/acoustic_classify_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/correction_plan_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/measurement_analyze_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_artifact_store.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_execution.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_reference_resolver.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_registry.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';

// ── FRD fixtures ──────────────────────────────────────────────────────────────

/// 10 points — classifier status=ok, planner status=ok.
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

/// 3 points — classifier status=insufficientEvidence → planner status mirrors.
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

ProOrchestratorStep _step(String toolId, String inputRef, String outputRef) =>
    ProOrchestratorStep(
      stepId: 'step-$toolId',
      toolId: ProOrchestratorToolId.values.firstWhere((e) => e.name == toolId),
      objective: 'test $toolId',
      inputRefs: [inputRef],
      outputRef: outputRef,
      requiresUserConfirmation: false,
    );

/// Full chain: measurementAnalyze → acousticClassify → acousticPlan.
/// Returns the store so callers can inspect CorrectionPlanArtifact.
ProToolArtifactStore _chain(String frdContent, String planRef) {
  final resolver = InMemoryProToolReferenceResolver();
  final store = ProToolArtifactStore();
  final ctx = _ctx(resolver, store);
  resolver.put(
      _project,
      'src:frd',
      ProMeasurementSource(
          fileName: 'test.frd',
          content: frdContent,
          format: AcousticFileType.frd));
  const MeasurementAnalyzeAdapter()
      .run(ctx, _step('measurementAnalyze', 'src:frd', 'meas:1'));
  const AcousticClassifyAdapter()
      .run(ctx, _step('acousticClassify', 'meas:1', 'class:1'));
  const CorrectionPlanAdapter()
      .run(ctx, _step('acousticPlan', 'class:1', planRef));
  return store;
}

void main() {
  const plan = CorrectionPlanAdapter();

  // ── Tool identity ─────────────────────────────────────────────────────────

  test('toolId is acousticPlan', () {
    expect(plan.toolId, ProOrchestratorToolId.acousticPlan);
  });

  test('acousticPlan can be registered in ProDeterministicToolRegistry', () {
    expect(
      () => ProDeterministicToolRegistry([plan]),
      returnsNormally,
    );
  });

  // ── Chain: measurementAnalyze → acousticClassify → acousticPlan ───────────

  group('full chain', () {
    test('10-point FRD → CorrectionPlanArtifact stored with ok status', () {
      final store = _chain(_frd10, 'plan:1');
      expect(store.has(_project, 'plan:1'), isTrue);
      final artifact =
          store.getTyped<CorrectionPlanArtifact>(_project, 'plan:1');
      expect(artifact.value.status, CorrectionPlanStatus.ok);
    });

    test('3-point FRD → plan status mirrors classifier insufficientEvidence',
        () {
      final store = _chain(_frd3, 'plan:1');
      final artifact =
          store.getTyped<CorrectionPlanArtifact>(_project, 'plan:1');
      expect(artifact.value.status, CorrectionPlanStatus.insufficientEvidence);
    });

    test('evidenceRefs propagated through the chain', () {
      final store = _chain(_frd10, 'plan:1');
      final artifact =
          store.getTyped<CorrectionPlanArtifact>(_project, 'plan:1');
      expect(artifact.value.evidenceRefs, isNotEmpty);
    });

    test('policyId is pro_provisional', () {
      final store = _chain(_frd10, 'plan:1');
      final artifact =
          store.getTyped<CorrectionPlanArtifact>(_project, 'plan:1');
      expect(artifact.value.policyId, 'pro_provisional');
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
          .run(ctx, _step('measurementAnalyze', 'src:frd', 'meas:1'));
      const AcousticClassifyAdapter()
          .run(ctx, _step('acousticClassify', 'meas:1', 'class:1'));

      final result =
          plan.run(ctx, _step('acousticPlan', 'class:1', 'plan:out'));

      expect(result.toolId, ProOrchestratorToolId.acousticPlan);
      expect(result.outputRef, 'plan:out');
    });

    test('result summary contains directive count and status', () {
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
          .run(ctx, _step('measurementAnalyze', 'src:frd', 'meas:1'));
      const AcousticClassifyAdapter()
          .run(ctx, _step('acousticClassify', 'meas:1', 'class:1'));

      final result = plan.run(ctx, _step('acousticPlan', 'class:1', 'plan:1'));

      expect(result.summary, contains('status='));
    });
  });

  // ── Tool confidence mapping ───────────────────────────────────────────────

  group('tool confidence', () {
    test('ok plan → high tool confidence', () {
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
          .run(ctx, _step('measurementAnalyze', 'src:frd', 'meas:1'));
      const AcousticClassifyAdapter()
          .run(ctx, _step('acousticClassify', 'meas:1', 'class:1'));

      final result = plan.run(ctx, _step('acousticPlan', 'class:1', 'plan:1'));
      expect(result.confidence, ProConfidence.high);
    });

    test('insufficientEvidence plan → low tool confidence', () {
      final resolver = InMemoryProToolReferenceResolver();
      final store2 = ProToolArtifactStore();
      final ctx = _ctx(resolver, store2);
      resolver.put(
          _project,
          'src:frd',
          const ProMeasurementSource(
              fileName: 'f.frd', content: _frd3, format: AcousticFileType.frd));
      const MeasurementAnalyzeAdapter()
          .run(ctx, _step('measurementAnalyze', 'src:frd', 'meas:1'));
      const AcousticClassifyAdapter()
          .run(ctx, _step('acousticClassify', 'meas:1', 'class:1'));
      final result = plan.run(ctx, _step('acousticPlan', 'class:1', 'plan:1'));
      expect(result.confidence, ProConfidence.low);
    });
  });

  // ── Wrong input type ──────────────────────────────────────────────────────

  test('SimulationArtifact as input → typeMismatch', () {
    final resolver = InMemoryProToolReferenceResolver();
    final store = ProToolArtifactStore();
    final ctx = _ctx(resolver, store);
    store.put(_project, 'sim:1', SimulationArtifact([1.0, 2.0, 3.0]));

    expect(
      () => plan.run(ctx, _step('acousticPlan', 'sim:1', 'plan:1')),
      throwsA(predicate<ProToolException>(
          (e) => e.code == ProToolFailureCode.typeMismatch)),
    );
  });

  test('unknown inputRef → missingReference', () {
    final resolver = InMemoryProToolReferenceResolver();
    final store = ProToolArtifactStore();
    final ctx = _ctx(resolver, store);

    expect(
      () => plan.run(ctx, _step('acousticPlan', 'no-such-ref', 'plan:1')),
      throwsA(predicate<ProToolException>(
          (e) => e.code == ProToolFailureCode.missingReference)),
    );
  });

  // ── JSON / no DSP fields ──────────────────────────────────────────────────

  group('JSON', () {
    test('CorrectionPlan.toJson has no DSP forbidden fields', () {
      final store = _chain(_frd10, 'plan:1');
      final j = store
          .getTyped<CorrectionPlanArtifact>(_project, 'plan:1')
          .value
          .toJson();

      for (final key in [
        'biquad',
        'address',
        'payload',
        'gainDb',
        'register',
        'coefficients',
      ]) {
        expect(j.containsKey(key), isFalse, reason: 'forbidden key: $key');
      }
    });

    test('CorrectionPlan.toJson contains status, policyId, directives', () {
      final store = _chain(_frd10, 'plan:1');
      final j = store
          .getTyped<CorrectionPlanArtifact>(_project, 'plan:1')
          .value
          .toJson();

      expect(j.containsKey('status'), isTrue);
      expect(j.containsKey('policyId'), isTrue);
      expect(j.containsKey('directives'), isTrue);
    });

    test('directive regions carry Hz bounds (not DSP commands)', () {
      final store = _chain(_frd10, 'plan:1');
      final artifact =
          store.getTyped<CorrectionPlanArtifact>(_project, 'plan:1');
      for (final d in artifact.value.directives) {
        final rj = d.region.toJson();
        expect(rj.containsKey('startHz'), isTrue);
        expect(rj.containsKey('centerHz'), isTrue);
        expect(rj.containsKey('endHz'), isTrue);
      }
    });
  });

  // ── Determinism ───────────────────────────────────────────────────────────

  test('same FRD → same plan status and directive count', () {
    final store1 = _chain(_frd10, 'plan:1');
    final store2 = _chain(_frd10, 'plan:1');
    final p1 =
        store1.getTyped<CorrectionPlanArtifact>(_project, 'plan:1').value;
    final p2 =
        store2.getTyped<CorrectionPlanArtifact>(_project, 'plan:1').value;

    expect(p1.status, p2.status);
    expect(p1.directives.length, p2.directives.length);
    expect(p1.policyId, p2.policyId);
  });
}
