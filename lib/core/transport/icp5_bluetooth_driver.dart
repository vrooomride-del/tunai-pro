import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'icp5_serial_driver.dart';

abstract interface class Icp5BluetoothConnectionDiagnostics {
  String? get selectedUiIdentifier;
  String? get connectingIdentifier;
  String? get platformName;
  String? get advertisedName;
  int? get lastKnownRssi;
  List<String> get discoveredServiceUuids;
  String? get failureStage;
}

/// Capture-proven ICP5 BLE GATT byte channel.
///
/// This adapter knows only how to move bytes through FFF2/FFF1. ICP5 framing,
/// handshake, ACK parsing, diagnostics, rollback, and STOP remain owned by the
/// shared ICP5 session transport.
class Icp5BluetoothGattDriver
    implements Icp5SerialDriver, Icp5BluetoothConnectionDiagnostics {
  static const serviceUuid = 'fff0';
  static const txCharacteristicUuid = 'fff2';
  static const rxCharacteristicUuid = 'fff1';
  static const discoverySource =
      'BLE connectable-device scan; FFF0 verified after connect';
  final Duration scanTimeout;

  Icp5BluetoothGattDriver({this.scanTimeout = const Duration(seconds: 10)});

  final Map<String, BluetoothDevice> _discoveredDevices = {};
  final Map<String, Icp5SerialDevice> _discoveredMetadata = {};
  String? _selectedUiIdentifier;
  String? _connectingIdentifier;
  String? _platformName;
  String? _advertisedName;
  int? _lastKnownRssi;
  List<String> _discoveredServiceUuids = const [];
  String? _failureStage;

  @override
  String? get selectedUiIdentifier => _selectedUiIdentifier;
  @override
  String? get connectingIdentifier => _connectingIdentifier;
  @override
  String? get platformName => _platformName;
  @override
  String? get advertisedName => _advertisedName;
  @override
  int? get lastKnownRssi => _lastKnownRssi;
  @override
  List<String> get discoveredServiceUuids => _discoveredServiceUuids;
  @override
  String? get failureStage => _failureStage;

  @override
  bool get platformSupported =>
      !kIsWeb &&
      (Platform.isMacOS ||
          Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isLinux);

  @override
  Future<Icp5DiscoveryResult> discover() async {
    const source = discoverySource;
    _discoveredDevices.clear();
    _discoveredMetadata.clear();
    if (!platformSupported) {
      return const Icp5DiscoveryResult(
          source: source,
          allPorts: [],
          matches: [],
          error: 'ICP5 BLE GATT is unavailable on this platform.');
    }
    try {
      if (await FlutterBluePlus.adapterState.first !=
          BluetoothAdapterState.on) {
        return const Icp5DiscoveryResult(
            source: source,
            allPorts: [],
            matches: [],
            error: 'Bluetooth adapter is not on.');
      }
      await FlutterBluePlus.startScan(timeout: scanTimeout);
      await FlutterBluePlus.isScanning
          .where((scanning) => !scanning)
          .first
          .timeout(scanTimeout + const Duration(seconds: 1));
      final results = await FlutterBluePlus.scanResults.first;
      final matches = results
          .where((result) => result.advertisementData.connectable)
          .map((result) {
        final id = result.device.remoteId.str;
        _discoveredDevices[id] = result.device;
        final name = result.device.advName.trim();
        final metadata = Icp5SerialDevice(
            portName: id,
            productName: name.isEmpty ? null : name,
            friendlyName: name.isEmpty ? 'Unnamed BLE device' : name,
            instanceId: id,
            rssi: result.rssi,
            enumerationSource: source);
        _discoveredMetadata[id] = metadata;
        return metadata;
      }).toList(growable: true)
        ..sort(_compareCandidates);
      return Icp5DiscoveryResult(
          source: source, allPorts: matches, matches: matches);
    } on TimeoutException {
      return const Icp5DiscoveryResult(
          source: source,
          allPorts: [],
          matches: [],
          error: 'BLE scan timed out before connectable devices were listed.');
    } catch (error) {
      return Icp5DiscoveryResult(
          source: source,
          allPorts: const [],
          matches: const [],
          error: 'ICP5 BLE discovery failed: $error');
    } finally {
      await FlutterBluePlus.stopScan();
    }
  }

  static int _compareCandidates(Icp5SerialDevice left, Icp5SerialDevice right) {
    final leftPreferred = _isWondomIcp5(left.friendlyName);
    final rightPreferred = _isWondomIcp5(right.friendlyName);
    if (leftPreferred != rightPreferred) return leftPreferred ? -1 : 1;
    return (right.rssi ?? -999).compareTo(left.rssi ?? -999);
  }

  static bool _isWondomIcp5(String? name) =>
      (name ?? '').trim().toUpperCase() == 'WONDOM ICP5';

  @override
  Future<Icp5SerialConnection> open(String portName) async {
    _selectedUiIdentifier = portName;
    _connectingIdentifier = null;
    _platformName = null;
    _advertisedName = null;
    _lastKnownRssi = null;
    _discoveredServiceUuids = const [];
    _failureStage = 'selected device lookup';
    final device = _discoveredDevices[portName];
    if (device == null) {
      throw StateError(
          'Selected ICP5 BLE identifier is no longer available: $portName.');
    }
    final connectingId = device.remoteId.str;
    final metadata = _discoveredMetadata[portName];
    _connectingIdentifier = connectingId;
    _platformName = device.platformName;
    _advertisedName = device.advName;
    _lastKnownRssi = metadata?.rssi;
    debugPrint('[ICP5 BLE Connect] selectedUiIdentifier=$portName '
        'connectingIdentifier=$connectingId platformName=${device.platformName} '
        'advertisedName=${device.advName} rssi=${metadata?.rssi ?? 'unknown'}');
    if (!identifiersMatch(portName, connectingId)) {
      _failureStage = 'identifier validation';
      throw StateError('BLE identifier mismatch before connect: selected '
          '$portName, connecting $connectingId. Connection aborted.');
    }
    _failureStage = 'connect';
    await device.connect(timeout: const Duration(seconds: 10));
    _failureStage = 'service discovery';
    final services = await device.discoverServices();
    _discoveredServiceUuids = List.unmodifiable(
        services.map((service) => service.uuid.str128.toLowerCase()));
    debugPrint('[ICP5 BLE Services] ${_discoveredServiceUuids.join(', ')}');
    final service = services
        .where((candidate) => isExpectedUuid(candidate.uuid, serviceUuid))
        .firstOrNull;
    if (service == null) {
      await device.disconnect();
      throw StateError('Service discovery failed: FFF0 was not found.');
    }
    BluetoothCharacteristic? tx;
    BluetoothCharacteristic? rx;
    for (final characteristic in service.characteristics) {
      if (isExpectedUuid(characteristic.uuid, txCharacteristicUuid)) {
        tx = characteristic;
      }
      if (isExpectedUuid(characteristic.uuid, rxCharacteristicUuid)) {
        rx = characteristic;
      }
    }
    if (tx == null ||
        !(tx.properties.write || tx.properties.writeWithoutResponse)) {
      await device.disconnect();
      throw StateError(
          'Service discovery failed: writable FFF2 was not found.');
    }
    if (rx == null || !rx.properties.notify) {
      await device.disconnect();
      throw StateError(
          'Notify subscription failed: notifiable FFF1 was not found.');
    }
    try {
      _failureStage = 'notify subscription';
      await rx.setNotifyValue(true);
    } catch (error) {
      await device.disconnect();
      throw StateError('Notify subscription failed for FFF1: $error');
    }
    _failureStage = null;
    return _Icp5BluetoothGattConnection(device: device, tx: tx, rx: rx);
  }

  @visibleForTesting
  static bool isExpectedUuid(Guid uuid, String shortUuid) {
    final normalizedShort = shortUuid.toLowerCase();
    final normalizedFull = '0000$normalizedShort-0000-1000-8000-00805f9b34fb';
    final shortest = uuid.str.toLowerCase();
    final full = uuid.str128.toLowerCase();
    return shortest == normalizedShort || full == normalizedFull;
  }

  @visibleForTesting
  static bool identifiersMatch(String selected, String connecting) =>
      selected == connecting;
}

