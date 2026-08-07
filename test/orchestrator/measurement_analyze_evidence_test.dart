import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/measurement_confidence.dart';
import 'package:tunai_pro/core/acoustic/measurement_evidence.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_plan.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_types.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/measurement_analyze_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_artifact_store.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_execution.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_reference_resolver.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_registry.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';

const _frdWithPhase = '100 -3.0 0\n200 -2.0 0\n400 -1.0 0';
const _frdNoPhase = '100 -3.0\n200 -2.0\n400 -1.0';
const _zma = '100 8.0 0\n200 7.0 0\n400 6.5 0';

ProMeasurementSource _src(String content, AcousticFileType fmt,
        {String name = 'a.frd'}) =>
    ProMeasurementSource(fileName: name, content: content, format: fmt);

ProOrchestratorStep _step(
        {String inputRef = 'in1', String outputRef = 'out1'}) =>
    ProOrchestratorStep(
      stepId: 's1',
      toolId: ProOrchestratorToolId.measurementAnalyze,
      objective: 'analyze',
      inputRefs: [inputRef],
      outputRef: outputRef,
      requiresUserConfirmation: false,
    );

({
  ProToolExecutionContext ctx,
  InMemoryProToolReferenceResolver resolver,
  ProToolArtifactStore store,
}) _ctx({String projectId = 'p1'}) {
  final resolver = InMemoryProToolReferenceResolver();
  final store = ProToolArtifactStore();
  return (
    ctx: ProToolExecutionContext(
        projectId: projectId,
        contextRef: 'c',
        resolver: resolver,
        store: store),
    resolver: resolver,
    store: store,
  );
}

final _registry =
    ProDeterministicToolRegistry(const [MeasurementAnalyzeAdapter()]);

/// MeasurementAnalyzeAdapter always produces import evidence;
/// MeasurementArtifact.evidence widened to the sealed base in Phase 3-D3C so
/// live captures can carry MeasurementCaptureEvidence, so import-specific
/// fields are read through this explicit cast.
ImportedMeasurementEvidence _importedEv(MeasurementArtifact a) =>
    a.evidence as ImportedMeasurementEvidence;

MeasurementArtifact _run(
  ({
    ProToolExecutionContext ctx,
    InMemoryProToolReferenceResolver resolver,
    ProToolArtifactStore store,
  }) env, {
  String outputRef = 'out1',
  String inputRef = 'in1',
}) {
  final outcome = _registry.execute(
      _step(inputRef: inputRef, outputRef: outputRef), env.ctx);
  expect(outcome, isA<ProToolSuccess>(),
      reason: outcome is ProToolFailure ? outcome.message : null);
  return env.store.getTyped<MeasurementArtifact>(env.ctx.projectId, outputRef);
}

