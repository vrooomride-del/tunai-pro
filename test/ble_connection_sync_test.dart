// Focused test: BLE PASS_HANDSHAKE and disconnect callbacks immediately
// sync both activeAdau1701ContextProvider and project.connection in the
// project store so the status bar Connected badge and the Deploy button
// activate (and deactivate) together without a frame gap.
//
// These tests model the exact two operations performed by
// hardware_tab.dart's _onBlePassHandshake() and _onBleDisconnected():
//
//   _onBlePassHandshake():
//     ref.read(activeAdau1701ContextProvider.notifier).state = bleContext;
//     ref.read(proProjectStoreProvider.notifier)
//         .updateHardwareConnection(projectId, HardwareConnection.connected);
//
//   _onBleDisconnected():
//     ref.read(activeAdau1701ContextProvider.notifier).state = null;
//     ref.read(proProjectStoreProvider.notifier)
//         .updateHardwareConnection(projectId, HardwareConnection.disconnected);
//
// The tests also verify the null-safe guard in updateHardwareConnection —
// a missing projectId must not throw (unawaited call would silently drop
// the exception, leaving project.connection stale while
// activeAdau1701ContextProvider is already updated).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/deploy/pro_adau1701_hardware_context.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_context_provider.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/transport/adau1701_tuning_transport.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';

// ── Minimal fake transport ────────────────────────────────────────────────────

class _FakeTransport implements Adau1701TuningTransport {
  @override bool get isConnected => true;
  @override bool get handshakeComplete => true;
  @override String? get detectedProfile => 'DSP1701.100.00.01';
  @override Future<RawDspStateSnapshot> readRawDspState() async => throw UnimplementedError();
  @override Future<Adau1701WriteAck> writePeqGain(int c, double g, {int band = 0}) async => const Adau1701WriteAck(success: true, message: 'ok');
  @override Future<Adau1701WriteAck> writePeqFrequency(int c, int f, {int band = 0}) async => const Adau1701WriteAck(success: true, message: 'ok');
  @override Future<Adau1701WriteAck> writeFilterFrequency(int c, int f, {int band = 0, bool isHighPass = false}) async => const Adau1701WriteAck(success: true, message: 'ok');
  @override Future<Adau1701WriteAck> writePeqQ(int c, double q, {int band = 0}) async => const Adau1701WriteAck(success: true, message: 'ok');
  @override Future<Adau1701WriteAck> writeOutputGain(int c, double g) async => const Adau1701WriteAck(success: true, message: 'ok');
  @override Future<Adau1701WriteAck> writeMasterMute(bool muted) async => const Adau1701WriteAck(success: true, message: 'ok');
}

// ── Shared fixtures ───────────────────────────────────────────────────────────

const _kProjectId = 'proj_ble_sync';
const _kProjectIdB = 'proj_ble_sync_b';

ProProject _project() {
  final now = DateTime(2026, 7, 31);
  return ProProject(
    id: _kProjectId,
    name: 'BLE Sync Test',
    createdAt: now,
    updatedAt: now,
    connection: HardwareConnection.disconnected,
  );
}

/// Simulates _onBlePassHandshake() from hardware_tab.dart.
Future<void> _onPassHandshake(
  ProviderContainer c,
  Adau1701HardwareContext bleCtx,
) async {
  c.read(activeAdau1701ContextProvider.notifier).state = bleCtx;
  await c
      .read(proProjectStoreProvider.notifier)
      .updateHardwareConnection(_kProjectId, HardwareConnection.connected);
}

