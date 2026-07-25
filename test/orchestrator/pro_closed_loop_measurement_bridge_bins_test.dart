// Phase 16-B — ProClosedLoopMeasurementBridge.snapshotFromBins / evaluateWithBins tests.
//
// Verifies:
//   1. FrequencyBin list → LoopMeasurementSnapshot 정상 변환
//   2. Empty bins → zero score + insufficientEvidence confidence
//   3. Deterministic — same bins produce same snapshot
//   4. No DSP-forbidden keys in LoopMeasurementSnapshot from snapshotFromBins
//   5. evaluateWithBins null/empty afterBins → null (pending)
//   6. evaluateWithBins ≥ 10 bins → ClosedLoopResult (regression)

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/closed_loop_evaluator.dart';
import 'package:tunai_pro/core/acoustic/measurement_confidence.dart';
import 'package:tunai_pro/core/orchestrator/pro_closed_loop_measurement_bridge.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_plan.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_types.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/parsed_measurement_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_project_resolver.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_artifact_store.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_registry.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/spectrum_snapshot.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _pid = 'proj-bins';
final _now = DateTime(2025, 1, 1);

// 10 FrequencyBins spanning 100 Hz–16 kHz with non-zero deviations from 0 dB.
final _bins10 = <FrequencyBin>[
  const FrequencyBin(frequency: 100, magnitude: -5.0),
  const FrequencyBin(frequency: 200, magnitude: -3.0),
  const FrequencyBin(frequency: 400, magnitude: -8.0),
  const FrequencyBin(frequency: 800, magnitude: -1.5),
  const FrequencyBin(frequency: 1000, magnitude: -1.0),
  const FrequencyBin(frequency: 2000, magnitude: -0.5),
  const FrequencyBin(frequency: 4000, magnitude: -2.0),
  const FrequencyBin(frequency: 8000, magnitude: -3.0),
  const FrequencyBin(frequency: 12000, magnitude: -4.0),
  const FrequencyBin(frequency: 16000, magnitude: -5.0),
];

// Flatter bins (closer to 0 dB) for testing positive score delta in regression.
final _binsFlatter = <FrequencyBin>[
  const FrequencyBin(frequency: 100, magnitude: -0.5),
  const FrequencyBin(frequency: 200, magnitude: -0.3),
  const FrequencyBin(frequency: 400, magnitude: -0.8),
  const FrequencyBin(frequency: 800, magnitude: -0.2),
  const FrequencyBin(frequency: 1000, magnitude: -0.1),
  const FrequencyBin(frequency: 2000, magnitude: -0.1),
  const FrequencyBin(frequency: 4000, magnitude: -0.2),
  const FrequencyBin(frequency: 8000, magnitude: -0.3),
  const FrequencyBin(frequency: 12000, magnitude: -0.4),
  const FrequencyBin(frequency: 16000, magnitude: -0.5),
];

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

ParsedMeasurementData _frdData() => ParsedMeasurementData(
      id: 'frd-bins',
      sourceFileName: 'test.frd',
      fileType: AcousticFileType.frd,
      importedAt: _now,
      points: _points10,
    );

ProProject _project() => ProProject(
      id: _pid,
      name: 'Bins Test',
      createdAt: _now,
      updatedAt: _now,
      acousticState: MeasurementProjectState(
        driverChannels: [
          DriverChannel(
            id: 'ch_wf_l',
            name: 'Woofer L',
            role: DriverRole.woofer,
            side: DriverSide.left,
            frdData: _frdData(),
          ),
        ],
      ),
    );

const _measStep = ProOrchestratorStep(
  stepId: 'step-meas',
  toolId: ProOrchestratorToolId.measurementAnalyze,
  objective: 'analyze frd',
  inputRefs: ['ch_wf_l'],
  outputRef: 'out:meas',
  requiresUserConfirmation: false,
);

