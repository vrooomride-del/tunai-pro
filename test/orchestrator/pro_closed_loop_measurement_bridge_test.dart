// Phase 16-A — ProClosedLoopMeasurementBridge tests.
//
// Verifies:
//   1. before + after snapshot 정상 연결 — returns a ClosedLoopResult
//   2. after 없음 → pending (null)
//   3. invalid confidence → inconclusive
//   4. deterministic result — same inputs produce same output
//   5. DSP forbidden key 없음 — no register/address/biquad keys in JSON

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

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _pid = 'proj-bridge';
final _now = DateTime(2025, 1, 1);

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

// Flatter FRD data (closer to 0 dB) for testing positive score delta.
final _pointsFlatter = <MeasurementDataPoint>[
  const MeasurementDataPoint(frequencyHz: 100, magnitudeDb: -0.5),
  const MeasurementDataPoint(frequencyHz: 200, magnitudeDb: -0.3),
  const MeasurementDataPoint(frequencyHz: 400, magnitudeDb: -0.8),
  const MeasurementDataPoint(frequencyHz: 800, magnitudeDb: -0.2),
  const MeasurementDataPoint(frequencyHz: 1000, magnitudeDb: -0.1),
  const MeasurementDataPoint(frequencyHz: 2000, magnitudeDb: -0.1),
  const MeasurementDataPoint(frequencyHz: 4000, magnitudeDb: -0.2),
  const MeasurementDataPoint(frequencyHz: 8000, magnitudeDb: -0.3),
  const MeasurementDataPoint(frequencyHz: 12000, magnitudeDb: -0.4),
  const MeasurementDataPoint(frequencyHz: 16000, magnitudeDb: -0.5),
];

ParsedMeasurementData _frdData({List<MeasurementDataPoint>? points}) =>
    ParsedMeasurementData(
      id: 'frd-001',
      sourceFileName: 'test.frd',
      fileType: AcousticFileType.frd,
      importedAt: _now,
      points: points ?? _points10,
    );

