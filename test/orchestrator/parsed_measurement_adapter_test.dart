import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/measurement_confidence.dart';
import 'package:tunai_pro/core/acoustic/measurement_evidence.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_plan.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_types.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/parsed_measurement_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_project_resolver.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_artifact_store.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_execution.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_registry.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/measurement/measurement_capture_provenance.dart';
import 'package:tunai_pro/core/measurement/measurement_quality_snapshot.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _pid = 'proj-pma-test';
final _now = DateTime(2025, 1, 1);

/// 10 representative FRD points with magnitude — satisfies confidence engine.
final _points10 = <MeasurementDataPoint>[
  const MeasurementDataPoint(frequencyHz: 100, magnitudeDb: -5.0),
  const MeasurementDataPoint(frequencyHz: 200, magnitudeDb: -3.0),
  const MeasurementDataPoint(frequencyHz: 400, magnitudeDb: -8.0),
  const MeasurementDataPoint(frequencyHz: 800, magnitudeDb: -1.5),
  const MeasurementDataPoint(frequencyHz: 1000, magnitudeDb: -1.0),
  const MeasurementDataPoint(frequencyHz: 2000, magnitudeDb: -0.5),
  const MeasurementDataPoint(frequencyHz: 4000, magnitudeDb: -2.0),
  const MeasurementDataPoint(frequencyHz: 8000, magnitudeDb: -3.0),
  const MeasurementDataPoint(frequencyHz: 12000, magnitudeDb: -4.0),
  const MeasurementDataPoint(frequencyHz: 16000, magnitudeDb: -5.0),
];

ParsedMeasurementData _frdData({
  String id = 'frd-001',
  String fileName = 'woofer.frd',
  List<MeasurementDataPoint>? points,
  String? warning,
  MeasurementDataSource source = MeasurementDataSource.imported,
  CalibrationStatus calibrationStatus = CalibrationStatus.legacyUnknown,
  String? calibrationCurveChecksum,
  MeasurementQualitySnapshot? qualitySnapshot,
}) =>
    ParsedMeasurementData(
      id: id,
      sourceFileName: fileName,
      fileType: AcousticFileType.frd,
      importedAt: _now,
      points: points ?? _points10,
      warning: warning,
      source: source,
      calibrationStatus: calibrationStatus,
      calibrationCurveChecksum: calibrationCurveChecksum,
      qualitySnapshot: qualitySnapshot,
    );

DriverChannel _driver({
  String id = 'ch_wf_l',
  ParsedMeasurementData? frdData,
  bool withFrd = true,
}) =>
    DriverChannel(
      id: id,
      name: 'Woofer L',
      role: DriverRole.woofer,
      side: DriverSide.left,
      frdData: withFrd ? (frdData ?? _frdData()) : null,
    );

ProProject _project({
  List<DriverChannel>? drivers,
  String id = _pid,
}) =>
    ProProject(
      id: id,
      name: 'Test',
      createdAt: _now,
      updatedAt: _now,
      acousticState: MeasurementProjectState(
        driverChannels: drivers ?? [_driver()],
      ),
    );

ProOrchestratorStep _step({String inputRef = 'ch_wf_l'}) => ProOrchestratorStep(
      stepId: 'step-measurementAnalyze',
      toolId: ProOrchestratorToolId.measurementAnalyze,
      objective: 'analyze frd',
      inputRefs: [inputRef],
      outputRef: 'out:measurement',
      requiresUserConfirmation: false,
    );