void main() {
  group('contentHash / evidence id', () {
    test('1. same content → same hash and evidence id', () {
      final a = _ctx()
        ..resolver.put('p1', 'in1', _src(_frdWithPhase, AcousticFileType.frd));
      final b = _ctx()
        ..resolver.put('p1', 'in1', _src(_frdWithPhase, AcousticFileType.frd));
      final ea = _run(a).evidence;
      final eb = _run(b).evidence;
      expect(ea.provenance.contentHash, eb.provenance.contentHash);
      expect(ea.evidenceId, eb.evidenceId);
    });
    test('2. one character change → different hash', () {
      final a = _ctx()
        ..resolver.put('p1', 'in1', _src(_frdWithPhase, AcousticFileType.frd));
      final b = _ctx()
        ..resolver.put('p1', 'in1',
            _src('$_frdWithPhase\n800 0.0 0', AcousticFileType.frd));
      expect(_run(a).evidence.provenance.contentHash,
          isNot(_run(b).evidence.provenance.contentHash));
    });
    test('3. filename change, same content → same contentHash', () {
      final a = _ctx()
        ..resolver.put('p1', 'in1',
            _src(_frdWithPhase, AcousticFileType.frd, name: 'x.frd'));
      final b = _ctx()
        ..resolver.put('p1', 'in1',
            _src(_frdWithPhase, AcousticFileType.frd, name: 'y.frd'));
      expect(_run(a).evidence.provenance.contentHash,
          _run(b).evidence.provenance.contentHash);
    });
    test('4. original content is not embedded in evidence JSON', () {
      final env = _ctx()
        ..resolver.put('p1', 'in1', _src(_frdWithPhase, AcousticFileType.frd));
      final json = jsonEncode(_importedEv(_run(env)).toJson());
      expect(json.contains('-3.0'), isFalse);
      expect(json.contains('100 '), isFalse);
    });
  });

  group('FRD evidence + confidence', () {
    test('10/11/14/15. FRD → acoustic/importedFrd, magnitude, unavailable set',
        () {
      final env = _ctx()
        ..resolver.put('p1', 'in1', _src(_frdWithPhase, AcousticFileType.frd));
      final ev = _importedEv(_run(env));
      expect(ev.domain, MeasurementDomain.acousticResponse);
      expect(ev.source, MeasurementSource.importedFrd);
      expect(ev.magnitudePresent, isTrue);
      expect(ev.availableMetrics, contains(EvidenceMetric.validBandCoverage));
      for (final m in [
        EvidenceMetric.repeatability,
        EvidenceMetric.snr,
        EvidenceMetric.clipping,
      ]) {
        expect(ev.unavailableMetrics, contains(m));
        expect(ev.availableMetrics, isNot(contains(m)));
      }
    });
    test('12. phase present → phasePresent true, phase available', () {
      final env = _ctx()
        ..resolver.put('p1', 'in1', _src(_frdWithPhase, AcousticFileType.frd));
      final ev = _importedEv(_run(env));
      expect(ev.phasePresent, isTrue);
      expect(ev.availableMetrics, contains(EvidenceMetric.phase));
    });
    test('13. no phase column → phasePresent false, phase unavailable', () {
      final env = _ctx()
        ..resolver.put('p1', 'in1', _src(_frdNoPhase, AcousticFileType.frd));
      final ev = _importedEv(_run(env));
      expect(ev.phasePresent, isFalse);
      expect(ev.unavailableMetrics, contains(EvidenceMetric.phase));
    });
    test(
        '16/17/18. confidence evaluated; single FRD → insufficient (still success)',
        () {
      final env = _ctx()
        ..resolver.put('p1', 'in1', _src(_frdWithPhase, AcousticFileType.frd));
      final art = _run(env);
      expect(art.evaluation, MeasurementConfidenceEvaluation.evaluated);
      expect(art.confidence, isNotNull);
      expect(art.confidence!.repeatability.status, MetricStatus.unavailable);
      expect(art.confidence!.status, ConfidenceStatus.insufficientEvidence);
    });
    test('19. no placeholder confidence value on the parse result path', () {
      final env = _ctx()
        ..resolver.put('p1', 'in1', _src(_frdWithPhase, AcousticFileType.frd));
      final art = _run(env);
      // overallScore is null (unavailable), NOT a fabricated 0.72.
      expect(art.confidence!.overallScore, isNull);
    });
  });

  group('ZMA evidence — unsupported acoustic domain', () {
    test('20/21. ZMA → impedance/importedZma, impedancePresent', () {
      final env = _ctx()
        ..resolver
            .put('p1', 'in1', _src(_zma, AcousticFileType.zma, name: 'a.zma'));
      final ev = _importedEv(_run(env));
      expect(ev.domain, MeasurementDomain.impedance);
      expect(ev.source, MeasurementSource.importedZma);
      expect(ev.impedancePresent, isTrue);
      expect(ev.magnitudePresent, isFalse);
    });
    test(
        '22/23/24. no acoustic confidence; unsupportedDomain reason; no magnitude',
        () {
      final env = _ctx()
        ..resolver
            .put('p1', 'in1', _src(_zma, AcousticFileType.zma, name: 'a.zma'));
      final art = _run(env);
      expect(art.confidence, isNull);
      expect(art.evaluation, MeasurementConfidenceEvaluation.unsupportedDomain);
      expect(art.evaluationReason, isNotEmpty);
      expect(_importedEv(art).magnitudePresent, isFalse);
    });
  });

  group('failures / boundary', () {
    test('8/9. malformed content → typed failure (no artifact stored)', () {
      final env = _ctx()
        ..resolver
            .put('p1', 'in1', _src('not a spectrum', AcousticFileType.frd));
      final outcome = _registry.execute(_step(), env.ctx);
      expect(outcome, isA<ProToolFailure>());
      expect(
          (outcome as ProToolFailure).code,
          anyOf(ProToolFailureCode.parseFailure,
              ProToolFailureCode.missingMagnitude));
      expect(env.store.has('p1', 'out1'), isFalse);
    });
    test(
        '25/26/27. artifact holds parse+evidence+evaluation; scoped; write-once',
        () {
      final env = _ctx()
        ..resolver.put('p1', 'in1', _src(_frdWithPhase, AcousticFileType.frd));
      final art = _run(env);
      expect(art.parse.data, isNotNull);
      expect(art.evidence, isA<ImportedMeasurementEvidence>());
      // another project cannot read it
      expect(() => env.store.getTyped<MeasurementArtifact>('other', 'out1'),
          throwsA(isA<ProToolException>()));
      // write-once
      expect(() => env.store.put('p1', 'out1', art),
          throwsA(isA<ProToolException>()));
    });
    test(
        '28/29. cloud result has references only, no spectrum/confidence numbers',
        () {
      final env = _ctx()
        ..resolver.put('p1', 'in1', _src(_frdWithPhase, AcousticFileType.frd));
      final outcome = _registry.execute(_step(), env.ctx) as ProToolSuccess;
      final json = jsonEncode(outcome.result.toJson()).toLowerCase();
      // No numeric confidence/spectrum leaks. The result's coarse ProConfidence
      // enum "high"/"medium"/"low" is a descriptor word (not a number), so the
      // key "confidence" itself is legitimate and not checked here.
      for (final t in [
        'frequency',
        'gaindb',
        '"q"',
        'overallscore',
        'magnitude',
        'spectra'
      ]) {
        expect(json.contains(t), isFalse, reason: t);
      }
      expect(outcome.result.outputRef, 'out1');
      expect(outcome.result.evidenceRefs, contains('out1'));
    });
    test('measurementRef is the input ref, not the filename', () {
      final env = _ctx()
        ..resolver.put('p1', 'measRefX',
            _src(_frdWithPhase, AcousticFileType.frd, name: 'file.frd'));
      final art = _run(env, inputRef: 'measRefX');
      expect(art.evidence.measurementRef, 'measRefX');
      expect(art.evidence.measurementRef, isNot('file.frd'));
    });
  });
}
