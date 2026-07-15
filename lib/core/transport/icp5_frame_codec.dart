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
    if (!hasValidEnvelope(frame) || frame.length != 9 || frame[2] != 0xE1) {
      return false;
    }
    final parameter = ByteData.sublistView(Uint8List.fromList(frame), 3, 7)
        .getUint32(0, Endian.big);
    return parameter == masterVolumeParameterId && frame[7] == 0x00;
  }
}

class Icp5FrameBuffer {
  final List<int> _bytes = [];

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
