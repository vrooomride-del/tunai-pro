import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_usbi_native_backend.dart';
import 'package:tunai_pro/core/transport/icp5_frame_codec.dart';
import 'package:tunai_pro/core/transport/icp5_serial_driver.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';
import 'package:tunai_pro/features/workbench/tabs/transport_connection_panel.dart';

const _identityRx = <int>[
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
  final List<List<int>> writes = [];
  final List<int>? identity;
  final bool disconnectDuringHandshake;

  _Connection(
      {this.identity = _identityRx, this.disconnectDuringHandshake = false});

  @override
  Stream<List<int>> get bytes => _bytes.stream;

  @override
  Future<int> write(List<int> bytes, Duration timeout) async {
    writes.add(List<int>.of(bytes));
    if (writes.length == 1) {
      if (disconnectDuringHandshake) {
        _bytes.addError(StateError('ICP5 BLE Notify disconnected.'));
      } else if (identity != null) {
        _bytes.add(identity!);
      }
    }
    return bytes.length;
  }

  @override
  Future<void> close() async {
    if (!_bytes.isClosed) await _bytes.close();
  }
}

class _Driver implements Icp5SerialDriver {
  final _Connection connection;
  final String? discoveryError;
  final Completer<void>? discoveryGate;
  int discoverCalls = 0;
  int openCalls = 0;

  _Driver(this.connection, {this.discoveryError, this.discoveryGate});

  static const device = Icp5SerialDevice(
    portName: 'ble-wondom',
    friendlyName: 'WONDOM ICP5',
    productName: 'WONDOM ICP5',
    instanceId: 'ble-wondom',
    enumerationSource: 'fake FFF0',
  );

  @override
  bool get platformSupported => true;

  @override
  Future<Icp5DiscoveryResult> discover() async {
    discoverCalls++;
    await discoveryGate?.future;
    if (discoveryError != null) {
      return Icp5DiscoveryResult(
        source: 'fake FFF0',
        allPorts: const [],
        matches: const [],
        error: discoveryError,
      );
    }
    return const Icp5DiscoveryResult(
      source: 'fake FFF0',
      allPorts: [device],
      matches: [device],
    );
  }

  @override
  Future<Icp5SerialConnection> open(String portName) async {
    openCalls++;
    expect(portName, device.portName);
    return connection;
  }
}

Widget _app(Icp5BluetoothTransport transport) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TransportConnectionPanel(
            backend: const ProUsbiNativeBackendDisabled(),
            deviceOpen: false,
            isMacOS: true,
            icp5BluetoothTransport: transport,
          ),
        ),
      ),
    );

