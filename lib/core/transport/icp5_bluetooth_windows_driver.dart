// ── TUNAI PRO — Windows ICP5 Bluetooth (BLE) transport driver ─────────────────
// Implements the SAME Icp5SerialDriver interface as the ICP5 USB/serial and the
// flutter_blue_plus BLE drivers, so Icp5UsbTransport, the ICP5 frame codec, and
// HardwareWriteExecutor are all reused unchanged. This driver only moves bytes
// over GATT (write FFF2 / notify FFF1 under service FFF0); framing, handshake,
// and parameter writes remain the transport/codec's job.
//
// flutter_blue_plus has no Windows backend in this project, so the actual radio
// access goes through a [WindowsBleBackend] seam — a WinRT MethodChannel backend
// in production, a fake in tests. Fail-closed: any missing UUID / char / adapter
// aborts before returning a connection.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'icp5_serial_driver.dart';

/// A BLE peripheral seen during a scan.
class WinBleDevice {
  final String id; // stable remote identifier (also the "portName")
  final String? name;
  final int? rssi;
  final bool connectable;
  const WinBleDevice({
    required this.id,
    this.name,
    this.rssi,
    this.connectable = true,
  });
}

/// A discovered GATT characteristic and its capabilities.
class WinBleCharacteristic {
  final String serviceUuid;
  final String uuid;
  final bool canWrite;
  final bool canNotify;
  const WinBleCharacteristic({
    required this.serviceUuid,
    required this.uuid,
    required this.canWrite,
    required this.canNotify,
  });
}

/// The result of connect + service/characteristic discovery.
class WinBleGattProfile {
  final String deviceId;
  final List<String> serviceUuids;
  final List<WinBleCharacteristic> characteristics;
  const WinBleGattProfile({
    required this.deviceId,
    required this.serviceUuids,
    required this.characteristics,
  });
}

/// Native BLE radio seam. Production implementation talks to WinRT over a
/// MethodChannel; tests inject a fake. No ICP5 framing lives here.
abstract interface class WindowsBleBackend {
  Future<bool> isAdapterOn();
  Future<List<WinBleDevice>> scan(Duration timeout);

  /// Connects and discovers services/characteristics.
  Future<WinBleGattProfile> connect(String deviceId, Duration timeout);
  Future<void> enableNotify(String deviceId, WinBleCharacteristic rx);
  Stream<List<int>> notifyStream(String deviceId, WinBleCharacteristic rx);
  Future<int> writeValue(
      String deviceId, WinBleCharacteristic tx, List<int> data, Duration timeout);
  Future<void> disconnect(String deviceId);
}

/// Windows ICP5 BLE driver. Exposes [Icp5SerialDriver] so the transport stack is
/// unchanged.
class WindowsIcp5BluetoothDriver implements Icp5SerialDriver {
  static const String serviceUuid = 'fff0';
  static const String txCharacteristicUuid = 'fff2'; // write
  static const String rxCharacteristicUuid = 'fff1'; // notify
  static const String discoverySource =
      'Windows WinRT BLE scan; FFF0 verified after connect';

  final WindowsBleBackend _backend;
  final Duration scanTimeout;
  final Duration connectTimeout;
  final bool Function() _isWindows;

  WindowsIcp5BluetoothDriver({
    WindowsBleBackend? backend,
    this.scanTimeout = const Duration(seconds: 10),
    this.connectTimeout = const Duration(seconds: 10),
    bool Function()? isWindowsOverride,
  })  : _backend = backend ?? const _MethodChannelWindowsBleBackend(),
        _isWindows =
            isWindowsOverride ?? (() => defaultTargetPlatform == TargetPlatform.windows);

  @override
  bool get platformSupported => _isWindows();

  /// Matches a discovered UUID (16-bit short or full 128-bit) against a short
  /// Bluetooth SIG UUID such as `fff0`.
  @visibleForTesting
  static bool uuidMatches(String uuid, String shortUuid) {
    final s = shortUuid.toLowerCase();
    final full = '0000$s-0000-1000-8000-00805f9b34fb';
    final normalized = uuid.toLowerCase().replaceAll('{', '').replaceAll('}', '');
    return normalized == s || normalized == full;
  }

