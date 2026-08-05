// TUNAI PRO — Hardware Connection State UX fix.
//
// The top status bar previously showed "DEVICE Connected" whenever
// project.connection (persisted) was HardwareConnection.connected, with no
// check of the live transport (activeAdau1701ContextProvider). Since
// project.connection survives an app restart while the live provider always
// starts null, this let a stale, unverified connection display as
// "Connected" — exactly the bug this fix addresses.
//
// project_status_bar.dart now computes `isLiveConnected = isConnected &&
// hasLiveContext` and renders a "TRANSPORT" status item that says either
// "Transport Connected" (live) or "Disconnected" — never the old ambiguous
// "DEVICE"/"Connected" wording, and never a claim of DSP verification (that
// wording is owned exclusively by deploy_dialog.dart's PASS_ACK result view,
// which this change does not touch).
//
// Tests:
//   - no connection => Disconnected
//   - transport connected (live) => Transport Connected
//   - stale persisted "connected" + no live context (app restart) => Disconnected
//   - the TRANSPORT status item never claims DSP verification itself

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/deploy/pro_adau1701_hardware_context.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_context_provider.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/transport/adau1701_tuning_transport.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';
import 'package:tunai_pro/features/workbench/project_status_bar.dart';

const _kProjectsKey = 'tunai_pro_projects';

/// Always-connected fake transport — stands in for a real, live PASS_HANDSHAKE
/// ICP5 transport without touching any hardware/transport/executor code.
class _FakeConnectedTransport implements Adau1701TuningTransport {
  @override
  bool get isConnected => true;
  @override
  bool get handshakeComplete => true;
  @override
  String? get detectedProfile => 'DSP1701.100.00.01';
  @override
  Future<RawDspStateSnapshot> readRawDspState() async =>
      throw StateError('not used');
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

const _kChannel = DriverChannel(
  id: 'ch_tw_l',
  name: 'Tweeter L',
  role: DriverRole.tweeter,
  side: DriverSide.left,
  dspOutputIndex: 1,
);

ProProject _project({HardwareConnection connection = HardwareConnection.disconnected}) =>
    ProProject(
      id: 'p1',
      name: 'Status bar test',
      createdAt: DateTime.utc(2026, 8, 5),
      updatedAt: DateTime.utc(2026, 8, 5),
      dspTarget: 'ADAU1701',
      connection: connection,
      acousticState: MeasurementProjectState.createDefault()
          .copyWith(driverChannels: const [_kChannel]),
    );

void _seed(ProProject project) {
  SharedPreferences.setMockInitialValues({
    _kProjectsKey: ProProject.encodeList([project]),
  });
}

Widget _host() => const ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: ProjectStatusBar(projectId: 'p1')),
      ),
    );

void main() {
  group('ProjectStatusBar — TRANSPORT status presentation', () {
    testWidgets('no connection => Disconnected', (tester) async {
      _seed(_project());
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.text('TRANSPORT'), findsOneWidget);
      expect(find.text('Disconnected'), findsOneWidget);
      expect(find.text('Transport Connected'), findsNothing);
      expect(find.text('DEVICE'), findsNothing,
          reason: 'the ambiguous DEVICE label must be gone entirely');
    });

    testWidgets(
        'transport connected (live context present) => Transport Connected',
        (tester) async {
      _seed(_project(connection: HardwareConnection.connected));
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
          tester.element(find.byType(ProjectStatusBar)),
          listen: false);
      container.read(activeAdau1701ContextProvider.notifier).state =
          Adau1701HardwareContext.fromTransport(_FakeConnectedTransport());
      await tester.pumpAndSettle();

      expect(find.text('Transport Connected'), findsOneWidget);
      expect(find.text('Disconnected'), findsNothing);
    });

    testWidgets(
        'stale persisted "connected" but no live context (app restart) => '
        'Disconnected, not Transport Connected', (tester) async {
      // Simulates a cold restart: project.connection was persisted as
      // connected in a prior session (see pro_project_store._load, which
      // restores it unconditionally), but activeAdau1701ContextProvider
      // always starts null on a fresh launch and nothing here re-verifies
      // the real transport.
      _seed(_project(connection: HardwareConnection.connected));
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.text('Disconnected'), findsOneWidget,
          reason: 'a stale persisted connection must not display as '
              'connected without a live, re-verified transport');
      expect(find.text('Transport Connected'), findsNothing);
      expect(find.text('Connected'), findsNothing);
    });

    testWidgets(
        'the TRANSPORT status item never claims DSP verification itself '
        '(PASS_ACK does not imply DSP Verified)', (tester) async {
      _seed(_project(connection: HardwareConnection.connected));
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
          tester.element(find.byType(ProjectStatusBar)),
          listen: false);
      container.read(activeAdau1701ContextProvider.notifier).state =
          Adau1701HardwareContext.fromTransport(_FakeConnectedTransport());
      await tester.pumpAndSettle();

      expect(find.text('Transport Connected'), findsOneWidget);

      // Scope the check to the TRANSPORT status item's own Row (its nearest
      // Row ancestor) — the status bar also legitimately shows an unrelated
      // "Verified" PROFILE badge, so this must not be a whole-tree scan.
      final transportRow = find
          .ancestor(of: find.text('TRANSPORT'), matching: find.byType(Row))
          .first;
      final textsInRow = tester.widgetList<Text>(
          find.descendant(of: transportRow, matching: find.byType(Text)));
      expect(
          textsInRow.any(
              (t) => (t.data ?? '').toLowerCase().contains('verified')),
          isFalse,
          reason: 'connection-state wording must stay separate from the '
              'PASS_ACK/DSP-verified claim, which is owned by '
              'deploy_dialog.dart alone');
    });
  });
}
