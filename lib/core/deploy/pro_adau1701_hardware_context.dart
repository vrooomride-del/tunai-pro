// ── TUNAI PRO — ADAU1701 Hardware Context factory ─────────────────────────────
// A single construction layer that wires the real ICP5 PEQ write path:
//   transport → Adau1701PeqDeploymentGate → Adau1701Ch0Band0ReadService
//            → Adau1701Icp5PeqWritePort
//
// Construction only. It performs no hardware writes and changes no transport,
// gate, executor, DSP codec, or address mapping. The same write port works with
// any Adau1701TuningTransport (USBi serial or BLE GATT), since it depends on the
// interface, not a concrete transport.

import '../transport/adau1701_ch0_band0_read_service.dart';
import '../transport/adau1701_peq_deployment_gate.dart';
import '../transport/adau1701_tuning_transport.dart';
import '../transport/icp5_bluetooth_driver.dart';
import '../transport/icp5_serial_driver.dart';
import '../transport/icp5_transports.dart';
import 'pro_hardware_capability.dart';
import 'pro_icp5_peq_write_port.dart';

class Adau1701HardwareContext {
  final Adau1701TuningTransport transport;
  final Adau1701PeqDeploymentGate gate;
  final Adau1701Ch0Band0ReadService readService;
  final Adau1701Icp5PeqWritePort writePort;
  final HardwareTransportType transportType;

  const Adau1701HardwareContext._({
    required this.transport,
    required this.gate,
    required this.readService,
    required this.writePort,
    required this.transportType,
  });

  /// True only when the transport is connected, handshaken, and identified.
  /// When false, the write port fails closed at preflight — no write occurs.
  bool get isReady =>
      transport.isConnected &&
      transport.handshakeComplete &&
      transport.detectedProfile != null;

  /// Default channel resolver: only channel 0 / Band 1 is capture-proven, so the
  /// initial supported scope maps to output channel 0. Override for multi-channel
  /// capture-proven mappings once they exist.
  static int defaultChannelResolver(String channelId) => 0;

  /// Wires a context around an already-constructed tuning transport. This is the
  /// composition root; the named transport factories delegate to it.
  factory Adau1701HardwareContext.fromTransport(
    Adau1701TuningTransport transport, {
    HardwareTransportType transportType = HardwareTransportType.icp5,
    Icp5ChannelResolver? channelResolver,
    DateTime Function()? clock,
  }) {
    final gate = Adau1701PeqDeploymentGate(transport: transport);
    final readService = Adau1701Ch0Band0ReadService(transport: transport);
    final writePort = Adau1701Icp5PeqWritePort(
      transport: transport,
      gate: gate,
      readService: readService,
      channelResolver: channelResolver ?? defaultChannelResolver,
      clock: clock,
    );
    return Adau1701HardwareContext._(
      transport: transport,
      gate: gate,
      readService: readService,
      writePort: writePort,
      transportType: transportType,
    );
  }

  /// ICP5 USB transport ([Icp5UsbTransport]) with a platform-appropriate serial
  /// driver — macOS on a Mac host, Windows elsewhere ([defaultIcp5UsbSerialDriver]).
  /// Construction only — discovery and connection happen later via the transport.
  factory Adau1701HardwareContext.icp5Usb({
    Icp5ChannelResolver? channelResolver,
    DateTime Function()? clock,
  }) =>
      Adau1701HardwareContext.fromTransport(
        Icp5UsbTransport(driver: defaultIcp5UsbSerialDriver()),
        transportType: HardwareTransportType.icp5,
        channelResolver: channelResolver,
        clock: clock,
      );

  /// BLE ICP5 transport placeholder: the same [Icp5UsbTransport] driven by the
  /// BLE GATT driver. Wiring is identical to USBi — only the injected driver
  /// differs. Marked placeholder because the BLE path's end-to-end write is not
  /// yet capture-proven.
  factory Adau1701HardwareContext.bleIcp5Placeholder({
    Icp5ChannelResolver? channelResolver,
    DateTime Function()? clock,
  }) =>
      Adau1701HardwareContext.fromTransport(
        Icp5UsbTransport(driver: Icp5BluetoothGattDriver()),
        transportType: HardwareTransportType.icp5,
        channelResolver: channelResolver,
        clock: clock,
      );
}
