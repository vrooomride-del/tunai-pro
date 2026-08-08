// Phase 3-D1 — MicMeasurementController.measureNoiseFloor() /
// runInputLevelCheck(): fail-closed branch tests.
//
// Both methods check permission and resolve the input device BEFORE ever
// touching the real recorder/player, so those two failure branches are
// exercised here against the REAL production method bodies by overriding
// only `inputDeviceService` (the documented test seam) on a subclass — no
// platform channel mocking needed for these paths.
//
// The full success path (actual recording -> WAV parse -> PCM analysis) is
// NOT unit-testable without a real platform channel, consistent with this
// codebase's existing precedent for the FFT capture flow — see the Phase
// 3-D1 completion report's "verify on real Mac hardware" section.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device_service.dart';
import 'package:tunai_pro/core/measurement/measurement_setup_capture_result.dart';
import 'package:tunai_pro/features/mic/mic_measurement_controller.dart' as mic;

class _FakeInputDeviceApi implements MeasurementInputDeviceApi {
  bool permissionGranted;
  List<MeasurementInputDeviceDescriptor> devices;

  _FakeInputDeviceApi({this.permissionGranted = true, this.devices = const []});

  @override
  Future<bool> hasPermission({bool request = true}) async => permissionGranted;

  @override
  Future<List<MeasurementInputDeviceDescriptor>> listInputDevices() async =>
      devices;
}

class _PartialFakeMicController extends mic.MicMeasurementController {
  _PartialFakeMicController(super.ref, this._fakeApi);

  final _FakeInputDeviceApi _fakeApi;

  @override
  MeasurementInputDeviceService get inputDeviceService =>
      MeasurementInputDeviceService(_fakeApi);

  @override
  // ignore: must_call_super
  void dispose() {}
}

