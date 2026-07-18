// Tests for band-index-aware PEQ readback (Band 1..10).
// Band 0 is capture-proven; bands 1..9 use an UNVERIFIED offset stride and are
// flagged pending. No hardware, transport, or write packets are involved.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/transport/adau1701_ch0_band0_decoder.dart';
import 'package:tunai_pro/core/transport/adau1701_ch0_band0_read_service.dart';
import 'package:tunai_pro/core/transport/adau1701_peq_band_decoder.dart';
import 'package:tunai_pro/core/transport/icp5_frame_codec.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';

const _kProfile = Icp5FrameCodec.expectedProfile;

RawDspStateSnapshot _snapshot(List<int> payload, {String? deviceId}) =>
    RawDspStateSnapshot(
      deviceId: deviceId ?? _kProfile,
      timestamp: DateTime.utc(2026, 1, 1),
      blockId: 0x2202,
      payload: payload,
    );

/// Sets one band's fields at the decoder's (assumed) offset window.
void _writeBand(List<int> p, int band,
    {required int freqHz, required int gainTenths, required int qTenths,
    required int prop}) {
  final base = Adau1701PeqBandDecoder.baseOffsetForBand(band);
  p[base] = freqHz & 0xFF;
  p[base + 1] = (freqHz >> 8) & 0xFF;
  p[base + 2] = gainTenths & 0xFF;
  p[base + 4] = qTenths & 0xFF;
  p[base + 5] = prop;
}

