// Phase 3-D2 — GuidedMeasurementSetupDialog: device enumeration/selection,
// permission banner, overflow, close-before-init safety, and reachability
// of the noise-floor/level-check actions (their SUCCESS path needs a real
// recorder platform channel and is not unit-testable — consistent with this
// codebase's established precedent; see the Phase 3-D2 completion report).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device_service.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/features/mic/guided_measurement_setup_dialog.dart';
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

ProProject _project({MeasurementInputDeviceSelection? inputDevice}) =>
    ProProject(
      id: 'proj-setup-1',
      name: 'Setup Test',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      selectedInputDevice: inputDevice,
    );

Future<ProviderContainer> _seed(
  ProProject project, {
  _FakeInputDeviceApi? fakeApi,
}) async {
  final container = ProviderContainer(overrides: [
    mic.micMeasurementProvider.overrideWith((ref) =>
        _PartialFakeMicController(ref, fakeApi ?? _FakeInputDeviceApi())),
  ]);
  await container.read(proProjectStoreProvider.notifier).addProject(project);
  return container;
}

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          return Center(
            child: ElevatedButton(
              onPressed: () => showGuidedMeasurementSetupDialog(context,
                  projectId: 'proj-setup-1'),
              child: const Text('open'),
            ),
          );
        }),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
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

  group('open/close safety and overflow', () {
    testWidgets('opens with no overflow at 1280x720, closes cleanly',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final container = await _seed(_project());
      addTearDown(container.dispose);
      await _pump(tester, container);

      expect(find.text('CHECK MEASUREMENT SETUP'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('CHECK MEASUREMENT SETUP'), findsNothing);
    });

    testWidgets(
        'closing immediately after opening (before async device '
        'enumeration completes) does not throw', (tester) async {
      final container = await _seed(_project());
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(builder: (context) {
              return Center(
                child: ElevatedButton(
                  onPressed: () => showGuidedMeasurementSetupDialog(context,
                      projectId: 'proj-setup-1'),
                  child: const Text('open'),
                ),
              );
            }),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pump(); // dialog opens, postFrameCallback enumeration queued
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('input device enumeration and selection', () {
    testWidgets('shows enumerated devices and System Default option',
        (tester) async {
      final container = await _seed(
        _project(),
        fakeApi: _FakeInputDeviceApi(
          permissionGranted: true,
          devices: const [
            MeasurementInputDeviceDescriptor(id: 'dev1', label: 'USB Mic'),
          ],
        ),
      );
      addTearDown(container.dispose);
      await _pump(tester, container);

      expect(find.text('System Default'), findsOneWidget);
      expect(find.text('USB Mic'), findsOneWidget);
    });

    testWidgets('selecting a specific device persists to the project',
        (tester) async {
      final container = await _seed(
        _project(),
        fakeApi: _FakeInputDeviceApi(
          permissionGranted: true,
          devices: const [
            MeasurementInputDeviceDescriptor(id: 'dev1', label: 'USB Mic'),
          ],
        ),
      );
      addTearDown(container.dispose);
      await _pump(tester, container);

      await tester.tap(find.text('USB Mic'));
      await tester.pumpAndSettle();

      final project = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj-setup-1');
      expect(project.selectedInputDevice?.deviceId, 'dev1');
      expect(project.selectedInputDevice?.useSystemDefault, isFalse);
    });

    testWidgets('selecting System Default persists useSystemDefault=true',
        (tester) async {
      final container = await _seed(_project(
        inputDevice: MeasurementInputDeviceSelection.specificDevice(
            deviceId: 'dev1',
            labelSnapshot: 'USB Mic',
            selectedAt: DateTime.now()),
      ));
      addTearDown(container.dispose);
      await _pump(tester, container);

      await tester.tap(find.text('System Default'));
      await tester.pumpAndSettle();

      final project = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj-setup-1');
      expect(project.selectedInputDevice?.useSystemDefault, isTrue);
    });

    testWidgets('permission denied shows the remediation banner',
        (tester) async {
      final container = await _seed(
        _project(),
        fakeApi: _FakeInputDeviceApi(permissionGranted: false),
      );
      addTearDown(container.dispose);
      await _pump(tester, container);

      expect(find.textContaining('마이크 접근 권한'), findsOneWidget);
      expect(find.text('Allow'), findsOneWidget);
    });
  });

  group('microphone section', () {
    testWidgets('shows "select a microphone" prompt when none selected',
        (tester) async {
      final container = await _seed(_project());
      addTearDown(container.dispose);
      await _pump(tester, container);

      expect(find.text('측정 마이크를 선택하세요.'), findsOneWidget);
    });

    testWidgets('explicitly uncalibrated shows the acknowledgement checkbox',
        (tester) async {
      final now = DateTime.utc(2026, 1, 1);
      final project = ProProject(
        id: 'proj-setup-1',
        name: 'Setup Test',
        dspTarget: 'ADAU1701',
        createdAt: now,
        updatedAt: now,
        selectedMicrophoneProfile: MeasurementMicrophoneProfile(
          id: 'uncalibrated-explicit',
          manufacturer: '—',
          model: 'No Calibration',
          connectionType: 'n/a',
          calibrationSource: CalibrationSource.uncalibrated,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final container = await _seed(project);
      addTearDown(container.dispose);
      await _pump(tester, container);

      expect(find.byType(Checkbox), findsOneWidget);
      expect(find.textContaining('정확도가 낮아질 수 있습니다'), findsOneWidget);
    });
  });

  group('noise-floor / level-check action buttons are reachable', () {
    // NOT tapped here: tapping calls the REAL MicMeasurementController
    // .measureNoiseFloor()/.runInputLevelCheck(), which — once permission
    // and device resolution pass — calls path_provider's
    // getTemporaryDirectory() and the real recorder. Neither has a test
    // mock anywhere in this codebase (see
    // test/mic_measurement_ble_warmup_test.dart's header comment: "no
    // injection seam" for _recorder/_player), so actually invoking that
    // path here hangs the test runner rather than failing fast. Presence/
    // enabled-state of the buttons is exactly what a widget test can
    // safely assert; the button's onPressed callback and the controller
    // methods it calls are exercised directly in
    // test/measurement/mic_measurement_setup_capture_test.dart (permission
    // -denied / device-unavailable branches) and must be confirmed on real
    // Mac hardware per the Phase 3-D2 completion report.
    testWidgets('Measure Background Noise button is present and enabled',
        (tester) async {
      final container = await _seed(
        _project(),
        fakeApi: _FakeInputDeviceApi(
          permissionGranted: true,
          devices: const [
            MeasurementInputDeviceDescriptor(id: 'dev1', label: 'USB Mic'),
          ],
        ),
      );
      addTearDown(container.dispose);
      await _pump(tester, container);

      await tester.tap(find.text('USB Mic'));
      await tester.pumpAndSettle();

      final button = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Measure Background Noise'));
      expect(button.onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Play Test Signal & Measure button is present and enabled',
        (tester) async {
      final container = await _seed(
        _project(),
        fakeApi: _FakeInputDeviceApi(
          permissionGranted: true,
          devices: const [
            MeasurementInputDeviceDescriptor(id: 'dev1', label: 'USB Mic'),
          ],
        ),
      );
      addTearDown(container.dispose);
      await _pump(tester, container);

      await tester.tap(find.text('USB Mic'));
      await tester.pumpAndSettle();

      final button = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Play Test Signal & Measure'));
      expect(button.onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('Expert Details', () {
    testWidgets('toggles open/closed without overflow', (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final container = await _seed(_project());
      addTearDown(container.dispose);
      await _pump(tester, container);

      await tester.ensureVisible(find.text('Expert Details'));
      await tester.tap(find.text('Expert Details'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
