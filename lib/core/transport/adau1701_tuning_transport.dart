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
  /// [band] is the PEQ band index (0 = Band 1). Band 0 is capture-proven;
  /// bands 1..9 (Band 2..10) reuse the confirmed band payload byte but are
  /// hardware-unverified.
  Future<Adau1701WriteAck> writePeqGain(int channel, double gainDb,
      {int band = 0});
  Future<Adau1701WriteAck> writeFilterFrequency(int channel, int frequencyHz,
      {int band = 0});

  /// Writes PEQ Q for [band] (0 = Band 1). NOT capture-proven — adopted from the
  /// Consumer Q encoding; hardware ACK + readback verification pending. See
  /// [Icp5FrameCodec.buildPeqQWriteArbitrary].
  Future<Adau1701WriteAck> writePeqQ(int channel, double q, {int band = 0});
}
