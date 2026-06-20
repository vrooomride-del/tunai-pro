import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ICP5(WONDOM) BLE GATT UUID — GATT 덤프로 확인된 실제 값
class _ICP5UUID {
  static const String service  = 'fff0';
  static const String dspWrite = 'fff2'; // WRITE|WRITE_NO_RSP
}

enum ConnectMode { uart, ble }

enum ConnectionStatus { disconnected, scanning, connecting, connected, error }

class ConnectState {
  final ConnectMode mode;
  final List<String> ports;
  final String? selectedPort;
  final ConnectionStatus connection;
  final String status;
  final String? deviceName;

  const ConnectState({
    this.mode = ConnectMode.uart,
    this.ports = const [],
    this.selectedPort,
    this.connection = ConnectionStatus.disconnected,
    this.status = 'READY',
    this.deviceName,
  });

  bool get connected => connection == ConnectionStatus.connected;

  ConnectState copyWith({
    ConnectMode? mode,
    List<String>? ports,
    String? selectedPort,
    ConnectionStatus? connection,
    String? status,
    String? deviceName,
  }) => ConnectState(
    mode: mode ?? this.mode,
    ports: ports ?? this.ports,
    selectedPort: selectedPort ?? this.selectedPort,
    connection: connection ?? this.connection,
    status: status ?? this.status,
    deviceName: deviceName ?? this.deviceName,
  );
}

final connectProvider = StateNotifierProvider<ConnectController, ConnectState>(
  (ref) => ConnectController(),
);

class ConnectController extends StateNotifier<ConnectState> {
  ConnectController() : super(const ConnectState()) {
    scanPorts();
  }

  // UART
  SerialPort? _port;

  // BLE
  BluetoothDevice? _bleDevice;
  BluetoothCharacteristic? _bleWriteChar;

  static const List<String> _bleTargetNames = [
    'ICP5', 'icp5', 'TUNAI', 'tunai', 'BT_AUDIO', 'WONDOM',
  ];

  // ── 모드 전환 ────────────────────────────────────────────────────────────

  void setMode(ConnectMode mode) {
    if (state.connected) return;
    state = state.copyWith(mode: mode, status: 'READY');
  }

  // ── UART ─────────────────────────────────────────────────────────────────

  // macOS 시스템 가상 포트 — DSP 연결과 무관, 자동 선택 후보에서 제외
  static const _kSystemPortPatterns = [
    'Bluetooth-Incoming-Port',
    'Bluetooth-Modem',
    'debug-console',
  ];

  // ICP5/CH34x 실제 디바이스 포트 패턴 (우선 자동 선택)
  static const _kPreferredPatterns = [
    'usbserial',   // CH340/CH341/FTDI macOS 드라이버
    'wchusbserial', // CH34x 공식 드라이버
    'usbmodem',    // CDC ACM
    'cu.ICP',
    'cu.TUNAI',
    'cu.WONDOM',
  ];

  static bool _isSystemPort(String port) =>
      _kSystemPortPatterns.any((p) => port.contains(p));

  static bool _isPreferredPort(String port) =>
      _kPreferredPatterns.any((p) => port.toLowerCase().contains(p.toLowerCase()));

  void scanPorts() {
    final all = SerialPort.availablePorts;

    // 시스템 가상 포트 제외
    final filtered = all.where((p) => !_isSystemPort(p)).toList();

    // 현재 선택 포트 유지 (필터된 목록에 있으면)
    String? selected = state.selectedPort != null && filtered.contains(state.selectedPort)
        ? state.selectedPort : null;

    // 자동 선택: 선호 패턴이 정확히 1개 → 자동 선택, 여러 개면 null 유지(수동 선택)
    if (selected == null) {
      final preferred = filtered.where(_isPreferredPort).toList();
      if (preferred.length == 1) selected = preferred.first;
    }

    state = state.copyWith(ports: filtered, selectedPort: selected);
  }

  void selectPort(String port) {
    state = state.copyWith(selectedPort: port);
  }

  Future<void> connectUart() async {
    if (state.selectedPort == null) return;
    try {
      _port?.close();
      _port = SerialPort(state.selectedPort!);
      final config = SerialPortConfig();
      config.baudRate = 38400;
      config.bits = 8;
      config.stopBits = 1;
      config.parity = SerialPortParity.none;
      if (!_port!.openReadWrite()) throw Exception('포트 열기 실패');
      _port!.config = config;
      state = state.copyWith(
        connection: ConnectionStatus.connected,
        status: 'CONNECTED',
        deviceName: state.selectedPort,
      );
    } catch (e) {
      state = state.copyWith(
        connection: ConnectionStatus.error,
        status: 'ERROR: $e',
      );
    }
  }

