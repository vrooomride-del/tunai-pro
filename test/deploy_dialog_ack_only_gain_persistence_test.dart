// Phase 7-2 regression: channelGain has no readback service and can only
// ever complete as HardwareWriteOpStatus.ackOnly, never `written`. Before
// this fix, deploy_dialog.dart only persisted applied-gain state when
// status == written — meaning a fully successful, ACKed gain deploy (or
// restore) never actually updated the host-side "applied gains" record.
//
// Covers:
//  1. An ack-only channelGain deploy still persists updateDeployAppliedGains
//  2. An ack-only channelGain restore still persists updateDeployAppliedGains
//  3. The result banner distinguishes ack-only ("not DSP-verified") from a
//     fully readback-verified result ("verified") — ACK received is never
//     shown as equivalent to DSP-confirmed.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/deploy/pro_adau1701_hardware_context.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_context_provider.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_executor.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_deploy_package_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/core/transport/adau1701_deployment_preflight.dart';
import 'package:tunai_pro/core/transport/adau1701_deployment_report.dart';
import 'package:tunai_pro/core/transport/adau1701_tuning_transport.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';
import 'package:tunai_pro/features/workbench/widgets/deploy_dialog.dart';

const _kProjectsKey = 'tunai_pro_projects';
final _kAt = DateTime.utc(2026, 8, 1);

// Ack-only report: exactly what the real Adau1701Icp5PeqWritePort produces
// for channelGain — deploymentAllowed, deploymentResult.success, and
// isAckOnly all true, with no capturedOriginalState (no readback exists).
Adau1701DeploymentReport _ackOnlyGain() => Adau1701DeploymentReport(
      attemptedAt: _kAt,
      originalStateAvailable: false,
      preflightStatus: Adau1701PreflightStatus.passed,
      deploymentAllowed: true,
      isAckOnly: true,
      deploymentResult: const Icp5PhaseCResult(
        success: true,
        wasActualWrite: true,
        writeMayHaveReachedDevice: true,
        message: 'Channel gain write ACKed (no readback).',
      ),
    );

class _FakePort implements Icp5PeqWritePort {
  final Adau1701DeploymentReport Function(HardwareWriteOp op) responder;
  _FakePort(this.responder);

  @override
  Future<Adau1701DeploymentReport> preflightAndWrite(
          HardwareWriteOp op) async =>
      responder(op);
}

// Restore never honors overridePort (deploy_dialog.dart always routes it
// through the real activeAdau1701ContextProvider / adau1701Icp5UsbContextProvider
// chain — see the "Restore completed state" tests in
// deploy_dialog_result_label_test.dart for the same pattern). To exercise
// restore's ack-only persistence path, override the provider with a fake but
// *connected* transport instead of injecting a port.
List<int> _fakeStatePayload() {
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

class _FakeConnectedTransport implements Adau1701TuningTransport {
  @override
  bool get isConnected => true;
  @override
  bool get handshakeComplete => true;
  @override
  String? get detectedProfile => 'DSP1701.100.00.01';
  @override
  Future<RawDspStateSnapshot> readRawDspState() async => RawDspStateSnapshot(
        deviceId: 'DSP1701.100.00.01',
        timestamp: DateTime.utc(2026, 8, 1),
        blockId: 0x2202,
        payload: _fakeStatePayload(),
      );
  @override
  Future<Adau1701WriteAck> writePeqGain(int c, double g, {int band = 0}) async =>
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

const _kTweeterL = DriverChannel(
  id: 'ch_tw_l',
  name: 'Tweeter L',
  role: DriverRole.tweeter,
  side: DriverSide.left,
  dspOutputIndex: 1,
);

TuningProjectState _tuningWith(String channelId, double gainDb) {
  final base = TuningProjectState.createDefault();
  final ctrl = base.getOrCreateControl(channelId).copyWith(gainDb: gainDb);
  return base.replaceControl(ctrl);
}

ProProject _project({Map<String, double> appliedGains = const {}}) => ProProject(
      id: 'p_ackonly',
      name: 'Ack-only gain test',
      createdAt: _kAt,
      updatedAt: _kAt,
      dspTarget: 'ADAU1701',
      connection: HardwareConnection.connected,
      acousticState: MeasurementProjectState.createDefault()
          .copyWith(driverChannels: const [_kTweeterL]),
      deployState: appliedGains.isEmpty
          ? DeployProjectState.createDefault()
          : DeployProjectState.createDefault()
              .copyWith(appliedGainsByChannel: appliedGains),
    );

// Seeding SharedPreferences directly (rather than racing the store's own
// async load with a manual addProject call) is the pattern already used by
// other tab-widget tests in this suite (see target_tab_custom_coming_soon_test.dart).
void _seed(ProProject project) {
  SharedPreferences.setMockInitialValues({
    _kProjectsKey: ProProject.encodeList([project]),
  });
}

Widget _harness(Icp5PeqWritePort port, TuningProjectState tuning,
        {Map<String, double> previousAppliedGains = const {},
        List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: Consumer(
          // Force proProjectStoreProvider to be created (and its async
          // SharedPreferences load started) from the very first frame.
          // Nothing else in this harness reads it before the dialog's
          // _execute() does — without this, that first read happens deep
          // inside _execute(), after the write already completed, so the
          // load has not resolved yet and updateDeployAppliedGains's
          // firstWhere throws "No element" on the still-empty store.
          builder: (context, ref, _) {
            ref.watch(proProjectStoreProvider);
            return Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDeployDialog(
                    context: context,
                    projectId: 'p_ackonly',
                    channels: const [_kTweeterL],
                    tuning: tuning,
                    previousAppliedGains: previousAppliedGains,
                    overridePort: port,
                  ),
                  child: const Text('open'),
                ),
              ),
            );
          },
        ),
      ),
    );

