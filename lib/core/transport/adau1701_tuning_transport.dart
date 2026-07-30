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
  /// Writes an arbitrary crossover filter frequency (param 0x15, property 0x02)
  /// in 20 .. 20 000 Hz. This is the CROSSOVER path only — see [writePeqFrequency]
  /// for the PEQ band frequency path (param 0x18 property 0x02).
  Future<Adau1701WriteAck> writeFilterFrequency(int channel, int frequencyHz,
      {int band = 0});

  /// Writes an arbitrary PEQ band frequency in 20 .. 20 000 Hz for [channel]
  /// and [band] (0 = Band 1). Uses Consumer-production-proven param 0x18
  /// property 0x02 (uint16 LE Hz). Separate DSP memory block from
  /// [writeFilterFrequency] (param 0x15 = crossover cutoff).
  Future<Adau1701WriteAck> writePeqFrequency(int channel, int frequencyHz,
      {int band = 0});

  /// Writes PEQ Q for [band] (0 = Band 1). NOT capture-proven — adopted from the
  /// Consumer Q encoding; hardware ACK + readback verification pending. See
  /// [Icp5FrameCodec.buildPeqQWriteArbitrary].
  Future<Adau1701WriteAck> writePeqQ(int channel, double q, {int band = 0});

  /// Writes an arbitrary output gain in −20.0..+6.0 dB for [channel] (0–3).
  /// Uses the capture-confirmed ICP5 parameter-ID 0x14 and float32 LE dB
  /// encoding. See [Icp5FrameCodec.buildOutputGainWriteArbitrary].
  Future<Adau1701WriteAck> writeOutputGain(int channel, double gainDb);

  /// Writes the master mute state (param 0x12). Polarity confirmed:
  /// [muted]=true → State 0 (MUTED); [muted]=false → State 1 (UNMUTED).
  /// ACK-only — no readback service for mute.
  Future<Adau1701WriteAck> writeMasterMute(bool muted);
}
