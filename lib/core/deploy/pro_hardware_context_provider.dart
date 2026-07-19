// ── TUNAI PRO — Shared ADAU1701 ICP5 USB hardware context ─────────────────────
// A single app-wide Adau1701HardwareContext built on the real ICP5 USB
// transport (Icp5UsbTransport). Sharing one instance means the Deploy Apply
// flow and any other consumer act on the same transport/gate/write-port.
//
// Construction only — connecting the transport happens elsewhere. No transport,
// gate, DSP-codec, BLE, or address-mapping changes here.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../transport/icp5_bluetooth_windows_driver.dart';
import '../transport/icp5_transports.dart';
import 'pro_adau1701_hardware_context.dart';
import 'pro_hardware_capability.dart';

/// Shared ADAU1701 ICP5 USB hardware context. Lazily constructed once per
/// ProviderScope so the Hardware tab and the Deploy Apply flow act on the same
/// transport / gate / read service / write port — and therefore the same
/// connection state.
///
/// This context is dedicated to the ADAU1701 / TUNAI ONE ICP5 USB path. The
/// ADAU1466 developer USBi path and the BLE ICP5 placeholder are unaffected.
final adau1701Icp5UsbContextProvider = Provider<Adau1701HardwareContext>((ref) {
  final ctx = Adau1701HardwareContext.icp5Usb();
  ref.onDispose(() {
    final t = ctx.transport;
    if (t is Icp5UsbTransport) t.close();
  });
  return ctx;
});

/// Shared ADAU1701 ICP5 **Bluetooth (WinRT)** hardware context for Windows.
///
/// Wraps the WinRT [WindowsIcp5BluetoothDriver] in the generic ICP5 transport so
/// the existing identity handshake / write pipeline / gate / write-port are all
/// reused unchanged. Sharing one instance lets the Hardware tab's BLE connection
/// and (future) Deploy consumers act on the same BLE connection.
///
/// This is the Windows BLE path only. macOS BLE (flutter_blue_plus) and the ICP5
/// USB paths are untouched — nothing reads this provider off Windows.
final adau1701Icp5BleWindowsContextProvider =
    Provider<Adau1701HardwareContext>((ref) {
  final transport = Icp5BluetoothTransport(
    driver: WindowsIcp5BluetoothDriver(),
    readTimeout: const Duration(seconds: 3),
    writeTimeout: const Duration(seconds: 3),
  );
  final ctx = Adau1701HardwareContext.fromTransport(
    transport,
    transportType: HardwareTransportType.icp5,
  );
  ref.onDispose(transport.close);
  return ctx;
});