({ProToolExecutionContext ctx, ProToolArtifactStore store}) _setup({
  ProProject? proj,
  String projectId = _pid,
}) {
  final store = ProToolArtifactStore();
  final resolver = ProProjectResolver(project: proj ?? _project());
  final ctx = ProToolExecutionContext(
    projectId: projectId,
    contextRef: 'ctx:test',
    resolver: resolver,
    store: store,
  );
  return (ctx: ctx, store: store);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  const adapter = ParsedMeasurementAdapter();

  // ── 1. Normal flow: MeasurementArtifact produced ──────────────────────────

  group('normal flow', () {
    test('produces MeasurementArtifact from ParsedMeasurementData', () {
      final (:ctx, :store) = _setup();
      final step = _step();

      final result = adapter.run(ctx, step);

      expect(store.has(_pid, step.outputRef), isTrue);
      final artifact =
          store.getTyped<MeasurementArtifact>(_pid, step.outputRef);
      expect(artifact.parse.data, isNotNull);
      expect(artifact.evidence.measurementRef, equals('ch_wf_l'));
      expect(result.toolId, equals(ProOrchestratorToolId.measurementAnalyze));
      expect(result.outputRef, equals(step.outputRef));
    });

    test('toolId is measurementAnalyze', () {
      expect(adapter.toolId, ProOrchestratorToolId.measurementAnalyze);
    });

    test('confidence is high when no frdData.warning', () {
      final (:ctx, :store) = _setup();
      final result = adapter.run(ctx, _step());
      expect(result.confidence, equals(ProConfidence.high));
    });

    test('confidence is medium when frdData has warning', () {
      final proj = _project(
        drivers: [_driver(frdData: _frdData(warning: 'minor issue'))],
      );
      final (:ctx, :store) = _setup(proj: proj);
      final result = adapter.run(ctx, _step());
      expect(result.confidence, equals(ProConfidence.medium));
    });
  });

  // ── 2. frdData points preserved in parse result ───────────────────────────

  group('frdData preservation', () {
    test('parse.data.points frequencies match source', () {
      final (:ctx, :store) = _setup();
      adapter.run(ctx, _step());

      final artifact =
          store.getTyped<MeasurementArtifact>(_pid, 'out:measurement');
      final points = artifact.parse.data!.points;
      expect(points.length, equals(10));
      expect(points.first.frequencyHz, equals(100.0));
      expect(points.last.frequencyHz, equals(16000.0));
    });

    test('parse.data.points magnitude values match source', () {
      final (:ctx, :store) = _setup();
      adapter.run(ctx, _step());

      final artifact =
          store.getTyped<MeasurementArtifact>(_pid, 'out:measurement');
      expect(artifact.parse.data!.points.first.magnitudeDb, equals(-5.0));
      expect(artifact.parse.data!.points[2].magnitudeDb, equals(-8.0));
    });

    test('evidence domain is acousticResponse', () {
      final (:ctx, :store) = _setup();
      adapter.run(ctx, _step());

      final artifact =
          store.getTyped<MeasurementArtifact>(_pid, 'out:measurement');
      expect(
          artifact.evidence.domain, equals(MeasurementDomain.acousticResponse));
      expect(artifact.evidence.source, equals(MeasurementSource.importedFrd));
    });

    test('confidence evaluation is evaluated (not unsupported)', () {
      final (:ctx, :store) = _setup();
      adapter.run(ctx, _step());

      final artifact =
          store.getTyped<MeasurementArtifact>(_pid, 'out:measurement');
      expect(artifact.evaluation,
          equals(MeasurementConfidenceEvaluation.evaluated));
      expect(artifact.confidence, isNotNull);
    });
  });

  // ── 3. frdData absent → typed failure ─────────────────────────────────────

  group('frdData absent', () {
    test('throws missingReference when driver has no frdData', () {
      final proj = _project(drivers: [_driver(withFrd: false)]);
      final (:ctx, :store) = _setup(proj: proj);

      expect(
        () => adapter.run(ctx, _step()),
        throwsA(predicate<ProToolException>(
          (e) => e.code == ProToolFailureCode.missingReference,
        )),
      );
    });

    test('throws missingReference when driver channel id not found', () {
      final (:ctx, :store) = _setup();

      final wrongStep = ProOrchestratorStep(
        stepId: 'step-1',
        toolId: ProOrchestratorToolId.measurementAnalyze,
        objective: 'test',
        inputRefs: ['no-such-channel'],
        outputRef: 'out:x',
        requiresUserConfirmation: false,
      );

      expect(
        () => adapter.run(ctx, wrongStep),
        throwsA(predicate<ProToolException>(
          (e) => e.code == ProToolFailureCode.missingReference,
        )),
      );
    });

    test('throws missingMagnitude when all magnitudeDb are null', () {
      final noMagPoints = [
        const MeasurementDataPoint(frequencyHz: 100),
        const MeasurementDataPoint(frequencyHz: 200),
      ];
      final proj = _project(
        drivers: [_driver(frdData: _frdData(points: noMagPoints))],
      );
      final (:ctx, :store) = _setup(proj: proj);

      expect(
        () => adapter.run(ctx, _step()),
        throwsA(predicate<ProToolException>(
          (e) => e.code == ProToolFailureCode.missingMagnitude,
        )),
      );
    });
  });

  // ── 4. projectId mismatch ─────────────────────────────────────────────────

  group('projectId mismatch', () {
    test('throws when ctx.projectId differs from resolver project id', () {
      final (:ctx, :store) = _setup(projectId: 'other-project');

      expect(
        () => adapter.run(ctx, _step()),
        throwsA(predicate<ProToolException>(
          (e) => e.code == ProToolFailureCode.missingReference,
        )),
      );
    });
  });

  // ── 5. Deterministic output ───────────────────────────────────────────────

  group('deterministic output', () {
    test('same frdData.id produces identical contentHash in evidence', () {
      final frd = _frdData(id: 'fixed-id');
      final proj = _project(drivers: [_driver(frdData: frd)]);

      final store1 = ProToolArtifactStore();
      final ctx1 = ProToolExecutionContext(
        projectId: _pid,
        contextRef: 'ctx:1',
        resolver: ProProjectResolver(project: proj),
        store: store1,
      );
      adapter.run(ctx1, _step());

      final store2 = ProToolArtifactStore();
      final ctx2 = ProToolExecutionContext(
        projectId: _pid,
        contextRef: 'ctx:2',
        resolver: ProProjectResolver(project: proj),
        store: store2,
      );
      adapter.run(
          ctx2,
          ProOrchestratorStep(
            stepId: 'step-2',
            toolId: ProOrchestratorToolId.measurementAnalyze,
            objective: 'analyze',
            inputRefs: ['ch_wf_l'],
            outputRef: 'out:measurement',
            requiresUserConfirmation: false,
          ));

      final a1 = store1.getTyped<MeasurementArtifact>(_pid, 'out:measurement');
      final a2 = store2.getTyped<MeasurementArtifact>(_pid, 'out:measurement');
      expect(a1.evidence.provenance.contentHash,
          equals(a2.evidence.provenance.contentHash));
    });

    test('different frdData.id produces different contentHash', () {
      final frd1 = _frdData(id: 'id-A');
      final frd2 = _frdData(id: 'id-B');

      final proj1 = _project(drivers: [_driver(frdData: frd1)]);
      final proj2 = _project(drivers: [_driver(frdData: frd2)]);

      final store1 = ProToolArtifactStore();
      final ctx1 = ProToolExecutionContext(
        projectId: _pid,
        contextRef: 'ctx:1',
        resolver: ProProjectResolver(project: proj1),
        store: store1,
      );
      adapter.run(ctx1, _step());

      final store2 = ProToolArtifactStore();
      final ctx2 = ProToolExecutionContext(
        projectId: _pid,
        contextRef: 'ctx:2',
        resolver: ProProjectResolver(project: proj2),
        store: store2,
      );
      adapter.run(
          ctx2,
          ProOrchestratorStep(
            stepId: 'step-2',
            toolId: ProOrchestratorToolId.measurementAnalyze,
            objective: 'analyze',
            inputRefs: ['ch_wf_l'],
            outputRef: 'out:measurement',
            requiresUserConfirmation: false,
          ));

      final a1 = store1.getTyped<MeasurementArtifact>(_pid, 'out:measurement');
      final a2 = store2.getTyped<MeasurementArtifact>(_pid, 'out:measurement');
      expect(a1.evidence.provenance.contentHash,
          isNot(equals(a2.evidence.provenance.contentHash)));
    });
  });

  // ── 6. No DSP forbidden keys in result ────────────────────────────────────

  group('no DSP forbidden keys', () {
    test('ProOrchestratorResult carries no DSP values', () {
      final (:ctx, :store) = _setup();
      final result = adapter.run(ctx, _step());

      // result fields: resultId, toolId, inputRefs, outputRef, evidenceRefs,
      // confidence, summary — all reference/enum/string. No numeric data.
      expect(result.toolId, isA<ProOrchestratorToolId>());
      expect(result.confidence, isA<ProConfidence>());
      expect(result.outputRef, isA<String>());
      // evidenceRefs should not carry raw numbers
      for (final ref in result.evidenceRefs) {
        expect(ref, isA<String>());
      }
    });

    test('result summary is a plain string with no numeric spectra', () {
      final (:ctx, :store) = _setup();
      final result = adapter.run(ctx, _step());

      // Summary must be a non-empty string and not a DSP value bag
      expect(result.summary, isA<String>());
      expect(result.summary, isNotEmpty);
    });
  });
  // ── Phase 3-D3C: live vs imported evidence branch ───────────────────────
  group('Phase 3-D3C evidence source branch', () {
    MeasurementQualitySnapshot quality() => MeasurementQualitySnapshot(
          provenance: MeasurementCaptureProvenance(
            projectId: _pid,
            microphoneProfileChecksum: 'profile-abc',
            calibrationCurveChecksum: 'curve-abc',
            calibrationAngle: CalibrationAngle.zeroDegree.name,
            inputDeviceSelectionIdentity: 'device:dev-1',
            setupReadinessGenerationId: 'gen-1',
            qualityPolicyVersion: 'pro-provisional-1',
            actualSampleRate: 48000,
            actualChannelCount: 1,
            capturedAt: _now,
          ),
          setupCalibrationStatus: CalibrationStatus.calibrated,
          setupNoiseFloorDbFs: -72,
          setupPeakDbFs: -6,
          setupRmsDbFs: -18,
          setupSignalToNoiseDb: 54,
          setupClippedSampleCount: 0,
          setupClippedSampleRatio: 0,
          setupCheckedAt: _now,
        );

    test('a live capture produces MeasurementCaptureEvidence', () {
      final env = _setup(
        proj: _project(drivers: [
          _driver(
              frdData: _frdData(
            source: MeasurementDataSource.liveCapture,
            calibrationStatus: CalibrationStatus.calibrated,
            calibrationCurveChecksum: 'curve-abc',
            qualitySnapshot: quality(),
          )),
        ]),
      );
      const ParsedMeasurementAdapter().run(env.ctx, _step());
      final art =
          env.store.getTyped<MeasurementArtifact>(_pid, 'out:measurement');

      expect(art.evidence, isA<MeasurementCaptureEvidence>());
      expect(art.evidence.source, MeasurementSource.liveMicrophone);
      final capture = art.evidence as MeasurementCaptureEvidence;
      expect(capture.microphoneProfileRef, 'profile-abc');
      expect(capture.calibrationRef, 'curve-abc');
      expect(capture.availableMetrics, contains(EvidenceMetric.calibration));
      expect(capture.sampleRate, 48000);
    });

    test('an imported FRD keeps ImportedMeasurementEvidence unchanged', () {
      final env = _setup();
      const ParsedMeasurementAdapter().run(env.ctx, _step());
      final art =
          env.store.getTyped<MeasurementArtifact>(_pid, 'out:measurement');

      expect(art.evidence, isA<ImportedMeasurementEvidence>());
      expect(art.evidence.source, MeasurementSource.importedFrd);
    });

    test('legacyUnknown data keeps the imported path (no forced migration)',
        () {
      final env = _setup(
        proj: _project(drivers: [
          _driver(
              frdData: _frdData(source: MeasurementDataSource.legacyUnknown)),
        ]),
      );
      const ParsedMeasurementAdapter().run(env.ctx, _step());
      final art =
          env.store.getTyped<MeasurementArtifact>(_pid, 'out:measurement');

      expect(art.evidence, isA<ImportedMeasurementEvidence>());
      expect(art.evidence.source, MeasurementSource.importedFrd);
    });

    test(
        'the confidence result is identical for the same numbers regardless '
        'of evidence source (DSP path unchanged)', () {
      final importedEnv = _setup();
      const ParsedMeasurementAdapter().run(importedEnv.ctx, _step());
      final imported = importedEnv.store
          .getTyped<MeasurementArtifact>(_pid, 'out:measurement');

      final liveEnv = _setup(
        proj: _project(drivers: [
          _driver(
              frdData: _frdData(
                  source: MeasurementDataSource.liveCapture,
                  qualitySnapshot: quality())),
        ]),
      );
      const ParsedMeasurementAdapter().run(liveEnv.ctx, _step());
      final live =
          liveEnv.store.getTyped<MeasurementArtifact>(_pid, 'out:measurement');

      expect(live.confidence!.status, imported.confidence!.status);
      expect(live.confidence!.overallScore, imported.confidence!.overallScore);
      expect(live.confidence!.grade, imported.confidence!.grade);
    });
  });
}
