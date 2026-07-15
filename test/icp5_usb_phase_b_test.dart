import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/transport/icp5_frame_codec.dart';
import 'package:tunai_pro/core/transport/icp5_serial_driver.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';

const identityRx = <int>[
  0x55, 0x18, 0xE0, 0, 0, 0, 0, 0,
  0x44, 0x53, 0x50, 0x31, 0x37, 0x30, 0x31, 0x2E, 0x31,
  0x30, 0x30, 0x2E, 0x30, 0x30, 0x2E, 0x30, 0x31, 0xD9,
];
const goodAck = <int>[0x55, 0x07, 0xE1, 0, 0, 0, 0x10, 0, 0x4D];

class FakeConnection implements Icp5SerialConnection {
  final _controller = StreamController<List<int>>.broadcast(sync: true);
  final List<List<int>> writes = [];
  final void Function(FakeConnection connection, int call, List<int> bytes) onWrite;
  FakeConnection(this.onWrite);
  @override Stream<List<int>> get bytes => _controller.stream;
  void emit(List<int> bytes) => _controller.add(bytes);
  @override Future<int> write(List<int> bytes, Duration timeout) async {
    writes.add(List.from(bytes));
    onWrite(this, writes.length, bytes);
    return bytes.length;
  }
  @override Future<void> close() async => _controller.close();
}

class FakeDriver implements Icp5SerialDriver {
  final FakeConnection connection;
  final List<Icp5SerialDevice> devices;
  String? openedPort;
  FakeDriver(this.connection, {this.devices = const [
    Icp5SerialDevice(portName: 'COM27', vendorId: 0x1A86,
      productId: 0x55D6, productName: 'USB-BLE-SERIAL CH9143')
  ]});
  @override bool get platformSupported => true;
  @override List<Icp5SerialDevice> discover() => devices;
  @override Future<Icp5SerialConnection> open(String portName) async {
    openedPort = portName;
    return connection;
  }
}

void main() {
  test('exact identification and capture frames', () {
    expect(Icp5FrameCodec.identificationRequest,
        [0x55, 0x07, 0x1A, 0, 0, 0, 0, 0, 0x76]);
    expect(Icp5FrameCodec.parseIdentity(identityRx), 'DSP1701.100.00.01');
    expect(Icp5FrameCodec.buildMasterVolumeWrite(5.9),
        [0x55, 0x0A, 0x1C, 0, 0, 0, 0x10, 0xCD, 0xCC, 0xBC, 0x40, 0x20]);
    expect(Icp5FrameCodec.buildMasterVolumeWrite(6.0),
        [0x55, 0x0A, 0x1C, 0, 0, 0, 0x10, 0, 0, 0xC0, 0x40, 0x8B]);
    expect(() => Icp5FrameCodec.buildMasterVolumeWrite(5.8), throwsArgumentError);
  });

  test('checksum, ACK and parameter matching fail closed', () {
    expect(Icp5FrameCodec.checksum(goodAck.take(goodAck.length - 1)), 0x4D);
    expect(Icp5FrameCodec.parseMasterVolumeAck(goodAck), isTrue);
    final badChecksum = [...goodAck]..[8] = 0;
    expect(Icp5FrameCodec.parseMasterVolumeAck(badChecksum), isFalse);
    final wrongParameter = [...goodAck]..[6] = 0x11;
    wrongParameter[8] = Icp5FrameCodec.checksum(wrongParameter.take(8));
    expect(Icp5FrameCodec.parseMasterVolumeAck(wrongParameter), isFalse);
  });

  test('partial buffering extracts complete declared-length frames', () {
    final buffer = Icp5FrameBuffer();
    expect(buffer.add(identityRx.sublist(0, 7)), isEmpty);
    expect(buffer.add(identityRx.sublist(7, 20)), isEmpty);
    expect(buffer.add(identityRx.sublist(20)), [identityRx]);
  });

  test('VID/PID discovery is exact and does not hardcode COM3', () {
    const valid = Icp5SerialDevice(portName: 'COM27', vendorId: 0x1A86,
      productId: 0x55D6, productName: 'CH9143');
    const wrongPid = Icp5SerialDevice(portName: 'COM3', vendorId: 0x1A86,
      productId: 0x55D4, productName: 'CH9143');
    expect(valid.isCaptureProvenIcp5, isTrue);
    expect(wrongPid.isCaptureProvenIcp5, isFalse);
  });

  test('handshake is required and one action emits one write', () async {
    late FakeConnection connection;
    connection = FakeConnection((connection, call, bytes) {
      if (call == 1) connection.emit(identityRx);
      if (call == 2) connection.emit(goodAck);
    });
    final driver = FakeDriver(connection);
    final transport = Icp5UsbTransport(driver: driver);
    expect((await transport.writeCapturedMasterVolume(5.9)).success, isFalse);
    expect(connection.writes, isEmpty);
    expect((await transport.open()).success, isTrue);
    expect(driver.openedPort, 'COM27');
    final result = await transport.writeCapturedMasterVolume(5.9);
    expect(result.success, isTrue);
    expect(result.message, 'PASS_ACK');
    expect(connection.writes, hasLength(2)); // handshake + exactly one action
    await transport.close();
  });

  test('identity partial reads and timeout behavior', () async {
    late FakeConnection partial;
    partial = FakeConnection((connection, call, bytes) {
      connection.emit(identityRx.sublist(0, 5));
      connection.emit(identityRx.sublist(5));
    });
    final good = Icp5UsbTransport(driver: FakeDriver(partial));
    expect((await good.open()).success, isTrue);
    await good.close();

    final silent = FakeConnection((_, __, ___) {});
    final timed = Icp5UsbTransport(driver: FakeDriver(silent),
        readTimeout: const Duration(milliseconds: 10));
    expect((await timed.open()).success, isFalse);
  });

  test('TEST failure restores once; restore failure activates STOP', () async {
    late FakeConnection connection;
    connection = FakeConnection((connection, call, bytes) {
      if (call == 1) connection.emit(identityRx);
      if (call == 3) connection.emit(goodAck); // test times out; restore passes
    });
    final transport = Icp5UsbTransport(driver: FakeDriver(connection),
        readTimeout: const Duration(milliseconds: 10));
    await transport.open();
    final outcome = await transport.runTestWithGuardedRestore();
    expect(outcome.test.success, isFalse);
    expect(outcome.restore?.success, isTrue);
    expect(connection.writes[1], Icp5FrameCodec.buildMasterVolumeWrite(5.9));
    expect(connection.writes[2], Icp5FrameCodec.buildMasterVolumeWrite(6.0));
    await transport.close();

    final stops = <String>[];
    late FakeConnection failing;
    failing = FakeConnection((connection, call, bytes) {
      if (call == 1) connection.emit(identityRx);
    });
    final stopped = Icp5UsbTransport(driver: FakeDriver(failing),
      readTimeout: const Duration(milliseconds: 10), onDspWriteStop: stops.add);
    await stopped.open();
    final failed = await stopped.runTestWithGuardedRestore();
    expect(failed.stopActivated, isTrue);
    expect(stopped.stopped, isTrue);
    expect(stops.single, contains('shared DSP STOP'));
    await stopped.close();
  });
}
