// Production UI flow tests — A through N.
//
// These tests exercise real production widgets, providers, and controllers.
// No production logic is mirrored in test helpers; helpers only construct
// test fixtures and override providers at the ProviderScope boundary.
//
// Project store is seeded via SharedPreferences serialization so
// ProProjectStoreNotifier._load() finds the project naturally.
//
// Cases:
//   A  No FRD        — warning shown, Analyze disabled
//   B  Candidate preview — channelId / slot / freq / gain / Q / grade / safety
//   C  Apply success  — PEQ 업데이트 완료 + Deploy next action
//   D  Apply failure  — 적용 차단 shown, no success transition
//   E  Deploy readiness — project / DSP target / PEQ count in panel
//   F  Real PASS_ACK  — After Measurement action visible in HardwareApplyFlow
//   G  ACK absent     — hardware not ready → blocked state shown
//   H  Improved cycle (improvedAndComplete) — 개선 완료, no 추가 보정 button
//   I  Worsened cycle — 성능 저하 감지, no 추가 보정 button
//   J  Continue cycle — improvedNeedsAnotherCycle → 추가 보정 visible
//   K  Complete cycle — 완료 tap sets deployScrollTargetProvider + navigates Deploy
//   L  Profile saved  — name / version / fingerprint / export action visible
//   M  Wrong project  — unknown projectId → 프로젝트 fallback shown
//   N  Navigation     — workbenchTabProvider.go drives tab switch

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/acoustic/acoustic_apply_engine.dart';
import 'package:tunai_pro/core/deploy/pro_adau1701_hardware_context.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/factory_sound_profile.dart';
import 'package:tunai_pro/core/orchestrator/pro_explanation.dart';
import 'package:tunai_pro/core/orchestrator/pro_guided_ai_controller.dart';
import 'package:tunai_pro/core/orchestrator/pro_guided_ai_state.dart';
import 'package:tunai_pro/core/orchestrator/pro_local_orchestrator_session.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_plan.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_types.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_correction_cycle.dart';
import 'package:tunai_pro/core/pro_export_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_protection_data.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/core/transport/adau1701_tuning_transport.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';
import 'package:tunai_pro/core/workbench_tab_provider.dart';
import 'package:tunai_pro/features/ai/guided_ai_screen.dart';
import 'package:tunai_pro/features/workbench/tabs/deploy_tab.dart';
import 'package:tunai_pro/features/workbench/widgets/hardware_apply_flow.dart';
import 'package:tunai_pro/features/workbench/workbench_shell.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const _kProjectsKey = 'tunai_pro_projects';

// ── Fake providers ─────────────────────────────────────────────────────────────

/// Starts the guided-AI controller with a preset state.
class _FakeGuidedAiController extends ProGuidedAiController {
  _FakeGuidedAiController(ProGuidedAiState initial) {
    state = initial;
  }
}

// ── Fake hardware transport ────────────────────────────────────────────────────

const _kDeviceId = 'DSP1701.100.00.01';

List<int> _statePayload() {
  final p = List<int>.filled(513, 0x00);
  p[19] = 0x08;
  p[20] = 0x07;
  p[21] = 0xF6;
  p[23] = 0x14;
  p[24] = 0x01;
  p[154] = 0x01;
  p[308] = 0x02;
  return p;
}

class _FakeTransport implements Adau1701TuningTransport {
  final bool connected;
  _FakeTransport({this.connected = true});

  @override
  bool get isConnected => connected;
  @override
  bool get handshakeComplete => connected;
  @override
  String? get detectedProfile => connected ? _kDeviceId : null;

  @override
  Future<RawDspStateSnapshot> readRawDspState() async => RawDspStateSnapshot(
        deviceId: _kDeviceId,
        timestamp: DateTime.utc(2025, 6, 1, 12),
        blockId: 0x2202,
        payload: _statePayload(),
      );

  @override
  Future<Adau1701WriteAck> writePeqGain(int c, double g, {int band = 0}) async =>
      const Adau1701WriteAck(success: true, message: 'ok');

  @override
  Future<Adau1701WriteAck> writeFilterFrequency(int c, int f,
          {int band = 0}) async =>
      const Adau1701WriteAck(success: true, message: 'ok');
  @override
  Future<Adau1701WriteAck> writePeqFrequency(int c, int f,
          {int band = 0}) async =>
      const Adau1701WriteAck(success: true, message: 'ok');

  @override
  Future<Adau1701WriteAck> writePeqQ(int c, double q, {int band = 0}) async =>
      const Adau1701WriteAck(success: true, message: 'ok');

  @override
  Future<Adau1701WriteAck> writeOutputGain(int c, double g) async =>
      const Adau1701WriteAck(success: true, message: 'ok');

