import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/transport/dsp_transport.dart';
import '../../core/transport/icp5_frame_codec.dart';
import '../../core/transport/icp5_transports.dart';

enum ConsumerBleStatus {
  disconnected,
  bluetoothUnavailable,
  permissionRequired,
  scanning,
  deviceFound,
  connecting,
  connected,
  connectionFailed,
  deviceNotSupported,
}

@immutable
class ConsumerBleDevice {
  final String identifier;
  final String name;
  final int? rssi;

  const ConsumerBleDevice({
    required this.identifier,
    required this.name,
    this.rssi,
  });
}

@immutable
class ConsumerBleState {
  final ConsumerBleStatus status;
  final List<ConsumerBleDevice> devices;
  final String? selectedIdentifier;
  final String? connectedDeviceName;
  final String? message;

  const ConsumerBleState({
    this.status = ConsumerBleStatus.disconnected,
    this.devices = const [],
    this.selectedIdentifier,
    this.connectedDeviceName,
    this.message,
  });

  bool get connected => status == ConsumerBleStatus.connected;
  bool get busy =>
      status == ConsumerBleStatus.scanning ||
      status == ConsumerBleStatus.connecting;
}

/// Consumer-safe facade over the capture-proven shared ICP5 BLE transport.
///
/// It intentionally exposes no frame, UUID, profile, ACK, parameter, or DSP
/// command API. A successful shared identity handshake is represented only as
/// the consumer-facing `connected` state.
class ConsumerBleService extends ChangeNotifier {
  final Icp5BluetoothTransport _transport;
  ConsumerBleState _state = const ConsumerBleState();
  Timer? _connectionMonitor;

  ConsumerBleService({Icp5BluetoothTransport? transport})
      : _transport = transport ?? Icp5BluetoothTransport();

  ConsumerBleState get state => _state;
  bool get bluetoothAvailable => _transport.driver.platformSupported;

  Future<void> scan() async {
    if (_state.busy || _state.connected) return;
    if (!bluetoothAvailable) {
      _setState(const ConsumerBleState(
        status: ConsumerBleStatus.bluetoothUnavailable,
        message: 'Bluetooth unavailable',
      ));
      return;
    }
    _setState(ConsumerBleState(
      status: ConsumerBleStatus.scanning,
      devices: _state.devices,
      selectedIdentifier: _state.selectedIdentifier,
      message: 'Scanning',
    ));
    final result = await _transport.discover();
    final devices = result.allPorts
        .map((device) => ConsumerBleDevice(
              identifier: device.portName,
              name: (device.friendlyName ?? '').trim().isEmpty
                  ? 'Bluetooth device'
                  : device.friendlyName!.trim(),
              rssi: device.rssi,
            ))
        .toList(growable: false);
    if (result.error != null && devices.isEmpty) {
      _setState(ConsumerBleState(
        status: _classifyFailure(result.error!),
        message: _safeFailureMessage(result.error!),
      ));
      return;
    }
    final preferred = devices
        .where((device) => device.name.toUpperCase() == 'WONDOM ICP5')
        .firstOrNull;
    final selected = preferred?.identifier ?? devices.firstOrNull?.identifier;
    if (selected != null) _transport.selectEnumeratedPort(selected);
    _setState(ConsumerBleState(
      status: devices.isEmpty
          ? ConsumerBleStatus.connectionFailed
          : ConsumerBleStatus.deviceFound,
      devices: devices,
      selectedIdentifier: selected,
      message: devices.isEmpty ? 'Connection failed' : 'Device found',
    ));
  }

  bool selectDevice(String identifier) {
    if (_state.busy || _state.connected) return false;
    if (!_state.devices.any((device) => device.identifier == identifier) ||
        !_transport.selectEnumeratedPort(identifier)) {
      return false;
    }
    _setState(ConsumerBleState(
      status: ConsumerBleStatus.deviceFound,
      devices: _state.devices,
      selectedIdentifier: identifier,
      message: 'Device found',
    ));
    return true;
  }

  Future<void> connect() async {
    if (_state.busy || _state.connected) return;
    final selected = _state.selectedIdentifier;
    if (selected == null || !_transport.selectEnumeratedPort(selected)) {
      _setState(ConsumerBleState(
        status: ConsumerBleStatus.connectionFailed,
        devices: _state.devices,
        message: 'Connection failed',
      ));
      return;
    }
    final device = _state.devices
        .where((candidate) => candidate.identifier == selected)
        .firstOrNull;
    _setState(ConsumerBleState(
      status: ConsumerBleStatus.connecting,
      devices: _state.devices,
      selectedIdentifier: selected,
      message: 'Connecting',
    ));
    final result = await _transport.open();
    if (!result.success ||
        !_transport.handshakeComplete ||
        _transport.detectedProfile != Icp5FrameCodec.expectedProfile) {
      await _transport.close();
      _setState(ConsumerBleState(
        status: _classifyFailure(result.message),
        devices: _state.devices,
        selectedIdentifier: selected,
        message: _safeFailureMessage(result.message),
      ));
      return;
    }
    _setState(ConsumerBleState(
      status: ConsumerBleStatus.connected,
      devices: _state.devices,
      selectedIdentifier: selected,
      connectedDeviceName: device?.name ?? 'ICP5',
      message: 'Connected',
    ));
    _connectionMonitor?.cancel();
    _connectionMonitor = Timer.periodic(
        const Duration(milliseconds: 250), (_) => refreshConnectionState());
  }

  void refreshConnectionState() {
    if (_state.connected &&
        _transport.connectionState != DspConnectionState.connected) {
      _connectionMonitor?.cancel();
      _connectionMonitor = null;
      _setState(ConsumerBleState(
        status: ConsumerBleStatus.disconnected,
        devices: _state.devices,
        selectedIdentifier: _state.selectedIdentifier,
        message: 'Disconnected',
      ));
    }
  }

  Future<void> disconnect() async {
    _connectionMonitor?.cancel();
    _connectionMonitor = null;
    await _transport.close();
    _setState(ConsumerBleState(
      status: ConsumerBleStatus.disconnected,
      devices: _state.devices,
      selectedIdentifier: _state.selectedIdentifier,
      message: 'Disconnected',
    ));
  }

  ConsumerBleStatus _classifyFailure(String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('permission') ||
        normalized.contains('unauthorized')) {
      return ConsumerBleStatus.permissionRequired;
    }
    if (normalized.contains('adapter') ||
        normalized.contains('unavailable') ||
        normalized.contains('not on')) {
      return ConsumerBleStatus.bluetoothUnavailable;
    }
    if (normalized.contains('service') ||
        normalized.contains('notify') ||
        normalized.contains('handshake') ||
        normalized.contains('identity')) {
      return ConsumerBleStatus.deviceNotSupported;
    }
    return ConsumerBleStatus.connectionFailed;
  }

  String _safeFailureMessage(String message) =>
      switch (_classifyFailure(message)) {
        ConsumerBleStatus.permissionRequired => 'Permission required',
        ConsumerBleStatus.bluetoothUnavailable => 'Bluetooth unavailable',
        ConsumerBleStatus.deviceNotSupported => 'Device not supported',
        _ => 'Connection failed',
      };

  void _setState(ConsumerBleState next) {
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _connectionMonitor?.cancel();
    _transport.close();
    super.dispose();
  }
}
