import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/pro_adau1701_hardware_context.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_context_provider.dart';
import 'package:tunai_pro/core/deploy/pro_icp5_peq_write_port.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';

void main() {
  test('provider yields a shared ICP5 USB context', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final ctx = container.read(adau1701Icp5UsbContextProvider);
    expect(ctx, isA<Adau1701HardwareContext>());
    expect(ctx.transport, isA<Icp5UsbTransport>());
    expect(ctx.transportType, HardwareTransportType.icp5);
    expect(ctx.writePort, isA<Adau1701Icp5PeqWritePort>());

    // Same instance is shared across reads.
    expect(container.read(adau1701Icp5UsbContextProvider), same(ctx));
  });
}
