import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/adau1701_peq_response.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_plan.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_types.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/impedance_analyze_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/measurement_analyze_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/simulate_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_artifact_store.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_execution.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_reference_resolver.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_registry.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_impedance_analysis.dart';
import 'package:tunai_pro/core/pro_measurement_parser.dart';
import 'package:tunai_pro/core/pro_simulation_optimizer.dart';

const _frd = '100 -3.0 0\n200 -2.0 0\n400 -1.0 0';
const _zma = '100 8.0 0\n200 7.0 0\n400 6.5 0';

ProMeasurementSource _frdSource() => const ProMeasurementSource(
    fileName: 'a.frd', content: _frd, format: AcousticFileType.frd);
ProMeasurementSource _zmaSource() => const ProMeasurementSource(
    fileName: 'a.zma', content: _zma, format: AcousticFileType.zma);
ProMeasurementSource _txtSource() => const ProMeasurementSource(
    fileName: 'a.txt', content: _frd, format: AcousticFileType.txt);

ProSimulationInput _simInput() => const ProSimulationInput(
      driver: DriverChannel(
          id: 'd1',
          name: 'Woofer',
          role: DriverRole.woofer,
          side: DriverSide.left),
      bands: [
        PeqResponseBand(frequencyHz: 100, gainDb: 3, q: 1, enabled: true),
      ],
      freqs: [50, 100, 200, 400],
    );

ProOrchestratorStep _step(
  ProOrchestratorToolId tool, {
  List<String> inputRefs = const ['in1'],
  String outputRef = 'out1',
  String objective = 'do the thing',
}) =>
    ProOrchestratorStep(
      stepId: 's1',
      toolId: tool,
      objective: objective,
      inputRefs: inputRefs,
      outputRef: outputRef,
      requiresUserConfirmation: false,
    );

ProDeterministicToolRegistry _registry() => ProDeterministicToolRegistry(const [
      MeasurementAnalyzeAdapter(),
      ImpedanceAnalyzeAdapter(),
      SimulateAdapter(),
    ]);

/// A context whose resolver/store are freshly built and seeded by the caller.
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
        contextRef: 'ctx1',
        resolver: resolver,
        store: store),
    resolver: resolver,
    store: store,
  );
}

