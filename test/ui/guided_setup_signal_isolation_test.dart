// Phase 3-D2 final closure — Setup Level Check signal isolation.
//
// Policy under test:
//  - Guided Setup default is an explicit stereo LEFT-ONLY signal, never mono
//    (a mono WAV can be duplicated to both channels by the output device, so
//    it cannot guarantee that only one speaker played).
//  - Expert re-check may switch to Right (and mono stays available for
//    diagnostics / API compatibility only, never as the Guided default).
//  - L+R are never played simultaneously and isolation never uses a DSP
//    mute / gain / channel-routing write -- the stereo WAV itself carries it
//    (inactive channel is exact-zero PCM, produced by the same
//    buildStereoPinkNoiseWavBytes the Room measurement path already uses).
//  - The beginner screen names the playing/excluded speaker and never shows
//    the word "mono".
//
// The SUCCESS path of runInputLevelCheck itself needs a real recorder
// platform channel and is not unit-testable here (same precedent as
// guided_measurement_setup_dialog_test.dart) -- the signal routing is
// therefore asserted structurally plus on the shared byte builder.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device_service.dart';
import 'package:tunai_pro/core/measurement/measurement_setup_readiness.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/features/mic/guided_measurement_setup_dialog.dart';
import 'package:tunai_pro/features/mic/mic_measurement_controller.dart' as mic;

// ── Harness (same shape as guided_measurement_setup_dialog_test.dart) ────────

class _FakeInputDeviceApi implements MeasurementInputDeviceApi {
  @override
  Future<bool> hasPermission({bool request = true}) async => true;

