import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum UartConnectionState { disconnected, connected, error }

class ConnectState {
  final List<String> ports;
  final String? selectedPort;
  final UartConnectionState connection;
  final String status;

  const ConnectState({
    this.ports = const [],
    this.selectedPort,
    this.connection = UartConnectionState.disconnected,
    this.status = 'READY',
  });

  ConnectState copyWith({
    List<String>? ports,
    String? selectedPort,
    UartConnectionState? connection,
    String? status,
  }) => ConnectState(
    ports: ports ?? this.ports,
    selectedPort: selectedPort ?? this.selectedPort,
    connection: connection ?? this.connection,
    status: status ?? this.status,
  );
}

final connectProvider = StateNotifierProvider<ConnectController, ConnectState>(
  (ref) => ConnectController(),
);

class ConnectController extends StateNotifier<ConnectState> {
  ConnectController() : super(const ConnectState()) {
    scanPorts();
  }

  SerialPort? _port;

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

  Future<void> connect() async {
    if (state.selectedPort == null) return;
    try {
      _port?.close();
      _port = SerialPort(state.selectedPort!);
      final config = SerialPortConfig();
      config.baudRate = 38400;
      config.bits = 8;
      config.stopBits = 1;
      config.parity = SerialPortParity.none;
      if (!_port!.openReadWrite()) {
        throw Exception('포트 열기 실패');
      }
      _port!.config = config;
      state = state.copyWith(
        connection: UartConnectionState.connected,
        status: 'CONNECTED',
      );
    } catch (e) {
      state = state.copyWith(
        connection: UartConnectionState.error,
        status: 'ERROR: $e',
      );
    }
  }

  void disconnect() {
    _port?.close();
    _port = null;
    state = state.copyWith(
      connection: UartConnectionState.disconnected,
      status: 'READY',
    );
  }

  Future<bool> sendBytes(List<int> bytes) async {
    if (_port == null || state.connection != UartConnectionState.connected) return false;
    try {
      final written = _port!.write(Uint8List.fromList(bytes), timeout: 500);
      return written == bytes.length;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _port?.close();
    super.dispose();
  }
}
