import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/transport/adau1701_ch0_band0_decoder.dart';
import 'package:tunai_pro/core/transport/adau1701_ch0_band0_read_service.dart';
import 'package:tunai_pro/core/transport/icp5_frame_codec.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';
import 'package:tunai_pro/core/transport/icp5_serial_driver.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';

// ── Fixtures ─────────────────────────────────────────────────────────────────

const _kFirmwareId = 'DSP1701.100.00.01';
const _kPortName = 'COM27';

// State A payload: 1800 Hz, -1.0 dB, Q 2.0, property08State 1.
// Decoded offsets are 19-24 (all in page 0 / bytes 0-153).
// Bytes 154 and 308 are set to unique non-zero values so that pages 1 and 2
// produce distinct frames — the collector rejects exact frame duplicates.
List<int> _stateAPayload() {
  final p = List<int>.filled(513, 0x00);
  p[19] = 0x08;
  p[20] = 0x07;
  p[21] = 0xF6;
  p[23] = 0x14;
  p[24] = 0x01;
  p[154] = 0x01; // page 1 unique marker (outside decoded range)
  p[308] = 0x02; // page 2 unique marker (outside decoded range)
  return p;
}

// ICP5 identity response frame (DSP1701.100.00.01)
const _identityFrame = <int>[
  0x55, 0x18, 0xE0, 0, 0, 0, 0, 0,
  0x44, 0x53, 0x50, 0x31, 0x37, 0x30, 0x31, 0x2E,
  0x31, 0x30, 0x30, 0x2E, 0x30, 0x30, 0x2E, 0x30, 0x31,
  0xD9,
];

// Build a valid 0x2202 page frame of the given declared length with payload.
List<int> _pageFrame(int declaredLength, List<int> payload) {
  final frame = <int>[
    0x55, declaredLength, 0xE0, 0, 0, 0, 0x22, 0x02,
    ...payload,
  ];
  return [...frame, Icp5FrameCodec.checksum(frame)];
}

// Four pages carrying State A data in correct A1, A1, A1, 3A sequence.
List<List<int>> _stateAPages() {
  final payload = _stateAPayload();
  final pages = <List<int>>[
    _pageFrame(0xA1, payload.sublist(0, 154)),
    _pageFrame(0xA1, payload.sublist(154, 308)),
    _pageFrame(0xA1, payload.sublist(308, 462)),
    _pageFrame(0x3A, payload.sublist(462, 513)),
  ];
  return pages;
}

// ── Fake serial driver / connection ──────────────────────────────────────────

class _FakeConnection implements Icp5SerialConnection {
  final _controller = StreamController<List<int>>.broadcast(sync: true);
  int _writeCount = 0;
  final List<List<int>> rawPages;

  _FakeConnection(this.rawPages);

  @override
  Stream<List<int>> get bytes => _controller.stream;

  @override
  Future<int> write(List<int> bytes, Duration timeout) async {
    _writeCount++;
    // Write 1: identity request → emit identity frame
    if (_writeCount == 1) {
      _controller.add(_identityFrame);
    } else {
      // Writes 2..5: raw state page requests
      final pageIndex = _writeCount - 2;
      if (pageIndex < rawPages.length) {
        _controller.add(rawPages[pageIndex]);
      }
    }
    return bytes.length;
  }

  @override
  Future<void> close() async => _controller.close();
}

class _FakeDriver implements Icp5SerialDriver {
  final _FakeConnection connection;
  _FakeDriver(this.connection);

  @override
  bool get platformSupported => true;

  @override
  Future<Icp5DiscoveryResult> discover() async => const Icp5DiscoveryResult(
        source: 'Fake',
        allPorts: [
          Icp5SerialDevice(
            portName: _kPortName,
            vendorId: 0x1A86,
            productId: 0x55D6,
            productName: 'USB-BLE-SERIAL CH9143',
          ),
        ],
        matches: [
          Icp5SerialDevice(
            portName: _kPortName,
            vendorId: 0x1A86,
            productId: 0x55D6,
            productName: 'USB-BLE-SERIAL CH9143',
          ),
        ],
      );

