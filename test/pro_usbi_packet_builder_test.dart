// ── TUNAI PRO Phase T4A — USBi Packet Builder Tests ──────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_usbi_packet_builder.dart';

void main() {
  group('buildParameterWriteSetup', () {
    test('returns 8 bytes', () {
      expect(buildParameterWriteSetup().length, 8);
    });

    test('byte 0-1 are 0x40 0xB2', () {
      final p = buildParameterWriteSetup();
      expect(p[0], 0x40);
      expect(p[1], 0xB2);
    });

    test('bytes 2-5 are 00 00 01 01', () {
      final p = buildParameterWriteSetup();
      expect(p[2], 0x00);
      expect(p[3], 0x00);
      expect(p[4], 0x01);
      expect(p[5], 0x01);
    });

    test('byte 6 is bodyLength (default 6)', () {
      expect(buildParameterWriteSetup()[6], kUsbiBodyLength);
      expect(buildParameterWriteSetup()[6], 6);
    });

    test('byte 7 is 0x00', () {
      expect(buildParameterWriteSetup()[7], 0x00);
    });

    test('default body length matches kUsbiBodyLength', () {
      expect(buildParameterWriteSetup()[6], kUsbiBodyLength);
    });

    test('custom bodyLength is reflected in byte 6', () {
      expect(buildParameterWriteSetup(bodyLength: 10)[6], 10);
    });

    test('validated known setup: 40 B2 00 00 01 01 06 00', () {
      expect(
        buildParameterWriteSetup(),
        [0x40, 0xB2, 0x00, 0x00, 0x01, 0x01, 0x06, 0x00],
      );
    });
  });

  group('buildParameterWriteBody', () {
    test('returns 6 bytes', () {
      expect(
        buildParameterWriteBody(addressInt: 0x0067, fixedPointInt: 0x00800000)
            .length,
        6,
      );
    });

    test('test vector: 0x0067 + 0.5 → [00 67 00 80 00 00]', () {
      // 0.5 in 8.24 → 0x00800000
      expect(
        buildParameterWriteBody(addressInt: 0x0067, fixedPointInt: 0x00800000),
        [0x00, 0x67, 0x00, 0x80, 0x00, 0x00],
      );
    });

    test('test vector: 0x0064 + 1.0 → [00 64 01 00 00 00]', () {
      // 1.0 in 8.24 → 0x01000000
      expect(
        buildParameterWriteBody(addressInt: 0x0064, fixedPointInt: 0x01000000),
        [0x00, 0x64, 0x01, 0x00, 0x00, 0x00],
      );
    });

    test('test vector: 0x0064 + 0.0 → [00 64 00 00 00 00]', () {
      // 0.0 in 8.24 → 0x00000000
      expect(
        buildParameterWriteBody(addressInt: 0x0064, fixedPointInt: 0x00000000),
        [0x00, 0x64, 0x00, 0x00, 0x00, 0x00],
      );
    });

    test('address high byte is correct (0x0067 → addr_hi=0x00)', () {
      final b = buildParameterWriteBody(
          addressInt: 0x0067, fixedPointInt: 0x01000000);
      expect(b[0], 0x00);
    });

    test('address low byte is correct (0x0067 → addr_lo=0x67)', () {
      final b = buildParameterWriteBody(
          addressInt: 0x0067, fixedPointInt: 0x01000000);
      expect(b[1], 0x67);
    });

    test('address low byte for 0x0064 is 0x64', () {
      final b = buildParameterWriteBody(
          addressInt: 0x0064, fixedPointInt: 0x00000000);
      expect(b[1], 0x64);
    });

    test('data bytes are big-endian for 0x01000000', () {
      final b = buildParameterWriteBody(
          addressInt: 0x0067, fixedPointInt: 0x01000000);
      expect(b[2], 0x01);
      expect(b[3], 0x00);
      expect(b[4], 0x00);
      expect(b[5], 0x00);
    });

    test('data bytes are big-endian for 0x00800000', () {
      final b = buildParameterWriteBody(
          addressInt: 0x0067, fixedPointInt: 0x00800000);
      expect(b[2], 0x00);
      expect(b[3], 0x80);
      expect(b[4], 0x00);
      expect(b[5], 0x00);
    });

    test('zero value produces all-zero data bytes', () {
      final b = buildParameterWriteBody(
          addressInt: 0x0064, fixedPointInt: 0x00000000);
      expect(b.sublist(2), [0x00, 0x00, 0x00, 0x00]);
    });
  });

  group('buildAckReadRequest', () {
    test('returns 8 bytes', () {
      expect(buildAckReadRequest().length, 8);
    });

    test('validated known ACK read: C0 B5 00 00 00 00 01 00', () {
      expect(
        buildAckReadRequest(),
        [0xC0, 0xB5, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00],
      );
    });

    test('byte 0 is 0xC0', () => expect(buildAckReadRequest()[0], 0xC0));
    test('byte 1 is 0xB5', () => expect(buildAckReadRequest()[1], 0xB5));
    test('byte 6 is 0x01', () => expect(buildAckReadRequest()[6], 0x01));
    test('byte 7 is 0x00', () => expect(buildAckReadRequest()[7], 0x00));
  });

  group('isAckSuccess', () {
    test('true for standard ACK [C0 B5 00 00 00 00 01 00]', () {
      expect(
        isAckSuccess([0xC0, 0xB5, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00]),
        true,
      );
    });

    test('false for NAK [C0 B5 00 00 00 00 00 00]', () {
      expect(
        isAckSuccess([0xC0, 0xB5, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
        false,
      );
    });

    test('false for payload shorter than 7 bytes', () {
      expect(isAckSuccess([0xC0, 0xB5, 0x01, 0x00, 0x01, 0x00]), false);
    });

    test('false for empty payload', () {
      expect(isAckSuccess([]), false);
    });

    test('true when byte 6 is 0x01 regardless of other bytes', () {
      expect(
        isAckSuccess([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01, 0xFF]),
        true,
      );
    });

    test('false when byte 6 is 0x02 (not expected value)', () {
      expect(
        isAckSuccess([0xC0, 0xB5, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00]),
        false,
      );
    });
  });

  group('bytesToHex', () {
    test('formats empty list', () => expect(bytesToHex([]), ''));
    test('single byte', () => expect(bytesToHex([0x40]), '40'));
    test('formats setup packet', () {
      expect(
        bytesToHex([0x40, 0xB2, 0x00, 0x00, 0x01, 0x01, 0x06, 0x00]),
        '40 B2 00 00 01 01 06 00',
      );
    });
    test('pads single-digit bytes', () {
      expect(bytesToHex([0x00, 0x01, 0x0F]), '00 01 0F');
    });
    test('uppercase output', () {
      expect(bytesToHex([0xAB, 0xCD, 0xEF]), 'AB CD EF');
    });
  });

  group('constants', () {
    test('kUsbiBodyLength is 6', () => expect(kUsbiBodyLength, 6));
    test('kUsbiSetupByte0 is 0x40', () => expect(kUsbiSetupByte0, 0x40));
    test('kUsbiSetupByte1 is 0xB2', () => expect(kUsbiSetupByte1, 0xB2));
    test('kUsbiAckByte0 is 0xC0', () => expect(kUsbiAckByte0, 0xC0));
    test('kUsbiAckByte1 is 0xB5', () => expect(kUsbiAckByte1, 0xB5));
    test('kExpectedAckByte is 0x01', () => expect(kExpectedAckByte, 0x01));
  });
}
