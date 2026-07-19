import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/transport/icp5_serial_driver.dart';

Icp5SerialDevice _dev(String port, {int? vid, int? pid, String? product}) =>
    Icp5SerialDevice(
      portName: port,
      vendorId: vid,
      productId: pid,
      productName: product,
      enumerationSource: 'test',
    );

// A capture-proven ICP5 bridge (VID 0x1A86 / PID 0x55D6) on a cu.* port.
Icp5SerialDevice _icp5() =>
    _dev('/dev/cu.usbserial-1420', vid: 0x1A86, pid: 0x55D6, product: 'USB Serial');

void main() {
  MacIcp5SerialDriver mac({
    bool isMac = true,
    List<Icp5SerialDevice> ports = const [],
    Object? enumerateError,
  }) =>
      MacIcp5SerialDriver(
        isMacOsOverride: () => isMac,
        enumeratePorts: () {
          if (enumerateError != null) throw enumerateError;
          return ports;
        },
      );

  group('discovery', () {
    test('matches the ICP5 bridge by VID 0x1A86 / PID 0x55D6', () async {
      final driver = mac(ports: [
        _dev('/dev/cu.Bluetooth-Incoming-Port'),
        _dev('/dev/cu.usbmodem-other', vid: 0x1234, pid: 0x5678),
        _icp5(),
      ]);
      final result = await driver.discover();

      expect(result.allPorts, hasLength(3));
      expect(result.matches, hasLength(1));
      expect(result.matches.single.portName, '/dev/cu.usbserial-1420');
      expect(result.matches.single.vendorId, 0x1A86);
      expect(result.matches.single.productId, 0x55D6);
      expect(result.error, isNull);
      expect(result.source, contains('macOS'));
    });

    test('no ICP5 device → matches empty with an error message', () async {
      final driver = mac(ports: [
        _dev('/dev/cu.usbmodem-other', vid: 0x1234, pid: 0x5678),
      ]);
      final result = await driver.discover();
      expect(result.matches, isEmpty);
      expect(result.error, contains('No VID_1A86&PID_55D6'));
    });

    test('right VID but wrong PID does not match', () async {
      final driver = mac(ports: [
        _dev('/dev/cu.usbserial-x', vid: 0x1A86, pid: 0x0001),
      ]);
      final result = await driver.discover();
      expect(result.matches, isEmpty);
    });

    test('null VID/PID but wchusbserial name matches (macOS CH34x fallback)',
        () async {
      final driver = mac(ports: [
        _dev('/dev/cu.Bluetooth-Incoming-Port'),
        _dev('/dev/cu.wchusbserialWCH0642C2TS11'),
      ]);
      final result = await driver.discover();
      expect(result.matches, hasLength(1));
      expect(result.matches.single.portName,
          '/dev/cu.wchusbserialWCH0642C2TS11');
      expect(result.error, isNull);
    });

    test('null VID/PID with generic usbserial name matches', () async {
      final driver = mac(ports: [_dev('/dev/cu.usbserial-1420')]);
      final result = await driver.discover();
      expect(result.matches, hasLength(1));
    });

    test('null VID/PID non-CH34x port name does not match (fail-closed)',
        () async {
      final driver = mac(ports: [
        _dev('/dev/cu.Bluetooth-Incoming-Port'),
        _dev('/dev/cu.usbmodem1234'),
      ]);
      final result = await driver.discover();
      expect(result.matches, isEmpty);
      expect(result.error, contains('No VID_1A86&PID_55D6'));
    });

    test('VID/PID takes precedence over name: wrong VID on usbserial rejected',
        () async {
      // Name would match the fallback, but a present, different VID/PID wins.
      final driver = mac(ports: [
        _dev('/dev/cu.usbserial-ftdi', vid: 0x0403, pid: 0x6001),
      ]);
      final result = await driver.discover();
      expect(result.matches, isEmpty);
    });
  });

  group('fail-closed', () {
    test('unsupported platform → error, no enumeration', () async {
      var enumerated = false;
      final driver = MacIcp5SerialDriver(
        isMacOsOverride: () => false,
        enumeratePorts: () {
          enumerated = true;
          return const [];
        },
      );
      expect(driver.platformSupported, isFalse);
      final result = await driver.discover();
      expect(result.matches, isEmpty);
      expect(result.error, contains('unavailable on this platform'));
      expect(enumerated, isFalse);
    });

    test('open() throws on an unsupported platform', () async {
      final driver = mac(isMac: false);
      await expectLater(
        driver.open('/dev/cu.usbserial-1420'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('enumeration failure is caught → error result, no throw', () async {
      final driver = mac(enumerateError: StateError('libserialport missing'));
      final result = await driver.discover();
      expect(result.matches, isEmpty);
      expect(result.allPorts, isEmpty);
      expect(result.error, contains('failed'));
    });

    test('open() delegates to an injected opener when supported', () async {
      var openedPort = '';
      final driver = MacIcp5SerialDriver(
        isMacOsOverride: () => true,
        enumeratePorts: () => const [],
        openPort: (port) async {
          openedPort = port;
          return _FakeConnection();
        },
      );
      final conn = await driver.open('/dev/cu.usbserial-1420');
      expect(openedPort, '/dev/cu.usbserial-1420');
      expect(conn, isA<Icp5SerialConnection>());
    });
  });

  group('platform selection', () {
    test('defaultIcp5UsbSerialDriver returns the mac driver on macOS', () {
      final driver = defaultIcp5UsbSerialDriver();
      if (Platform.isMacOS) {
        expect(driver, isA<MacIcp5SerialDriver>());
      } else {
        expect(driver, isA<WindowsIcp5SerialDriver>());
      }
    });
  });
}

class _FakeConnection implements Icp5SerialConnection {
  @override
  Stream<List<int>> get bytes => const Stream.empty();
  @override
  Future<int> write(List<int> bytes, Duration timeout) async => bytes.length;
  @override
  Future<void> close() async {}
}