  @override
  Future<List<MeasurementInputDeviceDescriptor>> listInputDevices() async =>
      const [];
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

ProProject _project() => ProProject(
      id: 'proj-setup-signal',
      name: 'Setup Signal Test',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Future<ProviderContainer> _seed() async {
  final container = ProviderContainer(overrides: [
    mic.micMeasurementProvider.overrideWith(
        (ref) => _PartialFakeMicController(ref, _FakeInputDeviceApi())),
  ]);
  await container.read(proProjectStoreProvider.notifier).addProject(_project());
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
                  projectId: 'proj-setup-signal'),
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

/// Decodes the interleaved 16-bit stereo PCM body of a 44-byte-header WAV.
({List<int> left, List<int> right}) _splitStereoPcm(Uint8List wav) {
  final data = ByteData.sublistView(wav, 44);
  final left = <int>[];
  final right = <int>[];
  for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
    left.add(data.getInt16(i, Endian.little));
    right.add(data.getInt16(i + 2, Endian.little));
  }
  return (left: left, right: right);
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

  Future<void> useViewport(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  // ── 1. Guided Setup default signal ────────────────────────────────────────

  group('1. Guided Setup default signal is left-only, never mono', () {
    testWidgets('default check names the LEFT speaker as the one that plays',
        (tester) async {
      await useViewport(tester);
      final container = await _seed();
      addTearDown(container.dispose);
      await _pump(tester, container);

      expect(find.text('왼쪽 스피커에서 테스트 신호를 재생합니다.'), findsOneWidget);
      expect(find.text('오른쪽 스피커는 테스트 신호에서 자동으로 제외됩니다.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Expert Details shows "Test Left" pre-selected as the default',
        (tester) async {
      await useViewport(tester);
      final container = await _seed();
      addTearDown(container.dispose);
      await _pump(tester, container);

      await tester.ensureVisible(find.text('Expert Details'));
      await tester.tap(find.text('Expert Details'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ChoiceChip, 'Test Left'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Test Right'), findsOneWidget);
      final leftChip = tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Test Left'));
      final rightChip = tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Test Right'));
      expect(leftChip.selected, isTrue,
          reason: 'Guided default must be the left-only stereo signal');
      expect(rightChip.selected, isFalse);
    });

    testWidgets(
        'mono is never the Guided default and never appears on the '
        'beginner screen', (tester) async {
      await useViewport(tester);
      final container = await _seed();
      addTearDown(container.dispose);
      await _pump(tester, container);

      // Before opening Expert Details, no mono wording is visible anywhere.
      expect(find.textContaining('mono'), findsNothing);
      expect(find.textContaining('Mono'), findsNothing);

      await tester.ensureVisible(find.text('Expert Details'));
      await tester.tap(find.text('Expert Details'));
      await tester.pumpAndSettle();

      // It remains reachable for diagnostics under Expert Details only, and
      // is not the selected default there either.
      final monoChip = find.widgetWithText(ChoiceChip, 'Mono (diagnostic)');
      expect(monoChip, findsOneWidget);
      expect(tester.widget<ChoiceChip>(monoChip).selected, isFalse);
    });
  });

  // ── 2. Expert re-check switches side and invalidates the prior side ───────

  group('2. Expert re-check switches the announced speaker', () {
    testWidgets('selecting Test Right flips the guidance to the right speaker',
        (tester) async {
      await useViewport(tester);
      final container = await _seed();
      addTearDown(container.dispose);
      await _pump(tester, container);

      await tester.ensureVisible(find.text('Expert Details'));
      await tester.tap(find.text('Expert Details'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Test Right'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Test Right'));
      await tester.pumpAndSettle();

      expect(find.text('오른쪽 스피커에서 테스트 신호를 재생합니다.'), findsOneWidget);
      expect(find.text('왼쪽 스피커는 테스트 신호에서 자동으로 제외됩니다.'), findsOneWidget);
      expect(find.text('왼쪽 스피커에서 테스트 신호를 재생합니다.'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  // ── 3. Actual signal isolation (shared Room generator, exact-zero PCM) ────

  group('3. Setup Level Check signal isolation', () {
    test('leftOnly WAV: every Right PCM sample is exactly 0', () {
      final wav = mic.MicMeasurementController.buildStereoPinkNoiseWavBytes(
          leftActive: true, totalSec: 1);
      final pcm = _splitStereoPcm(wav);
      expect(pcm.right.every((s) => s == 0), isTrue);
      expect(pcm.left.any((s) => s != 0), isTrue);
    });

    test('rightOnly WAV: every Left PCM sample is exactly 0', () {
      final wav = mic.MicMeasurementController.buildStereoPinkNoiseWavBytes(
          leftActive: false, totalSec: 1);
      final pcm = _splitStereoPcm(wav);
      expect(pcm.left.every((s) => s == 0), isTrue);
      expect(pcm.right.any((s) => s != 0), isTrue);
    });

    test(
        'runInputLevelCheck routes every non-mono signal through the existing '
        '_generateStereoPinkNoise path -- no second signal generator', () {
      final src = File('lib/features/mic/mic_measurement_controller.dart')
          .readAsStringSync();
      // Isolate runInputLevelCheck's own body by brace matching -- the file
      // also contains the pre-existing Factory per-driver path
      // (startChannelMeasurement), which is DSP-mute-based by design and is
      // deliberately NOT in scope here.
      final start = src.indexOf('Future<MeasurementSetupCaptureResult> '
          'runInputLevelCheck(');
      expect(start, greaterThanOrEqualTo(0),
          reason: 'runInputLevelCheck was renamed?');
      final openBrace = src.indexOf('{', src.indexOf(')', start));
      var depth = 0;
      var end = openBrace;
      for (; end < src.length; end++) {
        if (src[end] == '{') depth++;
        if (src[end] == '}') {
          depth--;
          if (depth == 0) break;
        }
      }
      final body = src.substring(start, end + 1);

      // The level-check branch must delegate to the shared stereo generator
      // with leftActive derived from the requested side.
      expect(body.contains('_generateStereoPinkNoise'), isTrue);
      expect(
          body.contains(
              'leftActive: signal == MeasurementLevelCheckSignal.leftOnly'),
          isTrue,
          reason: 'Setup Level Check must reuse the Room stereo generator, '
              'mapping leftOnly/rightOnly onto its leftActive flag.');
      // Isolation must never be attempted through a DSP write from this path.
      for (final banned in const [
        'writeOutputGain',
        'writeMasterMute',
        'setMute',
        'muteAllExcept',
        'startChannelMeasurement',
      ]) {
        expect(body.contains('$banned('), isFalse,
            reason: 'Setup Level Check isolation must come from the stereo '
                'WAV only, never a DSP write ($banned)');
      }
    });
  });

  // ── 4. Readiness records the side actually measured ──────────────────────

  group('4. readiness stores the real setup signal side', () {
    MeasurementSetupReadinessSnapshot snapshot(
            MeasurementSetupSignalSide side, String generationId) =>
        MeasurementSetupReadinessSnapshot(
          generationId: generationId,
          identity: const MeasurementSetupReadinessIdentity(
            projectId: 'proj-setup-signal',
            profileChecksum: 'mic-1',
            calibrationCurveChecksum: null,
            calibrationAngle: null,
            inputDeviceIdentity: 'device:dev-1',
            expectedSampleRate: 48000,
            expectedChannelCount: 1,
            qualityPolicyVersion: 'pro-provisional-1',
          ),
          isReady: true,
          blockers: const [],
          warnings: const [],
          checkedAt: DateTime.utc(2026, 1, 1),
          expiresAt: DateTime.utc(2026, 1, 2),
          selectedSetupSignalSide: side,
        );

    test('left/right sides survive a JSON round-trip', () {
      for (final side in [
        MeasurementSetupSignalSide.left,
        MeasurementSetupSignalSide.right,
      ]) {
        final decoded = MeasurementSetupReadinessSnapshot.fromJson(
            snapshot(side, 'gen-$side').toJson());
        expect(decoded.selectedSetupSignalSide, side);
      }
    });

    test('a re-check on the other side is a distinct generation', () {
      final left = snapshot(MeasurementSetupSignalSide.left, 'gen-left');
      final right = snapshot(MeasurementSetupSignalSide.right, 'gen-right');
      expect(left.generationId, isNot(right.generationId));
      expect(
          left.selectedSetupSignalSide, isNot(right.selectedSetupSignalSide));
    });
  });
}