void main() {
  testWidgets(
      '1. Ack-only channelGain deploy still persists updateDeployAppliedGains',
      (tester) async {
    _seed(_project());
    final port = _FakePort((_) => _ackOnlyGain());
    final tuning = _tuningWith('ch_tw_l', -10.0);

    await tester.pumpWidget(_harness(port, tuning));
    await tester.pumpAndSettle(); // let the store's own load complete

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('APPROVE & WRITE'));
    await tester.pumpAndSettle();

    // Result banner must not claim DSP verification for an ack-only write.
    expect(find.textContaining('PASS_ACK'), findsOneWidget);
    expect(find.textContaining('not DSP-verified'), findsOneWidget);
    expect(find.text('PASS_ACK (verified)'), findsNothing);

    final element = tester.element(find.byType(MaterialApp));
    final applied = ProviderScope.containerOf(element)
        .read(proProjectStoreProvider)
        .projects
        .firstWhere((p) => p.id == 'p_ackonly')
        .deployState
        .appliedGainsByChannel;
    expect(applied['ch_tw_l'], -10.0,
        reason: 'ack-only (ACK received, no readback) must still count as '
            'applied for host-side rollback tracking — it is the best '
            'evidence available; it is not claimed to be DSP-verified');
  });

  testWidgets(
      '2. Ack-only channelGain restore still persists updateDeployAppliedGains',
      (tester) async {
    _seed(_project(appliedGains: {'ch_tw_l': -10.0}));
    final port = _FakePort((_) => _ackOnlyGain());
    // A pending change to -15.0 so the plan view has a writable op and a
    // deploy can complete (reaching _Phase.result, where RESTORE appears).
    final tuning = _tuningWith('ch_tw_l', -15.0);
    // Restore always goes through the real provider chain (never
    // overridePort), so it needs a fake but connected transport here.
    final fakeCtx =
        Adau1701HardwareContext.fromTransport(_FakeConnectedTransport());

    await tester.pumpWidget(_harness(port, tuning,
        previousAppliedGains: const {'ch_tw_l': -10.0},
        overrides: [adau1701Icp5UsbContextProvider.overrideWithValue(fakeCtx)]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('APPROVE & WRITE'));
    await tester.pumpAndSettle();

    final element = tester.element(find.byType(MaterialApp));
    final container = ProviderScope.containerOf(element);

    // Deploy persisted the new -15.0 dB value.
    var applied = container
        .read(proProjectStoreProvider)
        .projects
        .firstWhere((p) => p.id == 'p_ackonly')
        .deployState
        .appliedGainsByChannel;
    expect(applied['ch_tw_l'], -15.0);

    // Restore writes back the original -10.0 dB (the value captured in
    // widget.previousAppliedGains when the dialog was opened) and must
    // persist it via the same ack-only-aware path.
    // V3-6A: the shared DeployStepLadder also renders a "BACKUP/RESTORE"
    // step label, so a bare textContaining('RESTORE') is now ambiguous —
    // target the actual RESTORE button specifically.
    await tester.tap(find.ancestor(
      of: find.text('RESTORE (GAIN)'),
      matching: find.byWidgetPredicate((w) => w is OutlinedButton),
    ));
    await tester.pumpAndSettle();

    applied = container
        .read(proProjectStoreProvider)
        .projects
        .firstWhere((p) => p.id == 'p_ackonly')
        .deployState
        .appliedGainsByChannel;
    expect(applied['ch_tw_l'], -10.0);
  });
}
