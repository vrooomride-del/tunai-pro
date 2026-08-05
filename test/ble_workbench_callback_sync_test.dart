import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_context_provider.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/pro_usbi_native_backend.dart';
import 'package:tunai_pro/core/transport/icp5_bluetooth_driver.dart';
import 'package:tunai_pro/core/transport/icp5_frame_codec.dart';
import 'package:tunai_pro/core/transport/icp5_serial_driver.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';
import 'package:tunai_pro/features/workbench/tabs/hardware_tab.dart';
import 'package:tunai_pro/features/workbench/tabs/transport_connection_panel.dart';

const _projectId = 'open-workbench-project';
const _identityResponse = <int>[
  0x55,
  0x18,
  0xE0,
  0,
  0,
  0,
  0,
  0,
  0x44,
  0x53,
  0x50,
  0x31,
  0x37,
  0x30,
  0x31,
  0x2E,
  0x31,
  0x30,
  0x30,
  0x2E,
  0x30,
  0x30,
  0x2E,
  0x30,
  0x31,
  0xD9,
];

class _Connection implements Icp5SerialConnection {
  final _bytes = StreamController<List<int>>.broadcast(sync: true);

  @override
  Stream<List<int>> get bytes => _bytes.stream;

  @override
  Future<int> write(List<int> bytes, Duration timeout) async {
    _bytes.add(_identityResponse);
    return bytes.length;
  }

  @override
  // Must return a synchronously-completed Future; `async {}` requires a
  // microtask to complete its Future and fakeAsync never flushes that
  // microtask without an explicit pump(), causing a permanent hang.
  Future<void> close() => Future.value();
}

class _BleDriver
    implements Icp5SerialDriver, Icp5BluetoothConnectionDiagnostics {
  final _connection = _Connection();

  @override
  bool get platformSupported => true;
  @override
  String? selectedUiIdentifier;
  @override
  String? connectingIdentifier;
  @override
  String? platformName;
  @override
  String? advertisedName;
  @override
  int? lastKnownRssi;
  @override
  List<String> discoveredServiceUuids = const [];
  @override
  String? failureStage;

  @override
  Future<Icp5DiscoveryResult> discover() async => const Icp5DiscoveryResult(
        source: 'focused BLE callback test',
        allPorts: [
          Icp5SerialDevice(
            portName: 'ble-test',
            friendlyName: 'WONDOM ICP5',
            instanceId: 'ble-test',
          ),
        ],
        matches: [
          Icp5SerialDevice(
            portName: 'ble-test',
            friendlyName: 'WONDOM ICP5',
            instanceId: 'ble-test',
          ),
        ],
      );

  @override
  Future<Icp5SerialConnection> open(String portName) async {
    selectedUiIdentifier = portName;
    connectingIdentifier = portName;
    platformName = 'WONDOM ICP5';
    advertisedName = 'WONDOM ICP5';
    discoveredServiceUuids = const ['0000fff0-0000-1000-8000-00805f9b34fb'];
    return _connection;
  }
}

ProProject _project() => ProProject(
      id: _projectId,
      name: 'Open Workbench',
      createdAt: DateTime(2026, 8, 1),
      updatedAt: DateTime(2026, 8, 1),
      dspTarget: 'ADAU1701',
      connection: HardwareConnection.disconnected,
      acousticState: MeasurementProjectState.createDefault(),
    );

void main() {
  testWidgets(
      'actual BLE callbacks sync the open Workbench project and Deploy state',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(proProjectStoreProvider);
    await tester.pump();
    await container
        .read(proProjectStoreProvider.notifier)
        .addProject(_project());

    final transport = Icp5BluetoothTransport(
      driver: _BleDriver(),
      readTimeout: const Duration(milliseconds: 100),
    );
    Widget callbackPanel() => MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: UncontrolledProviderScope(
                container: container,
                child: HardwareTab(
                  projectId: _projectId,
                  usbiBackend: const ProUsbiNativeBackendDisabled(),
                  isWindowsPlatform: () => false,
                  icp5BluetoothTransport: transport,
                ),
              ),
            ),
          ),
        );
    await tester.pumpWidget(callbackPanel());
    await tester.tap(find.text('ICP5 Bluetooth'));
    await tester.pump();
    final scan = find.byKey(const Key('icp5_bluetooth_scan_button'));
    await tester.ensureVisible(scan);
    await tester.tap(scan);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final connect = find.byKey(const Key('icp5_bluetooth_connect_button'));
    await tester.ensureVisible(connect);
    await tester.tap(connect);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      container.read(proProjectStoreProvider).currentProject!.connection,
      HardwareConnection.connected,
    );
    expect(container.read(activeAdau1701ContextProvider), isNotNull);
    final connectedProject =
        container.read(proProjectStoreProvider).currentProject!;
    expect(
      connectedProject.dspTarget == 'ADAU1701' &&
          connectedProject.connection == HardwareConnection.connected &&
          connectedProject.acousticState.driverChannels.isNotEmpty,
      isTrue,
      reason: 'ProjectStatusBar Deploy condition must activate immediately',
    );

    tester
        .widget<TransportConnectionPanel>(
          find.byType(TransportConnectionPanel),
        )
        .onBleDisconnected!
        .call(_projectId);
    await tester.pump();

    expect(
      container.read(proProjectStoreProvider).currentProject!.connection,
      HardwareConnection.disconnected,
    );
    expect(container.read(activeAdau1701ContextProvider), isNull);
    final disconnectedProject =
        container.read(proProjectStoreProvider).currentProject!;
    expect(
      disconnectedProject.dspTarget == 'ADAU1701' &&
          disconnectedProject.connection == HardwareConnection.connected &&
          disconnectedProject.acousticState.driverChannels.isNotEmpty,
      isFalse,
      reason: 'ProjectStatusBar Deploy condition must deactivate immediately',
    );
    final panel = tester.widget<TransportConnectionPanel>(
      find.byType(TransportConnectionPanel),
    );
    expect(
      () => panel.onBlePassHandshake!.call('stale-project'),
      throwsStateError,
    );
    expect(
      container.read(proProjectStoreProvider).currentProject!.connection,
      HardwareConnection.disconnected,
    );
    expect(container.read(activeAdau1701ContextProvider), isNull);

    // Cancel the heartbeat timer synchronously before widget tree disposal.
    // Awaiting transport.close() hangs inside testWidgets' fakeAsync zone when
    // the microtask queue is not in a clean state at this point in the test;
    // calling stopHeartbeatForTest() is sufficient because HardwareTab sets
    // _ownsBleTransport=false for injected transports and never calls close().
    transport.stopHeartbeatForTest();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
