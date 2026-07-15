import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';

class Icp5SerialDevice {
  final String portName;
  final int? vendorId;
  final int? productId;
  final String? productName;
  const Icp5SerialDevice(
      {required this.portName,
      this.vendorId,
      this.productId,
      this.productName});

  bool get isCaptureProvenIcp5 =>
      vendorId == 0x1A86 &&
      productId == 0x55D6 &&
      (productName == null ||
          productName!.toUpperCase().contains('CH9143') ||
          productName!.toUpperCase().contains('USB-BLE-SERIAL'));
}

abstract interface class Icp5SerialConnection {
  Stream<List<int>> get bytes;
  Future<int> write(List<int> bytes, Duration timeout);
  Future<void> close();
}

abstract interface class Icp5SerialDriver {
  bool get platformSupported;
  List<Icp5SerialDevice> discover();
  Future<Icp5SerialConnection> open(String portName);
}

class WindowsIcp5SerialDriver implements Icp5SerialDriver {
  @override
  bool get platformSupported => Platform.isWindows;

  @override
  List<Icp5SerialDevice> discover() {
    if (!platformSupported) return const [];
    return SerialPort.availablePorts
        .map((name) {
          final port = SerialPort(name);
          try {
            return Icp5SerialDevice(
                portName: name,
                vendorId: port.vendorId,
                productId: port.productId,
                productName: port.productName);
          } finally {
            port.dispose();
          }
        })
        .where((device) => device.isCaptureProvenIcp5)
        .toList(growable: false);
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