void main() {
  group('Adau1701PeqBandDecoder', () {
    test('band 0 decodes byte-identically to the verified decoder', () {
      final p = List<int>.filled(513, 0);
      _writeBand(p, 0, freqHz: 2000, gainTenths: 0xF6, qTenths: 20, prop: 1);
      final snap = _snapshot(p);

      final proven = Adau1701Ch0Band0Decoder.decode(snap);
      final rb = Adau1701PeqBandDecoder.decode(snap, band: 0);

      expect(rb.band, 0);
      expect(rb.isCaptureProven, isTrue);
      expect(rb.withinVerifiedRanges, isTrue);
      expect(rb.frequencyHz, proven.frequencyHz);
      expect(rb.gainDb, proven.gainDb);
      expect(rb.q, proven.q);
      expect(rb.property08State, proven.property08State);
      // Sanity: -1.0 dB, 2.0 Q, 2000 Hz.
      expect(rb.frequencyHz, 2000);
      expect(rb.gainDb, closeTo(-1.0, 1e-9));
      expect(rb.q, closeTo(2.0, 1e-9));
    });

    test('band N reads at base + 6*N and is flagged unverified', () {
      final p = List<int>.filled(513, 0);
      _writeBand(p, 0, freqHz: 2000, gainTenths: 0xF6, qTenths: 20, prop: 1);
      // Band 3 (index 2) at offset 19 + 6*2 = 31.
      _writeBand(p, 2, freqHz: 1000, gainTenths: 20, qTenths: 30, prop: 0);
      final snap = _snapshot(p);

      expect(Adau1701PeqBandDecoder.baseOffsetForBand(2), 31);
      final rb = Adau1701PeqBandDecoder.decode(snap, band: 2);
      expect(rb.band, 2);
      expect(rb.isCaptureProven, isFalse);
      expect(rb.withinVerifiedRanges, isTrue);
      expect(rb.frequencyHz, 1000);
      expect(rb.gainDb, closeTo(2.0, 1e-9));
      expect(rb.q, closeTo(3.0, 1e-9));
      expect(rb.property08State, 0);
    });

    test('bands 1..9 do not throw on out-of-range values (flag instead)', () {
      final p = List<int>.filled(513, 0); // all-zero → freq 0, out of range
      final rb = Adau1701PeqBandDecoder.decode(p.let((x) => _snapshot(x)), band: 5);
      expect(rb.isCaptureProven, isFalse);
      expect(rb.withinVerifiedRanges, isFalse); // freq 0 Hz is below 20
    });

    test('band 0 still fails closed on an out-of-range value', () {
      final p = List<int>.filled(513, 0); // freq 0 → verified decoder throws
      expect(() => Adau1701PeqBandDecoder.decode(_snapshot(p), band: 0),
          throwsFormatException);
    });

    test('rejects an out-of-range band index', () {
      final p = List<int>.filled(513, 0);
      expect(() => Adau1701PeqBandDecoder.decode(_snapshot(p), band: 10),
          throwsFormatException);
      expect(() => Adau1701PeqBandDecoder.decode(_snapshot(p), band: -1),
          throwsFormatException);
    });

    test('device identity mismatch fails closed for bands 1..9', () {
      final p = List<int>.filled(513, 0);
      _writeBand(p, 1, freqHz: 1000, gainTenths: 0, qTenths: 10, prop: 0);
      expect(
          () => Adau1701PeqBandDecoder.decode(
              _snapshot(p, deviceId: 'WRONG.PROFILE.1'),
              band: 1),
          throwsFormatException);
    });

    test('covers band index 0..9 (10 fixed slots)', () {
      final p = List<int>.filled(513, 0);
      for (var band = 0; band < Icp5FrameCodec.peqBandCount; band++) {
        _writeBand(p, band,
            freqHz: 1000, gainTenths: 0, qTenths: 10, prop: 0);
      }
      for (var band = 0; band < Icp5FrameCodec.peqBandCount; band++) {
        final rb = Adau1701PeqBandDecoder.decode(_snapshot(p), band: band);
        expect(rb.band, band);
        expect(rb.frequencyHz, 1000);
        expect(rb.isCaptureProven, band == 0);
      }
    });
  });

  group('Adau1701Ch0Band0ReadService.readBandState', () {
    test('band 0 read is hardware-verified', () async {
      final p = List<int>.filled(513, 0);
      _writeBand(p, 0, freqHz: 2000, gainTenths: 0xF6, qTenths: 20, prop: 1);
      final svc = Adau1701Ch0Band0ReadService(transport: _FakeReadTransport(p));

      final r = await svc.readBandState(band: 0);
      expect(r.succeeded, isTrue);
      expect(r.isHardwareVerified, isTrue);
      expect(r.readback!.frequencyHz, 2000);
    });

    test('band 2 read succeeds but is not hardware-verified (pending)', () async {
      final p = List<int>.filled(513, 0);
      _writeBand(p, 0, freqHz: 2000, gainTenths: 0xF6, qTenths: 20, prop: 1);
      _writeBand(p, 2, freqHz: 1000, gainTenths: 20, qTenths: 30, prop: 0);
      final svc = Adau1701Ch0Band0ReadService(transport: _FakeReadTransport(p));

      final r = await svc.readBandState(band: 2);
      expect(r.succeeded, isTrue);
      expect(r.isHardwareVerified, isFalse);
      expect(r.message, contains('UNVERIFIED'));
      expect(r.readback!.gainDb, closeTo(2.0, 1e-9));
    });

    test('fails closed when transport is not ready', () async {
      final svc = Adau1701Ch0Band0ReadService(
          transport: _FakeReadTransport(List<int>.filled(513, 0),
              isConnected: false));
      final r = await svc.readBandState(band: 1);
      expect(r.succeeded, isFalse);
      expect(r.status, Adau1701Ch0Band0ReadStatus.transportNotReady);
    });
  });
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

class _FakeReadTransport implements Adau1701RawReadTransport {
  final List<int> payload;
  @override
  final bool isConnected;
  @override
  final bool handshakeComplete;
  @override
  final String? detectedProfile;

  _FakeReadTransport(this.payload,
      {this.isConnected = true,
      this.handshakeComplete = true,
      this.detectedProfile = _kProfile});

  @override
  Future<RawDspStateSnapshot> readRawDspState() async => RawDspStateSnapshot(
        deviceId: _kProfile,
        timestamp: DateTime.utc(2026, 1, 1),
        blockId: 0x2202,
        payload: payload,
      );
}
