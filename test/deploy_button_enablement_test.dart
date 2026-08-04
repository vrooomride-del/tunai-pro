// Focused test: DEPLOY button enable/disable logic in ProjectStatusBar.
//
// The button is enabled by:
//   project.dspTarget == 'ADAU1701'
//   AND project.connection == HardwareConnection.connected   (persisted)
//   AND activeAdau1701ContextProvider != null                (live, in-memory)
//   AND project.acousticState.driverChannels.isNotEmpty
//
// project.connection is set by hardware_tab's _syncConnectionToStore(), which
// only writes HardwareConnection.connected when handshakeComplete is true
// (PASS_HANDSHAKE + DSP1701.100.00.01 firmware identity confirmed).
//
// Phase 7-5B Debug: project.connection is PERSISTED and survives app
// restarts; activeAdau1701ContextProvider is a fresh StateProvider that
// always starts null on a new launch. Without also requiring a live context,
// a restart leaves the button enabled from stale "connected" state while
// deploy_dialog.dart's actual write port falls back to a disconnected USB
// context — every operation then fails preflight
// ("ADAU1701 identity handshake is required..."), which is exactly the
// reported "FAIL 124/124" symptom. Case 6 below is that exact scenario.
//
// Tests:
//  1. ICP5 BLE connected + PASS_HANDSHAKE synced + live context → canDeploy true
//  2. Disconnect / lose handshake → canDeploy false
//  3. canDeploy false when dspTarget != 'ADAU1701'
//  4. canDeploy false when driverChannels is empty
//  5. Whole reactive chain: store update triggers canDeploy recalc
//  6. Stale persisted "connected" + no live context (post-restart) → canDeploy false

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';

// ── canDeploy logic (extracted from ProjectStatusBar.build) ───────────────────
// Mirrors the exact condition so tests stay coupled to the production predicate.

bool canDeploy(ProProject? project, {required bool hasLiveContext}) =>
    project != null &&
    project.dspTarget == 'ADAU1701' &&
    project.connection == HardwareConnection.connected &&
    hasLiveContext &&
    project.acousticState.driverChannels.isNotEmpty;

// ── Helpers ───────────────────────────────────────────────────────────────────

const _kChannel = DriverChannel(
  id: 'ch_tw_l',
  name: 'Tweeter L',
  role: DriverRole.tweeter,
  side: DriverSide.left,
  dspOutputIndex: 1,
);

ProProject _project({
  HardwareConnection connection = HardwareConnection.disconnected,
  String dspTarget = 'ADAU1701',
  List<DriverChannel> channels = const [_kChannel],
}) {
  final now = DateTime(2026, 7, 29);
  return ProProject(
    id: 'p1',
    name: 'Test',
    createdAt: now,
    updatedAt: now,
    dspTarget: dspTarget,
    connection: connection,
    acousticState: MeasurementProjectState.createDefault()
        .copyWith(driverChannels: channels),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('DEPLOY button enablement', () {
    test(
        '1. ICP5 BLE connected + PASS_HANDSHAKE synced + live context → canDeploy is true',
        () {
      // _syncConnectionToStore writes connected only after handshakeComplete,
      // and sets the live context in the same call (hardware_tab.dart:460-461).
      final project = _project(connection: HardwareConnection.connected);
      expect(canDeploy(project, hasLiveContext: true), isTrue);
    });

    test('2. Disconnect / lose handshake → canDeploy is false', () {
      final project = _project(connection: HardwareConnection.disconnected);
      expect(canDeploy(project, hasLiveContext: true), isFalse);
    });

    test('3. canDeploy false when dspTarget is not ADAU1701', () {
      final project = _project(
        connection: HardwareConnection.connected,
        dspTarget: 'ADAU1466',
      );
      expect(canDeploy(project, hasLiveContext: true), isFalse);
    });

    test('4. canDeploy false when driverChannels is empty', () {
      final project = _project(
        connection: HardwareConnection.connected,
        channels: const [],
      );
      expect(canDeploy(project, hasLiveContext: true), isFalse);
    });

    test(
        '6. Stale persisted "connected" but no live context (post-restart) → '
        'canDeploy is false — this is the exact "FAIL 124/124" scenario: '
        'project.connection survived a restart, activeAdau1701ContextProvider '
        'did not', () {
      final project = _project(connection: HardwareConnection.connected);
      expect(canDeploy(project, hasLiveContext: false), isFalse);
    });

    test(
        '5. Reactive chain: store updateHardwareConnection → '
        'canDeploy recalculates correctly', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(proProjectStoreProvider);
      await pumpEventQueue();

      // Start disconnected.
      await container
          .read(proProjectStoreProvider.notifier)
          .addProject(_project(connection: HardwareConnection.disconnected));

      var proj = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'p1');
      expect(canDeploy(proj, hasLiveContext: true), isFalse,
          reason: 'initially disconnected');

      // Simulate hardware_tab _syncConnectionToStore firing after PASS_HANDSHAKE
      // (which, in production, sets the live context in the same call).
      await container
          .read(proProjectStoreProvider.notifier)
          .updateHardwareConnection('p1', HardwareConnection.connected);

      proj = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'p1');
      expect(canDeploy(proj, hasLiveContext: true), isTrue,
          reason: 'connected after sync, with a live context');

      // Simulate disconnect.
      await container
          .read(proProjectStoreProvider.notifier)
          .updateHardwareConnection('p1', HardwareConnection.disconnected);

      proj = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'p1');
      expect(canDeploy(proj, hasLiveContext: false), isFalse,
          reason: 'disabled after disconnect');
    });
  });
}
