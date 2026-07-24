import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/acoustic_problem_classifier.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_plan.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_types.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/acoustic_classify_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/measurement_analyze_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_artifact_store.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_execution.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_reference_resolver.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_registry.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';

// ── FRD fixtures ─────────────────────────────────────────────────────────────

/// 10 points across 100–16 kHz — enough to satisfy minimumBins (8).
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

/// 3 points only — below minimumBins (8), yields insufficientEvidence from
/// the classifier.
const _frd3 = '100 -3.0 0\n200 -2.0 0\n400 -1.0 0';

/// ZMA fixture — yields MeasurementArtifact with domain=impedance.
const _zma = '100 8.0 0\n200 7.0 0\n400 6.5 0\n800 6.0 0\n1000 5.5 0\n'
    '2000 5.0 0\n4000 4.5 0\n8000 4.0 0';

// ── Helpers ───────────────────────────────────────────────────────────────────

const _project = 'p1';

ProToolExecutionContext _ctx({
  required ProToolReferenceResolver resolver,
  required ProToolArtifactStore store,
}) =>
    ProToolExecutionContext(
      projectId: _project,
      contextRef: 'ctx:1',
      resolver: resolver,
      store: store,
    );

ProOrchestratorStep _step({
  required String toolId,
  required String inputRef,
  required String outputRef,
}) =>
    ProOrchestratorStep(
      stepId: 'step-$toolId',
      toolId: ProOrchestratorToolId.values.firstWhere((e) => e.name == toolId),
      objective: 'test $toolId',
      inputRefs: [inputRef],
      outputRef: outputRef,
      requiresUserConfirmation: false,
    );

/// Runs `measurementAnalyze` on [content] and stores the MeasurementArtifact
/// at [measureRef]. Returns the context + store pair for chaining.
({ProToolExecutionContext ctx, ProToolArtifactStore store}) _setupFrd(
    String content, String measureRef) {
  final resolver = InMemoryProToolReferenceResolver();
  final store = ProToolArtifactStore();
  final ctx = _ctx(resolver: resolver, store: store);

  resolver.put(
    _project,
    'src:frd',
    ProMeasurementSource(
      fileName: 'test.frd',
      content: content,
      format: AcousticFileType.frd,
    ),
  );

  const analyze = MeasurementAnalyzeAdapter();
  analyze.run(
      ctx,
      _step(
          toolId: 'measurementAnalyze',
          inputRef: 'src:frd',
          outputRef: measureRef));
  return (ctx: ctx, store: store);
}

({ProToolExecutionContext ctx, ProToolArtifactStore store}) _setupZma(
    String measureRef) {
  final resolver = InMemoryProToolReferenceResolver();
  final store = ProToolArtifactStore();
  final ctx = _ctx(resolver: resolver, store: store);

  resolver.put(
    _project,
    'src:zma',
    const ProMeasurementSource(
      fileName: 'test.zma',
      content: _zma,
      format: AcousticFileType.zma,
    ),
  );

  const analyze = MeasurementAnalyzeAdapter();
  analyze.run(
      ctx,
      _step(
          toolId: 'measurementAnalyze',
          inputRef: 'src:zma',
          outputRef: measureRef));
  return (ctx: ctx, store: store);
}