  Icp5DiscoveryResult _fail(String message) => Icp5DiscoveryResult(
        source: discoverySource,
        allPorts: const [],
        matches: const [],
        error: message,
      );

  @override
  Future<Icp5DiscoveryResult> discover() async {
    if (!platformSupported) {
      return _fail('ICP5 BLE (Windows) is unavailable on this platform.');
    }
    try {
      if (!await _backend.isAdapterOn()) {
        return _fail('Bluetooth adapter is not on.');
      }
      final scanned = await _backend.scan(scanTimeout);
      final connectable = scanned.where((d) => d.connectable).toList();
      final ports = [
        for (final d in connectable)
          Icp5SerialDevice(
            portName: d.id,
            productName: (d.name?.trim().isEmpty ?? true) ? null : d.name,
            friendlyName:
                (d.name?.trim().isEmpty ?? true) ? 'Unnamed BLE device' : d.name,
            instanceId: d.id,
            rssi: d.rssi,
            enumerationSource: discoverySource,
          ),
      ]..sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999));
      debugPrint('[ICP5 BLE win] scanned=${scanned.length} '
          'connectable=${ports.length}');
      return Icp5DiscoveryResult(
        source: discoverySource,
        allPorts: ports,
        matches: ports,
        error: ports.isEmpty ? 'No connectable BLE devices found.' : null,
      );
    } on TimeoutException {
      return _fail('BLE scan timed out before devices were listed.');
    } catch (error) {
      return _fail('ICP5 BLE discovery failed: $error');
    }
  }

  @override
  Future<Icp5SerialConnection> open(String portName) async {
    if (!platformSupported) {
      throw UnsupportedError(
          'ICP5 BLE (Windows) is unavailable on this platform.');
    }
    debugPrint('[ICP5 BLE win] connect deviceId=$portName');
    final profile = await _backend.connect(portName, connectTimeout);

    // Service FFF0 must be present.
    if (!profile.serviceUuids.any((u) => uuidMatches(u, serviceUuid))) {
      await _safeDisconnect(portName);
      throw StateError('Service discovery failed: FFF0 was not found.');
    }

    // TX = writable FFF2; RX = notifiable FFF1.
    final tx = _firstWhere(profile.characteristics,
        (c) => uuidMatches(c.uuid, txCharacteristicUuid) && c.canWrite);
    if (tx == null) {
      await _safeDisconnect(portName);
      throw StateError('Service discovery failed: writable FFF2 was not found.');
    }
    final rx = _firstWhere(profile.characteristics,
        (c) => uuidMatches(c.uuid, rxCharacteristicUuid) && c.canNotify);
    if (rx == null) {
      await _safeDisconnect(portName);
      throw StateError('Notify subscription failed: notifiable FFF1 was not found.');
    }

    try {
      await _backend.enableNotify(portName, rx);
    } catch (error) {
      await _safeDisconnect(portName);
      throw StateError('Notify subscription failed for FFF1: $error');
    }

    return _WindowsBleConnection(
        backend: _backend, deviceId: portName, tx: tx, rx: rx);
  }

  Future<void> _safeDisconnect(String deviceId) async {
    try {
      await _backend.disconnect(deviceId);
    } catch (_) {}
  }

  static T? _firstWhere<T>(List<T> items, bool Function(T) test) {
    for (final item in items) {
      if (test(item)) return item;
    }
    return null;
  }
}

/// Bridges BLE notify → bytes and write → FFF2. Same [Icp5SerialConnection]
/// contract as the USB connection; idempotent, single-subscription, guarded.
class _WindowsBleConnection implements Icp5SerialConnection {
  final WindowsBleBackend backend;
  final String deviceId;
  final WinBleCharacteristic tx;
  final WinBleCharacteristic rx;

  StreamController<List<int>>? _controller;
  StreamSubscription<List<int>>? _sub;
  bool _closed = false;

  _WindowsBleConnection({
    required this.backend,
    required this.deviceId,
    required this.tx,
    required this.rx,
  });

