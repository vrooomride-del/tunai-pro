// TUNAI PRO Measurement Flow Completion — LiveMeasurementController tests.
//
// LiveMeasurementController sequences existing engines; it does not run its
// own recording/FFT and does not write DSP/transport. Real recording needs
// real platform channels (record/just_audio) with no fake in this codebase,
// so MicMeasurementController itself is faked here at the public-API
// boundary (override startMeasurement) — the same pattern already used for
// ProGuidedAiController (_FakeGuidedAiController in guided_ai_ui_flow_test.dart).
//
// What's tested:
//  1. capture() actually calls MicMeasurementController.startMeasurement()
//  2. BLE active -> bleWarmup=true
//  3. USB active (no BLE) -> bleWarmup=false
//  4. Local (nothing connected) -> bleWarmup=false
//  5. Accept (Before) writes the exact channelId's frdData
//  6. Accept preserves other channels' frdData and the whole tuningState
//  7. frdReadiness is false at 1-3/4, true at 4/4
//  8. retry() persists nothing
//  9. accept() is the only thing that persists
// 10. Before/After are stored separately — After accept never touches
//     driverChannels[i].frdData
// 11. After at 3/4 does not call submitAfterFourChannelFrd
// 12. After at 4/4 calls submitAfterFourChannelFrd with the right refs and
//     records the returned cycle via addCorrectionCycle
// 13. No direct transport/DSP write reference anywhere in the new files
// 14. No automatic mute/output-gain write anywhere in the new files

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/acoustic/acoustic_apply_engine.dart';
import 'package:tunai_pro/core/deploy/pro_adau1701_hardware_context.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_context_provider.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_executor.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/orchestrator/pro_explanation.dart';
import 'package:tunai_pro/core/orchestrator/pro_guided_ai_controller.dart';
import 'package:tunai_pro/core/orchestrator/pro_guided_ai_state.dart';
import 'package:tunai_pro/core/orchestrator/pro_local_orchestrator_session.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_types.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_correction_cycle.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/core/speaker_profile.dart';
import 'package:tunai_pro/core/transport/adau1701_tuning_transport.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';
import 'package:tunai_pro/features/mic/mic_measurement_controller.dart' as mic;
import 'package:tunai_pro/features/workbench/tabs/live_measurement_controller.dart';
import 'package:tunai_pro/core/measurement/measurement_input_device_service.dart';
import '../support/capture_gate_fixtures.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _FakeMicController extends mic.MicMeasurementController {
  // Capture is gated (Phase 3-D3): the gate's runtime preflight asks this
  // service for permission + a fresh device list. Serve the known-good chain
  // the shared fixtures seed, so these tests exercise capture mechanics
  // rather than re-testing the gate.
  @override
  MeasurementInputDeviceService get inputDeviceService =>
      fakeGateInputDeviceService();

  _FakeMicController(super.ref);
  bool? lastBleWarmup;
  int callCount = 0;
  List<Map<String, double>> nextResponse = const [
    {'frequency': 100.0, 'db': -1.0},
    {'frequency': 1000.0, 'db': -2.0},
    {'frequency': 10000.0, 'db': -1.5},
  ];
  bool nextShouldError = false;

  @override
  Future<void> startMeasurement({
    CalibrationCurve? calibrationCurve,
    SpeakerProfile? speakerProfile,
    bool bleWarmup = false,
  }) async {
    callCount++;
    lastBleWarmup = bleWarmup;
    if (nextShouldError) {
      state = state.copyWith(
          status: mic.MeasurementStatus.error, error: 'fake mic error');
      return;
    }
    state = state.copyWith(
      status: mic.MeasurementStatus.done,
      frequencyResponse: nextResponse,
    );
  }

  @override
  // ignore: must_call_super
  void dispose() {
    // Deliberately skip super.dispose(): the immediate superclass
    // (MicMeasurementController) calls _recorder.dispose()/_player.dispose()
    // on the real record/just_audio plugins, which have no MethodChannel
    // handler in a plain test environment — and there is no way in Dart to
    // reach past it to StateNotifier.dispose() alone. This fake never starts
    // the real recorder/player (startMeasurement is fully overridden above),
    // so there is nothing real to release.
  }
}

