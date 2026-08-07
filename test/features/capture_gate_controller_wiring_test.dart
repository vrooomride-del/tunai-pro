// Phase 3-D3A-1 §2/§3/§4/§7 — Factory & Room controllers are gated at
// capture time by the SAME MeasurementCaptureGate, with a fresh runtime
// preflight (permission + device enumeration re-read at capture, never taken
// from what the UI cached at render time).
//
// The load-bearing assertion throughout: when the gate refuses, the recorder
// and player are called ZERO times and no preview/state mutation happens.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/measurement/measurement_capture_gate_types.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device_service.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/features/mic/mic_measurement_controller.dart' as mic;
import 'package:tunai_pro/features/workbench/tabs/live_measurement_controller.dart';
import 'package:tunai_pro/features/workbench/tabs/room_measurement_controller.dart';

import '../support/capture_gate_fixtures.dart';

/// Counts every recorder/player entry point the capture path could reach.
/// `startMeasurement`/`startRoomMeasurement` are the only ways either
/// controller can drive audio, so zero calls here proves zero recorder AND
/// zero player AND zero BLE-warmup work happened.
class _CountingMicController extends mic.MicMeasurementController {
  _CountingMicController(super.ref, this._api);
  final FakeGateInputDeviceApi _api;

  int factoryStarts = 0;
  int roomStarts = 0;
  bool failStart = false;

  int get totalStarts => factoryStarts + roomStarts;

  @override
  MeasurementInputDeviceService get inputDeviceService =>
      MeasurementInputDeviceService(_api);

  @override
  Future<void> startMeasurement({
    List<double>? scfCorrection,
    dynamic speakerProfile,
    bool bleWarmup = false,
    CalibrationCurve? calibrationCurve,
  }) async {
    factoryStarts++;
    if (failStart) {
      // Mirrors a real AudioRecorder.start() failure (e.g. the OS could not
      // resolve a default input): status=error, no frequency response.
      state = state.copyWith(
          status: mic.MeasurementStatus.error, error: 'RECORDER_START_FAILED');
      return;
    }
    state = state.copyWith(
      status: mic.MeasurementStatus.done,
      frequencyResponse: const [
        {'frequency': 100.0, 'db': -1.0},
        {'frequency': 1000.0, 'db': -2.0},
      ],
    );
  }

  @override
  Future<void> startRoomMeasurement({
    required bool leftActive,
    bool bleWarmup = false,
    CalibrationCurve? calibrationCurve,
  }) async {
    roomStarts++;
    if (failStart) {
      state = state.copyWith(
          status: mic.MeasurementStatus.error, error: 'RECORDER_START_FAILED');
      return;
    }
    state = state.copyWith(
      status: mic.MeasurementStatus.done,
      frequencyResponse: const [
        {'frequency': 100.0, 'db': -1.0},
        {'frequency': 1000.0, 'db': -2.0},
      ],
    );
  }

  @override
  // ignore: must_call_super
  void dispose() {}
}

DriverChannel _channel(String id) => DriverChannel(
      id: id,
      name: id,
      role: id.contains('tw') ? DriverRole.tweeter : DriverRole.woofer,
      side: id.endsWith('l') ? DriverSide.left : DriverSide.right,
    );

ProProject _bareProject() => ProProject(
      id: 'gate-wiring-1',
      name: 'Gate Wiring',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      acousticState: MeasurementProjectState(driverChannels: [
        _channel('ch_tw_l'),
        _channel('ch_wf_l'),
        _channel('ch_tw_r'),
        _channel('ch_wf_r'),
      ]),
    );

class _Harness {
  final ProviderContainer container;
  final _CountingMicController mic;
  final FakeGateInputDeviceApi api;
  const _Harness(this.container, this.mic, this.api);

  LiveMeasurementController get factory => container
      .read(liveMeasurementControllerProvider('gate-wiring-1').notifier);
  RoomMeasurementController get room => container
      .read(roomMeasurementControllerProvider('gate-wiring-1').notifier);
}