class _Icp5BluetoothGattConnection implements Icp5SerialConnection {
  final BluetoothDevice device;
  final BluetoothCharacteristic tx;
  final BluetoothCharacteristic rx;
  final StreamController<List<int>> _bytes =
      StreamController<List<int>>.broadcast();
  StreamSubscription<List<int>>? _notifySubscription;
  StreamSubscription<BluetoothConnectionState>? _stateSubscription;
  bool _closing = false;

  _Icp5BluetoothGattConnection(
      {required this.device, required this.tx, required this.rx}) {
    _notifySubscription = rx.onValueReceived.listen(
        (value) => _bytes.add(List<int>.unmodifiable(value)),
        onError: _bytes.addError);
    _stateSubscription = device.connectionState.listen((state) {
      if (!_closing && state == BluetoothConnectionState.disconnected) {
        _bytes.addError(StateError('ICP5 BLE Notify disconnected.'));
      }
    });
  }

  @override
  Stream<List<int>> get bytes => _bytes.stream;

  @override
  Future<int> write(List<int> bytes, Duration timeout) async {
    await tx
        .write(bytes, withoutResponse: false, timeout: timeout.inSeconds)
        .timeout(timeout);
    return bytes.length;
  }

  @override
  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    await _notifySubscription?.cancel();
    await _stateSubscription?.cancel();
    if (rx.isNotifying) await rx.setNotifyValue(false);
    await device.disconnect();
    await _bytes.close();
  }
}