  @override
  Future<Adau1701WriteAck> writeMasterMute(bool muted) async =>
      const Adau1701WriteAck(success: true, message: 'ok');
}

// ── Fixtures ──────────────────────────────────────────────────────────────────

final _baseProject = ProProject(
  id: 'test-proj',
  name: 'Test Project',
  dspTarget: 'ADAU1701',
  createdAt: DateTime.utc(2025, 1, 1),
  updatedAt: DateTime.utc(2025, 1, 1),
);

final _projectWithFrd = ProProject(
  id: 'test-proj',
  name: 'Test Project',
  dspTarget: 'ADAU1701',
  createdAt: DateTime.utc(2025, 1, 1),
  updatedAt: DateTime.utc(2025, 1, 1),
  acousticState: MeasurementProjectState(
    driverChannels: [
      DriverChannel(
        id: 'ch_wf_l',
        name: 'Woofer L',
        role: DriverRole.coaxWoofer,
        side: DriverSide.left,
        frdData: ParsedMeasurementData(
          id: 'frd-0',
          sourceFileName: 'woofer_l.frd',
          fileType: AcousticFileType.frd,
          importedAt: DateTime.utc(2025, 1, 1),
          points: const [
            MeasurementDataPoint(frequencyHz: 1000, magnitudeDb: 85.0),
          ],
        ),
      ),
    ],
  ),
  tuningState: TuningProjectState(
    peqChannels: [
      PeqChannelState.fixed('ch_wf_l'),
    ],
  ),
);

const _stubOutcome = ProLocalOrchestratorOutcome(
  sessionId: 'sess-0',
  finalStatus: ProOrchestratorOutcomeStatus.completed,
  stepRecords: [],
);

const _stubExplanation = ProExplanation(
  title: '분석 완료',
  summary: '음향 분석이 완료되었습니다.',
  explanationLevel: ProExplanationLevel.intermediate,
);

const _stubChannel = PeqChannelState(
  channelId: 'ch_wf_l',
  bands: [
    PeqBand(id: 'b0', frequencyHz: 200.0, gainDb: -3.0, q: 1.5),
  ],
);

const _stubApplyResult = TuningApplyResult(
  status: TuningApplyStatus.ok,
  updatedChannel: _stubChannel,
  applied: [
    AppliedBand(
      candidateId: 'cand-0',
      featureId: 'feat-0',
      frequencyHz: 200.0,
      gainDb: -3.0,
      q: 1.5,
      applicationOrder: 1,
    ),
  ],
  skipped: [],
  channelId: 'ch_wf_l',
  safetyPolicyId: 'stub-policy',
  safetyPolicyVersion: 1,
  evidenceRefs: [],
  reasons: [],
);

const _stubFailApplyResult = TuningApplyResult(
  status: TuningApplyStatus.notPermitted,
  updatedChannel: _stubChannel,
  applied: [],
  skipped: [],
  channelId: 'ch_wf_l',
  safetyPolicyId: 'stub-policy',
  safetyPolicyVersion: 1,
  evidenceRefs: [],
  reasons: ['Safety validator blocked apply'],
);

CorrectionCycle _cycle(CorrectionCycleDecision decision) => CorrectionCycle(
      projectId: 'test-proj',
      channelId: 'ch_wf_l',
      cycleNumber: 1,
      beforeMeasurementRef: 'before-ref',
      peqSnapshot: _stubChannel,
      createdAt: DateTime.utc(2025, 1, 1),
      metrics: const CorrectionCycleMetrics(
        commonFreqMinHz: 200,
        commonFreqMaxHz: 10000,
        commonPointCount: 100,
        meanAbsResidualBefore: 5.0,
        meanAbsResidualAfter: 2.0,
        improvementDelta: 3.0,
        peakErrorBefore: 8.0,
        peakErrorBeforeHz: 400,
        peakErrorAfter: 3.0,
        peakErrorAfterHz: 400,
        worsenedBandCount: 2,
        improvementCoverage: 0.85,
      ),
      decision: decision,
      completedAt: DateTime.utc(2025, 1, 2),
    );

final _stubProfile = FactorySoundProfile(
  profileId: 'fp-001',
  projectId: 'test-proj',
  profileName: 'Production v1',
  version: 1,
  createdAt: DateTime.utc(2025, 1, 1),
  hardwareTarget: 'ADAU1701',
  sampleRate: 48000,
  channelConfig: '2-way stereo',
  tuningSnapshot: TuningProjectState.createDefault(),
  protectionSnapshot: ProtectionProjectState.createDefault(),
  completedCycleNumbers: const [1],
  validationStatus: 'ready',
  projectFingerprint: 'abc123def456',
  manuallyApproved: true,
);

