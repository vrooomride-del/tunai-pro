import 'dart:collection';

import 'icp5_frame_codec.dart';

abstract final class Icp5ReadRequestBuilder {
  static const int identityBlockId = 0x0000;
  static const int stateHeaderBlockId = 0x2201;
  static const int rawStateBlockId = 0x2202;

  static List<int> identity() => build(identityBlockId);
  static List<int> stateHeader() => build(stateHeaderBlockId);
  static List<int> rawState() => build(rawStateBlockId);

  static List<int> build(int blockId) {
    if (blockId < 0 || blockId > 0xFFFF) {
      throw ArgumentError.value(blockId, 'blockId', 'Must be a uint16.');
    }
    final frame = <int>[
      0x55,
      0x07,
      0x1A,
      0x00,
      0x00,
      0x00,
      (blockId >> 8) & 0xFF,
      blockId & 0xFF,
    ];
    return List.unmodifiable([...frame, Icp5FrameCodec.checksum(frame)]);
  }
}

class Icp5ReadResponse {
  final int declaredLength;
  final int blockId;
  final List<int> payload;
  final List<int> rawFrame;

  Icp5ReadResponse._({
    required this.declaredLength,
    required this.blockId,
    required List<int> payload,
    required List<int> rawFrame,
  })  : payload = List.unmodifiable(payload),
        rawFrame = List.unmodifiable(rawFrame);
}

abstract final class Icp5ReadResponseValidator {
  static Icp5ReadResponse parse(
    List<int> frame, {
    required int expectedBlockId,
    int? expectedDeclaredLength,
  }) {
    if (frame.length < 9 || frame[0] != 0x55) {
      throw const FormatException('Malformed ICP5 response envelope.');
    }
    if (frame[1] + 2 != frame.length) {
      throw const FormatException('ICP5 response length does not match.');
    }
    if (frame[2] != 0xE0 || frame[3] != 0 || frame[4] != 0 || frame[5] != 0) {
      throw const FormatException('Invalid ICP5 read response header.');
    }
    final blockId = (frame[6] << 8) | frame[7];
    if (blockId != expectedBlockId) {
      throw FormatException(
        'Unexpected ICP5 block 0x${blockId.toRadixString(16)}.',
      );
    }
    if (expectedDeclaredLength != null && frame[1] != expectedDeclaredLength) {
      throw FormatException(
        'Unexpected ICP5 page length 0x${frame[1].toRadixString(16)}.',
      );
    }
    final checksum = Icp5FrameCodec.checksum(frame.take(frame.length - 1));
    if (checksum != frame.last) {
      throw const FormatException('Invalid ICP5 response checksum.');
    }
    return Icp5ReadResponse._(
      declaredLength: frame[1],
      blockId: blockId,
      payload: frame.sublist(8, frame.length - 1),
      rawFrame: frame,
    );
  }
}

class Icp5RawStateCollector {
  static const int blockId = Icp5ReadRequestBuilder.rawStateBlockId;
  static const int payloadLength = 513;
  static const expectedPageLengths = <int>[0xA1, 0xA1, 0xA1, 0x3A];

  final List<Icp5ReadResponse> _pages = [];
  final Set<List<int>> _rawPages = HashSet<List<int>>(
    equals: _listEquals,
    hashCode: Object.hashAll,
  );

  int get pageCount => _pages.length;
  bool get isComplete => pageCount == expectedPageLengths.length;

  void add(List<int> frame) {
    if (isComplete) {
      throw StateError('Raw DSP state already has all four pages.');
    }
    final response = Icp5ReadResponseValidator.parse(
      frame,
      expectedBlockId: blockId,
      expectedDeclaredLength: expectedPageLengths[pageCount],
    );
    if (!_rawPages.add(response.rawFrame)) {
      throw const FormatException('Duplicate ICP5 raw state page.');
    }
    _pages.add(response);
  }

  List<int> completePayload() {
    if (!isComplete) {
      throw StateError('Raw DSP state is incomplete: $pageCount/4 pages.');
    }
    final payload = _pages.expand((page) => page.payload).toList();
    if (payload.length != payloadLength) {
      throw StateError(
        'Raw DSP state payload is ${payload.length}, expected $payloadLength.',
      );
    }
    return List.unmodifiable(payload);
  }

  static bool _listEquals(List<int> left, List<int> right) {
    if (identical(left, right)) return true;
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

class RawDspStateSnapshot {
  final String deviceId;
  final DateTime timestamp;
  final int blockId;
  final List<int> payload;

  RawDspStateSnapshot({
    required this.deviceId,
    required this.timestamp,
    required this.blockId,
    required List<int> payload,
  }) : payload = List.unmodifiable(payload) {
    if (deviceId.isEmpty) throw ArgumentError.value(deviceId, 'deviceId');
    if (blockId != Icp5RawStateCollector.blockId) {
      throw ArgumentError.value(blockId, 'blockId', 'Must be 0x2202.');
    }
    if (payload.length != Icp5RawStateCollector.payloadLength) {
      throw ArgumentError.value(
          payload.length, 'payload.length', 'Must be 513.');
    }
  }
}

typedef Icp5ReadExchange = Future<List<int>> Function(List<int> request);

class Icp5RawStateReader {
  final Icp5ReadExchange exchange;
  final DateTime Function() clock;

  Icp5RawStateReader({required this.exchange, DateTime Function()? clock})
      : clock = clock ?? DateTime.now;

  Future<RawDspStateSnapshot> read({required String deviceId}) async {
    // Read the 0x2201 state-header descriptor before the 0x2202 pages, exactly
    // as the capture-proven device conversation does. The header read re-arms
    // the firmware's multi-page read pointer; without it, only the first read
    // after handshake returns pages and every subsequent read on the same
    // connection stalls. It is therefore required before EVERY multi-page read.
    // The response is validated (envelope + 0x2201 block + checksum) but its
    // payload is a descriptor and is not part of the 513-byte state.
    final header = await exchange(Icp5ReadRequestBuilder.stateHeader());
    Icp5ReadResponseValidator.parse(
      header,
      expectedBlockId: Icp5ReadRequestBuilder.stateHeaderBlockId,
    );
    final collector = Icp5RawStateCollector();
    for (var page = 0; page < 4; page++) {
      final response = await exchange(Icp5ReadRequestBuilder.rawState());
      collector.add(response);
    }
    return RawDspStateSnapshot(
      deviceId: deviceId,
      timestamp: clock(),
      blockId: Icp5RawStateCollector.blockId,
      payload: collector.completePayload(),
    );
  }
}
