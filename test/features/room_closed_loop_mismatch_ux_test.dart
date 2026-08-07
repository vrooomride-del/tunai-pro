// Phase 3-D3C-2 §6/§14 + 3-D3C-3 §0 — Room Closed Loop verdict/mismatch UX.
//
// Two distinct states share this banner slot and must never be confused:
//  - a provenance-blocked pair, which is NOT a verdict (mismatch banner,
//    re-measure CTA, no rollback);
//  - an actual verdict, whose tone must match its severity — a `worsened`
//    result may never render as a green check, and must keep its rollback
//    path.
// Both are checked for zero overflow at the 1280×720 minimum window.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/measurement/measurement_capture_provenance.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device_service.dart';
import 'package:tunai_pro/core/measurement/measurement_quality_snapshot.dart';
import 'package:tunai_pro/core/orchestrator/room_closed_loop_presentation.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_correction_cycle.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/room_measurement_data.dart';
import 'package:tunai_pro/features/mic/mic_measurement_controller.dart' as mic;
import 'package:tunai_pro/features/workbench/tabs/room_measurement_controller.dart';
import 'package:tunai_pro/features/workbench/tabs/room_measurement_section.dart';
import 'package:tunai_pro/shared/pro_widgets.dart';

import 'package:tunai_pro/core/deploy/pro_hardware_context_provider.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_executor.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/features/workbench/tabs/room_auto_peq_controller.dart';

import '../support/capture_gate_fixtures.dart';

const _pid = 'room-ux-1';

class _FakeMicController extends mic.MicMeasurementController {
  _FakeMicController(super.ref);

  @override
  MeasurementInputDeviceService get inputDeviceService =>
      fakeGateInputDeviceService();

  @override
  Future<void> startRoomMeasurement({
    required bool leftActive,
    bool bleWarmup = false,
    CalibrationCurve? calibrationCurve,
  }) async {
    state = state.copyWith(
      status: mic.MeasurementStatus.done,
      frequencyResponse: const [
        {'frequency': 100.0, 'db': -3.0},
        {'frequency': 1000.0, 'db': -2.0},
      ],
      calibrationStatus: CalibrationStatus.calibrated,
      calibrationCurveChecksum: 'gate-test-curve',
    );
  }

  @override
  // ignore: must_call_super
  void dispose() {}
}

ProProject _project() => withGateReadySetup(ProProject(
      id: _pid,
      name: 'Room UX',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    ));

RoomMeasurementProjectState _seededBefore(
    {required bool mismatchedProfile, double beforeDb = -6.0}) {
  final base = MeasurementCaptureProvenanceBuilder.build(
    project: _project(),
    actualSampleRate: mic.MicMeasurementController.sampleRate,
    actualChannelCount: 1,
    now: DateTime.utc(2026, 1, 1),
  );
  final provenance = mismatchedProfile
      ? MeasurementCaptureProvenance(
          projectId: base.projectId,
          microphoneProfileChecksum: 'a-completely-different-microphone',
          calibrationCurveChecksum: base.calibrationCurveChecksum,
          calibrationAngle: base.calibrationAngle,
          inputDeviceSelectionIdentity: base.inputDeviceSelectionIdentity,
          setupReadinessGenerationId: base.setupReadinessGenerationId,
          qualityPolicyVersion: base.qualityPolicyVersion,
          actualSampleRate: base.actualSampleRate,
          actualChannelCount: base.actualChannelCount,
          capturedAt: base.capturedAt,
        )
      : base;

  ParsedMeasurementData frd(String id) => ParsedMeasurementData(
        id: id,
        sourceFileName: '$id.frd',
        fileType: AcousticFileType.frd,
        importedAt: DateTime.utc(2026, 1, 1),
        points: [
          for (var f = 20.0; f <= 2000; f *= 1.3)
            MeasurementDataPoint(frequencyHz: f, magnitudeDb: beforeDb),
        ],
        calibrationStatus: CalibrationStatus.calibrated,
        calibrationCurveChecksum: 'gate-test-curve',
        qualitySnapshot: MeasurementQualitySnapshot(
          provenance: provenance,
          setupCalibrationStatus: CalibrationStatus.calibrated,
          setupNoiseFloorDbFs: -70,
          setupPeakDbFs: -6,
          setupRmsDbFs: -18,
          setupSignalToNoiseDb: 52,
          setupClippedSampleCount: 0,
          setupClippedSampleRatio: 0,
          setupCheckedAt: DateTime.utc(2026, 1, 1),
        ),
        source: MeasurementDataSource.liveCapture,
      );

  RoomSystemMeasurement m(RoomSystemSide side) => RoomSystemMeasurement(
        side: side,
        phase: RoomMeasurementPhase.before,
        frd: frd('before_${side.name}'),
        capturedAt: DateTime.utc(2026, 1, 1),
        sampleRate: mic.MicMeasurementController.sampleRate,
        source: RoomMeasurementSource.live,
        projectId: _pid,
      );

  return RoomMeasurementProjectState.createDefault().copyWith(
    before: RoomMeasurementSnapshot(
        leftSystemFrd: m(RoomSystemSide.left),
        rightSystemFrd: m(RoomSystemSide.right)),
  );
}

