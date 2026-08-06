// ADAU1701 release-closure — HardwareApplyFlow readiness gate.
//
// hardware_apply_flow_test.dart already proves the coarse "connected vs
// disconnected" gate and the stale-package gate. This file covers what the
// release-closure audit specifically asked for and found missing:
//
//   1. The three distinct readiness reasons are surfaced to the user
//      (not connected / handshake in progress / ready) instead of a flat
//      "Hardware disconnected" regardless of cause.
//   2. USB and BLE reach the SAME isReady/blocked outcome through the real
//      Adau1701HardwareContext factories, not just an abstract test fake —
//      proving parity, not just that some fake object behaves.
//   3. Stale context: HardwareApplyFlow (a plain StatefulWidget) resolves
//      contextFactory() once in initState and caches the result. Without a
//      widget key tied to the active transport's identity, a widget that
//      persists across rebuilds (e.g. inside WorkbenchShell's IndexedStack)
//      would keep gating on a stale snapshot forever after the real
//      connection changes underneath it. deploy_tab.dart now watches
//      activeAdau1701ContextProvider and keys HardwareApplyFlow on the
//      resolved transport's identity — this proves that mechanism, at the
//      widget level, independent of DeployTab.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/pro_adau1701_hardware_context.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/pro_export_data.dart';
import 'package:tunai_pro/core/transport/adau1701_tuning_transport.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';
import 'package:tunai_pro/features/workbench/widgets/hardware_apply_flow.dart';

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

/// Independently controls isConnected/handshakeComplete/detectedProfile —
/// hardware_apply_flow_test.dart's fake ties all three to one `connected`
/// flag, which cannot represent "connected but handshake not finished yet".
class _StateControlledTransport implements Adau1701TuningTransport {
  final bool connected;
  final bool handshakeOk;
  final String? profile;
  const _StateControlledTransport({
    this.connected = false,
    this.handshakeOk = false,
    this.profile,
  });

  @override
  bool get isConnected => connected;
  @override
  bool get handshakeComplete => connected && handshakeOk;
  @override
  String? get detectedProfile => (connected && handshakeOk) ? profile : null;

