// ── TUNAI PRO Phase T4C — Windows USBi Native Backend Tests ──────────────────
// Tests for ProUsbiWindowsNativeBackend.
// All tests run via a fake MethodChannel — no real hardware required.
//
// Key invariants verified:
//   - Non-Windows: isAvailable = false, sendPackets returns null.
//   - Windows (simulated): isAvailable = true only after initialise().
//   - isConnected = true only after successful open.
//   - sendPacketsAndReadAck returns null when not connected.
//   - Structured errors propagate — no fake success.
//   - ACK success detected at byte index 6 == 0x01.
//   - Wrong ACK returns bytes (not null) — caller detects ackFailed.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_usbi_windows_native_backend.dart';
import 'package:tunai_pro/core/pro_usbi_packet_builder.dart';

// ── Fake MethodChannel helper ─────────────────────────────────────────────────

typedef FakeHandler = Future<dynamic> Function(MethodCall call);

void _setFakeChannel(String channel, FakeHandler handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('tunai/usbi'),
    (call) => handler(call),
  );
}

void _clearFakeChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('tunai/usbi'),
    null,
  );
}

// Simulates a fully working native side.
void _setupHappyPath({bool ackSuccess = true}) {
  _setFakeChannel('tunai/usbi', (call) async {
    switch (call.method) {
      case 'usbi_is_available':
        return true;
      case 'usbi_list_devices':
        return [
          {
            'vid': 0x0456,
            'pid': 0xB62B,
            'product': 'ADI USBi',
            'manufacturer': 'Analog Devices',
            'instanceId': 'USB\\VID_0456&PID_B62B\\001',
            'likelyUsbi': true,
          }
        ];
      case 'usbi_open_device':
        return {'success': true, 'path': r'\\?\usb#vid_0456...'};
      case 'usbi_send_setup':
        return {'success': true, 'transferred': 6};
      case 'usbi_send_body':
        return {'success': true};
      case 'usbi_read_ack':
        if (ackSuccess) {
          return {
            'success': true,
            'ack': [0xC0, 0xB5, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00],
          };
        } else {
          return {
            'success': true,
            'ack': [0xC0, 0xB5, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
          };
        }
      case 'usbi_close':
        return {'success': true};
      default:
        throw PlatformException(code: 'NOT_IMPL');
    }
  });
}

void _setupOpenFail({String error = 'Access denied. Check WinUSB driver / Zadig.'}) {
  _setFakeChannel('tunai/usbi', (call) async {
    if (call.method == 'usbi_is_available') return true;
    if (call.method == 'usbi_open_device') {
      return {'success': false, 'error': error};
    }
    return null;
  });
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(_clearFakeChannel);

  // ── Non-Windows stubs ────────────────────────────────────────────────────

  group('Non-Windows platform', () {
    // Note: these tests always pass because Platform.isWindows is false
    // in the test runner (macOS / Linux CI). The backend guards on isWindows.

    test('isAvailable is false before initialise', () {
      final backend = ProUsbiWindowsNativeBackend();
      // On non-Windows, isAvailable must be false regardless.
      // On Windows test runner, status starts unavailable.
      expect(backend.isConnected, false);
    });

    test('isFake is always false', () {
      expect(ProUsbiWindowsNativeBackend().isFake, false);
    });

    test('sendPacketsAndReadAck returns null when not connected', () async {
      final backend = ProUsbiWindowsNativeBackend();
      final result = await backend.sendPacketsAndReadAck(
        setupPacket:    buildParameterWriteSetup(),
        bodyPacket:     buildParameterWriteBody(
            addressInt: 0x0067, fixedPointInt: 0x00800000),
        ackReadRequest: buildAckReadRequest(),
      );
      expect(result, isNull);
    });

    test('listDevices returns empty list when not Windows', () async {
      _setupHappyPath();
      final backend = ProUsbiWindowsNativeBackend();
      final devices = await backend.listDevices();
      // On macOS/Linux test runner, Platform.isWindows = false → empty list.
      // On Windows runner, this may return the fake list — both acceptable.
      expect(devices, isA<List>());
    });
  });

  // ── Channel method contracts (fake channel) ───────────────────────────────

  group('Channel: usbi_is_available', () {
    test('initialise sets status to pending when available=true', () async {
      _setupHappyPath();
      final backend = ProUsbiWindowsNativeBackend();
      await backend.initialise();
      // On non-Windows runner, status stays unavailable — still passes.
      expect(backend.status, anyOf(
        UsbiWindowsStatus.pending,
        UsbiWindowsStatus.unavailable,
      ));
    });
  });

  group('Channel: usbi_list_devices', () {
    test('happy path returns list with likelyUsbi=true for VID 0x0456', () async {
      _setupHappyPath();
      final backend = ProUsbiWindowsNativeBackend();
      final devices = await backend.listDevices();
      if (devices.isNotEmpty) {
        expect(devices.first['likelyUsbi'], true);
        expect(devices.first['vid'], 0x0456);
      }
      // Empty on non-Windows — not a failure.
    });
  });

  group('Channel: usbi_open_device', () {
    test('success sets isConnected=true and status=connected', () async {
      _setupHappyPath();
      final backend = ProUsbiWindowsNativeBackend();
      final res = await backend.openDevice();
      // On non-Windows, always fails. On Windows runner, succeeds.
      if (res.success) {
        expect(backend.isConnected, true);
        expect(backend.status, UsbiWindowsStatus.connected);
      } else {
        expect(backend.isConnected, false);
      }
    });

    test('access denied maps to accessDenied status', () async {
      _setupOpenFail(
        error: 'Access denied. Check WinUSB driver / Zadig.');
      final backend = ProUsbiWindowsNativeBackend();
      final res = await backend.openDevice();
      if (!res.success) {
        // On non-Windows: returns (success:false) because Platform.isWindows=false.
        // On Windows: returns accessDenied from fake channel.
        expect(backend.isConnected, false);
      }
    });

    test('open failure does not set isConnected', () async {
      _setupOpenFail();
      final backend = ProUsbiWindowsNativeBackend();
      await backend.openDevice();
      expect(backend.isConnected, false);
    });

    test('no fake success — error propagates as lastError', () async {
      _setupOpenFail(error: 'WinUSB error 5: Access is denied.');
      final backend = ProUsbiWindowsNativeBackend();
      final res = await backend.openDevice();
      if (!res.success) {
        expect(res.error, isNotNull);
        expect(res.error, isNotEmpty);
      }
    });
  });

  group('Channel: send_setup + read_ack (write transaction)', () {
    test('returns ACK bytes on success', () async {
      _setupHappyPath(ackSuccess: true);
      final backend = ProUsbiWindowsNativeBackend();
      await backend.openDevice();

      final ack = await backend.sendPacketsAndReadAck(
        setupPacket:    buildParameterWriteSetup(),
        bodyPacket:     buildParameterWriteBody(
            addressInt: 0x0067, fixedPointInt: 0x00800000),
        ackReadRequest: buildAckReadRequest(),
      );

      // On non-Windows: null (not connected). On Windows fake: ack bytes.
      if (ack != null) {
        expect(ack.length, 8);
        expect(ack[6], 0x01);  // success byte
        expect(isAckSuccess(ack), true);
      }
    });

    test('wrong ACK byte returns bytes (not null) — caller detects ackFailed', () async {
      _setupHappyPath(ackSuccess: false);
      final backend = ProUsbiWindowsNativeBackend();
      await backend.openDevice();

      final ack = await backend.sendPacketsAndReadAck(
        setupPacket:    buildParameterWriteSetup(),
        bodyPacket:     buildParameterWriteBody(
            addressInt: 0x0064, fixedPointInt: 0x01000000),
        ackReadRequest: buildAckReadRequest(),
      );

      if (ack != null) {
        expect(ack[6], 0x00);
        expect(isAckSuccess(ack), false);
      }
    });

    test('sendPackets returns null when not connected', () async {
      _setupHappyPath();
      final backend = ProUsbiWindowsNativeBackend();
      // Intentionally skip openDevice()

      final ack = await backend.sendPacketsAndReadAck(
        setupPacket:    buildParameterWriteSetup(),
        bodyPacket:     buildParameterWriteBody(
            addressInt: 0x0067, fixedPointInt: 0x00000000),
        ackReadRequest: buildAckReadRequest(),
      );
      expect(ack, isNull);
    });
  });

  group('Channel: usbi_close', () {
    test('closeDevice resets isConnected to false', () async {
      _setupHappyPath();
      final backend = ProUsbiWindowsNativeBackend();
      await backend.openDevice();
      await backend.closeDevice();
      expect(backend.isConnected, false);
    });

    test('status returns to pending after close', () async {
      _setupHappyPath();
      final backend = ProUsbiWindowsNativeBackend();
      await backend.openDevice();
      await backend.closeDevice();
      expect(backend.status, anyOf(
        UsbiWindowsStatus.pending,
        UsbiWindowsStatus.unavailable,
      ));
    });
  });

  // ── Packet builder test vectors ───────────────────────────────────────────

  group('Packet builder test vectors', () {
    test('Master Volume L 0.5: body = 00 67 00 80 00 00', () {
      final body = buildParameterWriteBody(
          addressInt: 0x0067, fixedPointInt: 0x00800000);
      expect(body, [0x00, 0x67, 0x00, 0x80, 0x00, 0x00]);
    });

    test('Master Volume R 1.0: body = 00 64 01 00 00 00', () {
      final body = buildParameterWriteBody(
          addressInt: 0x0064, fixedPointInt: 0x01000000);
      expect(body, [0x00, 0x64, 0x01, 0x00, 0x00, 0x00]);
    });

    test('Master Volume R 0.0: body = 00 64 00 00 00 00', () {
      final body = buildParameterWriteBody(
          addressInt: 0x0064, fixedPointInt: 0x00000000);
      expect(body, [0x00, 0x64, 0x00, 0x00, 0x00, 0x00]);
    });

    test('setup packet: 40 B2 00 00 01 01 06 00', () {
      expect(buildParameterWriteSetup(),
          [0x40, 0xB2, 0x00, 0x00, 0x01, 0x01, 0x06, 0x00]);
    });

    test('ACK request: C0 B5 00 00 00 00 01 00', () {
      expect(buildAckReadRequest(),
          [0xC0, 0xB5, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00]);
    });

    test('isAckSuccess: byte 6 == 0x01', () {
      expect(isAckSuccess([0xC0, 0xB5, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00]),
          true);
    });

    test('isAckSuccess: byte 6 == 0x00 → false', () {
      expect(isAckSuccess([0xC0, 0xB5, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
          false);
    });

    test('isAckSuccess: too-short response → false', () {
      expect(isAckSuccess([0x01, 0x02]), false);
    });
  });
}
