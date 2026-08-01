import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/measurement_confidence.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_plan.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_types.dart';
import 'package:tunai_pro/core/orchestrator/tools/adapters/parsed_measurement_adapter.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_artifact_store.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_project_resolver.dart';
import 'package:tunai_pro/core/orchestrator/tools/pro_tool_registry.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';

const _content = '100 -3\n200 -2\n300 -1\n400 0\n500 1\n600 2\n700 3\n800 4';
const _mismatch = '100 7\n200 8\n300 9\n400 10\n500 11\n600 12\n700 13\n800 14';

ProProject _project(String repeat) {
  final now = DateTime(2026, 8, 1);
  return ProProject(
    id: 'p',
    name: 'p',
    createdAt: now,
    updatedAt: now,
    acousticState: MeasurementProjectState(
      driverChannels: [
        DriverChannel(
          id: 'ch_tw_l',
          name: 'TW L',
          role: DriverRole.tweeter,
          side: DriverSide.left,
          frdData: ParsedMeasurementData(
            id: 'before',
            sourceFileName: 'before.frd',
            fileType: AcousticFileType.frd,
            importedAt: now,
            points: [
              for (var i = 0; i < 8; i++)
                MeasurementDataPoint(
                    frequencyHz: (100 + i * 100).toDouble(),
                    magnitudeDb: (-3 + i).toDouble()),
            ],
          ),
          additionalFrdSweeps: [
            FrdSweepEntry.fromRawContent('repeat.frd', repeat),
          ],
        ),
      ],
    ),
  );
}

MeasurementArtifact _run(ProProject project) {
  final store = ProToolArtifactStore();
  const step = ProOrchestratorStep(
    stepId: 'measure',
    toolId: ProOrchestratorToolId.measurementAnalyze,
    objective: 'repeat',
    inputRefs: ['ch_tw_l'],
    outputRef: 'measurement',
    requiresUserConfirmation: false,
  );
  const ParsedMeasurementAdapter().run(
    ProToolExecutionContext(
      projectId: 'p',
      contextRef: 'ctx',
      resolver: ProProjectResolver(project: project),
      store: store,
    ),
    step,
  );
  return store.getTyped<MeasurementArtifact>('p', 'measurement');
}

void main() {
  test('identical Repeat FRD is retained and raises repeatability confidence', () {
    final confidence = _run(_project(_content)).confidence!;
    expect(confidence.repeatability.status, MetricStatus.available);
    expect(confidence.repeatability.score, 1.0);
    expect(confidence.status, ConfidenceStatus.valid);
  });

  test('large Repeat FRD disagreement remains measured and blocks confidence', () {
    final confidence = _run(_project(_mismatch)).confidence!;
    expect(confidence.repeatability.status, MetricStatus.available);
    expect(confidence.repeatability.score, 0.0);
    expect(confidence.status, ConfidenceStatus.valid);
    expect(confidence.warnings, isNotEmpty);
  });

  test('no Repeat FRD keeps repeatability unavailable and insufficient', () {
    final project = _project(_content).copyWith(
      acousticState: MeasurementProjectState(
        driverChannels: [
          _project(_content).acousticState.driverChannels.single
              .copyWith(additionalFrdSweeps: const []),
        ],
      ),
    );
    final confidence = _run(project).confidence!;
    expect(confidence.repeatability.status, MetricStatus.unavailable);
    expect(confidence.status, ConfidenceStatus.insufficientEvidence);
  });
}
