import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

class Icp5SerialDevice {
  final String portName;
  final int? vendorId;
  final int? productId;
  final String? productName;
  final String? friendlyName;
  final String? instanceId;
  final String? serialNumber;
  final int? rssi;
  final String enumerationSource;

  const Icp5SerialDevice(
      {required this.portName,
      this.vendorId,
      this.productId,
      this.productName,
      this.friendlyName,
      this.instanceId,
      this.serialNumber,
      this.rssi,
      this.enumerationSource = 'unknown'});

  static final RegExp _comPattern =
      RegExp(r'\((COM\d+)\)', caseSensitive: false);
  static String? extractComPort(String? friendlyName) =>
      _comPattern.firstMatch(friendlyName ?? '')?.group(1)?.toUpperCase();

  bool get hasExactInstanceId {
    final normalized = instanceId?.toUpperCase() ?? '';
    return normalized.contains(r'VID_1A86&PID_55D6');
  }

  bool get hasSecondaryIdentity {
    final normalized =
        '${friendlyName ?? ''} ${productName ?? ''}'.toUpperCase();
    return normalized.contains('USB-BLE-SERIAL') &&
        normalized.contains('CH9143');
  }

  bool get isCaptureProvenIcp5 =>
      hasExactInstanceId ||
      (vendorId == 0x1A86 && productId == 0x55D6 && hasSecondaryIdentity);
}

class Icp5DiscoveryResult {
  final String source;
  final List<Icp5SerialDevice> allPorts;
  final List<Icp5SerialDevice> matches;
  final String? error;
  const Icp5DiscoveryResult(
      {required this.source,
      required this.allPorts,
      required this.matches,
      this.error});
  int get candidateCount => allPorts.length;
}

abstract interface class Icp5SerialConnection {
  Stream<List<int>> get bytes;
  Future<int> write(List<int> bytes, Duration timeout);
  Future<void> close();
}

abstract interface class Icp5SerialDriver {
  bool get platformSupported;
  Future<Icp5DiscoveryResult> discover();
  Future<Icp5SerialConnection> open(String portName);
}

class WindowsIcp5SerialDriver implements Icp5SerialDriver {
  static const _channel = MethodChannel('tunai/icp5_serial');
  @override
  bool get platformSupported => Platform.isWindows;

  @override
  Future<Icp5DiscoveryResult> discover() async {
    const source = 'Windows SetupAPI Ports class';
    if (!platformSupported) {
      return const Icp5DiscoveryResult(
          source: source,
          allPorts: [],
          matches: [],
          error: 'Windows SetupAPI discovery is unavailable on this platform.');
    }
    try {
      final raw = await _channel.invokeMethod<Map>('list_ports');
      final map = Map<Object?, Object?>.from(raw ?? const {});
      final ports = (map['ports'] as List? ?? const [])
          .map((entry) {
            final item = Map<Object?, Object?>.from(entry as Map);
            final friendly = item['friendlyName'] as String?;
            final instance = item['instanceId'] as String?;
            final portName = (item['portName'] as String?)?.toUpperCase() ??
                Icp5SerialDevice.extractComPort(friendly) ??
                '';
            final upperInstance = instance?.toUpperCase() ?? '';
            int? parseId(String marker) {
              final match =
                  RegExp('$marker([0-9A-F]{4})').firstMatch(upperInstance);
              return match == null
                  ? null
                  : int.tryParse(match.group(1)!, radix: 16);
            }

            final serial = instance?.split(r'\').lastOrNull;
            return Icp5SerialDevice(
                portName: portName,
                vendorId: parseId('VID_'),
                productId: parseId('PID_'),
                productName: item['description'] as String?,
                friendlyName: friendly,
                instanceId: instance,
                serialNumber: serial,
                enumerationSource: item['source'] as String? ?? source);
          })
          .where((device) => RegExp(r'^COM\d+$', caseSensitive: false)
              .hasMatch(device.portName))
          .toList(growable: false);

      for (final device in ports) {
        debugPrint('[ICP5 Discovery] candidate port=${device.portName} '
            'friendly=${device.friendlyName ?? '-'} instanceId=${device.instanceId ?? '-'} '
            'vidPidMatch=${device.isCaptureProvenIcp5}');
      }
      final matches = ports
          .where((device) => device.isCaptureProvenIcp5)
          .toList(growable: false);
      debugPrint(
          '[ICP5 Discovery] selected=${matches.firstOrNull?.portName ?? 'none'} '
          'source=$source candidates=${ports.length}');
      return Icp5DiscoveryResult(
          source: source,
          allPorts: ports,
          matches: matches,
          error: matches.isEmpty
              ? 'No VID_1A86&PID_55D6 ICP5 device found via $source; ${ports.length} candidate port(s) enumerated.'
              : null);
    } on PlatformException catch (error) {
      final message =
          '$source failed: ${error.message ?? error.code}; 0 candidate ports found.';
      debugPrint('[ICP5 Discovery] failure=$message');
      return Icp5DiscoveryResult(
          source: source,
          allPorts: const [],
          matches: const [],
          error: message);
    } catch (error) {
      final message = '$source failed: $error; 0 candidate ports found.';
      debugPrint('[ICP5 Discovery] failure=$message');
      return Icp5DiscoveryResult(
          source: source,
          allPorts: const [],
          matches: const [],
          error: message);
    }
  }

  @override
  Future<Icp5SerialConnection> open(String portName) async {
    if (!platformSupported) {
      throw UnsupportedError('ICP5 USB Phase B is Windows-only.');
    }
    final port = SerialPort(portName);
    if (!port.openReadWrite()) {
      final error = SerialPort.lastError;
      port.dispose();
      throw StateError(
          'Cannot exclusively open $portName: ${error?.message ?? 'unknown serial error'}');
    }
    final config = SerialPortConfig()
      ..baudRate = 115200
      ..bits = 8
      ..parity = SerialPortParity.none
      ..stopBits = 1;
    port.config = config;
    config.dispose();
    return _LibSerialConnection(port);
  }
}

/// ICP5 USB serial driver for macOS.
///
/// Enumerates `/dev/cu.*` serial ports via flutter_libserialport and matches the
/// ICP5 bridge by VID 0x1A86 / PID 0x55D6. Windows discovery/open remains in
/// [WindowsIcp5SerialDriver]; this class adds a parallel macOS path and does not
/// alter the Windows driver, the ICP5 protocol, or the frame codec.
///
/// Enumeration, platform detection, and open are injectable seams so the
/// discovery/matching logic is testable without the native serial library.
class MacIcp5SerialDriver implements Icp5SerialDriver {
  static const int icp5VendorId = 0x1A86;
  static const int icp5ProductId = 0x55D6;
  static const String _source = 'macOS libserialport (/dev/cu.*)';