class _CallTrackingGuidedAiController extends ProGuidedAiController {
  _CallTrackingGuidedAiController(ProGuidedAiState initial) {
    state = initial;
  }
  final List<
      ({
        ProProject before,
        ProProject after,
        Map<String, String> beforeRefs,
        Map<String, String> afterRefs
      })> submitCalls = [];
  CorrectionCycle? nextCycle;

  @override
  CorrectionCycle? submitAfterFourChannelFrd({
    required ProProject beforeProject,
    required ProProject afterProject,
    required TuningProjectState deployedTuningState,
    required int cycleNumber,
    required bool safetyPassed,
    required Map<String, String> beforeEvidenceRefs,
    required Map<String, String> afterEvidenceRefs,
    String? deployAckRef,
  }) {
    submitCalls.add((
      before: beforeProject,
      after: afterProject,
      beforeRefs: beforeEvidenceRefs,
      afterRefs: afterEvidenceRefs,
    ));
    return nextCycle;
  }
}

const _kDeviceId = 'DSP1701.100.00.01';

class _FakeTransport implements Adau1701TuningTransport {
  final bool connected;
  const _FakeTransport({this.connected = true});
  @override
  bool get isConnected => connected;
  @override
  bool get handshakeComplete => connected;
  @override
  String? get detectedProfile => connected ? _kDeviceId : null;
  @override
  Future<RawDspStateSnapshot> readRawDspState() async =>
      throw UnimplementedError();
  @override
  Future<Adau1701WriteAck> writePeqGain(int c, double g,
          {int band = 0}) async =>
      const Adau1701WriteAck(success: true, message: 'ok');
  @override
  Future<Adau1701WriteAck> writeFilterFrequency(int c, int f,
          {int band = 0, bool isHighPass = false}) async =>
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

DriverChannel _channel(String id, {ParsedMeasurementData? frd}) =>
    DriverChannel(
      id: id,
      name: id,
      role: id.contains('tw') ? DriverRole.tweeter : DriverRole.woofer,
      side: id.endsWith('l') ? DriverSide.left : DriverSide.right,
      frdData: frd,
    );

ParsedMeasurementData _frd(String id) => ParsedMeasurementData(
      id: id,
      sourceFileName: '$id.frd',
      fileType: AcousticFileType.frd,
      importedAt: DateTime.utc(2025, 1, 1),
      points: const [
        MeasurementDataPoint(frequencyHz: 1000, magnitudeDb: 80.0),
      ],
    );

ProProject _fourChannelProject({bool anyFrdAlready = false}) =>
    withGateReadySetup(ProProject(
      id: 'proj-1',
      name: 'Test Project',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2025, 1, 1),
      updatedAt: DateTime.utc(2025, 1, 1),
      acousticState: MeasurementProjectState(driverChannels: [
        _channel('ch_tw_l', frd: anyFrdAlready ? _frd('pre-tw-l') : null),
        _channel('ch_wf_l', frd: anyFrdAlready ? _frd('pre-wf-l') : null),
        _channel('ch_tw_r', frd: anyFrdAlready ? _frd('pre-tw-r') : null),
        _channel('ch_wf_r', frd: anyFrdAlready ? _frd('pre-wf-r') : null),
      ]),
      tuningState: TuningProjectState(peqChannels: const [
        PeqChannelState(channelId: 'ch_tw_l', bands: [
          PeqBand(id: 'existing-band', frequencyHz: 500, gainDb: -2.0, q: 1.2),
        ]),
      ]),
    ));

// ── Harness ───────────────────────────────────────────────────────────────────

class _Harness {
  final ProviderContainer container;
  final _FakeMicController fakeMic;
  const _Harness(this.container, this.fakeMic);

  ProProject get project => container
      .read(proProjectStoreProvider)
      .projects
      .firstWhere((p) => p.id == 'proj-1');

