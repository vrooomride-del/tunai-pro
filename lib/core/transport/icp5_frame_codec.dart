import 'dart:convert';
import 'dart:typed_data';

abstract final class Icp5FrameCodec {
  static const identificationRequest = <int>[
    0x55,
    0x07,
    0x1A,
    0,
    0,
    0,
    0,
    0,
    0x76
  ];
  static const expectedProfile = 'DSP1701.100.00.01';
  static const masterVolumeParameterId = 0x00000010;
  static const masterMuteParameterId = 0x00000012;
  static const outputDac1GainParameterId = 0x00000014;
  static const filterCutoffParameterId = 0x00000015;
  static const delayCandidateParameterId = 0x00000017;
  static const peqBandGainParameterId = 0x00000018;

  static int checksum(Iterable<int> bytes) =>
      bytes.fold<int>(0, (sum, byte) => (sum + byte) & 0xFF);

  static List<int> buildMasterVolumeWrite(double value) {
    if (value != 5.9 && value != 6.0) {
      throw ArgumentError.value(
          value, 'value', 'Only capture-proven 5.9 and 6.0 are allowed.');
    }
    final float = ByteData(4)..setFloat32(0, value, Endian.little);
    final frame = <int>[
      0x55,
      0x0A,
      0x1C,
      0,
      0,
      0,
      0x10,
      ...float.buffer.asUint8List(),
    ];
    return [...frame, checksum(frame)];
  }

  static bool hasValidEnvelope(List<int> frame) =>
      frame.length >= 4 &&
      frame.first == 0x55 &&
      frame.length == frame[1] + 2 &&
      checksum(frame.take(frame.length - 1)) == frame.last;

  static String? parseIdentity(List<int> frame) {
    if (!hasValidEnvelope(frame) || frame[2] != 0xE0 || frame.length < 10) {
      return null;
    }
    final profile =
        ascii.decode(frame.sublist(8, frame.length - 1), allowInvalid: false);
    return profile == expectedProfile ? profile : null;
  }

  static bool parseMasterVolumeAck(List<int> frame) {
    return _parseSuccessAck(frame, masterVolumeParameterId);
  }

  static List<int> buildMasterMuteWrite(int state) {
    if (state != 0 && state != 1) {
      throw ArgumentError.value(state, 'state',
          'Only capture-proven State 0 and State 1 are allowed.');
    }
    final frame = <int>[
      0x55,
      0x09,
      0x1C,
      0,
      0,
      0,
      0x12,
      0x01,
      0x00,
      state,
    ];
    return [...frame, checksum(frame)];
  }

  static bool parseMasterMuteAck(List<int> frame) {
    return _parseSuccessAck(frame, masterMuteParameterId);
  }

  static List<int> buildOutputDac1GainWrite(double value) {
    return buildOutputGainWrite(0, value);
  }

  static List<int> buildOutputGainWrite(int channel, double value) {
    const capturedValueBytes = <String, List<int>>{
      '0:-4.9': [0xCD, 0xCC, 0x9C, 0xC0],
      '0:-4.8': [0x9A, 0x99, 0x99, 0xC0],
      '1:-4.8': [0x9A, 0x99, 0x99, 0xC0],
      '1:-4.7': [0x67, 0x66, 0x96, 0xC0],
      '2:-0.16666946': [0x66, 0xAB, 0x2A, 0xBE],
      '2:-0.06666946': [0x00, 0x8A, 0x88, 0xBD],
      '3:-0.16666946': [0x66, 0xAB, 0x2A, 0xBE],
      '3:-0.06666946': [0x00, 0x8A, 0x88, 0xBD],
    };
    final data = capturedValueBytes['$channel:$value'];
    if (data == null) {
      throw ArgumentError(
          'Only capture-proven Output Gain channel/value pairs are allowed.');
    }
    final frame = <int>[
      0x55,
      0x0C,
      0x1C,
      0,
      0,
      0,
      0x14,
      0x01,
      channel,
      ...data,
    ];
    return [...frame, checksum(frame)];
  }

  static bool parseOutputDac1GainAck(List<int> frame) {
    return _parseSuccessAck(frame, outputDac1GainParameterId);
  }

  static bool parseOutputGainAck(List<int> frame) =>
      _parseSuccessAck(frame, outputDac1GainParameterId);

  static List<int> buildDelayCandidateWrite(int channel, double value) {
    if (channel < 0 || channel > 3 || (value != 1.0 && value != 0.04)) {
      throw ArgumentError(
          'Only channels 0-3 and captured Delay values 1.0/0.04 are allowed.');
    }
    final data = ByteData(4)..setFloat32(0, value, Endian.little);
    return _frame(0x0B, delayCandidateParameterId,
        [channel, ...data.buffer.asUint8List()]);
  }

  static bool parseDelayCandidateAck(List<int> frame) =>
      _parseSuccessAck(frame, delayCandidateParameterId);

  /// Writes an arbitrary PEQ band 1 gain for [channel] using the confirmed
  /// ICP5 parameter-ID 0x18 encoding. [gainDb] must be in −6.0 .. +3.0 dB
  /// (the range enforced by the ADAU1701 decoder at read time).
  static List<int> buildPeqGainWriteArbitrary(int channel, double gainDb) {
    if (channel < 0 || channel > 3) {
      throw ArgumentError.value(channel, 'channel', 'Channel must be 0–3.');
    }
    if (gainDb < -6.0 || gainDb > 3.0) {
      throw ArgumentError.value(
          gainDb, 'gainDb', 'Gain must be in −6.0 .. +3.0 dB.');
    }
    final tenths = (gainDb * 10).round() & 0xFF;
    return _frame(0x0A, peqBandGainParameterId, [channel, 0x01, 0x00, tenths]);
  }

