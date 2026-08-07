// Phase 3-D3C-2 §13 — MeasurementArtifact.evidence base-type regression guard.
//
// D3C widened MeasurementArtifact.evidence from ImportedMeasurementEvidence to
// the sealed MeasurementEvidence base so a live capture can carry
// MeasurementCaptureEvidence. That widening is only safe as long as every
// production consumer reads BASE-class members. This test drives a live-capture
// artifact through the one consumer that exists (acousticClassify) and pins
// that it succeeds and reports the live source rather than mislabelling it as
// an import.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/measurement_capture_evidence_builder.dart';
import 'package:tunai_pro/core/acoustic/measurement_evidence.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_plan.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_types.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/acoustic_classify_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/measurement_analyze_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_artifact_store.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_reference_resolver.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_registry.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';

const _project = 'p1';

const _frd = '100 -5.0 0\n'
    '200 -3.0 0\n'
    '400 -8.0 0\n'
    '800 -1.5 0\n'
    '1000 -1.0 0\n'
    '2000 -0.5 0\n'
    '4000 -2.0 0\n'
    '8000 -3.0 0\n'
    '12000 -4.0 0\n'
    '16000 -5.0 0';

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

void main() {
  test('a MeasurementCaptureEvidence artifact classifies as a live capture',
      () {
    final resolver = InMemoryProToolReferenceResolver();
    final store = ProToolArtifactStore();
    final ctx = ProToolExecutionContext(
      projectId: _project,
      contextRef: 'ctx:1',
      resolver: resolver,
      store: store,
    );

    // Reuse measurementAnalyze only to obtain a real parse + confidence.
    resolver.put(
      _project,
      'src:frd',
      const ProMeasurementSource(
        fileName: 'test.frd',
        content: _frd,
        format: AcousticFileType.frd,
      ),
    );
    const analyzeRef = 'a:1';
    const MeasurementAnalyzeAdapter().run(
        ctx,
        _step(
            toolId: 'measurementAnalyze',
            inputRef: 'src:frd',
            outputRef: analyzeRef));
    final analyzed = store.getTyped<MeasurementArtifact>(_project, analyzeRef);

    // Re-tag the same parse as a live capture and swap in capture evidence.
    final parsed = analyzed.parse.data!;
    final live = ParsedMeasurementData(
      id: parsed.id,
      sourceFileName: parsed.sourceFileName,
      fileType: parsed.fileType,
      importedAt: parsed.importedAt,
      points: parsed.points,
      source: MeasurementDataSource.liveCapture,
    );
    final captureEvidence = MeasurementCaptureEvidenceBuilder.build(
      projectId: _project,
      measurementRef: 'ch_tw_l',
      data: live,
    ).evidence;
    expect(captureEvidence, isA<MeasurementCaptureEvidence>());

    store.put(
      _project,
      'm:live',
      MeasurementArtifact(
        parse: analyzed.parse,
        evidence: captureEvidence,
        evaluation: analyzed.evaluation,
        evaluationReason: analyzed.evaluationReason,
        confidence: analyzed.confidence,
      ),
    );

    // The load-bearing assertion: the consumer runs on the widened base type
    // without a cast and without throwing.
    const AcousticClassifyAdapter().run(
        ctx,
        _step(
            toolId: 'acousticClassify',
            inputRef: 'm:live',
            outputRef: 'c:live'));

    final classified =
        store.getTyped<ClassificationArtifact>(_project, 'c:live');
    expect(captureEvidence.source, MeasurementSource.liveMicrophone,
        reason: 'a live capture must never be reported as an import');
    expect(classified.value.evidenceRefs, contains(captureEvidence.evidenceId),
        reason: 'the capture evidence identity survives into the '
            'classification, so the claim stays traceable to a live capture');
  });
}