void _authorizeAfterMode(ProviderContainer c) {
  const packageId = 'approved-room-pkg';
  c.read(roomAutoPeqControllerProvider(_pid).notifier).state =
      const RoomAutoPeqState(approvedPackageId: packageId);
  c.read(lastHardwareWriteResultProvider.notifier).state =
      const HardwareWriteExecutionResult(
    planId: '$packageId@2026-01-01T00:00:00.000Z',
    executed: true,
    rejectionReason: null,
    outcomes: [
      HardwareWriteOpOutcome(
        op: HardwareWriteOp(
          channelId: 'ch_wf_l',
          parameterKind: HardwareParamKind.peqGain,
          bandIndex: 0,
          targetValue: -1.0,
          verification: HardwareParamVerification.captureProven,
          writable: true,
          reason: 'test',
        ),
        status: HardwareWriteOpStatus.written,
        report: null,
        message: 'ok',
      ),
    ],
  );
}

Future<ProviderContainer> _driveToAfterComplete(
    {required bool mismatchedProfile, double beforeDb = -6.0}) async {
  final container = ProviderContainer(overrides: [
    mic.micMeasurementProvider.overrideWith((ref) => _FakeMicController(ref)),
  ]);
  await container.read(proProjectStoreProvider.notifier).addProject(_project());
  await container.read(proProjectStoreProvider.notifier).updateRoomState(_pid,
      _seededBefore(mismatchedProfile: mismatchedProfile, beforeDb: beforeDb));
  container.read(mic.micMeasurementProvider);
  _authorizeAfterMode(container);

  final ctrl = container.read(roomMeasurementControllerProvider(_pid).notifier);
  ctrl.setMode(RoomMeasurementPhase.after);
  for (var i = 0; i < 2; i++) {
    ctrl.markReady();
    await ctrl.capture();
    await ctrl.accept();
  }
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('verdict presentation mapping (§0)', () {
    test('every decision maps to copy and exactly one tone', () {
      for (final d in CorrectionCycleDecision.values) {
        expect(closedLoopVerdictText(d), isNotEmpty, reason: d.name);
        expect(closedLoopVerdictText(d), isNot(contains(d.name)),
            reason: 'the enum name must never leak into the UI');
        expect(closedLoopVerdictTone(d), isNotNull, reason: d.name);
      }
    });

    test('success is reserved for improvedAndComplete alone', () {
      for (final d in CorrectionCycleDecision.values) {
        expect(closedLoopVerdictTone(d) == ClosedLoopVerdictTone.success,
            d == CorrectionCycleDecision.improvedAndComplete,
            reason: d.name);
      }
    });

    test('rollback is offered for worsened alone', () {
      for (final d in CorrectionCycleDecision.values) {
        expect(closedLoopVerdictOffersRollback(d),
            d == CorrectionCycleDecision.worsened,
            reason: d.name);
      }
    });
  });

  const recordChannel = MethodChannel('com.llfbandit.record/messages');
  const justAudioChannel = MethodChannel('com.ryanheise.just_audio.methods');
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recordChannel, (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(justAudioChannel, (call) async => null);
  });
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recordChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(justAudioChannel, null);
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpSection(WidgetTester tester, ProviderContainer c) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final project = c
        .read(proProjectStoreProvider)
        .projects
        .firstWhere((p) => p.id == _pid);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RoomMeasurementSection(project: project),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('a blocked comparison shows the mismatch banner, not a verdict',
      (tester) async {
    final c = await _driveToAfterComplete(mismatchedProfile: true);
    addTearDown(c.dispose);
    await pumpSection(tester, c);

    expect(find.text('Before와 After가 서로 다른 측정 마이크로 측정되었습니다.'), findsOneWidget);
    expect(find.textContaining('측정 조건이 달라 Before/After를 비교할 수 없습니다.'),
        findsOneWidget,
        reason: 'the user is told what to do next');
    expect(find.textContaining('Closed Loop 판정'), findsNothing,
        reason: 'a blocked comparison must never render as improved/worsened '
            'or offer the rollback path');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a valid comparison still renders the Closed Loop verdict',
      (tester) async {
    final c = await _driveToAfterComplete(mismatchedProfile: false);
    addTearDown(c.dispose);
    await pumpSection(tester, c);

    final decision = c
        .read(roomMeasurementControllerProvider(_pid).notifier)
        .state
        .closedLoopResult!
        .decision;
    expect(decision, CorrectionCycleDecision.improvedAndComplete);
    expect(find.text(closedLoopVerdictText(decision)), findsOneWidget);
    expect(find.textContaining('측정 조건이 달라'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the mismatch banner overflows nothing at 1280x720',
      (tester) async {
    final c = await _driveToAfterComplete(mismatchedProfile: true);
    addTearDown(c.dispose);
    await pumpSection(tester, c);

    // Any RenderFlex overflow surfaces as a FlutterError on the exception
    // channel; an empty channel after a full pump means zero overflow.
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // ── Phase 3-D3C-3 §0 — verdict severity ────────────────────────────────
  //
  // The Before level chosen here is what steers the evaluator to each
  // decision; the verdict logic itself is untouched. beforeDb -6 gives a
  // clearly-improved After, -3 gives no meaningful change, and an already
  // near-flat 0 dB Before means the After can only be worse.

  group('verdict severity', () {
    /// The section renders check icons elsewhere (accepted side captures), so
    /// icon assertions are scoped to the banner's own Row — anchored on the
    /// verdict text — rather than the whole tree.
    Finder bannerIcon(CorrectionCycleDecision d) => find.descendant(
          of: find
              .ancestor(
                  of: find.text(closedLoopVerdictText(d)),
                  matching: find.byType(Row))
              .first,
          matching: find.byType(Icon),
        );

    testWidgets('improvedAndComplete reads as success, with no rollback CTA',
        (tester) async {
      final c = await _driveToAfterComplete(mismatchedProfile: false);
      addTearDown(c.dispose);
      await pumpSection(tester, c);

      expect(closedLoopVerdictTone(CorrectionCycleDecision.improvedAndComplete),
          ClosedLoopVerdictTone.success);
      expect(find.text('Room 보정 완료 — 측정 결과가 개선되었습니다.'), findsOneWidget);
      expect(
          tester
              .widget<Icon>(
                  bannerIcon(CorrectionCycleDecision.improvedAndComplete))
              .icon,
          Icons.check_circle_outline);
      expect(find.text('보정 전 상태로 되돌리기'), findsNothing,
          reason: 'nothing went wrong, so there is nothing to roll back');
      expect(tester.takeException(), isNull);
    });

    testWidgets('noMeaningfulImprovement is never styled as a completion',
        (tester) async {
      final c =
          await _driveToAfterComplete(mismatchedProfile: false, beforeDb: -3.0);
      addTearDown(c.dispose);
      await pumpSection(tester, c);

      final decision = c
          .read(roomMeasurementControllerProvider(_pid).notifier)
          .state
          .closedLoopResult!
          .decision;
      expect(decision, CorrectionCycleDecision.noMeaningfulImprovement);
      expect(find.text(closedLoopVerdictText(decision)), findsOneWidget);
      expect(tester.widget<Icon>(bannerIcon(decision)).icon,
          isNot(Icons.check_circle_outline),
          reason: 'the success check icon must be reserved for '
              'improvedAndComplete');
      expect(
          tester
              .widget<Text>(find.text(closedLoopVerdictText(decision)))
              .style
              ?.color,
          isNot(kProGreen));
      expect(find.text('보정 전 상태로 되돌리기'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('worsened is never green/check and keeps the rollback CTA',
        (tester) async {
      final c =
          await _driveToAfterComplete(mismatchedProfile: false, beforeDb: 0.0);
      addTearDown(c.dispose);
      await pumpSection(tester, c);

      final decision = c
          .read(roomMeasurementControllerProvider(_pid).notifier)
          .state
          .closedLoopResult!
          .decision;
      expect(decision, CorrectionCycleDecision.worsened);
      expect(
          find.text('성능 저하가 감지되었습니다 — 보정 전 상태로 되돌릴 수 있습니다.'), findsOneWidget);
      expect(tester.widget<Icon>(bannerIcon(decision)).icon,
          Icons.warning_amber_outlined,
          reason: 'never the success check icon');

      // The colour is asserted directly, not inferred from the icon: a green
      // "성능 저하" is the exact defect this test exists to prevent.
      final label = tester
          .widget<Text>(find.text('성능 저하가 감지되었습니다 — 보정 전 상태로 되돌릴 수 있습니다.'));
      expect(label.style?.color, kProRed);

      expect(find.text('보정 전 상태로 되돌리기'), findsOneWidget,
          reason: 'a worsened correction must offer the rollback path');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the worsened banner overflows nothing at 1280x720',
        (tester) async {
      final c =
          await _driveToAfterComplete(mismatchedProfile: false, beforeDb: 0.0);
      addTearDown(c.dispose);
      await pumpSection(tester, c);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
