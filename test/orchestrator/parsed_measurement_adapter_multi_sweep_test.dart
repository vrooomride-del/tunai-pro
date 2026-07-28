// Tests: production multi-sweep path through ParsedMeasurementAdapter.
//
// Covers the 7 required integration scenarios:
//   1. Import primary FRD — adapter runs, single-sweep, analysis-only.
//   2. Add second sweep — additionalFrdSweeps carried, adapter reaches multi-sweep branch.
//   3. Persist and reload project — JSON round-trip preserves additionalFrdSweeps.
//   4. Count and filenames preserved after JSON round-trip.
//   5. Resolver passes both primary and additional sweeps to adapter.
//   6. Guided analysis (ParsedMeasurementAdapter) reaches multi-sweep production branch.
//   7. Remove sweep restores single-sweep analysis-only behavior.

import 'dart:convert';

import 'package:crypto/crypto.dart';
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

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _pid = 'proj-multi-sweep';
final _now = DateTime(2025, 6, 1);
const _driverId = 'ch_wf_l';

/// A falling-trend FRD (10 points, 100–16 kHz) — primary sweep.
const _frdContent = '''
# Primary sweep
100  -5.0
200  -3.0
400  -6.0
800  -9.0
1000  -12.0
2000  -14.0
4000  -16.0
8000  -17.0
12000  -18.0
16000  -19.0
''';

/// A perturbed second sweep (same trend, ±0.2 dB) — numerically distinct.
const _frdContent2 = '''
# Second repeat sweep
100  -5.2
200  -3.2
400  -6.2
800  -9.2
1000  -12.2
2000  -14.2
4000  -16.2
8000  -17.2
12000  -18.2
16000  -19.2
''';

/// Identical numeric values as [_frdContent] but extra whitespace/decimals —
/// should be deduplicated (same fingerprint).
const _frdContentSameNumeric = '''
# Duplicate of primary (formatting differs, numerics identical)
100.0   -5.0000
200.0   -3.0000
400.0   -6.0000
800.0   -9.0000
1000.0  -12.0000
2000.0  -14.0000
4000.0  -16.0000
8000.0  -17.0000
12000.0 -18.0000
16000.0 -19.0000
''';

String _hash(String content) => sha256
    .convert(utf8.encode('${FrdSweepEntry.contentHashPrefix}|$content'))
    .toString();

FrdSweepEntry _entry(String fileName, String content) =>
    FrdSweepEntry.fromRawContent(fileName, content);

final _points10 = <MeasurementDataPoint>[
  const MeasurementDataPoint(frequencyHz: 100, magnitudeDb: -5.0),
  const MeasurementDataPoint(frequencyHz: 200, magnitudeDb: -3.0),
  const MeasurementDataPoint(frequencyHz: 400, magnitudeDb: -6.0),
  const MeasurementDataPoint(frequencyHz: 800, magnitudeDb: -9.0),
  const MeasurementDataPoint(frequencyHz: 1000, magnitudeDb: -12.0),
  const MeasurementDataPoint(frequencyHz: 2000, magnitudeDb: -14.0),
  const MeasurementDataPoint(frequencyHz: 4000, magnitudeDb: -16.0),
  const MeasurementDataPoint(frequencyHz: 8000, magnitudeDb: -17.0),
  const MeasurementDataPoint(frequencyHz: 12000, magnitudeDb: -18.0),
  const MeasurementDataPoint(frequencyHz: 16000, magnitudeDb: -19.0),
];

ParsedMeasurementData _frdData({
  List<FrdSweepEntry>? additionalSweeps,
}) =>
    ParsedMeasurementData(
      id: 'frd-primary',
      sourceFileName: 'woofer_primary.frd',
      fileType: AcousticFileType.frd,
      importedAt: _now,
      points: _points10,
    );

DriverChannel _driver({
  List<FrdSweepEntry> additionalFrdSweeps = const [],
}) =>
    DriverChannel(
      id: _driverId,
      name: 'Woofer L',
      role: DriverRole.woofer,
      side: DriverSide.left,
      frdData: _frdData(),
      additionalFrdSweeps: additionalFrdSweeps,
    );

ProProject _project({List<FrdSweepEntry> additionalSweeps = const []}) =>
    ProProject(
      id: _pid,
      name: 'Multi-sweep test',
      createdAt: _now,
      updatedAt: _now,
      acousticState: MeasurementProjectState(
        driverChannels: [_driver(additionalFrdSweeps: additionalSweeps)],
      ),
    );

({ProToolExecutionContext ctx, ProToolArtifactStore store}) _setup({
  List<FrdSweepEntry> additionalSweeps = const [],
}) {
  final store = ProToolArtifactStore();
  final resolver = ProProjectResolver(project: _project(additionalSweeps: additionalSweeps));
  final ctx = ProToolExecutionContext(
    projectId: _pid,
    contextRef: 'ctx:multi-sweep',
    resolver: resolver,
    store: store,
  );
  return (ctx: ctx, store: store);
}