ProProject _project({List<MeasurementDataPoint>? points}) => ProProject(
      id: _pid,
      name: 'Bridge Test',
      createdAt: _now,
      updatedAt: _now,
      acousticState: MeasurementProjectState(
        driverChannels: [
          DriverChannel(
            id: 'ch_wf_l',
            name: 'Woofer L',
            role: DriverRole.woofer,
            side: DriverSide.left,
            frdData: _frdData(points: points),
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

/// Builds a [MeasurementArtifact] via [ParsedMeasurementAdapter] — real engine,
/// no mocks. Confidence comes from whatever [MeasurementConfidenceEngine]
/// produces for a single imported FRD.
MeasurementArtifact _makeArtifact({List<MeasurementDataPoint>? points}) {
  final proj = _project(points: points);
  final store = ProToolArtifactStore();
  final ctx = ProToolExecutionContext(
    projectId: _pid,
    contextRef: 'ctx:test',
    resolver: ProProjectResolver(project: proj),
    store: store,
  );
  const ParsedMeasurementAdapter().run(ctx, _measStep);
  return store.getTyped<MeasurementArtifact>(_pid, 'out:meas');
}

/// Returns a copy of [base] with [ConfidenceStatus.valid] injected.
/// Used to bypass the single-import confidence limitation in unit tests —
/// the production path produces confidence from the real engine.
MeasurementArtifact _withValidConf(MeasurementArtifact base) =>
    MeasurementArtifact(
      parse: base.parse,
      evidence: base.evidence,
      evaluation: base.evaluation,
      confidence: const MeasurementConfidenceResult(
        status: ConfidenceStatus.valid,
        grade: ConfidenceGrade.excellent,
        overallScore: 0.9,
        repeatability: MetricOutcome.unavailable(ConfidenceMetric.repeatability),
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

/// Returns a copy of [base] with [ConfidenceStatus.invalid] injected.
MeasurementArtifact _withInvalidConf(MeasurementArtifact base) =>
    MeasurementArtifact(
      parse: base.parse,
      evidence: base.evidence,
      evaluation: MeasurementConfidenceEvaluation.evaluated,
      confidence: const MeasurementConfidenceResult(
        status: ConfidenceStatus.invalid,
        grade: ConfidenceGrade.unavailable,
        overallScore: null,
        repeatability:
            MetricOutcome.invalid(ConfidenceMetric.repeatability, 'stub'),
        snr: MetricOutcome.unavailable(ConfidenceMetric.snr),
        validBandCoverage:
            MetricOutcome.unavailable(ConfidenceMetric.validBandCoverage),
        clipping: MetricOutcome.unavailable(ConfidenceMetric.clipping),
        validBinCount: 0,
        requestedBinCount: 0,
        usableMinHz: null,
        usableMaxHz: null,
        reasons: ['invalid measurement stub'],
        warnings: [],
        unavailableMetrics: [],
        policyId: 'stub-invalid',
        policyVersion: 1,
      ),
    );

/// Returns a copy of [base] with [confidence] set to null
/// (bridge defaults to [ConfidenceStatus.insufficientEvidence]).
MeasurementArtifact _withNoConf(MeasurementArtifact base) => MeasurementArtifact(
      parse: base.parse,
      evidence: base.evidence,
      evaluation: MeasurementConfidenceEvaluation.notEvaluated,
      confidence: null,
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── 1. before + after snapshot 정상 연결 ──────────────────────────────────

  group('1. before + after snapshot connection', () {
    test('evaluate() returns ClosedLoopResult when both artifacts present',
        () {
      final base = _makeArtifact();
      final result = ProClosedLoopMeasurementBridge.evaluate(
        beforeArtifact: _withValidConf(base),
        beforeRef: 'ref-before',
        afterArtifact: _withValidConf(base),
        afterRef: 'ref-after',
      );
      expect(result, isNotNull);
    });

    test('evidenceRefs contains both refs', () {
      final base = _makeArtifact();
      final result = ProClosedLoopMeasurementBridge.evaluate(
        beforeArtifact: _withValidConf(base),
        beforeRef: 'ref-before',
        afterArtifact: _withValidConf(base),
        afterRef: 'ref-after',
      )!;
      expect(result.evidenceRefs, containsAll(['ref-before', 'ref-after']));
    });

    test('verdict is a valid ImprovementVerdict value', () {
      final base = _makeArtifact();
      final result = ProClosedLoopMeasurementBridge.evaluate(
        beforeArtifact: _withValidConf(base),
        beforeRef: 'ref-before',
        afterArtifact: _withValidConf(base),
        afterRef: 'ref-after',
      )!;
      expect(ImprovementVerdict.values, contains(result.verdict));
    });

    test('before + after with identical data → neutral verdict (score delta 0)',
        () {
      final base = _makeArtifact();
      final result = ProClosedLoopMeasurementBridge.evaluate(
        beforeArtifact: _withValidConf(base),
        beforeRef: 'ref-b',
        afterArtifact: _withValidConf(base),
        afterRef: 'ref-a',
      )!;
      // Same data → scoreDelta = 0 → neutral band
      expect(result.verdict, equals(ImprovementVerdict.neutral));
      expect(result.scoreDelta.abs(), lessThan(0.001));
    });
  });

  // ── 2. after 없음 → pending ────────────────────────────────────────────────

  group('2. pending state when after is null', () {
    test('evaluate() returns null when afterArtifact is null', () {
      final base = _makeArtifact();
      final result = ProClosedLoopMeasurementBridge.evaluate(
        beforeArtifact: _withValidConf(base),
        beforeRef: 'ref-before',
        afterArtifact: null,
        afterRef: 'ref-after',
      );
      expect(result, isNull);
    });

    test('snapshotFrom produces a snapshot regardless (not null)', () {
      final base = _makeArtifact();
      final snapshot =
          ProClosedLoopMeasurementBridge.snapshotFrom(base, 'ref-x');
      expect(snapshot, isNotNull);
      expect(snapshot.measurementRef, equals('ref-x'));
    });
  });

  // ── 3. invalid confidence → inconclusive ─────────────────────────────────

  group('3. confidence gate', () {
    test('after confidence null → inconclusive', () {
      final base = _makeArtifact();
      final result = ProClosedLoopMeasurementBridge.evaluate(
        beforeArtifact: _withValidConf(base),
        beforeRef: 'ref-b',
        afterArtifact: _withNoConf(base),
        afterRef: 'ref-a',
      )!;
      expect(result.verdict, equals(ImprovementVerdict.inconclusive));
    });

    test('after confidence explicitly invalid → inconclusive', () {
      final base = _makeArtifact();
      final result = ProClosedLoopMeasurementBridge.evaluate(
        beforeArtifact: _withValidConf(base),
        beforeRef: 'ref-b',
        afterArtifact: _withInvalidConf(base),
        afterRef: 'ref-a',
      )!;
      expect(result.verdict, equals(ImprovementVerdict.inconclusive));
    });

    test('before has no confidence but after is valid → evaluator proceeds', () {
      // Evaluator only gates on after.confidenceStatus.
      final base = _makeArtifact();
      final result = ProClosedLoopMeasurementBridge.evaluate(
        beforeArtifact: _withNoConf(base),  // no confidence on before
        beforeRef: 'ref-b',
        afterArtifact: _withValidConf(base), // valid after
        afterRef: 'ref-a',
      )!;
      // Should not be inconclusive due to before confidence
      expect(result.verdict, isNot(equals(ImprovementVerdict.inconclusive)));
    });

    test('valid after confidence → improved when after is flatter', () {
      final before = _withValidConf(_makeArtifact(points: _points10));
      final after = _withValidConf(_makeArtifact(points: _pointsFlatter));
      final result = ProClosedLoopMeasurementBridge.evaluate(
        beforeArtifact: before,
        beforeRef: 'ref-b',
        afterArtifact: after,
        afterRef: 'ref-a',
      )!;
      // Flatter data → higher score → positive delta → improved
      expect(result.scoreDelta, greaterThan(0));
      expect(result.verdict, equals(ImprovementVerdict.improved));
    });
  });

  // ── 4. deterministic result ───────────────────────────────────────────────

  group('4. deterministic result', () {
    test('same inputs always produce same verdict', () {
      final before = _withValidConf(_makeArtifact());
      final after = _withValidConf(_makeArtifact(points: _pointsFlatter));

      final r1 = ProClosedLoopMeasurementBridge.evaluate(
        beforeArtifact: before,
        beforeRef: 'ref-b',
        afterArtifact: after,
        afterRef: 'ref-a',
      )!;
      final r2 = ProClosedLoopMeasurementBridge.evaluate(
        beforeArtifact: before,
        beforeRef: 'ref-b',
        afterArtifact: after,
        afterRef: 'ref-a',
      )!;

      expect(r1.verdict, equals(r2.verdict));
    });

    test('same inputs always produce same scoreDelta', () {
      final before = _withValidConf(_makeArtifact());
      final after = _withValidConf(_makeArtifact(points: _pointsFlatter));

      final r1 = ProClosedLoopMeasurementBridge.evaluate(
        beforeArtifact: before,
        beforeRef: 'ref-b',
        afterArtifact: after,
        afterRef: 'ref-a',
      )!;
      final r2 = ProClosedLoopMeasurementBridge.evaluate(
        beforeArtifact: before,
        beforeRef: 'ref-b',
        afterArtifact: after,
        afterRef: 'ref-a',
      )!;

      expect(r1.scoreDelta, equals(r2.scoreDelta));
    });

    test('snapshotFrom is deterministic for same artifact', () {
      final base = _makeArtifact();
      final s1 = ProClosedLoopMeasurementBridge.snapshotFrom(base, 'ref-x');
      final s2 = ProClosedLoopMeasurementBridge.snapshotFrom(base, 'ref-x');
      expect(s1.scoreResult.score, equals(s2.scoreResult.score));
      expect(s1.confidenceStatus, equals(s2.confidenceStatus));
    });
  });

  // ── 5. DSP forbidden key 없음 ─────────────────────────────────────────────

  group('5. no DSP-forbidden keys', () {
    const forbiddenKeys = [
      'address',
      'register',
      'biquad',
      'coefficient',
      'payload',
    ];

    test('ClosedLoopResult.toJson() contains no DSP-forbidden keys', () {
      final base = _makeArtifact();
      final result = ProClosedLoopMeasurementBridge.evaluate(
        beforeArtifact: _withValidConf(base),
        beforeRef: 'ref-b',
        afterArtifact: _withValidConf(base),
        afterRef: 'ref-a',
      )!;

      void checkMap(Map<String, dynamic> map) {
        for (final key in map.keys) {
          for (final term in forbiddenKeys) {
            expect(key.toLowerCase(), isNot(contains(term)),
                reason: 'JSON key "$key" contains DSP term "$term"');
          }
          final v = map[key];
          if (v is Map<String, dynamic>) checkMap(v);
          if (v is List) {
            for (final item in v) {
              if (item is Map<String, dynamic>) checkMap(item);
            }
          }
        }
      }

      checkMap(result.toJson());
    });

    test('LoopMeasurementSnapshot.toJson() contains no DSP-forbidden keys', () {
      final base = _makeArtifact();
      final snapshot = ProClosedLoopMeasurementBridge.snapshotFrom(base, 'ref-x');
      final json = snapshot.toJson();

      for (final key in json.keys) {
        for (final term in forbiddenKeys) {
          expect(key.toLowerCase(), isNot(contains(term)),
              reason: 'Snapshot key "$key" contains DSP term "$term"');
        }
      }
    });

    test('verdict name contains no DSP terms', () {
      for (final verdict in ImprovementVerdict.values) {
        for (final term in forbiddenKeys) {
          expect(verdict.name.toLowerCase(), isNot(contains(term)));
        }
      }
    });
  });
}
