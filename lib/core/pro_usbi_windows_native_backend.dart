// ── TUNAI PRO Phase T4C — Windows USBi WinUSB Native Backend ─────────────────
// Real Windows MethodChannel backend for ADI USBi temporary engineering path.
//
// Channel: "tunai/usbi"  (must match usbi_channel.cpp)
// ADI USBi VID: 0x0456. PID may vary.
//
// ABSOLUTE RESTRICTIONS:
//   - Windows only. Non-Windows returns isAvailable = false.
//   - No auto-write. sendPacketsAndReadAck only called by executor after guards.
//   - Do NOT fake success. All errors propagate to caller.
//   - USBi is TEMPORARY. ICP5 is the final target.
//   - isConnected = true only after successful usbi_open_device.

import 'dart:io';
import 'package:flutter/services.dart';
import 'pro_usbi_native_backend.dart';

// ── Status enum ───────────────────────────────────────────────────────────────

enum UsbiWindowsStatus {
  unavailable,
  pending,
  deviceDetected,
  connected,
  accessDenied,
  error;

  bool get isReady => this == connected;
}

// ── Backend ───────────────────────────────────────────────────────────────────

class ProUsbiWindowsNativeBackend implements ProUsbiNativeBackend {
  static const _channel = MethodChannel('tunai/usbi');

  UsbiWindowsStatus _status = UsbiWindowsStatus.unavailable;
  bool _connected = false;
  String? _lastError;

  UsbiWindowsStatus get status => _status;
  bool get isConnected => _connected;
  String? get lastError => _lastError;

  @override
  bool get isAvailable {
    if (!Platform.isWindows) return false;
    return _status != UsbiWindowsStatus.unavailable;
  }

  @override
  bool get isFake => false;

  // ── Initialise — check native channel availability ───────────────────────

  Future<void> initialise() async {
    if (!Platform.isWindows) {
      _status = UsbiWindowsStatus.unavailable;
      return;
    }
    try {
      final ok = await _channel.invokeMethod<bool>('usbi_is_available');
      _status = (ok == true)
          ? UsbiWindowsStatus.pending
          : UsbiWindowsStatus.unavailable;
    } on PlatformException catch (e) {
      _status = UsbiWindowsStatus.error;
      _lastError = e.message;
    }
  }

  // ── List devices ─────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listDevices() async {
    if (!Platform.isWindows) return [];
    try {
      final raw = await _channel.invokeMethod<List>('usbi_list_devices');
      if (raw == null) return [];
      return raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } on PlatformException catch (e) {
      _lastError = e.message;
      return [];
    }
  }

  // ── Open device ───────────────────────────────────────────────────────────

  Future<({bool success, String? error})> openDevice() async {
    if (!Platform.isWindows) {
      return (success: false, error: 'Not Windows.');
    }
    try {
      final raw = await _channel.invokeMethod<Map>('usbi_open_device');
      final res = Map<String, dynamic>.from(raw ?? {});
      final ok  = res['success'] as bool? ?? false;
      if (ok) {
        _connected = true;
        _status    = UsbiWindowsStatus.connected;
        _lastError = null;
      } else {
        final err = res['error'] as String? ?? 'Unknown error';
        _lastError = err;
        _status    = err.toLowerCase().contains('denied') ||
                     err.toLowerCase().contains('zadig')
            ? UsbiWindowsStatus.accessDenied
            : UsbiWindowsStatus.error;
      }
      return (success: ok, error: _lastError);
    } on PlatformException catch (e) {
      _lastError = e.message;
      _status    = UsbiWindowsStatus.error;
      return (success: false, error: e.message);
    }
  }

  // ── Close device ──────────────────────────────────────────────────────────

  Future<void> closeDevice() async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<Map>('usbi_close');
    } on PlatformException {
      // ignore close errors
    } finally {
      _connected = false;
      _status    = UsbiWindowsStatus.pending;
    }
  }

  // ── sendPacketsAndReadAck — ProUsbiNativeBackend contract ─────────────────
  //
  // Called exclusively by ProUsbiTemporaryExecutor after all 7 guards pass.
  // Sends setup+body via usbi_send_setup (single control transfer),
  // then reads ACK via usbi_read_ack.
  // Returns raw ACK bytes on success, null on any transport error.

  @override
  Future<List<int>?> sendPacketsAndReadAck({
    required List<int> setupPacket,
    required List<int> bodyPacket,
    required List<int> ackReadRequest,
  }) async {
    if (!Platform.isWindows || !_connected) return null;

    // Phase 1: send setup + body as single control OUT transfer
    try {
      final setupRes = await _channel.invokeMethod<Map>('usbi_send_setup', {
        'setup': setupPacket,
        'body':  bodyPacket,
      });
      final setupMap = Map<String, dynamic>.from(setupRes ?? {});
      if (setupMap['success'] != true) {
        _lastError = setupMap['error'] as String? ?? 'Setup transfer failed';
        return null;
      }
    } on PlatformException catch (e) {
      _lastError = e.message;
      return null;
    }

    // Phase 2: read ACK
    try {
      final ackRes = await _channel.invokeMethod<Map>('usbi_read_ack', {
        'ack_request': ackReadRequest,
      });
      final ackMap = Map<String, dynamic>.from(ackRes ?? {});
      if (ackMap['success'] != true) {
        _lastError = ackMap['error'] as String? ?? 'ACK read failed';
        return null;
      }
      final ackBytes = (ackMap['ack'] as List?)?.cast<int>();
      return ackBytes;
    } on PlatformException catch (e) {
      _lastError = e.message;
      return null;
    }
  }
}
