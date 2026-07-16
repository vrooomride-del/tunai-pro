import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

class Icp5SerialDevice {
  final String portName;
  final int? vendorId;
  final int? productId;
  final String? productName;
  final String? friendlyName;
  final String? instanceId;
  final String? serialNumber;
  final int? rssi;
  final String enumerationSource;

  const Icp5SerialDevice(
      {required this.portName,
      this.vendorId,
      this.productId,
      this.productName,
      this.friendlyName,
      this.instanceId,
      this.serialNumber,
      this.rssi,
      this.enumerationSource = 'unknown'});

  static final RegExp _comPattern =
      RegExp(r'\((COM\d+)\)', caseSensitive: false);
  static String? extractComPort(String? friendlyName) =>
      _comPattern.firstMatch(friendlyName ?? '')?.group(1)?.toUpperCase();

  bool get hasExactInstanceId {
    final normalized = instanceId?.toUpperCase() ?? '';
    return normalized.contains(r'VID_1A86&PID_55D6');
  }

  bool get hasSecondaryIdentity {
    final normalized =
        '${friendlyName ?? ''} ${productName ?? ''}'.toUpperCase();
    return normalized.contains('USB-BLE-SERIAL') &&
        normalized.contains('CH9143');
  }

  bool get isCaptureProvenIcp5 =>
      hasExactInstanceId ||
      (vendorId == 0x1A86 && productId == 0x55D6 && hasSecondaryIdentity);
}

class Icp5DiscoveryResult {
  final String source;
  final List<Icp5SerialDevice> allPorts;
  final List<Icp5SerialDevice> matches;
  final String? error;
  const Icp5DiscoveryResult(
      {required this.source,
      required this.allPorts,
      required this.matches,
      this.error});
  int get candidateCount => allPorts.length;
}

abstract interface class Icp5SerialConnection {
  Stream<List<int>> get bytes;
  Future<int> write(List<int> bytes, Duration timeout);
  Future<void> close();
}

abstract interface class Icp5SerialDriver {
  bool get platformSupported;
  Future<Icp5DiscoveryResult> discover();
  Future<Icp5SerialConnection> open(String portName);
}

class WindowsIcp5SerialDriver implements Icp5SerialDriver {
  static const _channel = MethodChannel('tunai/icp5_serial');
  @override
  bool get platformSupported => Platform.isWindows;

  @override
  Future<Icp5DiscoveryResult> discover() async {
    const source = 'Windows SetupAPI Ports class';
    if (!platformSupported) {
      return const Icp5DiscoveryResult(
          source: source,
          allPorts: [],
          matches: [],
          error: 'Windows SetupAPI discovery is unavailable on this platform.');
    }
    try {
      final raw = await _channel.invokeMethod<Map>('list_ports');
      final map = Map<Object?, Object?>.from(raw ?? const {});
      final ports = (map['ports'] as List? ?? const [])
          .map((entry) {
            final item = Map<Object?, Object?>.from(entry as Map);
            final friendly = item['friendlyName'] as String?;
            final instance = item['instanceId'] as String?;
            final portName = (item['portName'] as String?)?.toUpperCase() ??
                Icp5SerialDevice.extractComPort(friendly) ??
                '';
            final upperInstance = instance?.toUpperCase() ?? '';
            int? parseId(String marker) {
              final match =
                  RegExp('$marker([0-9A-F]{4})').firstMatch(upperInstance);
              return match == null
                  ? null
                  : int.tryParse(match.group(1)!, radix: 16);
            }

            final serial = instance?.split(r'\').lastOrNull;
            return Icp5SerialDevice(
                portName: portName,
                vendorId: parseId('VID_'),
                productId: parseId('PID_'),
                productName: item['description'] as String?,
                friendlyName: friendly,
                instanceId: instance,
                serialNumber: serial,
                enumerationSource: item['source'] as String? ?? source);
          })
          .where((device) => RegExp(r'^COM\d+$', caseSensitive: false)
              .hasMatch(device.portName))
          .toList(growable: false);

      for (final device in ports) {
        debugPrint('[ICP5 Discovery] candidate port=${device.portName} '
            'friendly=${device.friendlyName ?? '-'} instanceId=${device.instanceId ?? '-'} '
            'vidPidMatch=${device.isCaptureProvenIcp5}');
      }
      final matches = ports
          .where((device) => device.isCaptureProvenIcp5)
          .toList(growable: false);
      debugPrint(
          '[ICP5 Discovery] selected=${matches.firstOrNull?.portName ?? 'none'} '
          'source=$source candidates=${ports.length}');
      return Icp5DiscoveryResult(
          source: source,
          allPorts: ports,
          matches: matches,
          error: matches.isEmpty
              ? 'No VID_1A86&PID_55D6 ICP5 device found via $source; ${ports.length} candidate port(s) enumerated.'
              : null);
    } on PlatformException catch (error) {
      final message =
          '$source failed: ${error.message ?? error.code}; 0 candidate ports found.';
      debugPrint('[ICP5 Discovery] failure=$message');
      return Icp5DiscoveryResult(
          source: source,
          allPorts: const [],
          matches: const [],
          error: message);
    } catch (error) {
      final message = '$source failed: $error; 0 candidate ports found.';
      debugPrint('[ICP5 Discovery] failure=$message');
      return Icp5DiscoveryResult(
          source: source,
          allPorts: const [],
          matches: const [],
          error: message);
    }
  }

  @override
  Future<Icp5SerialConnection> open(String portName) async {
    if (!platformSupported) {
      throw UnsupportedError('ICP5 USB Phase B is Windows-only.');
    }
    final port = SerialPort(portName);
    if (!port.openReadWrite()) {
      final error = SerialPort.lastError;
      port.dispose();
      throw StateError(
          'Cannot exclusively open $portName: ${error?.message ?? 'unknown serial error'}');
    }
    final config = SerialPortConfig()
      ..baudRate = 115200
      ..bits = 8
      ..parity = SerialPortParity.none
      ..stopBits = 1;
    port.config = config;
    config.dispose();
    return _LibSerialConnection(port);
  }
}

class _LibSerialConnection implements Icp5SerialConnection {
  final SerialPort _port;
  late final SerialPortReader _reader = SerialPortReader(_port);
  _LibSerialConnection(this._port);
  @override
  Stream<List<int>> get bytes => _reader.stream.map((data) => data.toList());
  @override
  Future<int> write(List<int> bytes, Duration timeout) => Future<int>(() =>
      _port.write(Uint8List.fromList(bytes), timeout: timeout.inMilliseconds));
  @override
  Future<void> close() async {
    _reader.close();
    _port.close();
    _port.dispose();
  }
}