  @override
  Stream<List<int>> get bytes {
    final existing = _controller;
    if (existing != null) return existing.stream;
    final controller = StreamController<List<int>>.broadcast();
    _controller = controller;
    _sub = backend.notifyStream(deviceId, rx).listen(
      (data) {
        if (_closed || controller.isClosed) return;
        controller.add(List<int>.unmodifiable(data));
      },
      onError: (Object error, StackTrace stack) {
        if (_closed || controller.isClosed) return;
        controller.addError(error, stack);
      },
    );
    return controller.stream;
  }

  @override
  Future<int> write(List<int> bytes, Duration timeout) async {
    if (_closed) throw StateError('ICP5 BLE connection is closed.');
    try {
      return await backend.writeValue(deviceId, tx, bytes, timeout);
    } catch (error) {
      throw StateError('ICP5 BLE write failed: $error');
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return; // idempotent
    _closed = true;
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;
    try {
      final controller = _controller;
      if (controller != null && !controller.isClosed) await controller.close();
    } catch (_) {}
    _controller = null;
    try {
      await backend.disconnect(deviceId);
    } catch (_) {}
  }
}

/// Production WinRT backend over a MethodChannel. The native side is not yet
/// implemented, so calls fail closed (MissingPluginException surfaces as a
/// discovery/connect error) until the WinRT plugin lands.
class _MethodChannelWindowsBleBackend implements WindowsBleBackend {
  const _MethodChannelWindowsBleBackend();
  static const MethodChannel _channel = MethodChannel('tunai/icp5_ble');
  static const EventChannel _notifyChannel =
      EventChannel('tunai/icp5_ble/notify');

  @override
  Future<bool> isAdapterOn() async =>
      (await _channel.invokeMethod<bool>('adapterOn')) ?? false;

  @override
  Future<List<WinBleDevice>> scan(Duration timeout) async {
    final raw = await _channel
        .invokeMethod<List>('scan', {'timeoutMs': timeout.inMilliseconds});
    return [
      for (final entry in raw ?? const [])
        () {
          final m = Map<Object?, Object?>.from(entry as Map);
          return WinBleDevice(
            id: m['id'] as String? ?? '',
            name: m['name'] as String?,
            rssi: (m['rssi'] as num?)?.toInt(),
            connectable: m['connectable'] as bool? ?? true,
          );
        }(),
    ];
  }

  @override
  Future<WinBleGattProfile> connect(String deviceId, Duration timeout) async {
    final raw = await _channel.invokeMethod<Map>('connect',
        {'deviceId': deviceId, 'timeoutMs': timeout.inMilliseconds});
    final m = Map<Object?, Object?>.from(raw ?? const {});
    final services = [
      for (final s in (m['services'] as List? ?? const [])) '$s',
    ];
    final chars = [
      for (final c in (m['characteristics'] as List? ?? const []))
        () {
          final cm = Map<Object?, Object?>.from(c as Map);
          return WinBleCharacteristic(
            serviceUuid: cm['service'] as String? ?? '',
            uuid: cm['uuid'] as String? ?? '',
            canWrite: cm['canWrite'] as bool? ?? false,
            canNotify: cm['canNotify'] as bool? ?? false,
          );
        }(),
    ];
    return WinBleGattProfile(
        deviceId: deviceId, serviceUuids: services, characteristics: chars);
  }

  @override
  Future<void> enableNotify(String deviceId, WinBleCharacteristic rx) =>
      _channel.invokeMethod('enableNotify',
          {'deviceId': deviceId, 'service': rx.serviceUuid, 'char': rx.uuid});

  @override
  Stream<List<int>> notifyStream(String deviceId, WinBleCharacteristic rx) =>
      _notifyChannel.receiveBroadcastStream(
          {'deviceId': deviceId, 'service': rx.serviceUuid, 'char': rx.uuid}).map(
          (event) => (event as List).cast<int>());

  @override
  Future<int> writeValue(String deviceId, WinBleCharacteristic tx,
      List<int> data, Duration timeout) async {
    await _channel.invokeMethod('write', {
      'deviceId': deviceId,
      'service': tx.serviceUuid,
      'char': tx.uuid,
      'data': data,
      'timeoutMs': timeout.inMilliseconds,
    });
    return data.length;
  }

  @override
  Future<void> disconnect(String deviceId) =>
      _channel.invokeMethod('disconnect', {'deviceId': deviceId});
}
