// V3-8A — ADAU1701 BLE Readback Verification
//
// Verifies the full BLE raw state read path at the protocol layer:
//   Icp5RawStateReader → frame sequence → 513-byte assembly → decoder → compare
//
// No real hardware required. A fake exchange function returns pre-built response
// frames that match the ICP5 0x2201 / 0x2202 protocol exactly (envelope, block
// ID, declared length, checksum). The tests confirm:
//   1. Correct TX frame sequence (0x2201 then 0x2202 × 4)
//   2. 513-byte payload assembly across four pages
//   3. Band0 gain decode at multiple known values
//   4. Expected-vs-actual comparison via HardwareReadbackResult
//   5. Unverified band provenance flag stays false for bands 1..9

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/hardware_readback_result.dart';
import 'package:tunai_pro/core/transport/adau1701_ch0_band0_decoder.dart';
import 'package:tunai_pro/core/transport/adau1701_peq_band_decoder.dart';
import 'package:tunai_pro/core/transport/icp5_frame_codec.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';

// ── Frame construction helpers ────────────────────────────────────────────────

// Page declared lengths in the ICP5 raw-state protocol (pages 0-2 = 0xA1, page 3 = 0x3A).
const _pageDeclaredLengths = [0xA1, 0xA1, 0xA1, 0x3A];

// Payload bytes carried per page (declaredLength - 7 = frame.length - 9).
const _pagePayloadSizes = [154, 154, 154, 51];

List<int> _stateHeaderResponse() {
  // Minimal 1-byte-payload 0x2201 response.
  // Validator: frame[1] + 2 == frame.length.
  // 1 payload byte → frame.length = 10 → frame[1] = 8 = 0x08.
  // frame (9 bytes before cs): [0x55, 0x08, 0xE0, 0, 0, 0, 0x22, 0x01, 0x00]
  // + 1 checksum byte = 10 bytes total.  0x08 + 2 = 10 ✓
  final frame = [0x55, 0x08, 0xE0, 0, 0, 0, 0x22, 0x01, 0x00];
  return [...frame, Icp5FrameCodec.checksum(frame)];
}

List<List<int>> _buildPageResponses(List<int> payload513) {
  assert(payload513.length == 513, 'Requires a 513-byte payload');
  final pages = <List<int>>[];
  var offset = 0;
  for (var i = 0; i < 4; i++) {
    final size = _pagePayloadSizes[i];
    final pagePayload = payload513.sublist(offset, offset + size);
    final frame = [
      0x55, _pageDeclaredLengths[i], 0xE0, 0, 0, 0, 0x22, 0x02,
      ...pagePayload,
    ];
    pages.add([...frame, Icp5FrameCodec.checksum(frame)]);
    offset += size;
  }
  return pages;
}

// ── Payload builder ───────────────────────────────────────────────────────────

// Build a 513-byte payload with known Band0 (Ch0) values at their
// capture-proven offsets (19=freqLo, 20=freqHi, 21=gain, 23=Q, 24=property08).
//
// Pages 0-2 each carry 154 bytes; page 3 carries 51 bytes.  Pages 1 and 2
// would otherwise be identical (same declared length + all-zero content), which
// would trigger Icp5RawStateCollector's duplicate-detection HashSet.  Marker
// bytes at the first byte of each page boundary make every page frame unique.
List<int> _buildPayload({
  int freqHz = 1000,
  double gainDb = 0.0,
  double q = 1.0,
  int property08 = 0,
}) {
  final payload = List<int>.filled(513, 0);
  // Page-boundary markers (must not overlap Band0 offsets 19-24).
  payload[154] = 0x01; // start of page 1
  payload[308] = 0x02; // start of page 2
  payload[462] = 0x03; // start of page 3
  // Band0 values (offsets 19-24, all within page 0).
  payload[19] = freqHz & 0xFF;
  payload[20] = (freqHz >> 8) & 0xFF;
  final gainRaw = (gainDb * 10).round();
  payload[21] = gainRaw < 0 ? gainRaw + 256 : gainRaw;
  payload[23] = (q * 10).round();
  payload[24] = property08;
  return payload;
}

// ── Stateful fake exchange ────────────────────────────────────────────────────

class _FakeExchange {
  final List<List<int>> _pages;
  final sentRequests = <List<int>>[];
  var _pageIdx = 0;

  _FakeExchange(List<int> payload513)
      : _pages = _buildPageResponses(payload513);

