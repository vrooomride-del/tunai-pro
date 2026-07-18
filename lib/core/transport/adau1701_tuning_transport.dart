import 'adau1701_ch0_band0_read_service.dart';

/// Minimal write result for the ADAU1701 tuning workflow.
class Adau1701WriteAck {
  final bool success;
  final String message;
  const Adau1701WriteAck({required this.success, required this.message});
}

/// Combined interface for the ADAU1701 read + write tuning workflow.
/// The tuning panel depends on this interface; [Icp5UsbTransport] implements it.
abstract interface class Adau1701TuningTransport
    implements Adau1701RawReadTransport {
  Future<Adau1701WriteAck> writePeqGain(int channel, double gainDb);
  Future<Adau1701WriteAck> writeFilterFrequency(int channel, int frequencyHz);
}
