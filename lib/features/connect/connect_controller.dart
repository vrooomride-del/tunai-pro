import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/profiles/system_profile.dart';

// ICP5(WONDOM) BLE GATT UUID — GATT 덤프로 확인된 실제 값
class _ICP5UUID {
  static const String service  = 'fff0';
  static const String dspWrite = 'fff2'; // WRITE|WRITE_NO_RSP
}

enum ConnectMode { uart, ble }

enum ConnectionStatus { disconnected, scanning, connecting, connected, error }

/// 연결 후 보드 자동탐지 결과
enum DetectedBoard {
  icp5Adau1701, // ICP5 + fff0 서비스 → ADAU1701(JAB4)
  adau1466,     // 파란보드 패턴 → ADAU1466 (미지원)
  unknown,      // 식별 불가 → 수동 선택 유지
}

class ConnectState {
  final ConnectMode mode;
  final List<String> ports;
  final String? selectedPort;
  final ConnectionStatus connection;
  final String status;
  final String? deviceName;
  final DetectedBoard? detectedBoard;

  const ConnectState({
    this.mode = ConnectMode.uart,
    this.ports = const [],
    this.selectedPort,
    this.connection = ConnectionStatus.disconnected,
    this.status = 'READY',
    this.deviceName,
    this.detectedBoard,
  });

  bool get connected => connection == ConnectionStatus.connected;

  ConnectState copyWith({
    ConnectMode? mode,
    List<String>? ports,
    String? selectedPort,
    ConnectionStatus? connection,
    String? status,
    String? deviceName,
    DetectedBoard? detectedBoard,
  }) => ConnectState(
    mode: mode ?? this.mode,
    ports: ports ?? this.ports,
    selectedPort: selectedPort ?? this.selectedPort,
    connection: connection ?? this.connection,
    status: status ?? this.status,
    deviceName: deviceName ?? this.deviceName,
    detectedBoard: detectedBoard ?? this.detectedBoard,
  );
}

final connectProvider = StateNotifierProvider<ConnectController, ConnectState>(
  (ref) => ConnectController(ref),
);

