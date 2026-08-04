// Phase 7-5B Debug — ADAU1701 Deploy Dialog Active Context Fix.
//
// Reported symptom: "DSP Write — ADAU1701" dialog showed FAIL 124/124, e.g.
// channel=ch_tw_l kind=peqFrequency, message="ADAU1701 identity handshake
// is required before deployment preflight."
//
// Root cause found: NOT a bypass inside deploy_dialog.dart (its _execute()
// already correctly prefers activeAdau1701ContextProvider, falling back to
// adau1701Icp5UsbContextProvider only when null — unchanged, not touched
// here). The actual gap was one level up, in project_status_bar.dart:
// project.connection is PERSISTED (survives app restarts) while
// activeAdau1701ContextProvider is a fresh in-memory StateProvider that
// always starts null on a new launch. The DEPLOY button's canDeploy only
// checked the persisted flag, so after a restart (or hot-restart) it stayed
// enabled from stale "connected" state while the live context was actually
// null — every op then hit the disconnected USB fallback and failed
// preflight. Fixed by also requiring a live activeAdau1701ContextProvider in
// canDeploy (see deploy_button_enablement_test.dart for that regression).
//
// This file separately proves deploy_dialog.dart's OWN context-selection
// path (the thing that actually executes the writes) behaves correctly for
// PEQ/XO ops specifically, not just gain:
//   Case A: activeAdau1701ContextProvider has a connected, handshaken fake
//           context -> the PEQ/XO plan passes preflight (ACK, not blocked).
//   Case B: no active context -> falls back to the disconnected USB
//           context -> the existing "identity handshake required" failure
//           is preserved (fail-closed, not silently bypassed).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/pro_adau1701_hardware_context.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_context_provider.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/core/transport/adau1701_tuning_transport.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';
import 'package:tunai_pro/features/workbench/widgets/deploy_dialog.dart';

const _kTweeterL = DriverChannel(
  id: 'ch_tw_l',
  name: 'Tweeter L',
  role: DriverRole.tweeter,
  side: DriverSide.left,
  dspOutputIndex: 1,
);

// A tuning with one enabled PEQ Band 1 (band 0) change on ch_tw_l — this is
// the readback-verified, full-preflight path (Adau1701DeploymentPreflight),
// the same one the reported failure came from ("kind=peqFrequency").
TuningProjectState _tuningWithPeqBand0() {
  final base = PeqChannelState.fixed('ch_tw_l');
  final bands = List<PeqBand>.from(base.bands);
  // 1800 Hz / -1.0 dB matches _fakeStatePayload()'s decoded readback exactly,
  // so the band-0 readback-verified path reports success, not a value
  // mismatch — this test is about context/handshake, not PEQ math.
  bands[0] = bands[0].copyWith(enabled: true, frequencyHz: 1800.0, gainDb: -1.0, q: 1.0);
  return TuningProjectState(peqChannels: [base.copyWith(bands: bands)]);
}

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
  Future<Adau1701WriteAck> writePeqFrequency(int c, int f, {int band = 0}) async =>
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

void main() {
  testWidgets(
      'Case A: connected+handshaken activeAdau1701ContextProvider -> PEQ '
      'plan passes preflight (PASS_ACK, no handshake failure)', (tester) async {
    final fakeCtx =
        Adau1701HardwareContext.fromTransport(_FakeConnectedTransport());

    await tester.pumpWidget(ProviderScope(
      overrides: [
        activeAdau1701ContextProvider.overrideWith((ref) => fakeCtx),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDeployDialog(
                context: context,
                projectId: 'p1',
                channels: const [_kTweeterL],
                tuning: _tuningWithPeqBand0(),
                previousAppliedGains: const {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('APPROVE & WRITE'));
    await tester.pumpAndSettle();

    expect(find.textContaining('identity handshake is required'), findsNothing);
    expect(find.textContaining('PASS_ACK'), findsOneWidget);
  });

  testWidgets(
      'Case B: no active context -> falls back to disconnected USB context -> '
      'existing "identity handshake required" failure is preserved',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDeployDialog(
                context: context,
                projectId: 'p1',
                channels: const [_kTweeterL],
                tuning: _tuningWithPeqBand0(),
                previousAppliedGains: const {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('APPROVE & WRITE'));
    await tester.pumpAndSettle();

    expect(find.textContaining('identity handshake is required'), findsWidgets);
  });
}