ProOrchestratorStep _step() => const ProOrchestratorStep(
      stepId: 'step-analyze',
      toolId: ProOrchestratorToolId.measurementAnalyze,
      objective: 'analyze frd',
      inputRefs: [_driverId],
      outputRef: 'out:measurement',
      requiresUserConfirmation: false,
    );

MeasurementArtifact _artifact(ProToolArtifactStore store) =>
    store.getTyped<MeasurementArtifact>(_pid, 'out:measurement');

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  const adapter = ParsedMeasurementAdapter();

  // ── Test 1: Import primary FRD — single-sweep, analysis-only ─────────────

  group('test 1: primary FRD — single-sweep analysis-only path', () {
    test('adapter runs and produces MeasurementArtifact', () {
      final (:ctx, :store) = _setup();
      adapter.run(ctx, _step());
      expect(store.has(_pid, 'out:measurement'), isTrue);
      final a = _artifact(store);
      expect(a.parse.data, isNotNull);
      expect(a.evaluation, equals(MeasurementConfidenceEvaluation.evaluated));
    });

    test('single-sweep: repeatability is unavailable', () {
      final (:ctx, :store) = _setup();
      adapter.run(ctx, _step());
      final a = _artifact(store);
      expect(a.evidence.unavailableMetrics,
          contains(EvidenceMetric.repeatability));
      expect(a.evidence.availableMetrics,
          isNot(contains(EvidenceMetric.repeatability)));
    });

    test('single-sweep: confidence status is insufficientEvidence', () {
      final (:ctx, :store) = _setup();
      adapter.run(ctx, _step());
      final a = _artifact(store);
      expect(a.confidence!.status,
          equals(ConfidenceStatus.insufficientEvidence));
    });
  });

  // ── Test 2: Add second sweep — adapter reaches multi-sweep branch ─────────

  group('test 2: second sweep added → multi-sweep branch', () {
    test('additionalFrdSweeps is non-empty before adapter run', () {
      final sweeps = [_entry('woofer_2.frd', _frdContent2)];
      final (:ctx, :store) = _setup(additionalSweeps: sweeps);
      final driver = ctx.resolver
          .resolveMeasurementProjectState(_pid, _driverId)
          .driverChannels
          .firstWhere((d) => d.id == _driverId);
      expect(driver.additionalFrdSweeps.length, equals(1));
      expect(driver.additionalFrdSweeps.first.fileName, 'woofer_2.frd');
    });

    // ImportedMeasurementEvidence invariant: repeatability always unavailable
    // in evidence regardless of how many sweeps are provided. The confidence
    // engine computes repeatability independently from spectraDb.
    test('two distinct sweeps → evidence still marks repeatability unavailable', () {
      final sweeps = [_entry('woofer_2.frd', _frdContent2)];
      final (:ctx, :store) = _setup(additionalSweeps: sweeps);
      adapter.run(ctx, _step());
      final a = _artifact(store);
      expect(a.evidence.unavailableMetrics,
          contains(EvidenceMetric.repeatability));
    });

    test('two distinct sweeps → confidence status is not insufficientEvidence', () {
      final sweeps = [_entry('woofer_2.frd', _frdContent2)];
      final (:ctx, :store) = _setup(additionalSweeps: sweeps);
      adapter.run(ctx, _step());
      final a = _artifact(store);
      expect(a.confidence!.status,
          isNot(equals(ConfidenceStatus.insufficientEvidence)));
    });
  });

  // ── Test 3 & 4: Persist and reload — JSON round-trip ─────────────────────

  group('tests 3-4: JSON persistence round-trip', () {
    test('DriverChannel with additionalFrdSweeps survives toJson/fromJson', () {
      final sweeps = [
        _entry('sweep_a.frd', _frdContent),
        _entry('sweep_b.frd', _frdContent2),
      ];
      final ch = _driver(additionalFrdSweeps: sweeps);
      final json = ch.toJson();
      final restored = DriverChannel.fromJson(Map<String, dynamic>.from(json));

      expect(restored.additionalFrdSweeps.length, equals(2));
    });

    test('filenames are preserved after JSON round-trip', () {
      final sweeps = [
        _entry('sweep_a.frd', _frdContent),
        _entry('sweep_b.frd', _frdContent2),
      ];
      final ch = _driver(additionalFrdSweeps: sweeps);
      final json = ch.toJson();
      final restored = DriverChannel.fromJson(Map<String, dynamic>.from(json));

      expect(restored.additionalFrdSweeps[0].fileName, equals('sweep_a.frd'));
      expect(restored.additionalFrdSweeps[1].fileName, equals('sweep_b.frd'));
    });

    test('content and contentHash survive JSON round-trip', () {
      final entry = _entry('test.frd', _frdContent);
      final ch = _driver(additionalFrdSweeps: [entry]);
      final json = ch.toJson();
      final restored = DriverChannel.fromJson(Map<String, dynamic>.from(json));

      final r = restored.additionalFrdSweeps.first;
      expect(r.content, equals(_frdContent));
      expect(r.contentHash, equals(_hash(_frdContent)));
    });

    test('additionalFrdSweeps absent from JSON when empty', () {
      final ch = _driver();
      final json = ch.toJson();
      expect(json.containsKey('additionalFrdSweeps'), isFalse);
    });

    test('empty additionalFrdSweeps restored when key absent in JSON', () {
      final ch = _driver();
      final json = ch.toJson()..remove('additionalFrdSweeps');
      final restored = DriverChannel.fromJson(Map<String, dynamic>.from(json));
      expect(restored.additionalFrdSweeps, isEmpty);
    });
  });

  // ── Test 5: Resolver passes both primary and additional sweeps ────────────

  group('test 5: resolver passes additional sweeps to adapter', () {
    test('ProProjectResolver carries additionalFrdSweeps into adapter context', () {
      final sweeps = [_entry('woofer_2.frd', _frdContent2)];
      final (:ctx, :store) = _setup(additionalSweeps: sweeps);

      // Verify the resolver exposes the additional sweeps.
      final state = ctx.resolver.resolveMeasurementProjectState(_pid, _driverId);
      final driver = state.driverChannels.firstWhere((d) => d.id == _driverId);
      expect(driver.additionalFrdSweeps, hasLength(1));
      expect(driver.additionalFrdSweeps.first.fileName, 'woofer_2.frd');

      // Adapter consumes them — multi-sweep confidence should differ from single.
      adapter.run(ctx, _step());
      final a = _artifact(store);
      expect(a.confidence!.status,
          isNot(equals(ConfidenceStatus.insufficientEvidence)));
    });
  });

  // ── Test 6: Multi-sweep production branch produces good/excellent score ───

  group('test 6: Guided AI reaches multi-sweep production branch', () {
    test('two distinct sweeps → confidence score above 0 and not insufficientEvidence', () {
      final sweeps = [_entry('woofer_2.frd', _frdContent2)];
      final (:ctx, :store) = _setup(additionalSweeps: sweeps);
      adapter.run(ctx, _step());
      final a = _artifact(store);

      expect(a.confidence, isNotNull);
      expect(a.confidence!.status,
          isNot(equals(ConfidenceStatus.insufficientEvidence)));
      expect(a.confidence!.overallScore, greaterThan(0));
    });

    test('multi-sweep path produces higher score than single-sweep path', () {
      // Single-sweep → insufficientEvidence, score may be partial.
      final setupSingle = _setup();
      adapter.run(setupSingle.ctx, _step());
      final single = _artifact(setupSingle.store);

      // Two distinct sweeps → score should improve.
      final sweeps = [_entry('woofer_2.frd', _frdContent2)];
      final setupMulti = _setup(additionalSweeps: sweeps);
      adapter.run(setupMulti.ctx, _step());
      final multi = _artifact(setupMulti.store);

      expect(multi.confidence!.overallScore ?? 0.0,
          greaterThan(single.confidence!.overallScore ?? 0.0));
    });

    test('numerically duplicate sweep is excluded — stays single-sweep', () {
      // Same numeric data formatted differently — should deduplicate to 1 sweep.
      final sweeps = [_entry('woofer_dup.frd', _frdContentSameNumeric)];
      final (:ctx, :store) = _setup(additionalSweeps: sweeps);
      adapter.run(ctx, _step());
      final a = _artifact(store);
      // After dedup, only 1 distinct sweep → single-sweep path.
      expect(a.confidence!.status,
          equals(ConfidenceStatus.insufficientEvidence));
    });
  });

  // ── Test 7: Remove sweep → back to single-sweep analysis-only ────────────

  group('test 7: remove sweep restores single-sweep behavior', () {
    test('after removing additional sweep, confidence reverts to insufficientEvidence', () {
      // With sweep: multi-sweep confidence.
      final sweeps = [_entry('woofer_2.frd', _frdContent2)];
      final setup1 = _setup(additionalSweeps: sweeps);
      adapter.run(setup1.ctx, _step());
      expect(_artifact(setup1.store).confidence!.status,
          isNot(equals(ConfidenceStatus.insufficientEvidence)));

      // After removal (no additional sweeps): back to single-sweep.
      final setup2 = _setup();
      adapter.run(setup2.ctx, _step());
      final a2 = _artifact(setup2.store);
      expect(a2.confidence!.status,
          equals(ConfidenceStatus.insufficientEvidence));
    });

    test('single-sweep path still produces a valid MeasurementArtifact', () {
      final (:ctx, :store) = _setup();
      adapter.run(ctx, _step());
      final a = _artifact(store);
      expect(a.parse.data, isNotNull);
      expect(a.evaluation, equals(MeasurementConfidenceEvaluation.evaluated));
    });

    test('FrdSweepEntry.fromRawContent contentHash matches expected prefix', () {
      final entry = _entry('test.frd', _frdContent);
      final expected = _hash(_frdContent);
      expect(entry.contentHash, equals(expected));
    });
  });
}