class ConnectController extends StateNotifier<ConnectState> {
  final Ref _ref;
  ConnectController(this._ref) : super(const ConnectState()) {
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

  // 파란보드(ADAU1466) advName 패턴
  static const List<String> _adau1466Names = ['REFERENCE', 'TUNAI-REF', 'QCC5125', 'CS42448'];

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

  // USB 시리얼 칩 VID 목록 — ICP5(WONDOM)은 CH34x 탑재
  // VID 0x1A86: WinChipHead (CH340/CH341)
  // VID 0x0403: FTDI
  // VID 0x10C4: Silicon Labs (CP210x)
  // VID 0x067B: Prolific (PL2303)
  static const _kIcp5Vids = {0x1A86, 0x0403, 0x10C4, 0x067B};

  // CH34x 구체적 PID (VID 0x1A86 기준) — 이 PID이면 CH34x로 확신
  static const _kCh34xPids = {0x7523, 0x5523, 0x7522, 0x55D4};

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

      // VID/PID는 포트를 열기 전에 조회 가능 (libserialport가 OS USB 트리에서 읽음)
      final board = _detectBoardFromUart(_port!, state.selectedPort!);
      debugPrint('[BOARD] UART 탐지: $board  VID=${_port!.vendorId?.toRadixString(16)}  PID=${_port!.productId?.toRadixString(16)}  port=${state.selectedPort}');

      final config = SerialPortConfig();
      config.baudRate = 38400;
      config.bits = 8;
      config.stopBits = 1;
      config.parity = SerialPortParity.none;
      if (!_port!.openReadWrite()) throw Exception('포트 열기 실패');
      _port!.config = config;

      String connStatus;
      switch (board) {
        case DetectedBoard.icp5Adau1701:
          _ref.read(systemProfileProvider.notifier).state = kTunaiOneSystemProfile;
          connStatus = 'CONNECTED (UART · ADAU1701 자동 선택됨)';
        case DetectedBoard.adau1466:
          connStatus = 'CONNECTED (UART · ADAU1466 — 지원 준비 중)';
        case DetectedBoard.unknown:
          connStatus = 'CONNECTED (UART · 보드 미식별 — 수동 선택 필요)';
      }

      state = state.copyWith(
        connection: ConnectionStatus.connected,
        status: connStatus,
        deviceName: state.selectedPort,
        detectedBoard: board,
      );
    } catch (e) {
      state = state.copyWith(
        connection: ConnectionStatus.error,
        status: 'ERROR: $e',
      );
    }
  }

  /// UART 포트 이름 + VID/PID 기반 보드 탐지
  ///
  /// 우선순위: VID/PID(정확) → 포트 이름 패턴(추정)
  DetectedBoard _detectBoardFromUart(SerialPort port, String portName) {
    final vid = port.vendorId;
    final pid = port.productId;
    final name = portName.toLowerCase();

    // VID/PID로 판별 (가장 신뢰도 높음)
    if (vid != null) {
      if (_kIcp5Vids.contains(vid)) {
        // CH34x VID(0x1A86) + 알려진 PID이면 CH34x로 확신
        if (vid == 0x1A86 && pid != null && _kCh34xPids.contains(pid)) {
          return DetectedBoard.icp5Adau1701;
        }
        // 다른 USB 시리얼 칩 VID → ADAU1701로 추정 (ICP5 탑재 가능성 높음)
        return DetectedBoard.icp5Adau1701;
      }
      // 알 수 없는 VID → unknown (포트 이름 패턴도 시도)
    }

    // 포트 이름 패턴으로 폴백
    if (_isPreferredPort(portName)) return DetectedBoard.icp5Adau1701;

    // 파란보드 패턴 (UART 경로로 연결될 경우 대비)
    if (_adau1466Names.any((n) => name.contains(n.toLowerCase()))) {
      return DetectedBoard.adau1466;
    }

    return DetectedBoard.unknown;
  }

  void disconnectUart() {
    _port?.close();
    _port = null;
    state = state.copyWith(
      connection: ConnectionStatus.disconnected,
      status: 'READY',
      deviceName: null,
      detectedBoard: null,
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

      // ── 보드 자동탐지 ──────────────────────────────────────────────────────
      final board = _detectBoard(found.advName, services);
      debugPrint('[BOARD] 탐지 결과: $board (advName=${found.advName})');

      String connStatus;
      switch (board) {
        case DetectedBoard.icp5Adau1701:
          _ref.read(systemProfileProvider.notifier).state = kTunaiOneSystemProfile;
          connStatus = 'CONNECTED (BLE · ADAU1701 자동 선택됨)';
        case DetectedBoard.adau1466:
          connStatus = 'CONNECTED (BLE · ADAU1466 — 지원 준비 중)';
        case DetectedBoard.unknown:
          connStatus = 'CONNECTED (BLE · 보드 미식별 — 수동 선택 필요)';
      }
      // ────────────────────────────────────────────────────────────────────────

      state = state.copyWith(
        connection: ConnectionStatus.connected,
        status: connStatus,
        deviceName: found.advName,
        detectedBoard: board,
      );

      found.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          _bleDevice = null;
          _bleWriteChar = null;
          state = state.copyWith(
            connection: ConnectionStatus.disconnected,
            status: 'READY',
            deviceName: null,
            detectedBoard: null,
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

  DetectedBoard _detectBoard(String advName, List<BluetoothService> services) {
    final name = advName.toUpperCase();
    final hasFff0 = services.any((s) => s.uuid.str128.contains(_ICP5UUID.service));
    final isIcp5Name = _bleTargetNames.any((n) => name.contains(n.toUpperCase()));
    if (isIcp5Name && hasFff0) return DetectedBoard.icp5Adau1701;
    if (isIcp5Name) return DetectedBoard.icp5Adau1701;
    if (_adau1466Names.any((n) => name.contains(n.toUpperCase()))) return DetectedBoard.adau1466;
    return DetectedBoard.unknown;
  }

  Future<void> disconnectBle() async {
    await _bleDevice?.disconnect();
    _bleDevice = null;
    _bleWriteChar = null;
    state = state.copyWith(
      connection: ConnectionStatus.disconnected,
      status: 'READY',
      deviceName: null,
      detectedBoard: null,
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