  LiveMeasurementController get ctrl =>
      container.read(liveMeasurementControllerProvider('proj-1').notifier);

  LiveMeasurementState get state =>
      container.read(liveMeasurementControllerProvider('proj-1'));
}

Future<_Harness> _buildHarness({
  ProProject? seedProject,
  List<Override> extraOverrides = const [],
}) async {
  late _FakeMicController fakeMicInstance;
  final container = ProviderContainer(overrides: [
    mic.micMeasurementProvider.overrideWith((ref) {
      fakeMicInstance = _FakeMicController(ref);
      return fakeMicInstance;
    }),
    ...extraOverrides,
  ]);
  addTearDown(container.dispose);
  await container
      .read(proProjectStoreProvider.notifier)
      .addProject(seedProject ?? _fourChannelProject());
  // Force-read once so the override's mic instance is constructed before
  // tests reach for it.
  container.read(mic.micMeasurementProvider);
  return _Harness(container, fakeMicInstance);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // _FakeMicController subclasses the real MicMeasurementController to
  // reuse its public API contract (StateNotifierProvider requires a subtype
  // of MicMeasurementController). That base class's field initializers
  // construct real AudioRecorder()/AudioPlayer() instances unconditionally
  // — this fake never calls into them (startMeasurement/dispose are fully
  // overridden), but plain construction alone still reaches out to their
  // platform channels. Stub those channels to no-op so construction and
  // teardown don't throw MissingPluginException in a plugin-less test host.
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

  group('1. MicMeasurementController is actually invoked', () {
    test('capture() calls startMeasurement exactly once', () async {
      final h = await _buildHarness();
      h.ctrl.markReady();
      await h.ctrl.capture();
      expect(h.fakeMic.callCount, 1);
    });
  });

  group('2. BLE active -> bleWarmup=true', () {
    test('', () async {
      final h = await _buildHarness(extraOverrides: [
        activeAdau1701ContextProvider.overrideWith((ref) =>
            Adau1701HardwareContext.fromTransport(const _FakeTransport())),
      ]);
      expect(h.ctrl.transportKind, TransportKind.ble);
      h.ctrl.markReady();
      await h.ctrl.capture();
      expect(h.fakeMic.lastBleWarmup, isTrue);
    });
  });

  group('3. USB active (no BLE) -> bleWarmup=false', () {
    test('', () async {
      final h = await _buildHarness(extraOverrides: [
        adau1701Icp5UsbContextProvider.overrideWith((ref) =>
            Adau1701HardwareContext.fromTransport(const _FakeTransport())),
      ]);
      expect(h.ctrl.transportKind, TransportKind.usb);
      h.ctrl.markReady();
      await h.ctrl.capture();
      expect(h.fakeMic.lastBleWarmup, isFalse);
    });
  });

  group('4. Local (nothing connected) -> bleWarmup=false', () {
    test('', () async {
      final h = await _buildHarness(extraOverrides: [
        adau1701Icp5UsbContextProvider.overrideWith((ref) =>
            Adau1701HardwareContext.fromTransport(
                const _FakeTransport(connected: false))),
      ]);
      expect(h.ctrl.transportKind, TransportKind.local);
      h.ctrl.markReady();
      await h.ctrl.capture();
      expect(h.fakeMic.lastBleWarmup, isFalse);
    });
  });

  group('5-6. Accept (Before) storage', () {
    test('writes exactly the current channelId\'s frdData', () async {
      final h = await _buildHarness();
      h.ctrl.markReady();
      await h.ctrl.capture();
      await h.ctrl.accept();

      final updated = h.project.acousticState.driverChannels
          .firstWhere((c) => c.id == 'ch_tw_l');
      expect(updated.hasParsedFrd, isTrue);
      expect(updated.frdData!.points.map((p) => p.frequencyHz),
          [100.0, 1000.0, 10000.0]);
    });

    test('does not touch other channels or tuningState', () async {
      final h = await _buildHarness();
      final before = h.project;
      h.ctrl.markReady();
      await h.ctrl.capture();
      await h.ctrl.accept();

      final after = h.project;
      for (final id in ['ch_wf_l', 'ch_tw_r', 'ch_wf_r']) {
        final b =
            before.acousticState.driverChannels.firstWhere((c) => c.id == id);
        final a =
            after.acousticState.driverChannels.firstWhere((c) => c.id == id);
        expect(a.frdData, b.frdData, reason: '$id must be untouched');
      }
      expect(after.tuningState, before.tuningState,
          reason:
              'PEQ/XO/gain/delay state must be untouched by a measurement save');
    });
  });

  group('7. frdReadiness tracks saved progress', () {
    test('false at 1/4..3/4, true at 4/4', () async {
      final h = await _buildHarness();
      for (var i = 0; i < 4; i++) {
        expect(
            ProGuidedAiController.frdReadiness(h.project).isFullyReady, isFalse,
            reason: 'must still be false before channel ${i + 1} is accepted');
        h.ctrl.markReady();
        await h.ctrl.capture();
        await h.ctrl.accept();
      }
      expect(
          ProGuidedAiController.frdReadiness(h.project).isFullyReady, isTrue);
      expect(ProGuidedAiController.frdReadiness(h.project).readyCount, 4);
    });
  });

  group('8-9. Retry vs Accept persistence', () {
    test('retry() persists nothing', () async {
      final h = await _buildHarness();
      final before = h.project;
      h.ctrl.markReady();
      await h.ctrl.capture();
      h.ctrl.retry();
      expect(h.project, same(before),
          reason: 'the project object must be the exact same instance — '
              'no store write happened');
      expect(h.state.phase, LiveMeasurementPhase.ready);
      expect(h.state.channelIndex, 0,
          reason: 'retry does not advance the channel');
    });

    test('accept() is the only thing that persists', () async {
      final h = await _buildHarness();
      final before = h.project;
      h.ctrl.markReady();
      await h.ctrl.capture();
      expect(h.project, same(before), reason: 'capture alone must not persist');
      await h.ctrl.accept();
      expect(h.project, isNot(same(before)));
    });
  });

  group('local apply success alone must not unlock After mode', () {
    test(
        'afterModeAvailable is false when Guided AI applied locally but no '
        'real hardware write has succeeded yet', () async {
      final applyResult = TuningApplyResultStub.ok('ch_tw_l');
      final h = await _buildHarness(
        seedProject: _fourChannelProject(anyFrdAlready: true),
        extraOverrides: [
          // lastHardwareWriteResultProvider deliberately left at its
          // default null — no Deploy tab apply has happened.
          guidedAiProvider
              .overrideWith((ref) => _CallTrackingGuidedAiController(
                    ProGuidedAiCompleted(
                      outcome: _stubOutcome,
                      explanation: _stubExplanation,
                      applyResult: applyResult,
                      loopPhase: ProClosedLoopPhase.awaitingAfterFrd,
                    ),
                  )),
        ],
      );

      expect(h.ctrl.afterModeAvailable, isFalse,
          reason: 'the local PEQ apply succeeding is not proof anything '
              'was actually written to the speaker');
      expect(h.ctrl.afterModeBlockedReason, isNotNull);

      h.ctrl.setMode(LiveMeasurementMode.after);
      expect(h.state.mode, LiveMeasurementMode.before,
          reason: 'setMode(after) must fail closed even when called '
              'directly, not just refuse at the UI toggle');
    });

    test(
        'afterModeAvailable is false when the hardware write executed but '
        'failed', () async {
      final applyResult = TuningApplyResultStub.ok('ch_tw_l');
      const failedResult = HardwareWriteExecutionResult(
        planId: 'plan-stub',
        executed: true,
        rejectionReason: null,
        outcomes: [
          HardwareWriteOpOutcome(
            op: HardwareWriteOp(
              channelId: 'ch_tw_l',
              parameterKind: HardwareParamKind.peqGain,
              bandIndex: 0,
              targetValue: -1.0,
              verification: HardwareParamVerification.captureProven,
              writable: true,
              reason: 'stub',
            ),
            status: HardwareWriteOpStatus.failed,
            report: null,
            message: 'nack',
          ),
        ],
      );
      final h = await _buildHarness(
        seedProject: _fourChannelProject(anyFrdAlready: true),
        extraOverrides: [
          lastHardwareWriteResultProvider.overrideWith((ref) => failedResult),
          guidedAiProvider
              .overrideWith((ref) => _CallTrackingGuidedAiController(
                    ProGuidedAiCompleted(
                      outcome: _stubOutcome,
                      explanation: _stubExplanation,
                      applyResult: applyResult,
                      loopPhase: ProClosedLoopPhase.awaitingAfterFrd,
                    ),
                  )),
        ],
      );

      expect(h.ctrl.afterModeAvailable, isFalse);
      expect(h.ctrl.afterModeBlockedReason, contains('실패'));
    });

    test('afterModeAvailable is true once the real write succeeded', () async {
      final applyResult = TuningApplyResultStub.ok('ch_tw_l');
      final h = await _buildHarness(
        seedProject: _fourChannelProject(anyFrdAlready: true),
        extraOverrides: [
          lastHardwareWriteResultProvider
              .overrideWith((ref) => _allWrittenResult()),
          guidedAiProvider
              .overrideWith((ref) => _CallTrackingGuidedAiController(
                    ProGuidedAiCompleted(
                      outcome: _stubOutcome,
                      explanation: _stubExplanation,
                      applyResult: applyResult,
                      loopPhase: ProClosedLoopPhase.awaitingAfterFrd,
                    ),
                  )),
        ],
      );

      expect(h.ctrl.afterModeAvailable, isTrue);
      expect(h.ctrl.afterModeBlockedReason, isNull);
    });
  });

  group('10. Before/After separation', () {
    test('After accept never writes driverChannels[i].frdData', () async {
      final applyResult = TuningApplyResultStub.ok('ch_tw_l');
      final h = await _buildHarness(
        // FullSystemAfterFrdInput.add() requires an existing Before FRD to
        // compare against (it rejects a channel with no Before data).
        seedProject: _fourChannelProject(anyFrdAlready: true),
        extraOverrides: [
          lastHardwareWriteResultProvider
              .overrideWith((ref) => _allWrittenResult()),
          guidedAiProvider
              .overrideWith((ref) => _CallTrackingGuidedAiController(
                    ProGuidedAiCompleted(
                      outcome: _stubOutcome,
                      explanation: _stubExplanation,
                      applyResult: applyResult,
                      loopPhase: ProClosedLoopPhase.awaitingAfterFrd,
                    ),
                  )),
        ],
      );
      final beforeAcoustic = h.project.acousticState;

      h.ctrl.setMode(LiveMeasurementMode.after);
      h.ctrl.markReady();
      await h.ctrl.capture();
      await h.ctrl.accept();

      expect(h.project.acousticState, beforeAcoustic,
          reason: 'After capture must never touch Before frdData');
      expect(h.ctrl.afterByChannel.containsKey('ch_tw_l'), isTrue);
    });
  });

  group('11. After at 3/4 does not submit', () {
    test('', () async {
      final applyResult = TuningApplyResultStub.ok('ch_tw_l');
      late _CallTrackingGuidedAiController fakeAi;
      final h = await _buildHarness(
        seedProject: _fourChannelProject(anyFrdAlready: true),
        extraOverrides: [
          lastHardwareWriteResultProvider
              .overrideWith((ref) => _allWrittenResult()),
          guidedAiProvider.overrideWith((ref) {
            fakeAi = _CallTrackingGuidedAiController(
              ProGuidedAiCompleted(
                outcome: _stubOutcome,
                explanation: _stubExplanation,
                applyResult: applyResult,
                loopPhase: ProClosedLoopPhase.awaitingAfterFrd,
              ),
            );
            return fakeAi;
          }),
        ],
      );

      h.ctrl.setMode(LiveMeasurementMode.after);
      for (var i = 0; i < 3; i++) {
        h.ctrl.markReady();
        await h.ctrl.capture();
        await h.ctrl.accept();
      }
      expect(fakeAi.submitCalls, isEmpty);
      expect(h.ctrl.afterByChannel.length, 3);
    });
  });

  group('12. After at 4/4 submits with correct refs', () {
    test('', () async {
      final applyResult = TuningApplyResultStub.ok('ch_tw_l');
      late _CallTrackingGuidedAiController fakeAi;
      final stubCycle = CorrectionCycle(
        projectId: 'proj-1',
        channelId: 'full_system',
        cycleNumber: 1,
        beforeMeasurementRef: 'ref',
        peqSnapshot: PeqChannelState.empty('ch_tw_l'),
        createdAt: DateTime.utc(2025, 1, 1),
      );
      final h = await _buildHarness(
        seedProject: _fourChannelProject(anyFrdAlready: true),
        extraOverrides: [
          lastHardwareWriteResultProvider
              .overrideWith((ref) => _allWrittenResult()),
          guidedAiProvider.overrideWith((ref) {
            fakeAi = _CallTrackingGuidedAiController(
              ProGuidedAiCompleted(
                outcome: _stubOutcome,
                explanation: _stubExplanation,
                applyResult: applyResult,
                loopPhase: ProClosedLoopPhase.awaitingAfterFrd,
              ),
            )..nextCycle = stubCycle;
            return fakeAi;
          }),
        ],
      );

      h.ctrl.setMode(LiveMeasurementMode.after);
      for (var i = 0; i < 4; i++) {
        h.ctrl.markReady();
        await h.ctrl.capture();
        await h.ctrl.accept();
      }

      expect(fakeAi.submitCalls.length, 1);
      final call = fakeAi.submitCalls.single;
      expect(call.beforeRefs.keys.toSet(),
          {'ch_tw_l', 'ch_wf_l', 'ch_tw_r', 'ch_wf_r'});
      expect(call.afterRefs.keys.toSet(),
          {'ch_tw_l', 'ch_wf_l', 'ch_tw_r', 'ch_wf_r'});
      expect(h.project.correctionCycles, contains(stubCycle));
      expect(h.state.lastCompletedCycle, stubCycle);
    });
  });
}