  final bool Function() _isMac;
  final List<Icp5SerialDevice> Function() _enumerate;
  final Future<Icp5SerialConnection> Function(String portName)? _openOverride;

  MacIcp5SerialDriver({
    bool Function()? isMacOsOverride,
    List<Icp5SerialDevice> Function()? enumeratePorts,
    Future<Icp5SerialConnection> Function(String portName)? openPort,
  })  : _isMac = isMacOsOverride ?? (() => Platform.isMacOS),
        _enumerate = enumeratePorts ?? _enumerateLibSerialPorts,
        _openOverride = openPort;

  @override
  bool get platformSupported => _isMac();

  /// CH34x bridge cu.* name patterns used as a macOS fallback when
  /// libserialport reports null VID/PID (common on macOS for the WCH CH34x).
  static bool _isCh34xPortName(String portName) =>
      portName.startsWith('/dev/cu.wchusbserial') ||
      portName.startsWith('/dev/cu.usbserial');

  static bool _isIcp5(Icp5SerialDevice d) {
    // Prefer VID/PID whenever libserialport provides them: a device that
    // reports a *different* VID/PID is rejected (fail-closed, no name fallback).
    if (d.vendorId != null && d.productId != null) {
      return d.vendorId == icp5VendorId && d.productId == icp5ProductId;
    }
    // macOS often returns null VID/PID for the CH34x bridge (system_profiler
    // still confirms 0x1A86/0x55D6). Fall back to the WCH/CH34x cu.* name.
    return _isCh34xPortName(d.portName);
  }

  @override
  Future<Icp5DiscoveryResult> discover() async {
    if (!platformSupported) {
      return const Icp5DiscoveryResult(
          source: _source,
          allPorts: [],
          matches: [],
          error: 'macOS serial discovery is unavailable on this platform.');
    }
    try {
      final ports = _enumerate();
      for (final d in ports) {
        debugPrint('[ICP5 Discovery] candidate port=${d.portName} '
            'vid=${d.vendorId?.toRadixString(16) ?? '-'} '
            'pid=${d.productId?.toRadixString(16) ?? '-'} match=${_isIcp5(d)}');
      }
      final matches = ports.where(_isIcp5).toList(growable: false);
      debugPrint(
          '[ICP5 Discovery] selected=${matches.firstOrNull?.portName ?? 'none'} '
          'source=$_source candidates=${ports.length}');
      return Icp5DiscoveryResult(
          source: _source,
          allPorts: ports,
          matches: matches,
          error: matches.isEmpty
              ? 'No VID_1A86&PID_55D6 ICP5 device found via $_source; '
                  '${ports.length} candidate port(s) enumerated.'
              : null);
    } catch (error) {
      final message = '$_source failed: $error; 0 candidate ports found.';
      debugPrint('[ICP5 Discovery] failure=$message');
      return Icp5DiscoveryResult(
          source: _source,
          allPorts: const [],
          matches: const [],
          error: message);
    }
  }