  static bool parsePeqGainAck(List<int> frame) =>
      _parseSuccessAck(frame, peqBandGainParameterId);

  /// Writes an arbitrary PEQ band 1 Q for [channel].
  ///
  /// PROVENANCE — NOT capture-proven on the PRO capture set. This encoding is
  /// ADOPTED FROM the hardware-proven Consumer q() builder (parameter 0x18,
  /// property byte 0x00; the same 0x18 parameter this file already uses for
  /// gain, with the property byte switched from 0x01 to 0x00). Hardware ACK +
  /// readback verification remains PENDING. Range is guarded to the ADAU1701
  /// decoder's validated 0.3 .. 10.0 window, exactly as gain/frequency are
  /// range-guarded, and the write is gated behind the same PEQ preflight.
  static List<int> buildPeqQWriteArbitrary(int channel, double q) {
    if (channel < 0 || channel > 3) {
      throw ArgumentError.value(channel, 'channel', 'Channel must be 0–3.');
    }
    if (q < 0.3 || q > 10.0) {
      throw ArgumentError.value(q, 'q', 'Q must be in 0.3 .. 10.0.');
    }
    final tenths = (q * 10).round() & 0xFF;
    return _frame(0x0A, peqBandGainParameterId, [channel, 0x00, 0x00, tenths]);
  }

  /// ACK for the adopted-from-Consumer Q write. Shares parameter 0x18 with the
  /// gain ACK (the ICP5 success ACK does not echo the property byte), so this
  /// is structurally identical to [parsePeqGainAck]; kept as a named parser so
  /// the unverified Q path stays self-documenting.
  static bool parsePeqQAck(List<int> frame) =>
      _parseSuccessAck(frame, peqBandGainParameterId);

  /// Writes an arbitrary filter frequency for [channel] using the confirmed
  /// ICP5 parameter-ID 0x15 encoding. [frequencyHz] must be in 20 .. 20000.
  static List<int> buildFilterFrequencyWriteArbitrary(
      int channel, int frequencyHz) {
    if (channel < 0 || channel > 3) {
      throw ArgumentError.value(channel, 'channel', 'Channel must be 0–3.');
    }
    if (frequencyHz < 20 || frequencyHz > 20000) {
      throw ArgumentError.value(
          frequencyHz, 'frequencyHz', 'Frequency must be in 20 .. 20 000 Hz.');
    }
    return _frame(0x0B, filterCutoffParameterId, [
      channel,
      0x02,
      0x00,
      frequencyHz & 0xFF,
      (frequencyHz >> 8) & 0xFF,
    ]);
  }

  static bool parseFilterFrequencyAck(List<int> frame) =>
      _parseSuccessAck(frame, filterCutoffParameterId);

  static List<int> buildFilterCutoffWrite(int channel, int value) {
    const pairs = <int, List<int>>{
      0: [2001, 2000],
      1: [2001, 2000],
      2: [21, 20],
      3: [21, 20],
    };
    final allowed = pairs[channel]?.contains(value) ?? false;
    if (!allowed) {
      throw ArgumentError(
          'Only captured Filter Cutoff channel/value pairs are allowed.');
    }
    return _frame(0x0B, filterCutoffParameterId,
        [channel, 0x02, 0x00, value & 0xFF, (value >> 8) & 0xFF]);
  }

  static bool parseFilterCutoffAck(List<int> frame) =>
      _parseSuccessAck(frame, filterCutoffParameterId);

  static List<int> buildPeqBand1GainWrite(int channel, double value) {
    const pairs = <int, List<double>>{
      0: [-0.9, -1.0],
      1: [4.2, 4.1],
      2: [-1.0, -2.0],
      3: [2.1, 2.0],
    };
    final allowed = pairs[channel]?.contains(value) ?? false;
    if (!allowed) {
      throw ArgumentError(
          'Only captured PEQ Band 1 channel/value pairs are allowed.');
    }
    final tenths = (value * 10).round() & 0xFF;
    return _frame(0x0A, peqBandGainParameterId, [channel, 0x01, 0x00, tenths]);
  }

  static bool parsePeqBand1GainAck(List<int> frame) =>
      _parseSuccessAck(frame, peqBandGainParameterId);

  static List<int> _frame(
      int declaredLength, int parameterId, List<int> payload) {
    final frame = <int>[
      0x55,
      declaredLength,
      0x1C,
      (parameterId >> 24) & 0xFF,
      (parameterId >> 16) & 0xFF,
      (parameterId >> 8) & 0xFF,
      parameterId & 0xFF,
      ...payload,
    ];
    return [...frame, checksum(frame)];
  }

  static bool _parseSuccessAck(List<int> frame, int expectedParameterId) {
    if (!hasValidEnvelope(frame) || frame.length != 9 || frame[2] != 0xE1) {
      return false;
    }
    final parameter = ByteData.sublistView(Uint8List.fromList(frame), 3, 7)
        .getUint32(0, Endian.big);
    return parameter == expectedParameterId && frame[7] == 0x00;
  }
}

class Icp5FrameBuffer {
  final List<int> _bytes = [];

  void reset() => _bytes.clear();

  List<List<int>> add(List<int> chunk) {
    _bytes.addAll(chunk);
    final frames = <List<int>>[];
    while (true) {
      final start = _bytes.indexOf(0x55);
      if (start < 0) {
        _bytes.clear();
        break;
      }
      if (start > 0) _bytes.removeRange(0, start);
      if (_bytes.length < 2) break;
      final total = _bytes[1] + 2;
      if (total < 4) {
        _bytes.removeAt(0);
        continue;
      }
      if (_bytes.length < total) break;
      frames.add(List<int>.from(_bytes.take(total)));
      _bytes.removeRange(0, total);
    }
    return frames;
  }
}
