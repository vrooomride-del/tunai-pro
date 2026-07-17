import 'icp5_raw_state_read.dart';

/// Verified device identity for ADAU1701 on WONDOM ICP5.
const _kExpectedDeviceId = 'DSP1701.100.00.01';

/// Decoded PEQ state for channel 0, band 0 only.
///
/// Field meanings and byte offsets are backed by physical captures.
/// No other channels or bands are decoded; no other offsets are inferred.
///
/// Validated offsets (channel 0, band 0):
///   19..20  frequencyHz   uint16 LE
///   21      gainDb        int8, dB × 10
///   22      (uninterpreted — remained 0x00 in both verified captures)
///   23      q             uint8, Q × 10
///   24      property08State  uint8, observed values: 0 or 1
class Adau1701Ch0Band0DecodedState {
  final int frequencyHz;
  final double gainDb;
  final double q;

  /// Raw value of DSP property 0x08 for channel 0 band 0.
  /// Validated values: 0 or 1. Semantic meaning is not yet confirmed.
  final int property08State;

  const Adau1701Ch0Band0DecodedState({
    required this.frequencyHz,
    required this.gainDb,
    required this.q,
    required this.property08State,
  });
}

/// Decodes [Adau1701Ch0Band0DecodedState] from a [RawDspStateSnapshot].
///
/// Only channel 0, band 0 is decoded. Fails closed for any constraint
/// violation: wrong device identity, wrong block ID, wrong payload length,
/// out-of-range field values, or unseen property08State values.
abstract final class Adau1701Ch0Band0Decoder {
  // Validated offsets — do not infer from these.
  static const _freqLowOffset = 19;
  static const _freqHighOffset = 20;
  static const _gainOffset = 21;
  // offset 22 is uninterpreted and not read.
  static const _qOffset = 23;
  static const _property08Offset = 24;

  static Adau1701Ch0Band0DecodedState decode(RawDspStateSnapshot snapshot) {
    if (snapshot.deviceId != _kExpectedDeviceId) {
      throw FormatException(
        'Device identity mismatch: expected $_kExpectedDeviceId, '
        'got ${snapshot.deviceId}.',
      );
    }
    // blockId and payload length are already validated by RawDspStateSnapshot
    // constructor, but we assert them here for explicitness.
    if (snapshot.blockId != 0x2202) {
      throw FormatException(
        'Block ID mismatch: expected 0x2202, '
        'got 0x${snapshot.blockId.toRadixString(16)}.',
      );
    }
    if (snapshot.payload.length != 513) {
      throw FormatException(
        'Payload length mismatch: expected 513, '
        'got ${snapshot.payload.length}.',
      );
    }

    final payload = snapshot.payload;

    // Frequency: unsigned LE16, valid range 20..20000 Hz
    final frequencyHz =
        payload[_freqLowOffset] | (payload[_freqHighOffset] << 8);
    if (frequencyHz < 20 || frequencyHz > 20000) {
      throw FormatException(
        'frequencyHz out of range: $frequencyHz.',
      );
    }

    // Gain: signed int8, dB × 10, valid range -60..+30 (covering -6.0..+3.0 dB)
    final rawGain = payload[_gainOffset];
    final gainRaw = rawGain >= 0x80 ? rawGain - 0x100 : rawGain;
    final gainDb = gainRaw / 10.0;
    if (gainDb < -6.0 || gainDb > 3.0) {
      throw FormatException(
        'gainDb out of validated range: $gainDb.',
      );
    }

    // Q: uint8, Q × 10, valid range 0x03..0x64 (0.3..10.0)
    final rawQ = payload[_qOffset];
    final q = rawQ / 10.0;
    if (q < 0.3 || q > 10.0) {
      throw FormatException(
        'q out of validated range: $q.',
      );
    }

    // property08State: validated values are 0 or 1 only
    final property08State = payload[_property08Offset];
    if (property08State != 0 && property08State != 1) {
      throw FormatException(
        'property08State has unseen value: $property08State.',
      );
    }

    return Adau1701Ch0Band0DecodedState(
      frequencyHz: frequencyHz,
      gainDb: gainDb,
      q: q,
      property08State: property08State,
    );
  }
}