  @override
  Future<RawDspStateSnapshot> readRawDspState() async => RawDspStateSnapshot(
        deviceId: _kDeviceId,
        timestamp: DateTime.utc(2025, 6, 1, 12),
        blockId: 0x2202,
        payload: _statePayload(),
      );
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

DspExportPackage _pkg() => DspExportPackage(id: 'exp1', parameterBlocks: [
      const ExportParameterBlock(
        id: 'blk',
        type: ExportBlockType.peq,
        channelId: 'ch_wf_l',
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
    ]);

Widget _wrap(Widget child, {Key? key}) => MaterialApp(
      key: key,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('readiness reason text (not just pass/fail)', () {
    testWidgets('never connected -> disconnected reason', (tester) async {
      await tester.pumpWidget(_wrap(HardwareApplyFlow(
        exportPackage: _pkg(),
        profile: HardwareDeviceProfiles.adau1701Icp5,
        contextFactory: () => Adau1701HardwareContext.fromTransport(
            const _StateControlledTransport(connected: false)),
      )));

      expect(find.textContaining('Hardware disconnected'), findsOneWidget);
    });

    testWidgets('connected but handshake not yet complete -> distinct reason',
        (tester) async {
      await tester.pumpWidget(_wrap(HardwareApplyFlow(
        exportPackage: _pkg(),
        profile: HardwareDeviceProfiles.adau1701Icp5,
        contextFactory: () => Adau1701HardwareContext.fromTransport(
            const _StateControlledTransport(
                connected: true, handshakeOk: false)),
      )));

      expect(find.textContaining('Handshake in progress'), findsOneWidget,
          reason: 'must not say the same "Hardware disconnected" text for a '
              'device that is physically connected but mid-handshake');
      expect(find.textContaining('Hardware disconnected'), findsNothing);
    });

    testWidgets('ready -> shows transport type and device identity',
        (tester) async {
      await tester.pumpWidget(_wrap(HardwareApplyFlow(
        exportPackage: _pkg(),
        profile: HardwareDeviceProfiles.adau1701Icp5,
        contextFactory: () => Adau1701HardwareContext.fromTransport(
            const _StateControlledTransport(
                connected: true, handshakeOk: true, profile: _kDeviceId)),
      )));

      expect(find.textContaining('Hardware connected'), findsOneWidget);
      expect(find.textContaining(_kDeviceId), findsOneWidget);
    });
  });

  group('USB / BLE parity via the real factories', () {
    testWidgets('Adau1701HardwareContext.icp5Usb() unconnected blocks apply',
        (tester) async {
      await tester.pumpWidget(_wrap(HardwareApplyFlow(
        exportPackage: _pkg(),
        profile: HardwareDeviceProfiles.adau1701Icp5,
        contextFactory: Adau1701HardwareContext.icp5Usb,
      )));

      expect(find.textContaining('Hardware disconnected'), findsOneWidget);
      final applyBtn = find.ancestor(
        of: find.text('APPLY VERIFIED SETTINGS'),
        matching: find.byWidgetPredicate((w) => w is OutlinedButton),
      );
      expect(tester.widget<OutlinedButton>(applyBtn).onPressed, isNull);
    });

    testWidgets(
        'Adau1701HardwareContext.bleIcp5Placeholder() unconnected blocks '
        'apply the same way USB does', (tester) async {
      await tester.pumpWidget(_wrap(HardwareApplyFlow(
        exportPackage: _pkg(),
        profile: HardwareDeviceProfiles.adau1701Icp5,
        contextFactory: Adau1701HardwareContext.bleIcp5Placeholder,
      )));

      expect(find.textContaining('Hardware disconnected'), findsOneWidget);
      final applyBtn = find.ancestor(
        of: find.text('APPLY VERIFIED SETTINGS'),
        matching: find.byWidgetPredicate((w) => w is OutlinedButton),
      );
      expect(tester.widget<OutlinedButton>(applyBtn).onPressed, isNull,
          reason: 'BLE must require a real handshake exactly like USB — no '
              'transport-specific bypass.');
    });
  });

  group('stale context — widget key forces a fresh snapshot', () {
    testWidgets(
        'without a key change, HardwareApplyFlow keeps its first-resolved '
        'context even if contextFactory would now return a ready one',
        (tester) async {
      const readyTransport = _StateControlledTransport(
          connected: true, handshakeOk: true, profile: _kDeviceId);
      var resolveReady = false;

      await tester.pumpWidget(_wrap(HardwareApplyFlow(
        exportPackage: _pkg(),
        profile: HardwareDeviceProfiles.adau1701Icp5,
        // Same widget identity across rebuilds (no key) — mirrors what
        // WorkbenchShell's IndexedStack does to every tab body.
        contextFactory: () => Adau1701HardwareContext.fromTransport(resolveReady
            ? readyTransport
            : const _StateControlledTransport(connected: false)),
      )));
      expect(find.textContaining('Hardware disconnected'), findsOneWidget);

      // The underlying connection is now ready, and a rebuild happens (e.g.
      // DeployTab rebuilding for an unrelated reason) — but without a key,
      // initState never re-runs, so the stale snapshot survives.
      resolveReady = true;
      await tester.pumpWidget(_wrap(HardwareApplyFlow(
        exportPackage: _pkg(),
        profile: HardwareDeviceProfiles.adau1701Icp5,
        contextFactory: () => Adau1701HardwareContext.fromTransport(resolveReady
            ? readyTransport
            : const _StateControlledTransport(connected: false)),
      )));

      expect(find.textContaining('Hardware disconnected'), findsOneWidget,
          reason: 'documents the trap deploy_tab.dart works around with a '
              'ValueKey — a bare rebuild alone does not refresh the '
              'snapshot captured in initState.');
    });

    testWidgets(
        'a key change tied to the active transport identity forces a '
        'remount, picking up the now-ready context', (tester) async {
      const notReadyTransport = _StateControlledTransport(connected: false);
      const readyTransport = _StateControlledTransport(
          connected: true, handshakeOk: true, profile: _kDeviceId);

      await tester.pumpWidget(_wrap(
        HardwareApplyFlow(
          key: const ValueKey('not-ready'),
          exportPackage: _pkg(),
          profile: HardwareDeviceProfiles.adau1701Icp5,
          contextFactory: () =>
              Adau1701HardwareContext.fromTransport(notReadyTransport),
        ),
      ));
      expect(find.textContaining('Hardware disconnected'), findsOneWidget);

      // Simulates deploy_tab.dart's `key: ValueKey(activeContext?.transport
      // ?? 'usb-fallback')` — a different transport identity means a
      // different key, which forces Flutter to unmount/remount rather than
      // reuse the existing State object.
      await tester.pumpWidget(_wrap(
        HardwareApplyFlow(
          key: const ValueKey('ready'),
          exportPackage: _pkg(),
          profile: HardwareDeviceProfiles.adau1701Icp5,
          contextFactory: () =>
              Adau1701HardwareContext.fromTransport(readyTransport),
        ),
      ));

      expect(find.textContaining('Hardware connected'), findsOneWidget,
          reason: 'a keyed remount must pick up the live, ready context — '
              'this is the fix for the trap the previous test documents.');
    });
  });
}
