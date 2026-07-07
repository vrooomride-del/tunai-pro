import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dsp_transport.dart';
import 'adau1466_usb_spi_transport.dart';
import 'adau1701_uart_transport.dart';
import '../../../features/connect/connect_controller.dart';

final dspTransportProvider = Provider<DspTransport?>((ref) {
  final conn = ref.watch(connectProvider);
  if (!conn.connected) return null;

  switch (conn.mode) {
    case ConnectMode.usbi:
      final usbi = ref.read(connectProvider.notifier).usbiTransport;
      return Adau1466UsbSpiTransport(usbi);
    case ConnectMode.uart:
    case ConnectMode.ble:
      // sendBytes가 UART/BLE 모두 처리 — 전송 모드 무관
      final sendFn = ref.read(connectProvider.notifier).sendBytes;
      return Adau1701ConnectTransport(sendFn);
  }
});