MeasurementArtifact _makeArtifact() {
  final store = ProToolArtifactStore();
  final ctx = ProToolExecutionContext(
    projectId: _pid,
    contextRef: 'ctx:bins',
    resolver: ProProjectResolver(project: _project()),
    store: store,
  );
  const ParsedMeasurementAdapter().run(ctx, _measStep);
  return store.getTyped<MeasurementArtifact>(_pid, 'out:meas');
}

MeasurementArtifact _withValidConf(MeasurementArtifact base) =>
    MeasurementArtifact(
      parse: base.parse,
      evidence: base.evidence,
      evaluation: base.evaluation,
      confidence: const MeasurementConfidenceResult(
        status: ConfidenceStatus.valid,
        grade: ConfidenceGrade.excellent,
        overallScore: 0.9,
        repeatability:
            MetricOutcome.unavailable(ConfidenceMetric.repeatability),
        snr: MetricOutcome.unavailable(ConfidenceMetric.snr),
        validBandCoverage:
            MetricOutcome.unavailable(ConfidenceMetric.validBandCoverage),
        clipping: MetricOutcome.unavailable(ConfidenceMetric.clipping),
        validBinCount: 10,
        requestedBinCount: 10,
        usableMinHz: 100.0,
        usableMaxHz: 16000.0,
        reasons: [],
        warnings: [],
        unavailableMetrics: [],
        policyId: 'stub-valid',
        policyVersion: 1,
      ),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── 1. FrequencyBin list → LoopMeasurementSnapshot 변환 ──────────────────

  group('1. snapshotFromBins: FrequencyBin list → LoopMeasurementSnapshot', () {
    test('returns a snapshot with matching measurementRef', () {
      final snap =
          ProClosedLoopMeasurementBridge.snapshotFromBins(_bins10, 'mic-ref');
      expect(snap.measurementRef, equals('mic-ref'));
    });

    test('non-empty bins produce a non-zero score', () {
      final snap =
          ProClosedLoopMeasurementBridge.snapshotFromBins(_bins10, 'mic-ref');
      expect(snap.scoreResult.score, greaterThan(0));
    });

    test('≥10 bins yield ConfidenceStatus.valid', () {
      final snap =
          ProClosedLoopMeasurementBridge.snapshotFromBins(_bins10, 'mic-ref');
      expect(snap.confidenceStatus, equals(ConfidenceStatus.valid));
    });

    test('<10 bins yield ConfidenceStatus.insufficientEvidence', () {
      final fewBins = _bins10.sublist(0, 5);
      final snap =
          ProClosedLoopMeasurementBridge.snapshotFromBins(fewBins, 'mic-ref');
      expect(
          snap.confidenceStatus, equals(ConfidenceStatus.insufficientEvidence));
    });
  });

  // ── 2. Empty bins → zero score + insufficientEvidence ────────────────────

  group('2. empty bins handling', () {
    test('empty bins → scoreResult.score == 0', () {
      final snap =
          ProClosedLoopMeasurementBridge.snapshotFromBins([], 'mic-empty');
      expect(snap.scoreResult.score, equals(0.0));
    });

    test('empty bins → rmsDb == 0', () {
      final snap =
          ProClosedLoopMeasurementBridge.snapshotFromBins([], 'mic-empty');
      expect(snap.scoreResult.rmsDb, equals(0.0));
    });

    test('empty bins → ConfidenceStatus.insufficientEvidence', () {
      final snap =
          ProClosedLoopMeasurementBridge.snapshotFromBins([], 'mic-empty');
      expect(
          snap.confidenceStatus, equals(ConfidenceStatus.insufficientEvidence));
    });
  });

  // ── 3. Deterministic — same bins produce same snapshot ───────────────────

  group('3. deterministic result', () {
    test('snapshotFromBins is deterministic for same bins', () {
      final s1 =
          ProClosedLoopMeasurementBridge.snapshotFromBins(_bins10, 'ref-x');
      final s2 =
          ProClosedLoopMeasurementBridge.snapshotFromBins(_bins10, 'ref-x');
      expect(s1.scoreResult.score, equals(s2.scoreResult.score));
      expect(s1.scoreResult.rmsDb, equals(s2.scoreResult.rmsDb));
      expect(s1.confidenceStatus, equals(s2.confidenceStatus));
    });

    test('snapshotFromBins is deterministic for empty bins', () {
      final s1 =
          ProClosedLoopMeasurementBridge.snapshotFromBins([], 'ref-empty');
      final s2 =
          ProClosedLoopMeasurementBridge.snapshotFromBins([], 'ref-empty');
      expect(s1.scoreResult.score, equals(s2.scoreResult.score));
      expect(s1.confidenceStatus, equals(s2.confidenceStatus));
    });
  });

  // ── 4. No DSP-forbidden keys ──────────────────────────────────────────────

  group('4. no DSP-forbidden keys in snapshotFromBins output', () {
    const forbiddenKeys = [
      'address',
      'register',
      'biquad',
      'coefficient',
      'payload',
    ];

    test(
        'LoopMeasurementSnapshot.toJson() from snapshotFromBins has no DSP keys',
        () {
      final snap =
          ProClosedLoopMeasurementBridge.snapshotFromBins(_bins10, 'mic-ref');
      final json = snap.toJson();
      for (final key in json.keys) {
        for (final term in forbiddenKeys) {
          expect(key.toLowerCase(), isNot(contains(term)),
              reason: 'Snapshot key "$key" contains DSP term "$term"');
        }
      }
    });
  });

  // ── 5. evaluateWithBins null/empty → null (pending) ─────────────────────

  group('5. evaluateWithBins: null / empty afterBins → null', () {
    test('null afterBins → null (pending)', () {
      final before = _withValidConf(_makeArtifact());
      final result = ProClosedLoopMeasurementBridge.evaluateWithBins(
        beforeArtifact: before,
        beforeRef: 'ref-b',
        afterBins: null,
        afterRef: 'ref-a',
      );
      expect(result, isNull);
    });

    test('empty afterBins → null (pending)', () {
      final before = _withValidConf(_makeArtifact());
      final result = ProClosedLoopMeasurementBridge.evaluateWithBins(
        beforeArtifact: before,
        beforeRef: 'ref-b',
        afterBins: const [],
        afterRef: 'ref-a',
      );
      expect(result, isNull);
    });
  });

  // ── 6. evaluateWithBins regression ───────────────────────────────────────

  group('6. evaluateWithBins regression', () {
    test('≥10 bins → returns a ClosedLoopResult', () {
      final before = _withValidConf(_makeArtifact());
      final result = ProClosedLoopMeasurementBridge.evaluateWithBins(
        beforeArtifact: before,
        beforeRef: 'ref-b',
        afterBins: _bins10,
        afterRef: 'ref-a',
      );
      expect(result, isNotNull);
    });

    test('evidenceRefs contains both refs', () {
      final before = _withValidConf(_makeArtifact());
      final result = ProClosedLoopMeasurementBridge.evaluateWithBins(
        beforeArtifact: before,
        beforeRef: 'ref-b',
        afterBins: _bins10,
        afterRef: 'ref-a',
      )!;
      expect(result.evidenceRefs, containsAll(['ref-b', 'ref-a']));
    });

    test('flatter after bins → positive scoreDelta', () {
      final before = _withValidConf(_makeArtifact());
      final result = ProClosedLoopMeasurementBridge.evaluateWithBins(
        beforeArtifact: before,
        beforeRef: 'ref-b',
        afterBins: _binsFlatter,
        afterRef: 'ref-a',
      )!;
      expect(result.scoreDelta, greaterThan(0));
    });

    test('verdict is a valid ImprovementVerdict value', () {
      final before = _withValidConf(_makeArtifact());
      final result = ProClosedLoopMeasurementBridge.evaluateWithBins(
        beforeArtifact: before,
        beforeRef: 'ref-b',
        afterBins: _bins10,
        afterRef: 'ref-a',
      )!;
      expect(ImprovementVerdict.values, contains(result.verdict));
    });
  });
}