Future<_Harness> _harness({
  bool gateReady = true,
  bool permission = true,
  List<MeasurementInputDeviceDescriptor>? devices,
  ProProject Function(ProProject)? mutate,
}) async {
  final api = FakeGateInputDeviceApi(permissionGranted: permission);
  if (devices != null) api.devices = devices;
  late _CountingMicController counting;
  final container = ProviderContainer(overrides: [
    mic.micMeasurementProvider.overrideWith((ref) {
      counting = _CountingMicController(ref, api);
      return counting;
    }),
  ]);
  var project = _bareProject();
  if (gateReady) project = withGateReadySetup(project);
  if (mutate != null) project = mutate(project);
  await container.read(proProjectStoreProvider.notifier).addProject(project);
  container.read(mic.micMeasurementProvider);
  return _Harness(container, counting, api);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('1. blocked chain -> zero recorder/player calls', () {
    Future<void> expectBlocked(_Harness h,
        {required MeasurementCaptureBlockerCode expected}) async {
      h.factory.markReady();
      await h.factory.capture();
      h.room.markReady();
      await h.room.capture();

      expect(h.mic.totalStarts, 0,
          reason: 'a blocked gate must never reach the recorder/player');
      expect(h.factory.state.captureGate?.hasBlocker(expected), isTrue);
      expect(h.room.state.captureGate?.hasBlocker(expected), isTrue);
      expect(h.factory.state.capturedResponse, isNull);
      expect(h.room.state.capturedResponse, isNull);
    }

    test('no microphone profile', () async {
      final h = await _harness(gateReady: false);
      addTearDown(h.container.dispose);
      await expectBlocked(h,
          expected: MeasurementCaptureBlockerCode.noMicrophoneProfile);
    });

    test('no setup check', () async {
      final h = await _harness(
          gateReady: false,
          mutate: (p) => p.copyWith(
              selectedMicrophoneProfile: gateReadyProfile(),
              selectedInputDevice: gateReadyDevice()));
      addTearDown(h.container.dispose);
      await expectBlocked(h,
          expected: MeasurementCaptureBlockerCode.setupNotChecked);
    });

    test('permission denied', () async {
      final h = await _harness(permission: false);
      addTearDown(h.container.dispose);
      await expectBlocked(h,
          expected: MeasurementCaptureBlockerCode.microphonePermissionDenied);
    });

    test(
        'device disappears between UI render and capture (fresh enumeration '
        'is re-read at capture time)', () async {
      final h = await _harness();
      addTearDown(h.container.dispose);
      // Gate is green at "render" time...
      expect((await h.factory.evaluateCaptureGate()).canCapture, isTrue);
      // ...then the device is unplugged before the user taps Capture.
      h.api.devices = const [];
      await expectBlocked(h,
          expected: MeasurementCaptureBlockerCode.inputDeviceUnavailable);
    });
  });

  group('2. valid chain runs the normal lifecycle', () {
    test('Factory capture proceeds and produces a preview', () async {
      final h = await _harness();
      addTearDown(h.container.dispose);
      h.factory.markReady();
      await h.factory.capture();
      expect(h.mic.factoryStarts, 1);
      expect(h.factory.state.phase, LiveMeasurementPhase.captured);
      expect(h.factory.state.capturedResponse, isNotNull);
      expect(h.factory.state.captureGate?.canCapture, isTrue);
    });

    test('Room capture proceeds and produces a preview', () async {
      final h = await _harness();
      addTearDown(h.container.dispose);
      h.room.markReady();
      await h.room.capture();
      expect(h.mic.roomStarts, 1);
      expect(h.room.state.phase, RoomMeasurementPhaseUi.captured);
      expect(h.room.state.capturedResponse, isNotNull);
    });
  });

  group('3. §4 recorder default-resolution failure stays a failure', () {
    test('Factory: recorder start failure -> error, no preview, no Accept',
        () async {
      final h = await _harness();
      addTearDown(h.container.dispose);
      h.mic.failStart = true;
      h.factory.markReady();
      await h.factory.capture();

      expect(h.mic.factoryStarts, 1, reason: 'the attempt was allowed...');
      expect(h.factory.state.phase, LiveMeasurementPhase.ready,
          reason: '...but it failed, so no captured state');
      expect(h.factory.state.capturedResponse, isNull);
      expect(h.factory.state.error, isNotNull);

      // Accept must not persist anything from a failed capture.
      final before = h.container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'gate-wiring-1');
      await h.factory.accept();
      final after = h.container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'gate-wiring-1');
      expect(after.acousticState.driverChannels.map((c) => c.frdData?.id),
          before.acousticState.driverChannels.map((c) => c.frdData?.id));
    });

    test('Room: recorder start failure -> error, no preview, no Accept',
        () async {
      final h = await _harness();
      addTearDown(h.container.dispose);
      h.mic.failStart = true;
      h.room.markReady();
      await h.room.capture();

      expect(h.mic.roomStarts, 1);
      expect(h.room.state.phase, RoomMeasurementPhaseUi.ready);
      expect(h.room.state.capturedResponse, isNull);
      expect(h.room.state.error, isNotNull);

      await h.room.accept();
      final project = h.container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'gate-wiring-1');
      expect(project.roomState.before.leftSystemFrd, isNull);
      expect(project.roomState.before.rightSystemFrd, isNull);
    });

    test('a failed capture never reuses the previous successful measurement',
        () async {
      final h = await _harness();
      addTearDown(h.container.dispose);
      h.room.markReady();
      await h.room.capture();
      final firstPreview = h.room.state.capturedResponse;
      expect(firstPreview, isNotNull);
      h.room.retry();

      h.mic.failStart = true;
      h.room.markReady();
      await h.room.capture();
      expect(h.room.state.capturedResponse, isNull,
          reason: 'the earlier successful response must not resurface as if '
              'it were this capture\'s result');
    });
  });

  group('4. warning acknowledgement gates capture in the controller', () {
    /// Uncalibrated profile -> the gate raises explicitlyUncalibrated.
    ProProject uncalibrated(ProProject p) => p.copyWith(
          selectedMicrophoneProfile: MeasurementMicrophoneProfile(
            id: 'uncal-mic',
            manufacturer: 'TUNAI',
            model: 'Uncal',
            connectionType: 'usb',
            calibrationSource: CalibrationSource.uncalibrated,
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );

    Future<_Harness> uncalibratedHarness() async {
      // Build the chain first, then swap in the uncalibrated profile and
      // re-run the setup check so the ONLY outstanding issue is the warning.
      final h = await _harness(mutate: (p) => uncalibrated(p));
      final store = h.container.read(proProjectStoreProvider.notifier);
      await refreshGateReadiness(
        store,
        h.container
            .read(proProjectStoreProvider)
            .projects
            .firstWhere((p) => p.id == 'gate-wiring-1'),
      );
      return h;
    }

    test('warning without acknowledgement blocks, zero recorder calls',
        () async {
      final h = await uncalibratedHarness();
      addTearDown(h.container.dispose);
      final gate = await h.factory.evaluateCaptureGate();
      expect(gate.blockers, isEmpty);
      expect(
          gate.hasWarning(MeasurementCaptureWarningCode.explicitlyUncalibrated),
          isTrue);
      expect(gate.requiresExplicitWarningAcknowledgement, isTrue);

      h.factory.markReady();
      await h.factory.capture();
      h.room.markReady();
      await h.room.capture();
      expect(h.mic.totalStarts, 0);
    });

    test('explicit acknowledgement unlocks capture on both controllers',
        () async {
      final h = await uncalibratedHarness();
      addTearDown(h.container.dispose);

      h.factory.acknowledgeWarnings(await h.factory.evaluateCaptureGate());
      h.room.acknowledgeWarnings(await h.room.evaluateCaptureGate());

      h.factory.markReady();
      await h.factory.capture();
      h.room.markReady();
      await h.room.capture();
      expect(h.mic.factoryStarts, 1);
      expect(h.mic.roomStarts, 1);
    });

    test('acknowledgement is not created for a verdict carrying blockers',
        () async {
      final h = await _harness(permission: false);
      addTearDown(h.container.dispose);
      h.factory.acknowledgeWarnings(await h.factory.evaluateCaptureGate());
      expect(h.factory.warningAcknowledgement, isNull,
          reason: 'a warning ack must never be minted for a blocked chain');
    });

    test('a later setup re-check invalidates an earlier acknowledgement',
        () async {
      final h = await uncalibratedHarness();
      addTearDown(h.container.dispose);
      h.factory.acknowledgeWarnings(await h.factory.evaluateCaptureGate());
      expect((await h.factory.evaluateCaptureGate()).canCapture, isTrue);

      // New generation id -> the old ack no longer covers it.
      await refreshGateReadiness(
        h.container.read(proProjectStoreProvider.notifier),
        h.container
            .read(proProjectStoreProvider)
            .projects
            .firstWhere((p) => p.id == 'gate-wiring-1'),
      );
      expect((await h.factory.evaluateCaptureGate()).canCapture, isFalse);

      h.factory.markReady();
      await h.factory.capture();
      expect(h.mic.factoryStarts, 0);
    });
  });

  group('5. UI/controller policy parity', () {
    test('both controllers evaluate the same gate for the same project',
        () async {
      final h = await _harness(permission: false);
      addTearDown(h.container.dispose);
      final f = await h.factory.evaluateCaptureGate();
      final r = await h.room.evaluateCaptureGate();
      expect(f.canCapture, r.canCapture);
      expect(f.primaryBlocker?.code, r.primaryBlocker?.code);
      expect(f.primaryBlocker?.remediation, r.primaryBlocker?.remediation);
    });

    test('system default input never reports as available', () async {
      final h = await _harness(
        mutate: (p) => withGateReadySetup(p.copyWith(
          selectedInputDevice: MeasurementInputDeviceSelection.systemDefault(
              selectedAt: DateTime.utc(2026, 1, 1)),
        )),
      );
      addTearDown(h.container.dispose);
      // Re-run setup so the readiness identity matches the system-default
      // selection (a specific-device check would not authorise it).
      await refreshGateReadiness(
        h.container.read(proProjectStoreProvider.notifier),
        h.container
            .read(proProjectStoreProvider)
            .projects
            .firstWhere((p) => p.id == 'gate-wiring-1'),
      );
      final gate = await h.factory.evaluateCaptureGate();
      expect(gate.inputAvailability,
          MeasurementRuntimeInputAvailability.systemDefaultUnverified);
      expect(gate.inputAvailability,
          isNot(MeasurementRuntimeInputAvailability.available));
      expect(gate.canCapture, isTrue);
    });
  });
}