Future<void> _selectBluetooth(WidgetTester tester) async {
  await tester.tap(find.text('ICP5 Bluetooth'));
  await tester.pump();
  expect(
      find.byKey(const Key('icp5_bluetooth_connection_panel')), findsOneWidget);
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

void main() {
  testWidgets('macOS exposes BLE option, scan state, and WONDOM selection',
      (tester) async {
    final gate = Completer<void>();
    final driver = _Driver(_Connection(), discoveryGate: gate);
    final transport = Icp5BluetoothTransport(driver: driver);
    await tester.pumpWidget(_app(transport));
    await _selectBluetooth(tester);

    await _tapKey(tester, 'icp5_bluetooth_scan_button');
    await tester.pump();
    expect(find.text('Scanning'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('WONDOM ICP5'), findsWidgets);
    expect(find.text('Device found'), findsOneWidget);
    expect(find.text('FFF0'), findsOneWidget);
    expect(find.textContaining('FFF2 · Write'), findsOneWidget);
    expect(find.text('FFF1 · Notify'), findsOneWidget);
  });

  testWidgets(
      'connect uses one handshake only and shows PASS_HANDSHAKE profile',
      (tester) async {
    final connection = _Connection();
    final driver = _Driver(connection);
    final transport = Icp5BluetoothTransport(
        driver: driver, readTimeout: const Duration(milliseconds: 50));
    await tester.pumpWidget(_app(transport));
    await _selectBluetooth(tester);
    await _tapKey(tester, 'icp5_bluetooth_scan_button');
    await tester.pumpAndSettle();
    await _tapKey(tester, 'icp5_bluetooth_connect_button');
    await tester.pumpAndSettle();

    expect(find.text('PASS_HANDSHAKE'), findsWidgets);
    expect(find.text(Icp5FrameCodec.expectedProfile), findsOneWidget);
    expect(connection.writes, [Icp5FrameCodec.identificationRequest]);
    expect(driver.openCalls, 1);
    expect(find.textContaining('No diagnostic command is sent automatically'),
        findsOneWidget);
  });

  testWidgets('wrong profile is rejected and never reports PASS_HANDSHAKE',
      (tester) async {
    final wrong = List<int>.of(_identityRx);
    wrong[8] = 0x58;
    wrong[wrong.length - 1] =
        Icp5FrameCodec.checksum(wrong.take(wrong.length - 1));
    final transport = Icp5BluetoothTransport(
        driver: _Driver(_Connection(identity: wrong)),
        readTimeout: const Duration(milliseconds: 5));
    await tester.pumpWidget(_app(transport));
    await _selectBluetooth(tester);
    await _tapKey(tester, 'icp5_bluetooth_scan_button');
    await tester.pumpAndSettle();
    await _tapKey(tester, 'icp5_bluetooth_connect_button');
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();

    expect(find.text('PASS_HANDSHAKE'), findsNothing);
    expect(transport.handshakeComplete, isFalse);
  });

  testWidgets('scan timeout is visible and does not select a fallback',
      (tester) async {
    final transport = Icp5BluetoothTransport(
        driver: _Driver(_Connection(), discoveryError: 'BLE scan timed out.'));
    await tester.pumpWidget(_app(transport));
    await _selectBluetooth(tester);
    await _tapKey(tester, 'icp5_bluetooth_scan_button');
    await tester.pumpAndSettle();

    expect(find.text('Timeout'), findsOneWidget);
    expect(transport.selectedPort, isNull);
  });

  testWidgets(
      'permission, service, notify, timeout, and disconnect states exist',
      (tester) async {
    for (final state in Icp5BluetoothUiState.values) {
      expect(state.label, isNotEmpty);
    }
    expect(Icp5BluetoothUiState.permissionDenied.label, 'Permission denied');
    expect(Icp5BluetoothUiState.serviceDiscoveryFailed.label,
        'Service discovery failed');
    expect(Icp5BluetoothUiState.notifySubscriptionFailed.label,
        'Notify subscription failed');
    expect(Icp5BluetoothUiState.timeout.label, 'Timeout');
    expect(Icp5BluetoothUiState.disconnected.label, 'Disconnected');
  });

  testWidgets('disconnect during handshake fails closed without fallback',
      (tester) async {
    final connection = _Connection(disconnectDuringHandshake: true);
    final transport = Icp5BluetoothTransport(
        driver: _Driver(connection),
        readTimeout: const Duration(milliseconds: 5));
    await tester.pumpWidget(_app(transport));
    await _selectBluetooth(tester);
    await _tapKey(tester, 'icp5_bluetooth_scan_button');
    await tester.pumpAndSettle();
    await _tapKey(tester, 'icp5_bluetooth_connect_button');
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();

    expect(find.text('PASS_HANDSHAKE'), findsNothing);
    expect(connection.writes, [Icp5FrameCodec.identificationRequest]);
  });

  testWidgets('BLE option is hidden outside macOS scope', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TransportConnectionPanel(
            backend: ProUsbiNativeBackendDisabled(),
            deviceOpen: false,
            isMacOS: false,
          ),
        ),
      ),
    ));
    expect(find.text('ICP5 Bluetooth'), findsNothing);
  });
}