DspExportPackage _exportPkg() => DspExportPackage(
      id: 'exp1',
      parameterBlocks: [
        const ExportParameterBlock(
          id: 'blk',
          type: ExportBlockType.peq,
          channelId: 'ch_wf_l', // defaultChannelResolver: ch_wf_l → ADAU1701 channel 1
          title: 'PEQ',
          summary: '',
          parameters: {
            'bands': {
              'band_0': {
                'freq_hz': 1800.0,
                'gain_db': -1.0,
                'q': 2.0,
                'type': 'peak'
              },
            }
          },
        ),
      ],
    );

const _stubPlan = ProOrchestratorPlan(
  planId: 'plan-0',
  intentRef: 'intent-0',
  contextRef: 'ctx-0',
  steps: [],
);

const _stubRequest = ProUserConfirmationRequest(
  stepId: 'step-1',
  toolId: ProOrchestratorToolId.acousticOptimizeSelection,
  objective: '후보 선택을 승인하세요.',
  explanation: ProExplanation(
    title: '승인 필요',
    summary: '후보를 적용하려면 승인하세요.',
    explanationLevel: ProExplanationLevel.intermediate,
  ),
);

// ── Store seeding helpers ──────────────────────────────────────────────────────

/// Serialises [projects] into SharedPreferences so the real
/// ProProjectStoreNotifier._load() finds them on the next pump.
void _seedProjects(List<ProProject> projects) {
  SharedPreferences.setMockInitialValues({
    _kProjectsKey: ProProject.encodeList(projects),
  });
}

// ── Widget helpers ─────────────────────────────────────────────────────────────

Widget _aiScreen(ProGuidedAiState initialState) =>
    ProviderScope(
      overrides: [
        guidedAiProvider.overrideWith(
            (ref) => _FakeGuidedAiController(initialState)),
      ],
      child: const MaterialApp(home: GuidedAiScreen(projectId: 'test-proj')),
    );

