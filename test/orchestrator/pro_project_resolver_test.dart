import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_project_resolver.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_execution.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_reference_resolver.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

final _now = DateTime(2025, 1, 1);

/// Minimal project skeleton — only override what each test needs.
ProProject project({
  String id = 'p1',
  MeasurementProjectState? acoustic,
  TuningProjectState? tuning,
}) =>
    ProProject(
      id: id,
      name: 'Test Project',
      createdAt: _now,
      updatedAt: _now,
      acousticState: acoustic,
      tuningState: tuning,
    );

/// A DriverChannel with parsed FRD data at two frequency points.
DriverChannel driver({
  String id = 'ch_wf',
  bool withFrd = true,
}) =>
    DriverChannel(
      id: id,
      name: 'Woofer L',
      role: DriverRole.woofer,
      side: DriverSide.left,
      frdData: withFrd
          ? ParsedMeasurementData(
              id: 'frd-1',
              sourceFileName: 'woofer.frd',
              fileType: AcousticFileType.frd,
              importedAt: _now,
              points: const [
                MeasurementDataPoint(frequencyHz: 100.0, magnitudeDb: -3.0),
                MeasurementDataPoint(frequencyHz: 200.0, magnitudeDb: -6.0),
              ],
            )
          : null,
    );

/// A PeqChannelState with one active band at 200 Hz.
PeqChannelState peqChannel({
  String channelId = 'ch_wf',
  bool bypassed = false,
  List<PeqBand>? bands,
}) =>
    PeqChannelState(
      channelId: channelId,
      bypassed: bypassed,
      bands: bands ??
          [
            const PeqBand(id: 'b0', frequencyHz: 200.0, gainDb: -3.0, q: 1.5),
          ],
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── resolveMeasurementProjectState ────────────────────────────────────────

  group('resolveMeasurementProjectState', () {
    test('returns project acousticState regardless of ref', () {
      final acoustic = MeasurementProjectState(
        driverChannels: [driver()],
      );
      final resolver = ProProjectResolver(project: project(acoustic: acoustic));

      final result = resolver.resolveMeasurementProjectState('p1', 'any-ref');

      expect(result, same(acoustic));
    });

    test('ref is ignored — always returns the same acoustic state', () {
      final acoustic = MeasurementProjectState(driverChannels: [driver()]);
      final resolver = ProProjectResolver(project: project(acoustic: acoustic));

      final r1 = resolver.resolveMeasurementProjectState('p1', 'ref-a');
      final r2 = resolver.resolveMeasurementProjectState('p1', 'ref-b');

      expect(r1, same(r2));
    });

    test('wrong projectId throws missingReference', () {
      final resolver = ProProjectResolver(project: project(id: 'p1'));

      expect(
        () => resolver.resolveMeasurementProjectState('p999', 'ref'),
        throwsA(predicate<ProToolException>(
            (e) => e.code == ProToolFailureCode.missingReference)),
      );
    });

    test('error message names both scoped and requested project id', () {
      final resolver = ProProjectResolver(project: project(id: 'p1'));

      expect(
        () => resolver.resolveMeasurementProjectState('p999', 'ref'),
        throwsA(predicate<ProToolException>(
            (e) => e.message.contains('p1') && e.message.contains('p999'))),
      );
    });
  });

  // ── resolveSimulationInput ─────────────────────────────────────────────────

  group('resolveSimulationInput', () {
    test('returns driver and freq grid from frdData', () {
      final ch = driver();
      final acoustic = MeasurementProjectState(driverChannels: [ch]);
      final resolver = ProProjectResolver(project: project(acoustic: acoustic));

      final result = resolver.resolveSimulationInput('p1', 'ch_wf');

      expect(result.driver.id, 'ch_wf');
      expect(result.freqs, [100.0, 200.0]);
    });

    test('freq grid is empty when driver has no frdData', () {
      final ch = driver(withFrd: false);
      final acoustic = MeasurementProjectState(driverChannels: [ch]);
      final resolver = ProProjectResolver(project: project(acoustic: acoustic));

      final result = resolver.resolveSimulationInput('p1', 'ch_wf');

      expect(result.freqs, isEmpty);
    });

    test('bands are populated from matching PeqChannelState', () {
      final ch = driver();
      final acoustic = MeasurementProjectState(driverChannels: [ch]);
      final tuning = TuningProjectState(peqChannels: [peqChannel()]);
      final resolver = ProProjectResolver(
          project: project(acoustic: acoustic, tuning: tuning));

      final result = resolver.resolveSimulationInput('p1', 'ch_wf');

      expect(result.bands, hasLength(1));
      expect(result.bands.single.frequencyHz, 200.0);
      expect(result.bands.single.gainDb, -3.0);
      expect(result.bands.single.q, 1.5);
    });

    test('PeqBand values are mapped correctly to PeqResponseBand', () {
      const band = PeqBand(
        id: 'b0',
        frequencyHz: 800.0,
        gainDb: -4.5,
        q: 2.0,
      );
      final ch = driver();
      final acoustic = MeasurementProjectState(driverChannels: [ch]);
      final tuning = TuningProjectState(peqChannels: [
        peqChannel(bands: [band])
      ]);
      final resolver = ProProjectResolver(
          project: project(acoustic: acoustic, tuning: tuning));

      final result = resolver.resolveSimulationInput('p1', 'ch_wf');

      final rb = result.bands.single;
      expect(rb.frequencyHz, 800.0);
      expect(rb.gainDb, -4.5);
      expect(rb.q, 2.0);
    });

    test('bypassed band (PeqBandStatus.bypassed) is excluded', () {
      final ch = driver();
      final acoustic = MeasurementProjectState(driverChannels: [ch]);
      final tuning = TuningProjectState(peqChannels: [
        peqChannel(bands: [
          const PeqBand(
              id: 'b0',
              frequencyHz: 200.0,
              gainDb: -3.0,
              q: 1.5,
              status: PeqBandStatus.bypassed),
          const PeqBand(id: 'b1', frequencyHz: 400.0, gainDb: -2.0, q: 1.0),
        ])
      ]);
      final resolver = ProProjectResolver(
          project: project(acoustic: acoustic, tuning: tuning));

      final result = resolver.resolveSimulationInput('p1', 'ch_wf');

      expect(result.bands, hasLength(1));
      expect(result.bands.single.frequencyHz, 400.0);
    });

    test('disabled band (enabled = false) is excluded', () {
      final ch = driver();
      final acoustic = MeasurementProjectState(driverChannels: [ch]);
      final tuning = TuningProjectState(peqChannels: [
        peqChannel(bands: [
          const PeqBand(
              id: 'b0',
              frequencyHz: 200.0,
              gainDb: -3.0,
              q: 1.5,
              enabled: false),
          const PeqBand(id: 'b1', frequencyHz: 400.0, gainDb: -2.0, q: 1.0),
        ])
      ]);
      final resolver = ProProjectResolver(
          project: project(acoustic: acoustic, tuning: tuning));

      final result = resolver.resolveSimulationInput('p1', 'ch_wf');

      expect(result.bands, hasLength(1));
      expect(result.bands.single.frequencyHz, 400.0);
    });

    test('channel-level bypass yields empty band list', () {
      final ch = driver();
      final acoustic = MeasurementProjectState(driverChannels: [ch]);
      final tuning =
          TuningProjectState(peqChannels: [peqChannel(bypassed: true)]);
      final resolver = ProProjectResolver(
          project: project(acoustic: acoustic, tuning: tuning));

      final result = resolver.resolveSimulationInput('p1', 'ch_wf');

      expect(result.bands, isEmpty);
    });

    test('no matching PeqChannelState yields empty band list', () {
      final ch = driver();
      final acoustic = MeasurementProjectState(driverChannels: [ch]);
      // tuning has no channel for 'ch_wf'
      final tuning =
          TuningProjectState(peqChannels: [peqChannel(channelId: 'ch_tw')]);
      final resolver = ProProjectResolver(
          project: project(acoustic: acoustic, tuning: tuning));

      final result = resolver.resolveSimulationInput('p1', 'ch_wf');

      expect(result.bands, isEmpty);
    });

    test('no peqChannels at all yields empty band list', () {
      final ch = driver();
      final acoustic = MeasurementProjectState(driverChannels: [ch]);
      final resolver = ProProjectResolver(project: project(acoustic: acoustic));

      final result = resolver.resolveSimulationInput('p1', 'ch_wf');

      expect(result.bands, isEmpty);
    });

    test('unknown driver ref throws missingReference', () {
      final acoustic =
          MeasurementProjectState(driverChannels: [driver(id: 'ch_wf')]);
      final resolver = ProProjectResolver(project: project(acoustic: acoustic));

      expect(
        () => resolver.resolveSimulationInput('p1', 'ch_unknown'),
        throwsA(predicate<ProToolException>(
            (e) => e.code == ProToolFailureCode.missingReference)),
      );
    });

    test('wrong projectId throws missingReference', () {
      final resolver = ProProjectResolver(project: project(id: 'p1'));

      expect(
        () => resolver.resolveSimulationInput('p999', 'ch_wf'),
        throwsA(predicate<ProToolException>(
            (e) => e.code == ProToolFailureCode.missingReference)),
      );
    });

    test('multiple active bands all included', () {
      final ch = driver();
      final acoustic = MeasurementProjectState(driverChannels: [ch]);
      final tuning = TuningProjectState(peqChannels: [
        peqChannel(bands: [
          const PeqBand(id: 'b0', frequencyHz: 100.0, gainDb: -1.0, q: 1.0),
          const PeqBand(id: 'b1', frequencyHz: 200.0, gainDb: -2.0, q: 1.0),
          const PeqBand(id: 'b2', frequencyHz: 400.0, gainDb: -3.0, q: 1.0),
        ])
      ]);
      final resolver = ProProjectResolver(
          project: project(acoustic: acoustic, tuning: tuning));

      final result = resolver.resolveSimulationInput('p1', 'ch_wf');

      expect(result.bands, hasLength(3));
    });
  });

  // ── resolveMeasurementSource ───────────────────────────────────────────────

  group('resolveMeasurementSource', () {
    test('throws unsupportedTool — raw content not stored in ProProject', () {
      final resolver = ProProjectResolver(project: project());

      expect(
        () => resolver.resolveMeasurementSource('p1', 'any-ref'),
        throwsA(predicate<ProToolException>(
            (e) => e.code == ProToolFailureCode.unsupportedTool)),
      );
    });
  });

  // ── Determinism ───────────────────────────────────────────────────────────

  group('determinism', () {
    test('same project produces identical simulation input on two calls', () {
      final ch = driver();
      final acoustic = MeasurementProjectState(driverChannels: [ch]);
      final tuning = TuningProjectState(peqChannels: [peqChannel()]);
      final resolver = ProProjectResolver(
          project: project(acoustic: acoustic, tuning: tuning));

      final r1 = resolver.resolveSimulationInput('p1', 'ch_wf');
      final r2 = resolver.resolveSimulationInput('p1', 'ch_wf');

      expect(r1.driver.id, r2.driver.id);
      expect(r1.freqs, r2.freqs);
      expect(r1.bands.length, r2.bands.length);
      for (var i = 0; i < r1.bands.length; i++) {
        expect(r1.bands[i].frequencyHz, r2.bands[i].frequencyHz);
        expect(r1.bands[i].gainDb, r2.bands[i].gainDb);
        expect(r1.bands[i].q, r2.bands[i].q);
      }
    });
  });

  // ── No DSP in Cloud-facing path ───────────────────────────────────────────

  group('no DSP in Cloud-facing path', () {
    // ProSimulationInput has no toJson() — numeric values never serialise to
    // a Cloud-facing structure. This test verifies the resolver produces a
    // well-typed local result without any unexpected dynamic Map.
    test('resolveSimulationInput returns typed ProSimulationInput, not a Map',
        () {
      final ch = driver();
      final acoustic = MeasurementProjectState(driverChannels: [ch]);
      final resolver = ProProjectResolver(project: project(acoustic: acoustic));

      final result = resolver.resolveSimulationInput('p1', 'ch_wf');

      expect(result, isA<ProSimulationInput>());
      // Verify driver is the actual DriverChannel object, not a Map.
      expect(result.driver, isA<DriverChannel>());
    });

    test('resolveMeasurementProjectState returns typed MeasurementProjectState',
        () {
      final acoustic = MeasurementProjectState(driverChannels: [driver()]);
      final resolver = ProProjectResolver(project: project(acoustic: acoustic));

      final result = resolver.resolveMeasurementProjectState('p1', 'ref');

      expect(result, isA<MeasurementProjectState>());
    });
  });
}
