// Phase 7-3 regression: DeployTab's "HARDWARE APPLY" flow (used for PEQ/full
// package apply, via HardwareApplyFlow) was hardcoded to
// adau1701Icp5UsbContextProvider — a standalone, always-disconnected USB
// context — never activeAdau1701ContextProvider (the BLE context Gain
// deploy already prefers via deploy_dialog.dart). So a BLE-connected device
// that successfully deployed Gain would still fail PEQ apply here with
// "ADAU1701 identity handshake is required before deployment preflight.",
// because this flow was reading from a completely different, disconnected
// context object.
//
// Covers:
//  1. With activeAdau1701ContextProvider set to a connected BLE-style
//     context, APPLY VERIFIED SETTINGS becomes enabled after approval (no
//     "Hardware not ready" note) — proving the active context is now used.
//  2. With no active context set (falls back to the disconnected USB
//     context, unchanged pre-existing behavior), the readiness note still
//     appears — proving the fallback itself was not altered.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/deploy/pro_adau1701_hardware_context.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_context_provider.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_export_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/transport/adau1701_tuning_transport.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';
import 'package:tunai_pro/features/workbench/tabs/deploy_tab.dart';

const _kProjectsKey = 'tunai_pro_projects';

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

const _kTweeterL = DriverChannel(
  id: 'ch_tw_l',
  name: 'Tweeter L',
  role: DriverRole.tweeter,
  side: DriverSide.left,
  dspOutputIndex: 1,
);

ProProject _project() {
  final now = DateTime.utc(2026, 8, 1);
  final pkg = DspExportPackage(
    id: 'pkg_peq',
    targetPlatform: DspTargetPlatform.adau1701,
    status: ExportStatus.draftReady,
    projectName: 'PEQ apply context test',
    parameterBlocks: [
      ExportParameterBlock(
        id: 'peq_ch_tw_l',
        type: ExportBlockType.peq,
        channelId: 'ch_tw_l',
        title: 'Tweeter L PEQ',
        summary: 'Band 1',
        parameters: {
          'bands': {
            'band_0': {'freq_hz': 1000.0, 'gain_db': -3.0, 'q': 1.0},
          },
        },
      ),
    ],
  );
  return ProProject(
    id: 'p_peq',
    name: 'PEQ apply context test',
    createdAt: now,
    updatedAt: now,
    dspTarget: 'ADAU1701',
    connection: HardwareConnection.connected,
    acousticState: MeasurementProjectState.createDefault()
        .copyWith(driverChannels: const [_kTweeterL]),
    exportState: ExportProjectState(
      selectedTarget: DspTargetPlatform.adau1701,
      packages: [pkg],
      activePackageId: pkg.id,
    ),
  );
}

void _seed(ProProject project) {
  SharedPreferences.setMockInitialValues({
    _kProjectsKey: ProProject.encodeList([project]),
  });
}

void main() {
  testWidgets(
      '1. BLE active context connected → APPLY VERIFIED SETTINGS enabled, no "not ready" note',
      (tester) async {
    _seed(_project());
    final fakeCtx =
        Adau1701HardwareContext.fromTransport(_FakeConnectedTransport());

    await tester.pumpWidget(ProviderScope(
      overrides: [
        activeAdau1701ContextProvider.overrideWith((ref) => fakeCtx),
      ],
      child: const MaterialApp(
        home: Scaffold(body: DeployTab(projectId: 'p_peq')),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('APPROVE VERIFIED WRITE'));
    await tester.tap(find.text('APPROVE VERIFIED WRITE'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Hardware not ready'), findsNothing);
    final applyButton = tester.widget<OutlinedButton>(find.ancestor(
      of: find.text('APPLY VERIFIED SETTINGS'),
      matching: find.byWidgetPredicate((w) => w is OutlinedButton),
    ));
    expect(applyButton.onPressed, isNotNull,
        reason: 'apply must be enabled once the active (BLE) context is '
            'connected — this is the exact case that previously failed '
            'with "ADAU1701 identity handshake is required" because the '
            'flow was hardcoded to a separate, disconnected USB context');
  });

  testWidgets(
      '2. No active context set → falls back to disconnected USB context, '
      '"Hardware not ready" note shown (unchanged fallback behavior)',
      (tester) async {
    _seed(_project());

    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: DeployTab(projectId: 'p_peq')),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('APPROVE VERIFIED WRITE'));
    await tester.tap(find.text('APPROVE VERIFIED WRITE'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Hardware not ready'), findsOneWidget);
    final applyButton = tester.widget<OutlinedButton>(find.ancestor(
      of: find.text('APPLY VERIFIED SETTINGS'),
      matching: find.byWidgetPredicate((w) => w is OutlinedButton),
    ));
    expect(applyButton.onPressed, isNull);
  });
}