ProviderContainer _buildContainer(_FakeInputDeviceApi fakeApi) =>
    ProviderContainer(overrides: [
      mic.micMeasurementProvider
          .overrideWith((ref) => _PartialFakeMicController(ref, fakeApi)),
    ]);

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

  group('measureNoiseFloor — fail-closed branches', () {
    test('permission denied returns failure before touching the recorder',
        () async {
      final container =
          _buildContainer(_FakeInputDeviceApi(permissionGranted: false));
      addTearDown(container.dispose);
      final ctrl = container.read(mic.micMeasurementProvider.notifier);

      final result = await ctrl.measureNoiseFloor(
        inputSelection: MeasurementInputDeviceSelection.systemDefault(
            selectedAt: DateTime.now()),
      );
      expect(result.isSuccess, isFalse);
      expect(result.error, 'MIC_PERMISSION_DENIED');
    });

    test(
        'a vanished selected device returns failure, never silently uses '
        'system default instead', () async {
      final container = _buildContainer(
          _FakeInputDeviceApi(permissionGranted: true, devices: const []));
      addTearDown(container.dispose);
      final ctrl = container.read(mic.micMeasurementProvider.notifier);

      final result = await ctrl.measureNoiseFloor(
        inputSelection: MeasurementInputDeviceSelection.specificDevice(
          deviceId: 'dev-gone',
          labelSnapshot: 'Unplugged Mic',
          selectedAt: DateTime.now(),
        ),
      );
      expect(result.isSuccess, isFalse);
      expect(result.error, contains('dev-gone'));
    });
  });

  group('runInputLevelCheck — fail-closed branches', () {
    test('permission denied returns failure before touching the recorder',
        () async {
      final container =
          _buildContainer(_FakeInputDeviceApi(permissionGranted: false));
      addTearDown(container.dispose);
      final ctrl = container.read(mic.micMeasurementProvider.notifier);

      final result = await ctrl.runInputLevelCheck(
        inputSelection: MeasurementInputDeviceSelection.systemDefault(
            selectedAt: DateTime.now()),
      );
      expect(result.isSuccess, isFalse);
      expect(result.error, 'MIC_PERMISSION_DENIED');
    });

    test('a vanished selected device returns failure', () async {
      final container = _buildContainer(
          _FakeInputDeviceApi(permissionGranted: true, devices: const []));
      addTearDown(container.dispose);
      final ctrl = container.read(mic.micMeasurementProvider.notifier);

      final result = await ctrl.runInputLevelCheck(
        inputSelection: MeasurementInputDeviceSelection.specificDevice(
          deviceId: 'dev-gone',
          labelSnapshot: 'Unplugged Mic',
          selectedAt: DateTime.now(),
        ),
      );
      expect(result.isSuccess, isFalse);
      expect(result.error, contains('dev-gone'));
    });
  });

  group('startLiveLevelCheck — fail-closed branches', () {
    test('permission denied throws before touching the recorder', () async {
      final container =
          _buildContainer(_FakeInputDeviceApi(permissionGranted: false));
      addTearDown(container.dispose);
      final ctrl = container.read(mic.micMeasurementProvider.notifier);

      expect(
        () => ctrl.startLiveLevelCheck(
          inputSelection: MeasurementInputDeviceSelection.systemDefault(
              selectedAt: DateTime.now()),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test(
        'a vanished selected device throws MeasurementInputDeviceUnavailable '
        '— never silently uses system default', () async {
      final container = _buildContainer(
          _FakeInputDeviceApi(permissionGranted: true, devices: const []));
      addTearDown(container.dispose);
      final ctrl = container.read(mic.micMeasurementProvider.notifier);

      expect(
        () => ctrl.startLiveLevelCheck(
          inputSelection: MeasurementInputDeviceSelection.specificDevice(
            deviceId: 'dev-gone',
            labelSnapshot: 'Unplugged Mic',
            selectedAt: DateTime.now(),
          ),
        ),
        throwsA(isA<MeasurementInputDeviceUnavailable>()),
      );
    });

    test('isLiveLevelCheckActive stays false after a failed start', () async {
      final container =
          _buildContainer(_FakeInputDeviceApi(permissionGranted: false));
      addTearDown(container.dispose);
      final ctrl = container.read(mic.micMeasurementProvider.notifier);

      try {
        await ctrl.startLiveLevelCheck(
          inputSelection: MeasurementInputDeviceSelection.systemDefault(
              selectedAt: DateTime.now()),
        );
      } catch (_) {}
      expect(ctrl.isLiveLevelCheckActive, isFalse);
    });
  });

  group('stopLiveLevelCheck — no-op safety', () {
    test('is safe to call when no live session is active (no-op, no '
        'exception, no platform channel touched)', () async {
      final container =
          _buildContainer(_FakeInputDeviceApi(permissionGranted: true));
      addTearDown(container.dispose);
      final ctrl = container.read(mic.micMeasurementProvider.notifier);

      expect(ctrl.isLiveLevelCheckActive, isFalse);
      await ctrl.stopLiveLevelCheck();
      expect(ctrl.isLiveLevelCheckActive, isFalse);
    });

    test('is safe to call repeatedly back-to-back', () async {
      final container =
          _buildContainer(_FakeInputDeviceApi(permissionGranted: true));
      addTearDown(container.dispose);
      final ctrl = container.read(mic.micMeasurementProvider.notifier);

      await ctrl.stopLiveLevelCheck();
      await ctrl.stopLiveLevelCheck();
      await ctrl.stopLiveLevelCheck();
      expect(ctrl.isLiveLevelCheckActive, isFalse);
    });
  });

  group('buildLiveLevelPassEvidence — fail-closed with no prior session', () {
    test('returns failure() when no live level-check session has ever run',
        () async {
      final container =
          _buildContainer(_FakeInputDeviceApi(permissionGranted: true));
      addTearDown(container.dispose);
      final ctrl = container.read(mic.micMeasurementProvider.notifier);

      final result = ctrl.buildLiveLevelPassEvidence(
        inputSelection: MeasurementInputDeviceSelection.systemDefault(
            selectedAt: DateTime.now()),
        representativeDbFs: -20.0,
        peakDbFs: -15.0,
        stableDuration: const Duration(seconds: 1),
      );
      expect(result.isSuccess, isFalse);
    });
  });

  group('MeasurementSetupCaptureResult factories', () {
    test('failure() produces isSuccess=false with the given error', () {
      final r = MeasurementSetupCaptureResult.failure('boom');
      expect(r.isSuccess, isFalse);
      expect(r.error, 'boom');
      expect(r.evaluation, isNull);
    });
  });
}