void main() {
  const classify = AcousticClassifyAdapter();

  // ── Tool identity ─────────────────────────────────────────────────────────

  test('toolId is acousticClassify', () {
    expect(classify.toolId, ProOrchestratorToolId.acousticClassify);
  });

  test('acousticClassify can be registered in ProDeterministicToolRegistry',
      () {
    expect(
      () => ProDeterministicToolRegistry([classify]),
      returnsNormally,
    );
  });

  // ── Chain: measurementAnalyze → acousticClassify ──────────────────────────

  group('FRD chain', () {
    test('10-point FRD produces ClassificationArtifact with ok status', () {
      final (:ctx, :store) = _setupFrd(_frd10, 'meas:1');

      classify.run(
          ctx,
          _step(
            toolId: 'acousticClassify',
            inputRef: 'meas:1',
            outputRef: 'class:1',
          ));

      expect(store.has(_project, 'class:1'), isTrue);
      final artifact =
          store.getTyped<ClassificationArtifact>(_project, 'class:1');
      expect(artifact.value.status, AcousticClassificationStatus.ok);
    });

    test(
        '3-point FRD produces ClassificationArtifact with insufficientEvidence',
        () {
      final (:ctx, :store) = _setupFrd(_frd3, 'meas:1');

      classify.run(
          ctx,
          _step(
            toolId: 'acousticClassify',
            inputRef: 'meas:1',
            outputRef: 'class:1',
          ));

      final artifact =
          store.getTyped<ClassificationArtifact>(_project, 'class:1');
      expect(artifact.value.status,
          AcousticClassificationStatus.insufficientEvidence);
    });

    test('result carries evidenceRefs from the measurement', () {
      final (:ctx, :store) = _setupFrd(_frd10, 'meas:1');

      classify.run(
          ctx,
          _step(
            toolId: 'acousticClassify',
            inputRef: 'meas:1',
            outputRef: 'class:1',
          ));

      final artifact =
          store.getTyped<ClassificationArtifact>(_project, 'class:1');
      expect(artifact.value.evidenceRefs, isNotEmpty);
    });

    test('result reference carries outputRef', () {
      final (:ctx, :store) = _setupFrd(_frd10, 'meas:1');

      final result = classify.run(
          ctx,
          _step(
            toolId: 'acousticClassify',
            inputRef: 'meas:1',
            outputRef: 'class:out',
          ));

      expect(result.outputRef, 'class:out');
      expect(result.toolId, ProOrchestratorToolId.acousticClassify);
    });

    test('result summary contains feature count and status', () {
      final (:ctx, :store) = _setupFrd(_frd10, 'meas:1');

      final result = classify.run(
          ctx,
          _step(
            toolId: 'acousticClassify',
            inputRef: 'meas:1',
            outputRef: 'class:1',
          ));

      expect(result.summary, contains('status='));
    });
  });

  // ── Domain gate ───────────────────────────────────────────────────────────

  group('domain gate', () {
    test('ZMA MeasurementArtifact → throws typeMismatch', () {
      final (:ctx, :store) = _setupZma('meas:zma');

      expect(
        () => classify.run(
            ctx,
            _step(
              toolId: 'acousticClassify',
              inputRef: 'meas:zma',
              outputRef: 'class:1',
            )),
        throwsA(predicate<ProToolException>(
          (e) => e.code == ProToolFailureCode.typeMismatch,
        )),
      );
    });

    test('ZMA rejection message names the domain', () {
      final (:ctx, :store) = _setupZma('meas:zma');

      try {
        classify.run(
            ctx,
            _step(
              toolId: 'acousticClassify',
              inputRef: 'meas:zma',
              outputRef: 'class:1',
            ));
        fail('should have thrown');
      } on ProToolException catch (e) {
        expect(e.message, contains('impedance'));
      }
    });

    test('ZMA rejection does NOT store an artifact', () {
      final (:ctx, :store) = _setupZma('meas:zma');

      try {
        classify.run(
            ctx,
            _step(
              toolId: 'acousticClassify',
              inputRef: 'meas:zma',
              outputRef: 'class:1',
            ));
      } on ProToolException {
        // expected
      }

      expect(store.has(_project, 'class:1'), isFalse);
    });
  });

  // ── Missing reference ─────────────────────────────────────────────────────

  test('unknown inputRef → missingReference', () {
    final resolver = InMemoryProToolReferenceResolver();
    final store = ProToolArtifactStore();
    final ctx = _ctx(resolver: resolver, store: store);

    expect(
      () => classify.run(
          ctx,
          _step(
            toolId: 'acousticClassify',
            inputRef: 'no-such-ref',
            outputRef: 'class:1',
          )),
      throwsA(predicate<ProToolException>(
        (e) => e.code == ProToolFailureCode.missingReference,
      )),
    );
  });

  // ── Tool confidence mapping ───────────────────────────────────────────────

  group('tool confidence', () {
    test('ok classification → high tool confidence', () {
      final (:ctx, :store) = _setupFrd(_frd10, 'meas:1');

      final result = classify.run(
          ctx,
          _step(
            toolId: 'acousticClassify',
            inputRef: 'meas:1',
            outputRef: 'class:1',
          ));

      expect(result.confidence, ProConfidence.high);
    });

    test('insufficientEvidence classification → low tool confidence', () {
      final (:ctx, :store) = _setupFrd(_frd3, 'meas:1');

      final result = classify.run(
          ctx,
          _step(
            toolId: 'acousticClassify',
            inputRef: 'meas:1',
            outputRef: 'class:1',
          ));

      expect(result.confidence, ProConfidence.low);
    });
  });

  // ── JSON / no DSP fields ──────────────────────────────────────────────────

  group('JSON', () {
    test('ClassificationResult.toJson has no DSP forbidden fields', () {
      final (:ctx, :store) = _setupFrd(_frd10, 'meas:1');

      classify.run(
          ctx,
          _step(
            toolId: 'acousticClassify',
            inputRef: 'meas:1',
            outputRef: 'class:1',
          ));

      final artifact =
          store.getTyped<ClassificationArtifact>(_project, 'class:1');
      final j = artifact.value.toJson();

      for (final key in [
        'biquad',
        'address',
        'payload',
        'gainDb',
        'register'
      ]) {
        expect(j.containsKey(key), isFalse, reason: 'forbidden key: $key');
      }
    });

    test('ClassificationResult.toJson contains status and policyId', () {
      final (:ctx, :store) = _setupFrd(_frd10, 'meas:1');

      classify.run(
          ctx,
          _step(
            toolId: 'acousticClassify',
            inputRef: 'meas:1',
            outputRef: 'class:1',
          ));

      final j = store
          .getTyped<ClassificationArtifact>(_project, 'class:1')
          .value
          .toJson();
      expect(j.containsKey('status'), isTrue);
      expect(j.containsKey('policyId'), isTrue);
      expect(j['policyId'], 'pro_provisional');
    });
  });

  // ── Determinism ───────────────────────────────────────────────────────────

  test('same FRD content → same classification status', () {
    final (:ctx, :store) = _setupFrd(_frd10, 'meas:a');
    final store2 = ProToolArtifactStore();
    final resolver2 = InMemoryProToolReferenceResolver();
    final ctx2 = _ctx(resolver: resolver2, store: store2);
    resolver2.put(
        _project,
        'src:frd',
        const ProMeasurementSource(
            fileName: 'test.frd',
            content: _frd10,
            format: AcousticFileType.frd));
    const MeasurementAnalyzeAdapter().run(
        ctx2,
        _step(
            toolId: 'measurementAnalyze',
            inputRef: 'src:frd',
            outputRef: 'meas:a'));

    classify.run(
        ctx,
        _step(
            toolId: 'acousticClassify',
            inputRef: 'meas:a',
            outputRef: 'class:a'));
    classify.run(
        ctx2,
        _step(
            toolId: 'acousticClassify',
            inputRef: 'meas:a',
            outputRef: 'class:a'));

    final r1 =
        store.getTyped<ClassificationArtifact>(_project, 'class:a').value;
    final r2 =
        store2.getTyped<ClassificationArtifact>(_project, 'class:a').value;

    expect(r1.status, r2.status);
    expect(r1.observedFeatures.length, r2.observedFeatures.length);
    expect(r1.policyId, r2.policyId);
  });

  // ── ProContract: new ToolId values ────────────────────────────────────────

  group('ProOrchestratorToolId extension', () {
    test('acousticClassify is a valid ToolId member', () {
      expect(ProOrchestratorToolId.values,
          contains(ProOrchestratorToolId.acousticClassify));
    });

    test('all 7 acoustic engine ToolIds are present', () {
      final names = ProOrchestratorToolId.values.map((e) => e.name).toSet();
      for (final id in [
        'acousticClassify',
        'acousticPlan',
        'acousticGenerateCandidates',
        'acousticScoreCandidates',
        'acousticOptimizeSelection',
        'acousticValidateSafety',
        'acousticEvaluateLoop',
      ]) {
        expect(names, contains(id),
            reason: '$id missing from ProOrchestratorToolId');
      }
    });

    test('toJson returns the enum name string', () {
      expect(
          ProOrchestratorToolId.acousticClassify.toJson(), 'acousticClassify');
    });

    test('parse round-trips all 7 new ids', () {
      for (final id in ProOrchestratorToolId.values
          .where((e) => e.name.startsWith('acoustic'))) {
        expect(
          ProOrchestratorToolId.parse(id.name, 'test'),
          id,
        );
      }
    });
  });
}
