import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/transport/icp5_frame_codec.dart';
import 'package:tunai_pro/core/transport/icp5_serial_driver.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';

const identityRx = <int>[
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
  final void Function(_Connection, int, List<int>) onWrite;
  final writes = <List<int>>[];
  _Connection(this.onWrite);
  @override
  Stream<List<int>> get bytes => _bytes.stream;
  void emit(List<int> value) => _bytes.add(value);
  @override
  Future<int> write(List<int> bytes, Duration timeout) async {
    writes.add(List.of(bytes));
    onWrite(this, writes.length, bytes);
    return bytes.length;
  }

  @override
  Future<void> close() => _bytes.close();
}

class _Driver implements Icp5SerialDriver {
  final _Connection connection;
  _Driver(this.connection);
  @override
  bool get platformSupported => true;
  @override
  Future<Icp5DiscoveryResult> discover() async => const Icp5DiscoveryResult(
      matches: [Icp5SerialDevice(portName: 'COM27')],
      allPorts: [Icp5SerialDevice(portName: 'COM27')],
      source: 'test');
  @override
  Future<Icp5SerialConnection> open(String portName) async => connection;
}

void main() {
  test('exact Delay candidate frames for all four channels', () {
    const testFrames = [
      [0x55, 0x0B, 0x1C, 0, 0, 0, 0x17, 0, 0, 0, 0x80, 0x3F, 0x52],
      [0x55, 0x0B, 0x1C, 0, 0, 0, 0x17, 1, 0, 0, 0x80, 0x3F, 0x53],
      [0x55, 0x0B, 0x1C, 0, 0, 0, 0x17, 2, 0, 0, 0x80, 0x3F, 0x54],
      [0x55, 0x0B, 0x1C, 0, 0, 0, 0x17, 3, 0, 0, 0x80, 0x3F, 0x55],
    ];
    const restoreFrames = [
      [0x55, 0x0B, 0x1C, 0, 0, 0, 0x17, 0, 0x0A, 0xD7, 0x23, 0x3D, 0xD4],
      [0x55, 0x0B, 0x1C, 0, 0, 0, 0x17, 1, 0x0A, 0xD7, 0x23, 0x3D, 0xD5],
      [0x55, 0x0B, 0x1C, 0, 0, 0, 0x17, 2, 0x0A, 0xD7, 0x23, 0x3D, 0xD6],
      [0x55, 0x0B, 0x1C, 0, 0, 0, 0x17, 3, 0x0A, 0xD7, 0x23, 0x3D, 0xD7],
    ];
    for (var channel = 0; channel < 4; channel++) {
      expect(Icp5FrameCodec.buildDelayCandidateWrite(channel, 1.0),
          testFrames[channel]);
      expect(Icp5FrameCodec.buildDelayCandidateWrite(channel, 0.04),
          restoreFrames[channel]);
    }
    expect(() => Icp5FrameCodec.buildDelayCandidateWrite(4, 1.0),
        throwsArgumentError);
    expect(() => Icp5FrameCodec.buildDelayCandidateWrite(0, 0.5),
        throwsArgumentError);
  });

  test('cutoff and PEQ vectors exactly match captures', () {
    expect(Icp5FrameCodec.buildFilterCutoffWrite(0, 2001),
        [0x55, 0x0B, 0x1C, 0, 0, 0, 0x15, 0, 2, 0, 0xD1, 7, 0x6B]);
    expect(Icp5FrameCodec.buildFilterCutoffWrite(0, 2000),
        [0x55, 0x0B, 0x1C, 0, 0, 0, 0x15, 0, 2, 0, 0xD0, 7, 0x6A]);
    expect(Icp5FrameCodec.buildFilterCutoffWrite(1, 2001),
        [0x55, 0x0B, 0x1C, 0, 0, 0, 0x15, 1, 2, 0, 0xD1, 7, 0x6C]);
    expect(Icp5FrameCodec.buildFilterCutoffWrite(1, 2000),
        [0x55, 0x0B, 0x1C, 0, 0, 0, 0x15, 1, 2, 0, 0xD0, 7, 0x6B]);
    expect(Icp5FrameCodec.buildFilterCutoffWrite(2, 21),
        [0x55, 0x0B, 0x1C, 0, 0, 0, 0x15, 2, 2, 0, 0x15, 0, 0xAA]);
    expect(Icp5FrameCodec.buildFilterCutoffWrite(2, 20),
        [0x55, 0x0B, 0x1C, 0, 0, 0, 0x15, 2, 2, 0, 0x14, 0, 0xA9]);
    expect(Icp5FrameCodec.buildFilterCutoffWrite(3, 21),
        [0x55, 0x0B, 0x1C, 0, 0, 0, 0x15, 3, 2, 0, 0x15, 0, 0xAB]);
    expect(Icp5FrameCodec.buildFilterCutoffWrite(3, 20),
        [0x55, 0x0B, 0x1C, 0, 0, 0, 0x15, 3, 2, 0, 0x14, 0, 0xAA]);
    expect(Icp5FrameCodec.buildPeqBand1GainWrite(0, -0.9),
        [0x55, 0x0A, 0x1C, 0, 0, 0, 0x18, 0, 1, 0, 0xF7, 0x8B]);
    expect(Icp5FrameCodec.buildPeqBand1GainWrite(0, -1.0),
        [0x55, 0x0A, 0x1C, 0, 0, 0, 0x18, 0, 1, 0, 0xF6, 0x8A]);
    expect(Icp5FrameCodec.buildPeqBand1GainWrite(1, 4.2),
        [0x55, 0x0A, 0x1C, 0, 0, 0, 0x18, 1, 1, 0, 0x2A, 0xBF]);
    expect(Icp5FrameCodec.buildPeqBand1GainWrite(1, 4.1),
        [0x55, 0x0A, 0x1C, 0, 0, 0, 0x18, 1, 1, 0, 0x29, 0xBE]);
    expect(Icp5FrameCodec.buildPeqBand1GainWrite(2, -1.0),
        [0x55, 0x0A, 0x1C, 0, 0, 0, 0x18, 2, 1, 0, 0xF6, 0x8C]);
    expect(Icp5FrameCodec.buildPeqBand1GainWrite(2, -2.0),
        [0x55, 0x0A, 0x1C, 0, 0, 0, 0x18, 2, 1, 0, 0xEC, 0x82]);
    expect(Icp5FrameCodec.buildPeqBand1GainWrite(3, 2.1),
        [0x55, 0x0A, 0x1C, 0, 0, 0, 0x18, 3, 1, 0, 0x15, 0xAC]);
    expect(Icp5FrameCodec.buildPeqBand1GainWrite(3, 2.0),
        [0x55, 0x0A, 0x1C, 0, 0, 0, 0x18, 3, 1, 0, 0x14, 0xAB]);
    expect(() => Icp5FrameCodec.buildFilterCutoffWrite(4, 2000),
        throwsArgumentError);
    expect(() => Icp5FrameCodec.buildFilterCutoffWrite(1, 20),
        throwsArgumentError);
    expect(() => Icp5FrameCodec.buildPeqBand1GainWrite(1, 4.0),
        throwsArgumentError);
  });

  test('ACK parsers require exact parameter and checksum', () {
    const gain = [0x55, 7, 0xE1, 0, 0, 0, 0x14, 0, 0x51];
    const cutoff = [0x55, 7, 0xE1, 0, 0, 0, 0x15, 0, 0x52];
    const delay = [0x55, 7, 0xE1, 0, 0, 0, 0x17, 0, 0x54];
    const peq = [0x55, 7, 0xE1, 0, 0, 0, 0x18, 0, 0x55];
    expect(Icp5FrameCodec.parseOutputGainAck(gain), isTrue);
    expect(Icp5FrameCodec.parseFilterCutoffAck(cutoff), isTrue);
    expect(Icp5FrameCodec.parseDelayCandidateAck(delay), isTrue);
    expect(Icp5FrameCodec.parsePeqBand1GainAck(peq), isTrue);
    expect(Icp5FrameCodec.parseDelayCandidateAck(cutoff), isFalse);
    expect(Icp5FrameCodec.parsePeqBand1GainAck([...peq]..[8] = 0), isFalse);
    expect(Icp5FrameCodec.parseOutputGainAck(gain.sublist(0, 8)), isFalse);
    expect(Icp5FrameCodec.parseFilterCutoffAck([0x55, 7, 0xE1]), isFalse);
  });

  test('all four exact Output Gain channel pairs are enabled', () {
    expect(Icp5FrameCodec.buildOutputGainWrite(0, -4.9),
        [0x55, 0x0C, 0x1C, 0, 0, 0, 0x14, 1, 0, 0xCD, 0xCC, 0x9C, 0xC0, 0x87]);
    expect(Icp5FrameCodec.buildOutputGainWrite(1, -4.8),
        [0x55, 0x0C, 0x1C, 0, 0, 0, 0x14, 1, 1, 0x9A, 0x99, 0x99, 0xC0, 0x1F]);
    expect(Icp5FrameCodec.buildOutputGainWrite(1, -4.7),
        [0x55, 0x0C, 0x1C, 0, 0, 0, 0x14, 1, 1, 0x67, 0x66, 0x96, 0xC0, 0xB6]);
    expect(Icp5FrameCodec.buildOutputGainWrite(2, -0.16666946),
        [0x55, 0x0C, 0x1C, 0, 0, 0, 0x14, 1, 2, 0x66, 0xAB, 0x2A, 0xBE, 0x8D]);
    expect(Icp5FrameCodec.buildOutputGainWrite(2, -0.06666946),
        [0x55, 0x0C, 0x1C, 0, 0, 0, 0x14, 1, 2, 0, 0x8A, 0x88, 0xBD, 0x63]);
    expect(Icp5FrameCodec.buildOutputGainWrite(3, -0.16666946),
        [0x55, 0x0C, 0x1C, 0, 0, 0, 0x14, 1, 3, 0x66, 0xAB, 0x2A, 0xBE, 0x8E]);
    expect(Icp5FrameCodec.buildOutputGainWrite(3, -0.06666946),
        [0x55, 0x0C, 0x1C, 0, 0, 0, 0x14, 1, 3, 0, 0x8A, 0x88, 0xBD, 0x64]);
    expect(() => Icp5FrameCodec.buildOutputGainWrite(4, -4.9),
        throwsArgumentError);
    expect(() => Icp5FrameCodec.buildOutputGainWrite(1, -4.9),
        throwsArgumentError);
    expect(() => Icp5FrameCodec.buildOutputGainWrite(0, -4.7),
        throwsArgumentError);
  });

  test('handshake gates writes and failed restore activates shared STOP',
      () async {
    late _Connection connection;
    connection = _Connection((connection, call, bytes) {
      if (call == 1) connection.emit(identityRx);
    });
    final stops = <String>[];
    final transport = Icp5UsbTransport(
        driver: _Driver(connection),
        readTimeout: const Duration(milliseconds: 10),
        onDspWriteStop: stops.add);
    expect(
        (await transport.writeCapturedDelayCandidate(0, 1.0)).success, isFalse);
    expect(connection.writes, isEmpty);
    await transport.open();
    final outcome = await transport.runDelayCandidateTest(0);
    expect(connection.writes, hasLength(3));
    expect(outcome.test.success, isFalse);
    expect(outcome.restore?.success, isFalse);
    expect(outcome.stopActivated, isTrue);
    expect(transport.stopped, isTrue);
    expect(stops.single, contains('Delay candidate DAC0 restore failed'));
    await transport.close();
  });

  test('one explicit Delay action emits one frame and PASS_ACK gates success',
      () async {
    const delayAck = [0x55, 7, 0xE1, 0, 0, 0, 0x17, 0, 0x54];
    late _Connection connection;
    connection = _Connection((connection, call, bytes) {
      if (call == 1) connection.emit(identityRx);
      if (call == 2) connection.emit(delayAck);
    });
    final transport = Icp5UsbTransport(driver: _Driver(connection));
    await transport.open();
    final result = await transport.writeCapturedDelayCandidate(3, 1.0);
    expect(result.success, isTrue);
    expect(result.message, 'PASS_ACK');
    expect(connection.writes, hasLength(2));
    expect(connection.writes.last,
        Icp5FrameCodec.buildDelayCandidateWrite(3, 1.0));
    await transport.close();
  });

  test('failed PEQ index 1 TEST performs one exact paired RESTORE', () async {
    const peqAck = [0x55, 7, 0xE1, 0, 0, 0, 0x18, 0, 0x55];
    late _Connection connection;
    connection = _Connection((connection, call, bytes) {
      if (call == 1) connection.emit(identityRx);
      if (call == 3) connection.emit(peqAck);
    });
    final transport = Icp5UsbTransport(
        driver: _Driver(connection),
        readTimeout: const Duration(milliseconds: 10));
    await transport.open();
    final outcome = await transport.runPeqBand1GainTest(1);
    expect(outcome.test.success, isFalse);
    expect(outcome.restore?.success, isTrue);
    expect(outcome.stopActivated, isFalse);
    expect(connection.writes, hasLength(3));
    expect(connection.writes[1], Icp5FrameCodec.buildPeqBand1GainWrite(1, 4.2));
    expect(connection.writes[2], Icp5FrameCodec.buildPeqBand1GainWrite(1, 4.1));
    await transport.close();
  });
}