  Future<List<int>> call(List<int> request) async {
    sentRequests.add(List<int>.of(request));
    final blockId = (request[6] << 8) | request[7];
    if (blockId == Icp5ReadRequestBuilder.stateHeaderBlockId) {
      return _stateHeaderResponse();
    }
    if (blockId == Icp5ReadRequestBuilder.rawStateBlockId) {
      if (_pageIdx >= _pages.length) throw StateError('Unexpected extra page request.');
      return _pages[_pageIdx++];
    }
    throw StateError('Unexpected TX blockId: 0x${blockId.toRadixString(16)}');
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  const kDeviceId = 'DSP1701.100.00.01';

  Future<RawDspStateSnapshot> readSnapshot(List<int> payload513) async {
    final exchange = _FakeExchange(payload513);
    final reader = Icp5RawStateReader(
      exchange: exchange.call,
      clock: () => DateTime.utc(2026, 8, 5),
    );
    return reader.read(deviceId: kDeviceId);
  }

  // ── 1. BLE raw state read frame sequence ───────────────────────────────────

  group('BLE readRawDspState frame sequence', () {
    test('sends 0x2201 first, then exactly four 0x2202 requests', () async {
      final exchange = _FakeExchange(_buildPayload());
      final reader = Icp5RawStateReader(exchange: exchange.call);
      await reader.read(deviceId: kDeviceId);

      expect(exchange.sentRequests, hasLength(5));
      final blockIds = exchange.sentRequests
          .map((r) => (r[6] << 8) | r[7])
          .toList();
      expect(blockIds[0], equals(Icp5ReadRequestBuilder.stateHeaderBlockId),
          reason: 'First TX must be 0x2201 state header');
      for (var i = 1; i < 5; i++) {
        expect(blockIds[i], equals(Icp5ReadRequestBuilder.rawStateBlockId),
            reason: 'TX $i must be 0x2202 raw state');
      }
    });

    test('each TX frame carries a valid ICP5 checksum', () async {
      final exchange = _FakeExchange(_buildPayload());
      final reader = Icp5RawStateReader(exchange: exchange.call);
      await reader.read(deviceId: kDeviceId);

      for (final request in exchange.sentRequests) {
        final expectedCs =
            Icp5FrameCodec.checksum(request.take(request.length - 1));
        expect(request.last, equals(expectedCs),
            reason: 'TX frame checksum must be valid');
      }
    });
  });

  // ── 2. 513-byte payload assembly ───────────────────────────────────────────

  group('513-byte payload assembly', () {
    test('snapshot payload is exactly 513 bytes', () async {
      final snapshot = await readSnapshot(_buildPayload());
      expect(snapshot.payload.length, equals(513));
    });

    test('payload bytes are the original 513 values (round-trip)', () async {
      final original = _buildPayload(freqHz: 1000, gainDb: 2.0, q: 1.4);
      final snapshot = await readSnapshot(original);
      expect(snapshot.payload, equals(original));
    });

    test('snapshot carries the correct deviceId', () async {
      final snapshot = await readSnapshot(_buildPayload());
      expect(snapshot.deviceId, equals(kDeviceId));
    });

    test('snapshot blockId is 0x2202', () async {
      final snapshot = await readSnapshot(_buildPayload());
      expect(snapshot.blockId, equals(0x2202));
    });
  });

  // ── 3. Band0 gain decode ──────────────────────────────────────────────────

  group('Band0 gain decode (capture-proven offset 21)', () {
    Adau1701Ch0Band0DecodedState decodeGain(double gainDb) {
      final snapshot = RawDspStateSnapshot(
        deviceId: kDeviceId,
        timestamp: DateTime.utc(2026, 8, 5),
        blockId: 0x2202,
        payload: _buildPayload(gainDb: gainDb),
      );
      return Adau1701Ch0Band0Decoder.decode(snapshot);
    }

    test('decodes +3.0 dB (0x1E at offset 21)', () {
      final result = decodeGain(3.0);
      expect(result.gainDb, equals(3.0));
    });

    test('decodes 0.0 dB (0x00 at offset 21)', () {
      final result = decodeGain(0.0);
      expect(result.gainDb, equals(0.0));
    });

    test('decodes -1.0 dB (0xF6 = 246 as uint8 = -10 as int8 → /10)', () {
      final result = decodeGain(-1.0);
      expect(result.gainDb, equals(-1.0));
    });

    test('decodes -6.0 dB (minimum in -6.0..+3.0 range)', () {
      final result = decodeGain(-6.0);
      expect(result.gainDb, equals(-6.0));
    });

    test('decodes frequency 1000 Hz at offsets 19..20', () {
      final snapshot = RawDspStateSnapshot(
        deviceId: kDeviceId,
        timestamp: DateTime.utc(2026, 8, 5),
        blockId: 0x2202,
        payload: _buildPayload(freqHz: 1000, gainDb: 1.0),
      );
      final result = Adau1701Ch0Band0Decoder.decode(snapshot);
      expect(result.frequencyHz, equals(1000));
    });

    test('decodes Q 1.4 at offset 23', () {
      final snapshot = RawDspStateSnapshot(
        deviceId: kDeviceId,
        timestamp: DateTime.utc(2026, 8, 5),
        blockId: 0x2202,
        payload: _buildPayload(gainDb: 0.0, q: 1.4),
      );
      final result = Adau1701Ch0Band0Decoder.decode(snapshot);
      expect(result.q, closeTo(1.4, 0.01));
    });
  });

  // ── 4. Expected vs actual gain compare ────────────────────────────────────

  group('Expected vs actual gain comparison (HardwareReadbackResult)', () {
    test('write +3.0 dB → readback +3.0 dB: verified', () async {
      const expectedGain = 3.0;
      final snapshot =
          await readSnapshot(_buildPayload(gainDb: expectedGain));
      final decoded = Adau1701Ch0Band0Decoder.decode(snapshot);

      final result = HardwareReadbackResult.verify(
        parameter: 'PEQ Ch0 Band0 Gain',
        expectedValue: expectedGain,
        actualValue: decoded.gainDb,
      );

      expect(result.status, equals(HardwareReadbackStatus.verified));
      expect(result.isVerified, isTrue);
      expect(result.difference, lessThanOrEqualTo(0.1));
    });

    test('write +3.0 dB → DSP contains 0.0 dB: mismatch detected', () async {
      const expectedGain = 3.0;
      final snapshot =
          await readSnapshot(_buildPayload(gainDb: 0.0));
      final decoded = Adau1701Ch0Band0Decoder.decode(snapshot);

      final result = HardwareReadbackResult.verify(
        parameter: 'PEQ Ch0 Band0 Gain',
        expectedValue: expectedGain,
        actualValue: decoded.gainDb,
      );

      expect(result.status, equals(HardwareReadbackStatus.mismatch));
      expect(result.isVerified, isFalse);
      expect(result.difference, closeTo(3.0, 0.01));
    });

    test('write 0.0 dB → readback 0.0 dB: verified', () async {
      const expectedGain = 0.0;
      final snapshot =
          await readSnapshot(_buildPayload(gainDb: expectedGain));
      final decoded = Adau1701Ch0Band0Decoder.decode(snapshot);

      final result = HardwareReadbackResult.verify(
        parameter: 'PEQ Ch0 Band0 Gain',
        expectedValue: expectedGain,
        actualValue: decoded.gainDb,
      );

      expect(result.status, equals(HardwareReadbackStatus.verified));
    });

    test('difference is the absolute |actual - expected|', () async {
      final snapshot = await readSnapshot(_buildPayload(gainDb: 1.0));
      final decoded = Adau1701Ch0Band0Decoder.decode(snapshot);

      final result = HardwareReadbackResult.verify(
        parameter: 'PEQ Ch0 Band0 Gain',
        expectedValue: 3.0,
        actualValue: decoded.gainDb,
      );

      expect(result.difference, closeTo(2.0, 0.01));
    });

    test('unavailable result carries correct status and no values', () {
      final result = HardwareReadbackResult.unavailable('Output Gain Ch0');
      expect(result.status, equals(HardwareReadbackStatus.unavailable));
      expect(result.isVerified, isFalse);
      expect(result.difference.isNaN, isTrue);
    });

    test('readError result carries status and reason message', () {
      final result = HardwareReadbackResult.readError(
          'PEQ Ch0 Band0 Gain', 'Raw state read timed out.');
      expect(result.status, equals(HardwareReadbackStatus.readError));
      expect(result.message, contains('timed out'));
    });
  });

  // ── 5. Unverified band provenance flag ────────────────────────────────────

  group('Unverified band isCaptureProven flag', () {
    RawDspStateSnapshot buildSnapshot({double gainDb = 1.0}) =>
        RawDspStateSnapshot(
          deviceId: kDeviceId,
          timestamp: DateTime.utc(2026, 8, 5),
          blockId: 0x2202,
          payload: _buildPayload(gainDb: gainDb),
        );

    test('band 0 isCaptureProven is true', () {
      final readback =
          Adau1701PeqBandDecoder.decode(buildSnapshot(), band: 0);
      expect(readback.isCaptureProven, isTrue);
    });

    test('band 1 isCaptureProven is false (unverified stride assumption)', () {
      final readback =
          Adau1701PeqBandDecoder.decode(buildSnapshot(), band: 1);
      expect(readback.isCaptureProven, isFalse);
    });

    test('band 9 isCaptureProven is false', () {
      final readback =
          Adau1701PeqBandDecoder.decode(buildSnapshot(), band: 9);
      expect(readback.isCaptureProven, isFalse);
    });

    test('band 1 withinVerifiedRanges is false when payload bytes are zero '
        '(unverified offset returns freq=0, Q=0 — both out of range)', () {
      final readback =
          Adau1701PeqBandDecoder.decode(buildSnapshot(), band: 1);
      expect(readback.withinVerifiedRanges, isFalse,
          reason: 'Zeroed payload at band-1 offset is outside freq/Q range');
    });

    test('band 0 withinVerifiedRanges is true for valid payload', () {
      final readback =
          Adau1701PeqBandDecoder.decode(buildSnapshot(gainDb: 1.0), band: 0);
      expect(readback.withinVerifiedRanges, isTrue);
    });

    test('bands 1..9 do not throw even when decoded values are out of range '
        '(fail-open for unverified offsets; provenance flag is the guard)', () {
      final snapshot = buildSnapshot();
      for (var band = 1; band <= 9; band++) {
        expect(
          () => Adau1701PeqBandDecoder.decode(snapshot, band: band),
          returnsNormally,
          reason: 'Band $band must not throw on unverified offset values',
        );
      }
    });
  });
}