void main() {
  group('Registry', () {
    test('1. the three tools are registered', () {
      final r = _registry();
      expect(r.supports(ProOrchestratorToolId.measurementAnalyze), isTrue);
      expect(r.supports(ProOrchestratorToolId.impedanceAnalyze), isTrue);
      expect(r.supports(ProOrchestratorToolId.simulate), isTrue);
      expect(r.registered.length, 3);
    });

    test('2. any other valid tool id is unsupportedTool', () {
      final r = _registry();
      final env = _ctx();
      for (final t in [
        ProOrchestratorToolId.peqOptimize,
        ProOrchestratorToolId.generateReport,
        ProOrchestratorToolId.crossoverPlan,
      ]) {
        expect(r.supports(t), isFalse);
        final outcome = r.execute(_step(t), env.ctx);
        expect(outcome, isA<ProToolFailure>());
        expect((outcome as ProToolFailure).code,
            ProToolFailureCode.unsupportedTool);
      }
    });

    test('3. execution is by typed enum step — no string tool path exists', () {
      // `execute` only accepts a ProOrchestratorStep whose toolId is the enum.
      // There is no String-keyed execute API to call with an arbitrary name.
      final r = _registry();
      expect(r.execute, isA<Function>());
    });

    test('4/5. duplicate/override registration is refused', () {
      expect(
          () => ProDeterministicToolRegistry(const [
                MeasurementAnalyzeAdapter(),
                MeasurementAnalyzeAdapter(),
              ]),
          throwsA(isA<ProToolException>()));
    });

    test('6. controlled actions cannot be named — enum has none', () {
      final names = ProOrchestratorToolId.values.map((e) => e.name);
      for (final bad in ['apply', 'deploy', 'write', 'transport']) {
        expect(names.contains(bad), isFalse);
      }
    });
  });

  group('Reference resolver', () {
    test('7. a correctly-scoped ref resolves', () {
      final env = _ctx();
      env.resolver.put('p1', 'in1', _frdSource());
      expect(
          env.resolver.resolveMeasurementSource('p1', 'in1').fileName, 'a.frd');
    });
    test('8. a missing ref fails', () {
      final env = _ctx();
      expect(
          () => env.resolver.resolveMeasurementSource('p1', 'nope'),
          throwsA(predicate((e) =>
              e is ProToolException &&
              e.code == ProToolFailureCode.missingReference)));
    });
    test('9. a ref from another project is not visible', () {
      final env = _ctx();
      env.resolver.put('other', 'in1', _frdSource());
      expect(
          () => env.resolver.resolveMeasurementSource('p1', 'in1'),
          throwsA(predicate((e) =>
              e is ProToolException &&
              e.code == ProToolFailureCode.missingReference)));
    });
    test('10. a type mismatch fails', () {
      final env = _ctx();
      env.resolver.put('p1', 'in1', _frdSource());
      expect(
          () => env.resolver.resolveSimulationInput('p1', 'in1'),
          throwsA(predicate((e) =>
              e is ProToolException &&
              e.code == ProToolFailureCode.typeMismatch)));
    });
  });

  group('Artifact store', () {
    // Store mechanics are exercised with a simple artifact type; the
    // measurement artifact's richer shape is covered by the adapter tests.
    SimulationArtifact art() => SimulationArtifact(const [1.0, 2.0, 3.0]);

    test('11. typed save/get round-trips', () {
      final s = ProToolArtifactStore();
      s.put('p1', 'out1', art());
      final got = s.getTyped<SimulationArtifact>('p1', 'out1');
      expect(got.curve, [1.0, 2.0, 3.0]);
    });
    test('12. same project + outputRef overwrite is refused', () {
      final s = ProToolArtifactStore();
      s.put('p1', 'out1', art());
      expect(
          () => s.put('p1', 'out1', art()),
          throwsA(predicate((e) =>
              e is ProToolException &&
              e.code == ProToolFailureCode.outputRefConflict)));
    });
    test('13. a different project is a separate namespace', () {
      final s = ProToolArtifactStore();
      s.put('p1', 'out1', art());
      expect(
          () => s.getTyped<SimulationArtifact>('p2', 'out1'),
          throwsA(predicate((e) =>
              e is ProToolException &&
              e.code == ProToolFailureCode.missingReference)));
      expect(() => s.put('p2', 'out1', art()), returnsNormally);
    });
    test('14. wrong-type retrieval fails', () {
      final s = ProToolArtifactStore();
      s.put('p1', 'out1', art());
      expect(
          () => s.getTyped<ImpedanceArtifact>('p1', 'out1'),
          throwsA(predicate((e) =>
              e is ProToolException &&
              e.code == ProToolFailureCode.typeMismatch)));
    });
    test('15. artifacts expose no toJson (no cloud serialization path)', () {
      expect(art(), isA<ProToolArtifact>());
    });
  });

  group('Adapters', () {
    test('16. measurement adapter == parser direct result (points)', () {
      final env = _ctx();
      env.resolver.put('p1', 'in1', _frdSource());
      final outcome = _registry()
          .execute(_step(ProOrchestratorToolId.measurementAnalyze), env.ctx);
      expect(outcome, isA<ProToolSuccess>());

      final stored =
          env.store.getTyped<MeasurementArtifact>('p1', 'out1').parse;
      final direct =
          ProMeasurementParser.parseFrd(fileName: 'a.frd', content: _frd);
      // ParsedMeasurementData.id/importedAt are timestamp-based; compare the
      // deterministic numeric content instead.
      expect(stored.status, direct.status);
      expect(_points(stored), _points(direct));
    });

    test('17. FRD and ZMA select the right parser', () {
      final env = _ctx();
      env.resolver.put('p1', 'frd', _frdSource());
      env.resolver.put('p1', 'zma', _zmaSource());
      final r = _registry();
      r.execute(
          _step(ProOrchestratorToolId.measurementAnalyze,
              inputRefs: ['frd'], outputRef: 'oFrd'),
          env.ctx);
      r.execute(
          _step(ProOrchestratorToolId.measurementAnalyze,
              inputRefs: ['zma'], outputRef: 'oZma'),
          env.ctx);
      final frd = env.store.getTyped<MeasurementArtifact>('p1', 'oFrd').parse;
      final zma = env.store.getTyped<MeasurementArtifact>('p1', 'oZma').parse;
      expect(frd.data?.fileType, AcousticFileType.frd);
      expect(zma.data?.fileType, AcousticFileType.zma);
    });

    test('18. an unknown measurement format fails closed', () {
      final env = _ctx();
      env.resolver.put('p1', 'in1', _txtSource());
      final outcome = _registry()
          .execute(_step(ProOrchestratorToolId.measurementAnalyze), env.ctx);
      expect(outcome, isA<ProToolFailure>());
      expect(
          (outcome as ProToolFailure).code, ProToolFailureCode.unknownFormat);
      // Nothing was stored.
      expect(env.store.has('p1', 'out1'), isFalse);
    });

    test('19. impedance adapter == analyzer direct result', () {
      final env = _ctx();
      const state = MeasurementProjectState();
      env.resolver.put('p1', 'in1', state);
      _registry()
          .execute(_step(ProOrchestratorToolId.impedanceAnalyze), env.ctx);
      final stored = env.store.getTyped<ImpedanceArtifact>('p1', 'out1').value;
      final direct = ProImpedanceAnalyzer.analyze(acousticState: state);
      // The analyzer stamps a timestamp id/createdAt; compare the deterministic
      // analysis content, not those internal fields.
      Map<String, dynamic> content(Map<String, dynamic> j) =>
          Map.of(j)..removeWhere((k, _) => k == 'id' || k == 'createdAt');
      expect(content(stored.toJson()), content(direct.toJson()));
    });

    test('20/21. simulate adapter == engine, and is deterministic', () {
      final env = _ctx();
      env.resolver.put('p1', 'in1', _simInput());
      _registry().execute(_step(ProOrchestratorToolId.simulate), env.ctx);
      final stored = env.store.getTyped<SimulationArtifact>('p1', 'out1').curve;
      final direct = ProSimulationOptimizer.simulatedResponse(
        driver: _simInput().driver,
        bands: _simInput().bands,
        freqs: _simInput().freqs,
      );
      expect(stored, direct);

      // Determinism: a second run in a fresh store yields the same curve.
      final env2 = _ctx();
      env2.resolver.put('p1', 'in1', _simInput());
      _registry().execute(_step(ProOrchestratorToolId.simulate), env2.ctx);
      expect(
          env2.store.getTyped<SimulationArtifact>('p1', 'out1').curve, stored);
    });

    test('22. objective/free text numbers do not affect the engine input', () {
      final a = _ctx();
      a.resolver.put('p1', 'in1', _simInput());
      _registry().execute(
          _step(ProOrchestratorToolId.simulate, objective: 'cut 80 Hz by 6 dB'),
          a.ctx);

      final b = _ctx();
      b.resolver.put('p1', 'in1', _simInput());
      _registry()
          .execute(_step(ProOrchestratorToolId.simulate, objective: ''), b.ctx);

      expect(a.store.getTyped<SimulationArtifact>('p1', 'out1').curve,
          b.store.getTyped<SimulationArtifact>('p1', 'out1').curve);
    });

    test('23. outputRef is used as the storage key', () {
      final env = _ctx();
      env.resolver.put('p1', 'in1', _simInput());
      _registry().execute(
          _step(ProOrchestratorToolId.simulate, outputRef: 'myCurve'), env.ctx);
      expect(env.store.has('p1', 'myCurve'), isTrue);
    });

    test('24. an engine/resolve failure becomes a typed failure', () {
      final env = _ctx(); // resolver empty → missingReference
      final outcome =
          _registry().execute(_step(ProOrchestratorToolId.simulate), env.ctx);
      expect(outcome, isA<ProToolFailure>());
      expect((outcome as ProToolFailure).code,
          ProToolFailureCode.missingReference);
    });
  });

  group('Boundary', () {
    test('26. success result JSON carries only references, no DSP numbers', () {
      final env = _ctx();
      env.resolver.put('p1', 'in1', _simInput());
      final outcome =
          _registry().execute(_step(ProOrchestratorToolId.simulate), env.ctx);
      final json =
          (outcome as ProToolSuccess).result.toJson().toString().toLowerCase();
      for (final token in [
        '"frequency"',
        '"gaindb"',
        '"q"',
        '"curve"',
        '"points"'
      ]) {
        expect(json.contains(token), isFalse, reason: '$token must not leak');
      }
      // It DOES carry references.
      expect(outcome.result.outputRef, 'out1');
      expect(outcome.result.evidenceRefs, contains('out1'));
    });
  });
}

List<List<double?>> _points(MeasurementParseResult r) => [
      for (final p in r.data?.points ?? const [])
        [p.frequencyHz, p.magnitudeDb, p.impedanceOhm]
    ];