  @override
  Future<Icp5SerialConnection> open(String portName) async {
    if (!platformSupported) {
      throw UnsupportedError(
          'ICP5 USB macOS serial driver is unavailable on this platform.');
    }
    if (_openOverride != null) return _openOverride!(portName);
    debugPrint('[ICP5 mac lifecycle] OPEN port=$portName');
    final port = SerialPort(portName);
    if (!port.openReadWrite()) {
      final error = SerialPort.lastError;
      port.dispose();
      throw StateError(
          'Cannot open $portName: ${error?.message ?? 'unknown serial error'}');
    }
    // Configure the port. OWNERSHIP: `SerialPort.config =` transfers ownership
    // of the SerialPortConfig to the port — the port frees it in
    // `SerialPort.dispose()` (libserialport `set config` stores it; `dispose`
    // calls `_config?.dispose()`). We therefore must NOT dispose the config
    // ourselves; doing so was a double-free (sp_free_config abort on macOS).
    // If configuration throws, `port.dispose()` frees any owned config exactly
    // once. The only single owner of both the port and its config is [port]
    // (and, after this returns, [_MacSerialConnection] via [close]).
    try {
      final config = SerialPortConfig()
        ..baudRate = 115200
        ..bits = 8
        ..parity = SerialPortParity.none
        ..stopBits = 1;
      port.config = config; // port now owns `config`; do not dispose it here.
    } catch (error) {
      try {
        port.close();
      } catch (_) {}
      try {
        port.dispose(); // frees the port and any config it took ownership of
      } catch (_) {}
      throw StateError('Cannot configure $portName: $error');
    }
    return _MacSerialConnection(port);
  }

  /// Default enumeration: `/dev/cu.*` ports with VID/PID from libserialport.
  static List<Icp5SerialDevice> _enumerateLibSerialPorts() {
    final out = <Icp5SerialDevice>[];
    for (final name in SerialPort.availablePorts) {
      if (!name.startsWith('/dev/cu.')) continue;
      final p = SerialPort(name);
      int? vid;
      int? pid;
      String? product;
      String? manufacturer;
      String? serial;
      try {
        vid = p.vendorId;
        pid = p.productId;
        product = p.productName;
        manufacturer = p.manufacturer;
        serial = p.serialNumber;
      } catch (_) {
        // Port busy or info unavailable — still list it as a candidate.
      } finally {
        p.dispose();
      }
      out.add(Icp5SerialDevice(
        portName: name,
        vendorId: vid,
        productId: pid,
        productName: product,
        friendlyName: manufacturer,
        serialNumber: serial,
        enumerationSource: _source,
      ));
    }
    return out;
  }
}

/// Platform-appropriate ICP5 USB serial driver. macOS uses
/// [MacIcp5SerialDriver]; all other platforms keep [WindowsIcp5SerialDriver]
/// unchanged.
Icp5SerialDriver defaultIcp5UsbSerialDriver() =>
    Platform.isMacOS ? MacIcp5SerialDriver() : WindowsIcp5SerialDriver();

/// Hardened macOS ICP5 serial connection.
///
/// Bridges the flutter_libserialport [SerialPortReader] through a single owned
/// [StreamController] so the transport never subscribes to (or tears down) the
/// reader isolate directly. This prevents the double-teardown / callback-after-
/// dispose race that surfaced as `dart::Message::~Message()` (EXC_BAD_ACCESS)
/// during connect/handshake. Guards:
///  - a single reader subscription (no duplicate listeners),
///  - `_closed` gate so no native callback is delivered after dispose,
///  - idempotent, exception-safe [close] with reader-before-port teardown.
/// Windows keeps using [_LibSerialConnection] unchanged.
class _MacSerialConnection implements Icp5SerialConnection {
  /// Reader poll timeout. The libserialport reader runs a background isolate
  /// looping on `sp_wait(timeout)` over the raw `sp_port*`. `Isolate.kill()`
  /// cannot interrupt a blocking native `sp_wait`, so a *short* timeout is what
  /// lets the isolate promptly observe a closed port and exit its loop.
  static const int _readerPollTimeoutMs = 50;

