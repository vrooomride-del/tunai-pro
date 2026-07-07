import 'package:flutter/foundation.dart';
import 'dsp_transport.dart';
import '../../../features/connect/usbi_transport.dart';
import '../../../features/connect/usbi_protocol.dart';

class Adau1466UsbSpiTransport implements DspTransport {
  final UsbiTransport? _usbi;

  Adau1466UsbSpiTransport(this._usbi);

  @override
  Future<void> writeParameter(int address, List<int> bytes4) async {
    final usbi = _usbi;
    if (usbi == null || !usbi.isOpen) {
      debugPrint('[Adau1466USBi] write failed — transport not open'
          ' (addr=0x${address.toRadixString(16)})');
      return;
    }
    final value = (bytes4[0] << 24) | (bytes4[1] << 16) | (bytes4[2] << 8) | bytes4[3];
    final steps = UsbiProtocol.buildSafeLoadWriteSequence(address, value);
    final ok = usbi.sendSequence(steps);
    if (!ok) {
      debugPrint('[Adau1466USBi] sendSequence failed'
          ' (addr=0x${address.toRadixString(16)})');
    }
  }

  @override
  Future<List<int>?> readParameter(int address) async => null;

  @override
  Future<bool> detectDevice() async {
    final usbi = _usbi;
    return usbi != null && usbi.isOpen;
  }

  @override
  void dispose() {}
}
