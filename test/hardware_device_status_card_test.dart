// TUNAI PRO UI/UX v3 Phase V3-5A — Hardware Device Status Card.
//
// Presentation-only: no BLE/USB transport, ICP5 protocol, ACK parser, DSP
// executor, or deploy write-flow logic is exercised or mutated here — only
// the two already-existing booleans (project.connection ==
// HardwareConnection.connected, activeAdau1701ContextProvider != null) that
// the card reads.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/deploy/pro_adau1701_hardware_context.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_context_provider.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/transport/adau1701_tuning_transport.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';
import 'package:tunai_pro/features/workbench/widgets/hardware_device_status_card.dart';

const _kProjectsKey = 'tunai_pro_projects';

/// Always-connected fake transport — mirrors the pattern already used in
/// hardware_connection_status_bar_test.dart.
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

ProProject _project({HardwareConnection connection = HardwareConnection.disconnected}) =>
    ProProject(
      id: 'p1',
      name: 'Device status card test',
      createdAt: DateTime.utc(2026, 8, 5),
      updatedAt: DateTime.utc(2026, 8, 5),
      connection: connection,
    );

void _seed(ProProject project) {
  SharedPreferences.setMockInitialValues({
    _kProjectsKey: ProProject.encodeList([project]),
  });
}

Widget _host() => const ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: HardwareDeviceStatusCard(projectId: 'p1')),
      ),
    );

void main() {
  group('HardwareDeviceStatusCard', () {
    testWidgets('disconnected state renders Disconnected/Not Verified',
        (tester) async {
      _seed(_project());
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.text('DEVICE STATUS'), findsOneWidget);
      expect(find.text('Transport'), findsOneWidget);
      expect(find.text('Disconnected'), findsOneWidget);
      expect(find.text('DSP Identity'), findsOneWidget);
      expect(find.text('Not Verified'), findsOneWidget);
    });

    testWidgets('transport connected (live context present) renders Connected',
        (tester) async {
      _seed(_project());
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
          tester.element(find.byType(HardwareDeviceStatusCard)),
          listen: false);
      container.read(activeAdau1701ContextProvider.notifier).state =
          Adau1701HardwareContext.fromTransport(_FakeConnectedTransport());
      await tester.pumpAndSettle();

      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Disconnected'), findsNothing);
    });

    testWidgets(
        'DSP Identity renders Verified only when both the persisted '
        'handshake flag and the live transport are present', (tester) async {
      // Persisted "connected" but no live context (e.g. after a restart) —
      // must NOT read as Verified, same stale-state guard already proven
      // for project_status_bar.dart's TRANSPORT chip.
      _seed(_project(connection: HardwareConnection.connected));
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.text('Not Verified'), findsOneWidget);
      expect(find.text('Verified'), findsNothing);

      final container = ProviderScope.containerOf(
          tester.element(find.byType(HardwareDeviceStatusCard)),
          listen: false);
      container.read(activeAdau1701ContextProvider.notifier).state =
          Adau1701HardwareContext.fromTransport(_FakeConnectedTransport());
      await tester.pumpAndSettle();

      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('Not Verified'), findsNothing);
    });

    testWidgets('physical output always renders Not Tested', (tester) async {
      _seed(_project(connection: HardwareConnection.connected));
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.text('Physical Output'), findsOneWidget);
      expect(find.text('Not Tested'), findsOneWidget);

      // Even once transport + identity are live, Physical Output must stay
      // "Not Tested" — no automatic verification is introduced by this card.
      final container = ProviderScope.containerOf(
          tester.element(find.byType(HardwareDeviceStatusCard)),
          listen: false);
      container.read(activeAdau1701ContextProvider.notifier).state =
          Adau1701HardwareContext.fromTransport(_FakeConnectedTransport());
      await tester.pumpAndSettle();

      expect(find.text('Not Tested'), findsOneWidget);
    });

    testWidgets(
        'Parameter Readback shows NOT AVAILABLE status', (tester) async {
      _seed(_project());
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.text('Parameter Readback'), findsOneWidget);
      expect(find.text('NOT AVAILABLE'), findsOneWidget);
    });

    testWidgets(
        'rendering the card never mutates project connection or deploy/write '
        'state', (tester) async {
      final project = _project(connection: HardwareConnection.connected);
      _seed(project);
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
          tester.element(find.byType(HardwareDeviceStatusCard)),
          listen: false);

      final before = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'p1');

      // Re-pump a few times (as would happen from provider rebuilds) and
      // confirm nothing about the persisted project changed.
      await tester.pump();
      await tester.pump();

      final after = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'p1');

      expect(after.connection, before.connection);
      expect(after.deployState, before.deployState);
      expect(after.tuningState, before.tuningState);
      expect(tester.takeException(), isNull);
    });
  });
}