  void disconnectUart() {
    _port?.close();
    _port = null;
    state = state.copyWith(
      connection: ConnectionStatus.disconnected,
      status: 'READY',
      deviceName: null,
    );
  }

  // ── BLE ──────────────────────────────────────────────────────────────────

  Future<void> scanAndConnectBle() async {
    state = state.copyWith(
      connection: ConnectionStatus.scanning,
      status: 'ICP5 스캔 중...',
    );

    try {
      // macOS: CBManagerState가 unknown → on으로 전환될 때까지 대기 (최대 5초)
      await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 5));

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

      BluetoothDevice? found;
      await for (final results in FlutterBluePlus.scanResults) {
        for (final r in results) {
          if (_bleTargetNames.any((n) => r.device.advName.contains(n))) {
            found = r.device;
            break;
          }
        }
        if (found != null) break;
        if (!FlutterBluePlus.isScanningNow) break;
      }
      await FlutterBluePlus.stopScan();

      if (found == null) {
        state = state.copyWith(
          connection: ConnectionStatus.error,
          status: 'ICP5를 찾을 수 없습니다',
        );
        return;
      }

      state = state.copyWith(
        connection: ConnectionStatus.connecting,
        status: '${found.advName} 연결 중...',
      );

      await found.connect(timeout: const Duration(seconds: 10));
      _bleDevice = found;

      final services = await found.discoverServices();

      // DEBUG
      debugPrint('══ GATT dump: ${found.advName} ══');
      for (final s in services) {
        debugPrint('  SERVICE: ${s.uuid}');
        for (final c in s.characteristics) {
          debugPrint('    CHAR: ${c.uuid}  [${_propStr(c)}]');
        }
      }
      debugPrint('══════════════════════════════════════');

      for (final s in services) {
        if (s.uuid.str128.contains(_ICP5UUID.service)) {
          for (final c in s.characteristics) {
            if (c.uuid.str128.contains(_ICP5UUID.dspWrite)) {
              _bleWriteChar = c;
            }
          }
        }
      }

      if (_bleWriteChar == null) {
        throw Exception('DSP Write 캐릭터리스틱을 찾을 수 없습니다 (fff2)');
      }

      state = state.copyWith(
        connection: ConnectionStatus.connected,
        status: 'CONNECTED (BLE)',
        deviceName: found.advName,
      );

      found.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          _bleDevice = null;
          _bleWriteChar = null;
          state = state.copyWith(
            connection: ConnectionStatus.disconnected,
            status: 'READY',
            deviceName: null,
          );
        }
      });
    } catch (e) {
      debugPrint('BLE connect error: $e');
      state = state.copyWith(
        connection: ConnectionStatus.error,
        status: 'ERROR: $e',
      );
    }
  }

  Future<void> disconnectBle() async {
    await _bleDevice?.disconnect();
    _bleDevice = null;
    _bleWriteChar = null;
    state = state.copyWith(
      connection: ConnectionStatus.disconnected,
      status: 'READY',
      deviceName: null,
    );
  }

  // ── 공통 인터페이스 (dsp_controller가 사용) ───────────────────────────────

  Future<void> connect() async {
    if (state.mode == ConnectMode.ble) {
      await scanAndConnectBle();
    } else {
      await connectUart();
    }
  }

  void disconnect() {
    if (state.mode == ConnectMode.ble) {
      disconnectBle();
    } else {
      disconnectUart();
    }
  }

  Future<bool> sendBytes(List<int> bytes) async {
    if (!state.connected) return false;
    try {
      if (state.mode == ConnectMode.ble && _bleWriteChar != null) {
        await _bleWriteChar!.write(
          Uint8List.fromList(bytes),
          withoutResponse: true,
        );
        await Future.delayed(const Duration(milliseconds: 50));
        return true;
      } else if (_port != null) {
        final written = _port!.write(Uint8List.fromList(bytes), timeout: 500);
        return written == bytes.length;
      }
    } catch (e) {
      debugPrint('sendBytes error: $e');
    }
    return false;
  }

  String _propStr(BluetoothCharacteristic c) => [
    if (c.properties.read) 'READ',
    if (c.properties.write) 'WRITE',
    if (c.properties.writeWithoutResponse) 'WRITE_NO_RSP',
    if (c.properties.notify) 'NOTIFY',
    if (c.properties.indicate) 'INDICATE',
  ].join('|');

  @override
  void dispose() {
    _port?.close();
    _bleDevice?.disconnect();
    super.dispose();
  }
}
