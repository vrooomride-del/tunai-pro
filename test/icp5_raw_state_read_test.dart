import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/transport/icp5_frame_codec.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';

List<int> responseFrame({
  required int declaredLength,
  int blockId = 0x2202,
  required List<int> payload,
}) {
  final frame = <int>[
    0x55,
    declaredLength,
    0xE0,
    0,
    0,
    0,
    (blockId >> 8) & 0xFF,
    blockId & 0xFF,
    ...payload,
  ];
  expect(frame.length + 1, declaredLength + 2);
  return [...frame, Icp5FrameCodec.checksum(frame)];
}

void main() {
  test('builds capture-proven ICP5 read requests byte for byte', () {
    expect(Icp5ReadRequestBuilder.identity(),
        [0x55, 0x07, 0x1A, 0, 0, 0, 0, 0, 0x76]);
    expect(Icp5ReadRequestBuilder.stateHeader(),
        [0x55, 0x07, 0x1A, 0, 0, 0, 0x22, 0x01, 0x99]);
    expect(Icp5ReadRequestBuilder.rawState(),
        [0x55, 0x07, 0x1A, 0, 0, 0, 0x22, 0x02, 0x9A]);
  });

  test('strictly parses captured 0x2201 response envelope', () {
    const captured = <int>[
      0x55,
      0x0B,
      0xE0,
      0,
      0,
      0,
      0x22,
      0x01,
      0x01,
      0x02,
      0,
      0,
      0x66,
    ];
    final parsed = Icp5ReadResponseValidator.parse(
      captured,
      expectedBlockId: 0x2201,
      expectedDeclaredLength: 0x0B,
    );
    expect(parsed.blockId, 0x2201);
    expect(parsed.payload, [1, 2, 0, 0]);
  });

  test('assembles four pages in arrival order into 513 raw bytes', () async {
    final payloads = <List<int>>[
      List.generate(154, (index) => index & 0xFF),
      List.generate(154, (index) => (index + 40) & 0xFF),
      List.generate(154, (index) => (index + 80) & 0xFF),
      List.generate(51, (index) => (index + 120) & 0xFF),
    ];
    final frames = <List<int>>[
      responseFrame(declaredLength: 0xA1, payload: payloads[0]),
      responseFrame(declaredLength: 0xA1, payload: payloads[1]),
      responseFrame(declaredLength: 0xA1, payload: payloads[2]),
      responseFrame(declaredLength: 0x3A, payload: payloads[3]),
    ];
    final requests = <List<int>>[];
    var responseIndex = 0;
    final reader = Icp5RawStateReader(
      exchange: (request) async {
        requests.add(request);
        return frames[responseIndex++];
      },
      clock: () => DateTime.utc(2026, 7, 17, 12),
    );

    final snapshot = await reader.read(deviceId: 'ICP5-TEST');

    expect(requests, List.filled(4, Icp5ReadRequestBuilder.rawState()));
    expect(snapshot.deviceId, 'ICP5-TEST');
    expect(snapshot.timestamp, DateTime.utc(2026, 7, 17, 12));
    expect(snapshot.blockId, 0x2202);
    expect(snapshot.payload, payloads.expand((payload) => payload));
    expect(snapshot.payload, hasLength(513));
    expect(() => snapshot.payload[0] = 1, throwsUnsupportedError);
  });

  test('rejects a bad response checksum', () {
    final frame = responseFrame(
      declaredLength: 0xA1,
      payload: List.filled(154, 1),
    );
    frame[frame.length - 1] ^= 0x01;
    expect(() => Icp5RawStateCollector().add(frame), throwsFormatException);
  });

  test('rejects a response for the wrong block', () {
    final frame = responseFrame(
      declaredLength: 0xA1,
      blockId: 0x2201,
      payload: List.filled(154, 1),
    );
    expect(() => Icp5RawStateCollector().add(frame), throwsFormatException);
  });

  test('rejects completion when the final page is missing', () {
    final collector = Icp5RawStateCollector();
    for (var page = 0; page < 3; page++) {
      collector.add(responseFrame(
        declaredLength: 0xA1,
        payload: List.filled(154, page),
      ));
    }
    expect(collector.completePayload, throwsStateError);
  });

  test('rejects an exact duplicate page', () {
    final collector = Icp5RawStateCollector();
    final page = responseFrame(
      declaredLength: 0xA1,
      payload: List.filled(154, 7),
    );
    collector.add(page);
    expect(() => collector.add(page), throwsFormatException);
  });

  test('rejects malformed header and wrong page sequence', () {
    final malformed = responseFrame(
      declaredLength: 0xA1,
      payload: List.filled(154, 1),
    );
    malformed[3] = 1;
    malformed.last =
        Icp5FrameCodec.checksum(malformed.take(malformed.length - 1));
    expect(() => Icp5RawStateCollector().add(malformed), throwsFormatException);

    final finalPageFirst = responseFrame(
      declaredLength: 0x3A,
      payload: List.filled(51, 1),
    );
    expect(() => Icp5RawStateCollector().add(finalPageFirst),
        throwsFormatException);
  });
}
