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

class ProUsbiWindowsNativeBackend
    implements ProUsbiNativeBackend, ProUsbiTransactionDiagnosticsProvider {
  static const _channel = MethodChannel('tunai/usbi');

  UsbiWindowsStatus _status = UsbiWindowsStatus.unavailable;
  bool _connected = false;
  String? _lastError;
  UsbiNativeTransactionDiagnostics? _lastTransactionDiagnostics;

  UsbiWindowsStatus get status => _status;
  bool get isConnected => _connected;
  String? get lastError => _lastError;

  @override
  UsbiNativeTransactionDiagnostics? get lastTransactionDiagnostics =>
      _lastTransactionDiagnostics;

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
    void record({
      bool? setupSuccess,
      bool? bodySuccess,
      int? transferred,
      bool? ackSuccess,
      int? ackTransferred,
      List<int>? rawAck,
      String? transferError,
      String? ackError,
      String? nativeException,
      int? setupElapsedMs,
      int? ackElapsedMs,
    }) {
      _lastTransactionDiagnostics = UsbiNativeTransactionDiagnostics(
        setupPacket: List<int>.from(setupPacket),
        bodyPacket: List<int>.from(bodyPacket),
        ackRequestPacket: List<int>.from(ackReadRequest),
        setupTransferSuccess: setupSuccess,
        bodyTransferSuccess: bodySuccess,
        bytesTransferred: transferred,
        ackReadSuccess: ackSuccess,
        ackBytesTransferred: ackTransferred,
        rawAckBytes: rawAck == null ? null : List<int>.from(rawAck),
        transferError: transferError,
        ackReadError: ackError,
        nativeException: nativeException,
        setupElapsedMilliseconds: setupElapsedMs,
        ackElapsedMilliseconds: ackElapsedMs,
      );
    }

    if (!Platform.isWindows || !_connected) {
      const error = 'Backend is not connected on Windows.';
      record(transferError: error);
      _lastError = error;
      return null;
    }

    // Phase 1: send setup + body as single control OUT transfer
    final setupWatch = Stopwatch()..start();
    int? transferred;
    try {
      final setupRes = await _channel.invokeMethod<Map>('usbi_send_setup', {
        'setup': setupPacket,
        'body':  bodyPacket,
      });
      final setupMap = Map<String, dynamic>.from(setupRes ?? {});
      setupWatch.stop();
      transferred = setupMap['transferred'] as int?;
      if (setupMap['success'] != true) {
        _lastError = setupMap['error'] as String? ?? 'Setup transfer failed';
        record(
          setupSuccess: false,
          bodySuccess: false,
          transferred: transferred,
          transferError: _lastError,
          setupElapsedMs: setupWatch.elapsedMilliseconds,
        );
        return null;
      }
    } on PlatformException catch (e) {
      setupWatch.stop();
      _lastError = e.message;
      record(
        setupSuccess: false,
        bodySuccess: false,
        transferred: transferred,
        transferError: e.message,
        nativeException: '${e.code}: ${e.message ?? "PlatformException"}',
        setupElapsedMs: setupWatch.elapsedMilliseconds,
      );
      return null;
    }

    // Phase 2: read ACK
    final ackWatch = Stopwatch()..start();
    try {
      final ackRes = await _channel.invokeMethod<Map>('usbi_read_ack', {
        'ack_request': ackReadRequest,
      });
      final ackMap = Map<String, dynamic>.from(ackRes ?? {});
      ackWatch.stop();
      if (ackMap['success'] != true) {
        _lastError = ackMap['error'] as String? ?? 'ACK read failed';
        record(
          setupSuccess: true,
          bodySuccess: true,
          transferred: transferred,
          ackSuccess: false,
          ackTransferred: ackMap['transferred'] as int?,
          ackError: _lastError,
          setupElapsedMs: setupWatch.elapsedMilliseconds,
          ackElapsedMs: ackWatch.elapsedMilliseconds,
        );
        return null;
      }
      final ackBytes = (ackMap['ack'] as List?)?.cast<int>();
      record(
        setupSuccess: true,
        bodySuccess: true,
        transferred: transferred,
        ackSuccess: true,
        ackTransferred: ackMap['transferred'] as int? ?? ackBytes?.length,
        rawAck: ackBytes,
        setupElapsedMs: setupWatch.elapsedMilliseconds,
        ackElapsedMs: ackWatch.elapsedMilliseconds,
      );
      _lastError = null;
      return ackBytes;
    } on PlatformException catch (e) {
      ackWatch.stop();
      _lastError = e.message;
      record(
        setupSuccess: true,
        bodySuccess: true,
        transferred: transferred,
        ackSuccess: false,
        ackError: e.message,
        nativeException: '${e.code}: ${e.message ?? "PlatformException"}',
        setupElapsedMs: setupWatch.elapsedMilliseconds,
        ackElapsedMs: ackWatch.elapsedMilliseconds,
      );
      return null;
    }
  }
}
