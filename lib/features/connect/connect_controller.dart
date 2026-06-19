import 'dart:async';
import 'dart:io';
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

  void scanPorts() {
    final ports = SerialPort.availablePorts;
    state = state.copyWith(
      ports: ports,
      selectedPort: state.selectedPort != null && ports.contains(state.selectedPort)
          ? state.selectedPort : null,
    );
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