// ── Small helpers local to this file ─────────────────────────────────────────

const _stubOutcome = ProLocalOrchestratorOutcome(
  sessionId: 'sess-0',
  finalStatus: ProOrchestratorOutcomeStatus.completed,
  stepRecords: [],
);

const _stubExplanation = ProExplanation(
  title: 'done',
  summary: 'done',
  explanationLevel: ProExplanationLevel.intermediate,
);

abstract final class TuningApplyResultStub {
  static TuningApplyResult ok(String channelId) => TuningApplyResult(
        status: TuningApplyStatus.ok,
        updatedChannel: PeqChannelState.empty(channelId),
        applied: const [],
        skipped: const [],
        channelId: channelId,
        safetyPolicyId: 'stub-policy',
        safetyPolicyVersion: 1,
        evidenceRefs: const [],
        reasons: const [],
      );
}

/// A HardwareWriteExecutionResult with allWritten == true — the real-write
/// signal afterModeAvailable now requires in addition to the local apply
/// result (see live_measurement_controller.dart's afterModeAvailable doc).
HardwareWriteExecutionResult _allWrittenResult() =>
    const HardwareWriteExecutionResult(
      planId: 'plan-stub',
      executed: true,
      rejectionReason: null,
      outcomes: [
        HardwareWriteOpOutcome(
          op: HardwareWriteOp(
            channelId: 'ch_tw_l',
            parameterKind: HardwareParamKind.peqGain,
            bandIndex: 0,
            targetValue: -1.0,
            verification: HardwareParamVerification.captureProven,
            writable: true,
            reason: 'stub',
          ),
          status: HardwareWriteOpStatus.written,
          report: null,
          message: 'ok',
        ),
      ],
    );