  @override
  Future<Icp5SerialConnection> open(String portName) async => connection;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('transport / DSP identity separation', () {
    test('COM port name is not a valid DSP identity for the decoder', () {
      // The decoder must reject a snapshot whose deviceId is a COM port name.
      expect(
        () => RawDspStateSnapshot(
          deviceId: _kPortName,
          timestamp: DateTime.utc(2025, 1, 1),
          blockId: 0x2202,
          payload: _stateAPayload(),
        ).let(Adau1701Ch0Band0Decoder.decode),
        throwsA(isA<FormatException>()),
      );
    });

    test('firmware identity DSP1701.100.00.01 is accepted by the decoder', () {
      final snapshot = RawDspStateSnapshot(
        deviceId: _kFirmwareId,
        timestamp: DateTime.utc(2025, 1, 1),
        blockId: 0x2202,
        payload: _stateAPayload(),
      );
      final decoded = Adau1701Ch0Band0Decoder.decode(snapshot);
      expect(decoded.frequencyHz, 1800);
    });

    test(
        'read service rejects wrong firmware profile at transport readiness guard',
        () async {
      const service = Adau1701Ch0Band0ReadService(
        transport: _FakeReadTransport(detectedProfile: 'WRONG_PROFILE'),
      );
      final result = await service.readOriginalState();
      expect(result.status, Adau1701Ch0Band0ReadStatus.transportNotReady);
    });

    test('read service rejects COM port name passed as snapshot deviceId',
        () async {
      // Simulate a transport that is connected and has the right profile,
      // but incorrectly sets deviceId to the port name in the snapshot.
      const service = Adau1701Ch0Band0ReadService(
        transport: _FakeReadTransport(
          snapshotDeviceId: _kPortName, // wrong — should be firmware identity
        ),
      );
      final result = await service.readOriginalState();
      expect(result.status, Adau1701Ch0Band0ReadStatus.deviceIdentityMismatch);
    });

    test(
        'Icp5UsbTransport.readRawDspState sets snapshot deviceId to firmware identity, not port name',
        () async {
      final conn = _FakeConnection(_stateAPages());
      final transport = Icp5UsbTransport(driver: _FakeDriver(conn));
      await transport.open();

      expect(transport.selectedPort, _kPortName,
          reason: 'transport port should be the COM name');
      expect(transport.detectedProfile, _kFirmwareId,
          reason: 'firmware profile should be the handshake identity string');

      final snapshot = await transport.readRawDspState();

      expect(snapshot.deviceId, _kFirmwareId,
          reason: 'snapshot must carry firmware identity, not port name');
      expect(snapshot.deviceId, isNot(_kPortName),
          reason: 'COM port name must not appear in snapshot deviceId');
    });

    test('successful USB read → decoded original state via read service',
        () async {
      final conn = _FakeConnection(_stateAPages());
      final transport = Icp5UsbTransport(driver: _FakeDriver(conn));
      await transport.open();

      final service = Adau1701Ch0Band0ReadService(transport: transport);
      final result = await service.readOriginalState();

      expect(result.succeeded, isTrue);
      expect(result.originalState!.deviceId, _kFirmwareId);
      expect(result.originalState!.frequencyHz, 1800);
      expect(result.originalState!.gainDb, closeTo(-1.0, 0.001));
      expect(result.originalState!.q, closeTo(2.0, 0.001));
      expect(result.originalState!.property08State, 1);
    });
  });
}

// ── Helper fake transport for read-service guard tests ────────────────────────

class _FakeReadTransport implements Adau1701RawReadTransport {
  @override
  bool get isConnected => true;
  @override
  bool get handshakeComplete => true;
  @override
  final String? detectedProfile;
  final String? snapshotDeviceId;

  const _FakeReadTransport({
    this.detectedProfile = _kFirmwareId,
    this.snapshotDeviceId,
  });

  @override
  Future<RawDspStateSnapshot> readRawDspState() async =>
      RawDspStateSnapshot(
        deviceId: snapshotDeviceId ?? _kFirmwareId,
        timestamp: DateTime.utc(2025, 1, 1),
        blockId: 0x2202,
        payload: _stateAPayload(),
      );
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