/// Simulates _onBleDisconnected() from hardware_tab.dart.
Future<void> _onDisconnected(ProviderContainer c) async {
  c.read(activeAdau1701ContextProvider.notifier).state = null;
  await c
      .read(proProjectStoreProvider.notifier)
      .updateHardwareConnection(_kProjectId, HardwareConnection.disconnected);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer _container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  group('BLE PASS_HANDSHAKE callback sync', () {
    test('PASS → activeAdau1701ContextProvider set and project.connection = connected',
        () async {
      final c = _container();
      c.read(proProjectStoreProvider);
      await pumpEventQueue();
      await c.read(proProjectStoreProvider.notifier).addProject(_project());

      final bleCtx =
          Adau1701HardwareContext.fromTransport(_FakeTransport());

      await _onPassHandshake(c, bleCtx);

      // activeAdau1701ContextProvider must be the BLE context immediately.
      expect(c.read(activeAdau1701ContextProvider), same(bleCtx),
          reason: 'PASS must set activeAdau1701ContextProvider to the BLE context');

      // project.connection must be updated so status bar shows Connected
      // and the Deploy button activates.
      final proj = c
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == _kProjectId);
      expect(proj.connection, HardwareConnection.connected,
          reason: 'project.connection must be connected after PASS so Deploy button activates');
    });

    test('PASS then disconnect → both providers cleared immediately', () async {
      final c = _container();
      c.read(proProjectStoreProvider);
      await pumpEventQueue();
      await c.read(proProjectStoreProvider.notifier).addProject(_project());

      final bleCtx =
          Adau1701HardwareContext.fromTransport(_FakeTransport());

      await _onPassHandshake(c, bleCtx);
      await _onDisconnected(c);

      // Both must be cleared synchronously so the Deploy button deactivates.
      expect(c.read(activeAdau1701ContextProvider), isNull,
          reason: 'disconnect must clear activeAdau1701ContextProvider');

      final proj = c
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == _kProjectId);
      expect(proj.connection, HardwareConnection.disconnected,
          reason: 'project.connection must be disconnected so Deploy button deactivates');
    });

    test('canDeploy equivalent: PASS → connected + has ADAU1701 target', () async {
      final now = DateTime(2026, 7, 31);
      final projWithTarget = ProProject(
        id: _kProjectId,
        name: 'ADAU1701 Project',
        createdAt: now,
        updatedAt: now,
        dspTarget: 'ADAU1701',
        connection: HardwareConnection.disconnected,
      );

      final c = _container();
      c.read(proProjectStoreProvider);
      await pumpEventQueue();
      await c.read(proProjectStoreProvider.notifier).addProject(projWithTarget);

      final bleCtx =
          Adau1701HardwareContext.fromTransport(_FakeTransport());
      await _onPassHandshake(c, bleCtx);

      final proj = c
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == _kProjectId);

      // Mirrors ProjectStatusBar.canDeploy logic (excluding channels check).
      final isConnected = proj.connection == HardwareConnection.connected;
      final hasTarget = proj.dspTarget == 'ADAU1701';
      final activeCtx = c.read(activeAdau1701ContextProvider);

      expect(isConnected, isTrue);
      expect(hasTarget, isTrue);
      expect(activeCtx, isNotNull,
          reason: 'Deploy dialog needs a non-null active context');
    });

    test('unknown projectId → updateHardwareConnection returns silently (no throw)',
        () async {
      final c = _container();
      c.read(proProjectStoreProvider);
      await pumpEventQueue();
      // No project added — simulates race where projectId doesn't match.
      await expectLater(
        c.read(proProjectStoreProvider.notifier)
            .updateHardwareConnection('no_such_project', HardwareConnection.connected),
        completes,
        reason: 'missing projectId must not throw — silent exception in unawaited call '
            'would leave project.connection stale while activeAdau1701ContextProvider is already set',
      );
    });

    // Models the Windows-specific scenario: the global BLE transport
    // (adau1701Icp5BleWindowsContextProvider) is never closed on WorkbenchShell
    // back-press, so it stays connected when the user opens Project B after
    // having connected via Project A. _onBlePassHandshake never fires again
    // (no new BLE connection event) — but initState detects the already-
    // connected transport and fires _onBlePassHandshake immediately via
    // addPostFrameCallback. This test verifies that calling _onBlePassHandshake
    // with the NEW project's id (proj_b) correctly updates project B without
    // touching project A.
    test('Windows: already-connected transport on new project mount → '
        'new project.connection = connected, old project unchanged', () async {
      final now = DateTime(2026, 7, 31);
      final projA = ProProject(
        id: _kProjectId,
        name: 'Project A',
        createdAt: now,
        updatedAt: now,
        connection: HardwareConnection.connected, // was connected in prior session
      );
      final projB = ProProject(
        id: _kProjectIdB,
        name: 'Project B',
        createdAt: now,
        updatedAt: now,
        connection: HardwareConnection.disconnected,
      );

      final c = _container();
      c.read(proProjectStoreProvider);
      await pumpEventQueue();
      await c.read(proProjectStoreProvider.notifier).addProject(projA);
      await c.read(proProjectStoreProvider.notifier).addProject(projB);

      // Simulate what HardwareTab.initState addPostFrameCallback does for
      // Project B when the Windows BLE transport is already connected:
      // call _onBlePassHandshake with Project B's id.
      final bleCtx = Adau1701HardwareContext.fromTransport(_FakeTransport());
      c.read(activeAdau1701ContextProvider.notifier).state = bleCtx;
      await c
          .read(proProjectStoreProvider.notifier)
          .updateHardwareConnection(_kProjectIdB, HardwareConnection.connected);

      final storeProjects = c.read(proProjectStoreProvider).projects;
      final a = storeProjects.firstWhere((p) => p.id == _kProjectId);
      final b = storeProjects.firstWhere((p) => p.id == _kProjectIdB);

      expect(b.connection, HardwareConnection.connected,
          reason: 'Project B must be connected after initState BLE sync');
      expect(a.connection, HardwareConnection.connected,
          reason: 'Project A connection must be unchanged (not reset by Project B mount)');
      expect(c.read(activeAdau1701ContextProvider), same(bleCtx),
          reason: 'activeAdau1701ContextProvider must hold the BLE context');
    });

    test('Windows: already-connected transport on new project mount then '
        'disconnect → both providers cleared for the new project', () async {
      final now = DateTime(2026, 7, 31);
      final projB = ProProject(
        id: _kProjectIdB,
        name: 'Project B',
        createdAt: now,
        updatedAt: now,
        connection: HardwareConnection.disconnected,
      );

      final c = _container();
      c.read(proProjectStoreProvider);
      await pumpEventQueue();
      await c.read(proProjectStoreProvider.notifier).addProject(projB);

      // Simulate addPostFrameCallback PASS sync for Project B.
      final bleCtx = Adau1701HardwareContext.fromTransport(_FakeTransport());
      c.read(activeAdau1701ContextProvider.notifier).state = bleCtx;
      await c
          .read(proProjectStoreProvider.notifier)
          .updateHardwareConnection(_kProjectIdB, HardwareConnection.connected);

      // Now disconnect (user presses Disconnect in the panel).
      // Use inline form because _onDisconnected helper is hardcoded to _kProjectId.
      c.read(activeAdau1701ContextProvider.notifier).state = null;
      await c
          .read(proProjectStoreProvider.notifier)
          .updateHardwareConnection(_kProjectIdB, HardwareConnection.disconnected);

      final b = c
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == _kProjectIdB);

      expect(b.connection, HardwareConnection.disconnected,
          reason: 'Project B must be disconnected after explicit disconnect');
      expect(c.read(activeAdau1701ContextProvider), isNull,
          reason: 'activeAdau1701ContextProvider must be cleared on disconnect');
    });
  });
}