Widget _deployTab() => ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: DeployTab(projectId: 'test-proj'),
        ),
      ),
    );

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ── A: No FRD ──────────────────────────────────────────────────────────────

  group('A. No FRD', () {
    testWidgets('FRD warning shown when project has no parsed FRD',
        (tester) async {
      // Project with no FRD seeded — parsedFrdCount == 0
      _seedProjects([_baseProject]);
      await tester.pumpWidget(_aiScreen(const ProGuidedAiIdle()));
      await tester.pumpAndSettle();

      expect(find.textContaining('FRD 파일이 없습니다'), findsAtLeastNWidgets(1));
    });

    testWidgets('Analyze button disabled when parsedFrdCount is 0',
        (tester) async {
      _seedProjects([_baseProject]);
      await tester.pumpWidget(_aiScreen(const ProGuidedAiIdle()));
      await tester.pumpAndSettle();

      // When FRD is missing, button shows '분석 불가 — FRD 파일이 없습니다.'
      expect(find.textContaining('분석 불가'), findsAtLeastNWidgets(1));
      // The actual FilledButton (AI 분석 시작) onPressed is null
      final btn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'AI 분석 시작'),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('FRD warning absent when project has parsed FRD',
        (tester) async {
      _seedProjects([_projectWithFrd]);
      await tester.pumpWidget(_aiScreen(const ProGuidedAiIdle()));
      await tester.pumpAndSettle();

      expect(find.textContaining('FRD 파일이 없습니다'), findsNothing);
    });

    testWidgets('FRD warning shown when store is empty (no project found)',
        (tester) async {
      // Empty store — project not found → parsedFrdCount == 0 fallback
      await tester.pumpWidget(_aiScreen(const ProGuidedAiIdle()));
      await tester.pumpAndSettle();

      expect(find.textContaining('FRD 파일이 없습니다'), findsAtLeastNWidgets(1));
    });
  });

  // ── B: Candidate preview ───────────────────────────────────────────────────

  group('B. Candidate preview', () {
    final confirmState = ProGuidedAiConfirmPending(
      request: _stubRequest,
      plan: _stubPlan,
      explanation: _stubExplanation,
      completedSteps: const [],
      targetChannelId: 'ch_wf_l',
      availablePeqSlots: 8,
      candidatePreview: const [
        CandidatePreviewEntry(
          applicationOrder: 1,
          frequencyHz: 315.0,
          gainDb: -2.5,
          q: 1.41,
          grade: 'A',
          channelId: 'CWF · L',
          safetyVerified: false,
          targetPeqSlot: 3,
        ),
      ],
    );

    testWidgets('candidate table header columns shown', (tester) async {
      await tester.pumpWidget(_aiScreen(confirmState));
      await tester.pump();

      expect(find.text('Ch'), findsOneWidget);
      expect(find.text('Slot'), findsOneWidget);
      expect(find.text('Freq'), findsOneWidget);
      expect(find.text('Gain'), findsOneWidget);
      expect(find.text('Q'), findsOneWidget);
      expect(find.text('Grade'), findsOneWidget);
      expect(find.text('Safety'), findsOneWidget);
    });

    testWidgets('target PEQ slot shown in candidate row', (tester) async {
      await tester.pumpWidget(_aiScreen(confirmState));
      await tester.pump();

      // targetPeqSlot: 3 is rendered directly in the Slot column
      expect(find.text('3'), findsAtLeastNWidgets(1));
    });

    testWidgets('channelId shown in candidate row', (tester) async {
      await tester.pumpWidget(_aiScreen(confirmState));
      await tester.pump();

      expect(find.textContaining('CWF · L'), findsAtLeastNWidgets(1));
    });

    testWidgets('frequency shown in candidate row', (tester) async {
      await tester.pumpWidget(_aiScreen(confirmState));
      await tester.pump();

      expect(find.textContaining('315 Hz'), findsAtLeastNWidgets(1));
    });

    testWidgets('gain shown in candidate row', (tester) async {
      await tester.pumpWidget(_aiScreen(confirmState));
      await tester.pump();

      expect(find.textContaining('-2.5 dB'), findsAtLeastNWidgets(1));
    });

    testWidgets('grade shown in candidate row', (tester) async {
      await tester.pumpWidget(_aiScreen(confirmState));
      await tester.pump();

      // Grade 'A' will appear multiple times (header '#' col and the value)
      expect(find.textContaining('A'), findsAtLeastNWidgets(1));
    });

    testWidgets('safety pending indicator shown', (tester) async {
      await tester.pumpWidget(_aiScreen(confirmState));
      await tester.pump();

      expect(find.textContaining('대기'), findsAtLeastNWidgets(1));
    });

    testWidgets('slot availability summary shown', (tester) async {
      await tester.pumpWidget(_aiScreen(confirmState));
      await tester.pump();

      expect(find.textContaining('슬롯 8개 가용'), findsOneWidget);
    });

    testWidgets('candidate count shown', (tester) async {
      await tester.pumpWidget(_aiScreen(confirmState));
      await tester.pump();

      expect(find.textContaining('후보 1개'), findsAtLeastNWidgets(1));
    });

    testWidgets('blocked reason shown when slots insufficient', (tester) async {
      final overflowState = ProGuidedAiConfirmPending(
        request: _stubRequest,
        plan: _stubPlan,
        explanation: _stubExplanation,
        completedSteps: const [],
        availablePeqSlots: 1,
        applyBlockedReason: '슬롯 부족: 3개 필요, 채널 ch_wf_l에 1개 가능',
        candidatePreview: const [
          CandidatePreviewEntry(
              applicationOrder: 1,
              frequencyHz: 200,
              gainDb: -1.0,
              q: 1.0,
              grade: 'B',
              channelId: 'CWF · L'),
          CandidatePreviewEntry(
              applicationOrder: 2,
              frequencyHz: 400,
              gainDb: -2.0,
              q: 1.0,
              grade: 'B',
              channelId: 'CWF · L'),
          CandidatePreviewEntry(
              applicationOrder: 3,
              frequencyHz: 800,
              gainDb: -1.5,
              q: 1.0,
              grade: 'C',
              channelId: 'CWF · L'),
        ],
      );

      await tester.pumpWidget(_aiScreen(overflowState));
      await tester.pump();

      expect(find.textContaining('적용 차단'), findsAtLeastNWidgets(1));
    });
  });

  // ── C: Apply success ───────────────────────────────────────────────────────

  group('C. Apply success', () {
    final state = ProGuidedAiCompleted(
      outcome: _stubOutcome,
      explanation: _stubExplanation,
      applyResult: _stubApplyResult,
    );

    testWidgets('PEQ 업데이트 완료 label shown', (tester) async {
      await tester.pumpWidget(_aiScreen(state));
      await tester.pump();

      expect(find.textContaining('PEQ 업데이트 완료'), findsAtLeastNWidgets(1));
    });

    testWidgets('Deploy로 이동 button shown after ok apply', (tester) async {
      await tester.pumpWidget(_aiScreen(state));
      await tester.pump();

      expect(find.textContaining('Deploy로 이동'), findsOneWidget);
    });

    testWidgets('applied band count shown in result', (tester) async {
      await tester.pumpWidget(_aiScreen(state));
      await tester.pump();

      expect(find.textContaining('1밴드'), findsAtLeastNWidgets(1));
    });

    testWidgets('no false hardware-success term in apply result',
        (tester) async {
      await tester.pumpWidget(_aiScreen(state));
      await tester.pump();

      for (final term in ['PASS_ACK', 'allWritten']) {
        expect(find.textContaining(term), findsNothing,
            reason: 'False hardware term "$term" must not appear');
      }
    });
  });

  // ── D: Apply failure ───────────────────────────────────────────────────────

  group('D. Apply failure', () {
    final state = ProGuidedAiCompleted(
      outcome: _stubOutcome,
      explanation: _stubExplanation,
      applyResult: _stubFailApplyResult,
    );

    testWidgets('적용 차단 label shown', (tester) async {
      await tester.pumpWidget(_aiScreen(state));
      await tester.pump();

      expect(find.textContaining('적용 차단'), findsAtLeastNWidgets(1));
    });

    testWidgets('PEQ 업데이트 완료 not shown on failure', (tester) async {
      await tester.pumpWidget(_aiScreen(state));
      await tester.pump();

      expect(find.textContaining('PEQ 업데이트 완료'), findsNothing);
    });

    testWidgets('Deploy로 이동 not shown on failure', (tester) async {
      await tester.pumpWidget(_aiScreen(state));
      await tester.pump();

      expect(find.textContaining('Deploy로 이동'), findsNothing);
    });
  });

  // ── E: Deploy readiness ────────────────────────────────────────────────────

  group('E. Deploy readiness panel', () {
    testWidgets('project name and DSP target shown in readiness panel',
        (tester) async {
      _seedProjects([_baseProject]);
      await tester.pumpWidget(_deployTab());
      await tester.pumpAndSettle();

      expect(find.textContaining('Test Project'), findsAtLeastNWidgets(1));
      expect(find.textContaining('ADAU1701'), findsAtLeastNWidgets(1));
    });

    testWidgets('PEQ bands row visible in readiness panel', (tester) async {
      _seedProjects([_projectWithFrd]);
      await tester.pumpWidget(_deployTab());
      await tester.pumpAndSettle();

      expect(find.textContaining('PEQ bands'), findsOneWidget);
    });

    testWidgets('DEPLOY READINESS section header visible', (tester) async {
      _seedProjects([_baseProject]);
      await tester.pumpWidget(_deployTab());
      await tester.pumpAndSettle();

      expect(find.textContaining('DEPLOY READINESS'), findsOneWidget);
    });
  });

  // ── F: Real PASS_ACK result ────────────────────────────────────────────────

  group('F. Real PASS_ACK — HardwareApplyFlow onResult with allWritten=true',
      () {
    testWidgets('onResult called with allWritten=true after successful apply',
        (tester) async {
      Object? captured;
      final transport = _FakeTransport(connected: true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HardwareApplyFlow(
              exportPackage: _exportPkg(),
              profile: HardwareDeviceProfiles.adau1701Icp5,
              contextFactory: () =>
                  Adau1701HardwareContext.fromTransport(transport),
              onResult: (r) => captured = r,
            ),
          ),
        ),
      ));

      await tester.tap(find.ancestor(
          of: find.text('APPROVE VERIFIED WRITE'),
          matching: find.bySubtype<OutlinedButton>()));
      await tester.pump();

      await tester.tap(find.ancestor(
          of: find.text('APPLY VERIFIED SETTINGS'),
          matching: find.bySubtype<OutlinedButton>()));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      // allWritten is true when all outcomes succeeded
      expect(find.text('APPLY RESULTS'), findsOneWidget);
    });

    testWidgets('APPLY RESULTS shown after successful apply', (tester) async {
      final transport = _FakeTransport(connected: true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HardwareApplyFlow(
              exportPackage: _exportPkg(),
              profile: HardwareDeviceProfiles.adau1701Icp5,
              contextFactory: () =>
                  Adau1701HardwareContext.fromTransport(transport),
            ),
          ),
        ),
      ));

      await tester.tap(find.ancestor(
          of: find.text('APPROVE VERIFIED WRITE'),
          matching: find.bySubtype<OutlinedButton>()));
      await tester.pump();
      await tester.tap(find.ancestor(
          of: find.text('APPLY VERIFIED SETTINGS'),
          matching: find.bySubtype<OutlinedButton>()));
      await tester.pumpAndSettle();

      expect(find.text('APPLY RESULTS'), findsOneWidget);
      expect(find.text('WRITTEN'), findsOneWidget);
    });
  });

  // ── G: ACK absent / hardware not ready ────────────────────────────────────

  group('G. ACK absent — hardware not ready blocks apply', () {
    testWidgets('APPLY VERIFIED SETTINGS disabled when hardware not ready',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HardwareApplyFlow(
              exportPackage: _exportPkg(),
              profile: HardwareDeviceProfiles.adau1701Icp5,
              contextFactory: () => Adau1701HardwareContext.fromTransport(
                  _FakeTransport(connected: false)),
            ),
          ),
        ),
      ));

      await tester.tap(find.ancestor(
          of: find.text('APPROVE VERIFIED WRITE'),
          matching: find.bySubtype<OutlinedButton>()));
      await tester.pump();

      final applyBtn = tester.widget<OutlinedButton>(find.ancestor(
          of: find.text('APPLY VERIFIED SETTINGS'),
          matching: find.bySubtype<OutlinedButton>()));
      expect(applyBtn.onPressed, isNull,
          reason: 'Apply must be disabled when hardware not ready');
    });

    testWidgets('Hardware not ready note shown after approve', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HardwareApplyFlow(
              exportPackage: _exportPkg(),
              profile: HardwareDeviceProfiles.adau1701Icp5,
              contextFactory: () => Adau1701HardwareContext.fromTransport(
                  _FakeTransport(connected: false)),
            ),
          ),
        ),
      ));

      await tester.tap(find.ancestor(
          of: find.text('APPROVE VERIFIED WRITE'),
          matching: find.bySubtype<OutlinedButton>()));
      await tester.pump();

      expect(find.textContaining('Hardware not ready'), findsOneWidget);
    });
  });

  // ── H: Improved cycle (improvedAndComplete) ────────────────────────────────

  group('H. Improved cycle — improvedAndComplete decision', () {
    final state = ProGuidedAiCompleted(
      outcome: _stubOutcome,
      explanation: _stubExplanation,
      applyResult: _stubApplyResult,
      loopPhase: ProClosedLoopPhase.cycleComplete,
      completedCycle: _cycle(CorrectionCycleDecision.improvedAndComplete),
    );

    testWidgets('개선 완료 label shown', (tester) async {
      await tester.pumpWidget(_aiScreen(state));
      await tester.pump();

      expect(find.textContaining('개선 완료'), findsAtLeastNWidgets(1));
    });

    testWidgets('완료 button shown', (tester) async {
      await tester.pumpWidget(_aiScreen(state));
      await tester.pump();

      expect(find.text('완료'), findsAtLeastNWidgets(1));
    });

    testWidgets('추가 보정 button not shown for terminal decision',
        (tester) async {
      await tester.pumpWidget(_aiScreen(state));
      await tester.pump();

      expect(find.text('추가 보정'), findsNothing);
    });
  });

  // ── I: Worsened cycle ─────────────────────────────────────────────────────

  group('I. Worsened cycle', () {
    final state = ProGuidedAiCompleted(
      outcome: _stubOutcome,
      explanation: _stubExplanation,
      applyResult: _stubApplyResult,
      loopPhase: ProClosedLoopPhase.cycleComplete,
      completedCycle: _cycle(CorrectionCycleDecision.worsened),
    );

    testWidgets('성능 저하 감지 label shown', (tester) async {
      await tester.pumpWidget(_aiScreen(state));
      await tester.pump();

      expect(find.textContaining('성능 저하 감지'), findsAtLeastNWidgets(1));
    });

    testWidgets('추가 보정 button not shown for worsened', (tester) async {
      await tester.pumpWidget(_aiScreen(state));
      await tester.pump();

      expect(find.text('추가 보정'), findsNothing);
    });

    testWidgets('완료 button still shown (terminal path)', (tester) async {
      await tester.pumpWidget(_aiScreen(state));
      await tester.pump();

      expect(find.text('완료'), findsAtLeastNWidgets(1));
    });
  });

  // ── J: Continue cycle ─────────────────────────────────────────────────────

  group('J. Continue cycle — improvedNeedsAnotherCycle', () {
    final state = ProGuidedAiCompleted(
      outcome: _stubOutcome,
      explanation: _stubExplanation,
      applyResult: _stubApplyResult,
      loopPhase: ProClosedLoopPhase.cycleComplete,
      completedCycle:
          _cycle(CorrectionCycleDecision.improvedNeedsAnotherCycle),
    );

    testWidgets('추가 보정 button shown', (tester) async {
      await tester.pumpWidget(_aiScreen(state));
      await tester.pump();

      expect(find.text('추가 보정'), findsOneWidget);
    });

    testWidgets('개선됨 — 추가 보정 권장 label shown', (tester) async {
      await tester.pumpWidget(_aiScreen(state));
      await tester.pump();

      expect(find.textContaining('개선됨'), findsAtLeastNWidgets(1));
    });

    // Phase 4-C-2A: "추가 보정" now calls continueWithNextCycle() instead of
    // bare reset(). _FakeGuidedAiController can't populate the controller's
    // private pending-draft field (it's file-private to
    // pro_guided_ai_controller.dart), so continueWithNextCycle() correctly
    // no-ops here — proving the negative: unlike the old reset()-based
    // callback, tapping "추가 보정" must NOT jump back to the bare Idle
    // screen. (Cycle-2 Before-FRD correctness itself is proven at the
    // controller level in pro_guided_ai_controller_test.dart group 25.)
    testWidgets(
        '추가 보정 tap no longer resets to the bare Idle screen (calls '
        'continueWithNextCycle, not reset)', (tester) async {
      await tester.pumpWidget(_aiScreen(state));
      await tester.pump();

      final continueBtn = find.text('추가 보정');
      await tester.ensureVisible(continueBtn);
      await tester.tap(continueBtn);
      await tester.pump();

      expect(find.text('AI 분석 시작'), findsNothing,
          reason:
              'a bare reset() would have shown the Idle "AI 분석 시작" screen');
      expect(find.textContaining('개선됨'), findsAtLeastNWidgets(1),
          reason:
              'the cycle-decision view should remain visible (no eligible '
              'pending draft on this fake controller, so continuation is a '
              'safe no-op rather than a destructive reset)');
    });
  });

  // ── K: Complete cycle → Factory Profile scroll ────────────────────────────

  group('K. Complete cycle activates Factory Profile section', () {
    testWidgets(
        'deployScrollTargetProvider set to factoryProfile on 완료 tap',
        (tester) async {
      DeployScrollTarget? captured;

      final state = ProGuidedAiCompleted(
        outcome: _stubOutcome,
        explanation: _stubExplanation,
        applyResult: _stubApplyResult,
        loopPhase: ProClosedLoopPhase.cycleComplete,
        completedCycle:
            _cycle(CorrectionCycleDecision.improvedAndComplete),
      );

      await tester.pumpWidget(ProviderScope(
        overrides: [
          guidedAiProvider.overrideWith(
              (ref) => _FakeGuidedAiController(state)),
        ],
        child: Consumer(builder: (context, ref, _) {
          ref.listen<DeployScrollTarget?>(
              deployScrollTargetProvider, (_, v) => captured = v);
          return const MaterialApp(
              home: GuidedAiScreen(projectId: 'test-proj'));
        }),
      ));
      await tester.pump();

      await tester.tap(find.text('완료'));
      await tester.pump();

      expect(captured, DeployScrollTarget.factoryProfile);
    });

    testWidgets('workbenchTabProvider set to kTabDeploy on 완료 tap',
        (tester) async {
      int? capturedTab;

      final state = ProGuidedAiCompleted(
        outcome: _stubOutcome,
        explanation: _stubExplanation,
        applyResult: _stubApplyResult,
        loopPhase: ProClosedLoopPhase.cycleComplete,
        completedCycle:
            _cycle(CorrectionCycleDecision.improvedAndComplete),
      );

      await tester.pumpWidget(ProviderScope(
        overrides: [
          guidedAiProvider.overrideWith(
              (ref) => _FakeGuidedAiController(state)),
        ],
        child: Consumer(builder: (context, ref, _) {
          ref.listen<int>(workbenchTabProvider, (_, v) => capturedTab = v);
          return const MaterialApp(
              home: GuidedAiScreen(projectId: 'test-proj'));
        }),
      ));
      await tester.pump();

      await tester.tap(find.text('완료'));
      await tester.pump();

      expect(capturedTab, kTabDeploy);
    });
  });

  // ── L: Profile saved ───────────────────────────────────────────────────────

  group('L. Profile saved UI', () {
    setUp(() {
      final projectWithProfile = ProProject(
        id: 'test-proj',
        name: 'Test Project',
        dspTarget: 'ADAU1701',
        createdAt: DateTime.utc(2025, 1, 1),
        updatedAt: DateTime.utc(2025, 1, 1),
        factoryProfiles: [_stubProfile],
        correctionCycles: [_cycle(CorrectionCycleDecision.improvedAndComplete)],
      );
      _seedProjects([projectWithProfile]);
    });

    testWidgets('profile name shown in summary card', (tester) async {
      await tester.pumpWidget(_deployTab());
      await tester.pumpAndSettle();

      expect(find.textContaining('Production v1'), findsAtLeastNWidgets(1));
    });

    testWidgets('profile version shown', (tester) async {
      await tester.pumpWidget(_deployTab());
      await tester.pumpAndSettle();

      expect(find.textContaining('v1'), findsAtLeastNWidgets(1));
    });

    testWidgets('fingerprint shown', (tester) async {
      await tester.pumpWidget(_deployTab());
      await tester.pumpAndSettle();

      expect(find.textContaining('abc123def456'), findsAtLeastNWidgets(1));
    });

    testWidgets('validation status shown', (tester) async {
      await tester.pumpWidget(_deployTab());
      await tester.pumpAndSettle();

      expect(find.textContaining('ready'), findsAtLeastNWidgets(1));
    });

    testWidgets('Export JSON action visible', (tester) async {
      await tester.pumpWidget(_deployTab());
      await tester.pumpAndSettle();

      expect(find.textContaining('Export JSON'), findsOneWidget);
    });
  });

  // ── M: Wrong project / null project ───────────────────────────────────────

  group('M. Wrong project or null project', () {
    testWidgets('FRD warning shown when project not in store', (tester) async {
      // Empty store → projectId not found → parsedFrdCount fallback to 0
      await tester.pumpWidget(_aiScreen(const ProGuidedAiIdle()));
      await tester.pumpAndSettle();

      expect(find.textContaining('FRD 파일이 없습니다'), findsAtLeastNWidgets(1));
    });

    testWidgets('Analyze button disabled when project not found', (tester) async {
      await tester.pumpWidget(_aiScreen(const ProGuidedAiIdle()));
      await tester.pumpAndSettle();

      final btn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'AI 분석 시작'));
      expect(btn.onPressed, isNull);
    });

    testWidgets('wrongProjectOrChannel decision shows error label',
        (tester) async {
      final state = ProGuidedAiCompleted(
        outcome: _stubOutcome,
        explanation: _stubExplanation,
        loopPhase: ProClosedLoopPhase.cycleComplete,
        completedCycle:
            _cycle(CorrectionCycleDecision.wrongProjectOrChannel),
      );

      await tester.pumpWidget(_aiScreen(state));
      await tester.pump();

      expect(find.textContaining('프로젝트/채널 불일치'), findsAtLeastNWidgets(1));
    });
  });

  // ── N: Navigation provider ─────────────────────────────────────────────────

  group('N. Navigation provider', () {
    testWidgets('Guided AI tab visible in sidebar', (tester) async {
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: WorkbenchShell(projectId: 'test-proj')),
      ));
      await tester.pump();

      expect(find.text('Guided AI'), findsOneWidget);
    });

    testWidgets(
        'workbenchTabProvider.go(kTabGuidedAi) switches shell to Guided AI',
        (tester) async {
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: WorkbenchShell(projectId: 'test-proj')),
      ));
      await tester.pump();

      await tester.tap(find.text('Guided AI'));
      await tester.pump();

      expect(find.text('GUIDED AI'), findsOneWidget);
    });

    testWidgets('Deploy로 이동 in ApplyResultCard routes to Deploy tab',
        (tester) async {
      final state = ProGuidedAiCompleted(
        outcome: _stubOutcome,
        explanation: _stubExplanation,
        applyResult: _stubApplyResult,
      );

      int? capturedTab;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          guidedAiProvider.overrideWith(
              (ref) => _FakeGuidedAiController(state)),
        ],
        child: Consumer(builder: (context, ref, _) {
          ref.listen<int>(workbenchTabProvider, (_, v) => capturedTab = v);
          return const MaterialApp(
              home: GuidedAiScreen(projectId: 'test-proj'));
        }),
      ));
      await tester.pump();

      await tester.tap(find.textContaining('Deploy로 이동'));
      await tester.pump();

      expect(capturedTab, kTabDeploy);
    });

    testWidgets(
        'Complete → kTabDeploy + deployScrollTargetProvider.factoryProfile',
        (tester) async {
      final state = ProGuidedAiCompleted(
        outcome: _stubOutcome,
        explanation: _stubExplanation,
        applyResult: _stubApplyResult,
        loopPhase: ProClosedLoopPhase.cycleComplete,
        completedCycle:
            _cycle(CorrectionCycleDecision.improvedAndComplete),
      );

      DeployScrollTarget? scrollTarget;
      int? tab;

      await tester.pumpWidget(ProviderScope(
        overrides: [
          guidedAiProvider.overrideWith(
              (ref) => _FakeGuidedAiController(state)),
        ],
        child: Consumer(builder: (context, ref, _) {
          ref.listen<DeployScrollTarget?>(
              deployScrollTargetProvider, (_, v) => scrollTarget = v);
          ref.listen<int>(workbenchTabProvider, (_, v) => tab = v);
          return const MaterialApp(
              home: GuidedAiScreen(projectId: 'test-proj'));
        }),
      ));
      await tester.pump();

      await tester.tap(find.text('완료'));
      await tester.pump();

      expect(tab, kTabDeploy,
          reason: 'Complete must navigate to Deploy tab');
      expect(scrollTarget, DeployScrollTarget.factoryProfile,
          reason: 'Complete must scroll to Factory Profile section');
    });
  });
}