  /// Settle window AFTER `sp_close` (so `sp_input_waiting` returns < 0 and the
  /// isolate loop exits) and BEFORE `sp_free_port`. Comfortably exceeds
  /// [_readerPollTimeoutMs] so the isolate has left the loop before the native
  /// port struct is freed — this is what prevents the EXC_BAD_ACCESS.
  static const Duration _readerExitSettle = Duration(milliseconds: 250);

  final SerialPort _port;
  SerialPortReader? _reader;
  StreamController<List<int>>? _controller;
  StreamSubscription<Uint8List>? _readerSub;
  bool _closed = false;
  bool _lateCallbackLogged = false;

  _MacSerialConnection(this._port);

  @override
  Stream<List<int>> get bytes {
    // Return the same controller stream on every access — never start a second
    // reader isolate / listener.
    final existing = _controller;
    if (existing != null) return existing.stream;

    final controller = StreamController<List<int>>();
    _controller = controller;
    // Short poll timeout so the reader isolate can exit quickly on close.
    final reader = SerialPortReader(_port, timeout: _readerPollTimeoutMs);
    _reader = reader;
    debugPrint('[ICP5 mac lifecycle] READER_START');
    _readerSub = reader.stream.listen(
      (data) {
        if (_closed || controller.isClosed) {
          if (!_lateCallbackLogged) {
            _lateCallbackLogged = true;
            debugPrint('[ICP5 mac lifecycle] LATE_CALLBACK_DROPPED');
          }
          return; // never touch a closing/closed controller
        }
        controller.add(data.toList());
      },
      onError: (Object error, StackTrace stack) {
        if (_closed || controller.isClosed) {
          if (!_lateCallbackLogged) {
            _lateCallbackLogged = true;
            debugPrint('[ICP5 mac lifecycle] LATE_CALLBACK_DROPPED');
          }
          return;
        }
        controller.addError(error, stack);
      },
      onDone: () {
        if (!controller.isClosed) controller.close();
      },
      cancelOnError: false,
    );
    return controller.stream;
  }

  @override
  Future<int> write(List<int> bytes, Duration timeout) async {
    if (_closed) {
      throw StateError('ICP5 serial port is closed.');
    }
    try {
      return await Future<int>(() => _port.write(
          Uint8List.fromList(bytes),
          timeout: timeout.inMilliseconds));
    } catch (error) {
      // Convert a native write fault into a catchable async error rather than
      // letting it escape as an unhandled exception on a worker isolate.
      throw StateError('ICP5 serial write failed: $error');
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return; // idempotent — never double close/dispose
    _closed = true;
    debugPrint('[ICP5 mac lifecycle] CLOSE_REQUEST');

    // 1. Cancel our subscription. This fires the reader controller's onCancel
    //    (_cancelRead → ReceivePort.close + Isolate.kill request).
    try {
      await _readerSub?.cancel();
    } catch (_) {}
    _readerSub = null;
    debugPrint('[ICP5 mac lifecycle] SUB_CANCEL');

    // 2. Close the reader's own stream controller.
    try {
      _reader?.close();
    } catch (_) {}
    _reader = null;
    debugPrint('[ICP5 mac lifecycle] READER_CLOSE');

    // 3. Close the native OS handle FIRST. sp_close makes the isolate's next
    //    sp_input_waiting() return < 0, so its `while (bytes >= 0)` loop exits
    //    and the isolate terminates — WITHOUT freeing the struct it still reads.
    try {
      _port.close();
    } catch (_) {}
    debugPrint('[ICP5 mac lifecycle] PORT_CLOSE');

    // 4. Wait for the isolate to leave its loop (> poll timeout) before freeing
    //    the native port struct. This ordering is the crash fix.
    await Future<void>.delayed(_readerExitSettle);

    // 5. Close our controller so downstream listeners complete cleanly.
    try {
      final controller = _controller;
      if (controller != null && !controller.isClosed) {
        await controller.close();
      }
    } catch (_) {}
    _controller = null;

    // 6. Now free the native port struct — the reader isolate is gone.
    try {
      _port.dispose();
    } catch (_) {}
    debugPrint('[ICP5 mac lifecycle] PORT_DISPOSE');
  }
}

class _LibSerialConnection implements Icp5SerialConnection {
  final SerialPort _port;
  late final SerialPortReader _reader = SerialPortReader(_port);
  _LibSerialConnection(this._port);
  @override
  Stream<List<int>> get bytes => _reader.stream.map((data) => data.toList());
  @override
  Future<int> write(List<int> bytes, Duration timeout) => Future<int>(() =>
      _port.write(Uint8List.fromList(bytes), timeout: timeout.inMilliseconds));
  @override
  Future<void> close() async {
    _reader.close();
    _port.close();
    _port.dispose();
  }
}
