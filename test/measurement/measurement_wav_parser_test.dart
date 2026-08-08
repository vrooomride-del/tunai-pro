// Phase 3-D1 — measurement_wav_parser.dart: pure RIFF/WAVE chunk-walking
// tests. All fixtures are synthesized byte buffers built by hand (no file
// I/O) so this suite never depends on a real recorded file.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/measurement/measurement_wav_parser.dart';

void _writeAscii(ByteData bd, int offset, String s) {
  for (var i = 0; i < s.length; i++) {
    bd.setUint8(offset + i, s.codeUnitAt(i));
  }
}

/// Builds a minimal, structurally valid PCM16 WAV. [extraChunk] (id + data)
/// is inserted BETWEEN fmt and data when [extraBeforeData] is true, or
/// before fmt (fmt/data order variant) when false — lets tests exercise
/// non-canonical chunk orderings/extra metadata without assuming byte 44.
Uint8List _buildWav({
  int sampleRate = 48000,
  int channelCount = 1,
  int bitsPerSample = 16,
  int audioFormatTag = 1,
  List<int> pcm16Samples = const [0, 100, -100, 32767, -32768],
  ({String id, List<int> data})? extraChunk,
  bool extraBeforeFmt = false,
  bool omitFmt = false,
  bool omitData = false,
  int? overrideDataDeclaredSize,
}) {
  final dataBytes = <int>[];
  for (final s in pcm16Samples) {
    final v = s & 0xFFFF;
    dataBytes.add(v & 0xFF);
    dataBytes.add((v >> 8) & 0xFF);
  }

  final chunks = <List<int>>[];

  List<int> chunk(String id, List<int> payload) {
    final size = payload.length;
    final bytes = <int>[...id.codeUnits];
    final sizeBytes = ByteData(4)..setUint32(0, size, Endian.little);
    bytes.addAll(sizeBytes.buffer.asUint8List());
    bytes.addAll(payload);
    if (size.isOdd) bytes.add(0); // RIFF padding
    return bytes;
  }

  if (extraChunk != null && extraBeforeFmt) {
    chunks.add(chunk(extraChunk.id, extraChunk.data));
  }

  if (!omitFmt) {
    final fmtPayload = ByteData(16);
    fmtPayload.setUint16(0, audioFormatTag, Endian.little);
    fmtPayload.setUint16(2, channelCount, Endian.little);
    fmtPayload.setUint32(4, sampleRate, Endian.little);
    fmtPayload.setUint32(
        8, sampleRate * channelCount * (bitsPerSample ~/ 8), Endian.little);
    fmtPayload.setUint16(
        12, channelCount * (bitsPerSample ~/ 8), Endian.little);
    fmtPayload.setUint16(14, bitsPerSample, Endian.little);
    chunks.add(chunk('fmt ', fmtPayload.buffer.asUint8List()));
  }

  if (extraChunk != null && !extraBeforeFmt) {
    chunks.add(chunk(extraChunk.id, extraChunk.data));
  }

  if (!omitData) {
    if (overrideDataDeclaredSize != null) {
      // Manually build a data chunk with a declared size that may not
      // match the actual payload length, to test truncation detection.
      final bytes = <int>[...'data'.codeUnits];
      final sizeBytes = ByteData(4)
        ..setUint32(0, overrideDataDeclaredSize, Endian.little);
      bytes.addAll(sizeBytes.buffer.asUint8List());
      bytes.addAll(dataBytes);
      chunks.add(bytes);
    } else {
      chunks.add(chunk('data', dataBytes));
    }
  }

  final body = chunks.expand((c) => c).toList();
  final riffSize = 4 + body.length; // 'WAVE' + chunks
  final header = ByteData(12);
  _writeAscii(header, 0, 'RIFF');
  header.setUint32(4, riffSize, Endian.little);
  _writeAscii(header, 8, 'WAVE');

  return Uint8List.fromList([...header.buffer.asUint8List(), ...body]);
}

/// KSDATAFORMAT_SUBTYPE_PCM, byte-for-byte identical to the parser's own
/// constant — kept as a separate literal here (not imported) so the test
/// actually proves the parser recognizes the real GUID bytes, not just
/// round-trips whatever constant it imports.
const List<int> _pcmGuid = [
  0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x00, //
  0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71,
];

const List<int> _ieeeFloatGuid = [
  0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x00, //
  0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71,
];

/// Builds a WAVE_FORMAT_EXTENSIBLE (tag 0xFFFE) WAV — the shape macOS
/// CoreAudio's WAV writer actually produces for UMIK-1/USB audio interfaces
/// that report a channel layout, even for plain 16-bit linear PCM content.
Uint8List _buildExtensibleWav({
  int sampleRate = 48000,
  int channelCount = 1,
  int bitsPerSample = 16,
  int validBitsPerSample = 16,
  int channelMask = 0x4, // SPEAKER_FRONT_CENTER — typical for mono capture
  List<int>? subFormatGuid,
  int? overrideCbSize,
  List<int> pcm16Samples = const [0, 100, -100, 32767, -32768],
}) {
  final dataBytes = <int>[];
  for (final s in pcm16Samples) {
    final v = s & 0xFFFF;
    dataBytes.add(v & 0xFF);
    dataBytes.add((v >> 8) & 0xFF);
  }
  final guid = subFormatGuid ?? _pcmGuid;
  final cbSize = overrideCbSize ?? 22;

  List<int> chunk(String id, List<int> payload) {
    final size = payload.length;
    final bytes = <int>[...id.codeUnits];
    final sizeBytes = ByteData(4)..setUint32(0, size, Endian.little);
    bytes.addAll(sizeBytes.buffer.asUint8List());
    bytes.addAll(payload);
    if (size.isOdd) bytes.add(0);
    return bytes;
  }

  final fmtPayload = ByteData(18 + 22); // base(16) + cbSize(2) + ext(22)
  fmtPayload.setUint16(0, kWavFormatTagExtensible, Endian.little);
  fmtPayload.setUint16(2, channelCount, Endian.little);
  fmtPayload.setUint32(4, sampleRate, Endian.little);
  fmtPayload.setUint32(
      8, sampleRate * channelCount * (bitsPerSample ~/ 8), Endian.little);
  fmtPayload.setUint16(12, channelCount * (bitsPerSample ~/ 8), Endian.little);
  fmtPayload.setUint16(14, bitsPerSample, Endian.little);
  fmtPayload.setUint16(16, cbSize, Endian.little);
  fmtPayload.setUint16(18, validBitsPerSample, Endian.little);
  fmtPayload.setUint32(20, channelMask, Endian.little);
  final fmtBytes = fmtPayload.buffer.asUint8List();
  for (var i = 0; i < 16 && i < guid.length; i++) {
    fmtBytes[24 + i] = guid[i];
  }
  // If a shorter cbSize was requested (to test truncation), only keep that
  // many extension bytes.
  final fmtLen = overrideCbSize != null && overrideCbSize < 22
      ? 18 + overrideCbSize
      : fmtBytes.length;

  final chunks = <List<int>>[
    chunk('fmt ', fmtBytes.sublist(0, fmtLen)),
    chunk('data', dataBytes),
  ];

  final body = chunks.expand((c) => c).toList();
  final riffSize = 4 + body.length;
  final header = ByteData(12);
  _writeAscii(header, 0, 'RIFF');
  header.setUint32(4, riffSize, Endian.little);
  _writeAscii(header, 8, 'WAVE');
  return Uint8List.fromList([...header.buffer.asUint8List(), ...body]);
}

void main() {
  group('canonical WAV', () {
    test('parses a minimal 44-byte-equivalent PCM16 mono WAV', () {
      final bytes = _buildWav();
      final result = MeasurementWavParser.parse(bytes);
      expect(result.isSuccess, isTrue);
      expect(result.sampleRate, 48000);
      expect(result.channelCount, 1);
      expect(result.bitsPerSample, 16);
      expect(result.dataOffset, 44);
      expect(result.dataLength, 10); // 5 samples * 2 bytes
    });

    test('extracts normalized samples matching the source PCM16 values', () {
      final bytes = _buildWav(pcm16Samples: [0, 16384, -16384, 32767, -32768]);
      final result = MeasurementWavParser.parse(bytes);
      final samples =
          MeasurementWavParser.extractNormalizedSamples(bytes, result);
      expect(samples.length, 5);
      expect(samples[0], closeTo(0.0, 1e-9));
      expect(samples[1], closeTo(0.5, 1e-3));
      expect(samples[2], closeTo(-0.5, 1e-3));
      expect(samples[3], closeTo(0.99997, 1e-3));
      expect(samples[4], closeTo(-1.0, 1e-3));
      for (final s in samples) {
        expect(s.isFinite, isTrue);
      }
    });
  });

  group('non-canonical chunk layouts', () {
    test(
        'extra metadata chunk between fmt and data is skipped, data still '
        'found at the correct (non-44) offset', () {
      final bytes = _buildWav(
        extraChunk: (id: 'LIST', data: List.filled(20, 0)),
        extraBeforeFmt: false,
      );
      final result = MeasurementWavParser.parse(bytes);
      expect(result.isSuccess, isTrue);
      expect(result.dataOffset, isNot(44));
      expect(result.warnings.any((w) => w.contains('LIST')), isTrue);
    });

    test(
        'extra chunk before fmt (fmt/data order variation) still parses '
        'correctly', () {
      final bytes = _buildWav(
        extraChunk: (id: 'JUNK', data: List.filled(8, 0)),
        extraBeforeFmt: true,
      );
      final result = MeasurementWavParser.parse(bytes);
      expect(result.isSuccess, isTrue);
      expect(result.sampleRate, 48000);
    });

    test(
        'odd-size chunk is padded to an even boundary before the next '
        'chunk is read', () {
      final bytes = _buildWav(
        extraChunk: (id: 'fact', data: [1, 2, 3]), // odd length: 3 bytes
        extraBeforeFmt: false,
      );
      final result = MeasurementWavParser.parse(bytes);
      expect(result.isSuccess, isTrue);
      expect(result.dataLength, 10);
    });
  });

  group('rejections — malformed/unsupported input', () {
    test('missing RIFF header is rejected', () {
      final result = MeasurementWavParser.parse(Uint8List.fromList(
          [...'XXXX'.codeUnits, 0, 0, 0, 0, ...'WAVE'.codeUnits]));
      expect(result.isSuccess, isFalse);
    });

    test('missing WAVE tag is rejected', () {
      final bd = ByteData(12);
      _writeAscii(bd, 0, 'RIFF');
      bd.setUint32(4, 4, Endian.little);
      _writeAscii(bd, 8, 'XXXX');
      final result = MeasurementWavParser.parse(bd.buffer.asUint8List());
      expect(result.isSuccess, isFalse);
    });

    test('truncated file (too short for a RIFF header) is rejected', () {
      final result = MeasurementWavParser.parse(Uint8List.fromList([1, 2, 3]));
      expect(result.isSuccess, isFalse);
    });

    test('missing fmt chunk is rejected', () {
      final bytes = _buildWav(omitFmt: true);
      final result = MeasurementWavParser.parse(bytes);
      expect(result.isSuccess, isFalse);
      expect(result.errors.any((e) => e.contains('fmt')), isTrue);
    });

    test('missing data chunk is rejected', () {
      final bytes = _buildWav(omitData: true);
      final result = MeasurementWavParser.parse(bytes);
      expect(result.isSuccess, isFalse);
      expect(result.errors.any((e) => e.contains('data')), isTrue);
    });

    test(
        'data chunk declaring more bytes than present (truncated) is '
        'rejected', () {
      final bytes = _buildWav(overrideDataDeclaredSize: 10000);
      final result = MeasurementWavParser.parse(bytes);
      expect(result.isSuccess, isFalse);
      expect(result.errors.any((e) => e.contains('truncated')), isTrue);
    });

    test(
        'non-PCM audio format tag is rejected (fail-closed, never '
        'misinterpreted as PCM)', () {
      final bytes = _buildWav(audioFormatTag: 3); // IEEE float
      final result = MeasurementWavParser.parse(bytes);
      expect(result.isSuccess, isFalse);
      expect(result.errors.any((e) => e.contains('Unsupported audio format')),
          isTrue);
    });

    test(
        'non-16-bit depth is rejected, never silently reinterpreted as '
        'PCM16', () {
      final bytes = _buildWav(bitsPerSample: 24);
      final result = MeasurementWavParser.parse(bytes);
      expect(result.isSuccess, isFalse);
      expect(result.errors.any((e) => e.contains('bits-per-sample')), isTrue);
    });

    test('zero-length data chunk is rejected', () {
      final bytes = _buildWav(pcm16Samples: const []);
      final result = MeasurementWavParser.parse(bytes);
      expect(result.isSuccess, isFalse);
      expect(result.errors.any((e) => e.contains('empty')), isTrue);
    });

    test('invalid (zero) sample rate is rejected', () {
      final bytes = _buildWav(sampleRate: 0);
      final result = MeasurementWavParser.parse(bytes);
      expect(result.isSuccess, isFalse);
    });
  });

  group('sample rate / channel extraction correctness', () {
    test(
        'extracts a non-default sample rate and stereo channel count '
        'accurately', () {
      final bytes = _buildWav(
        sampleRate: 44100,
        channelCount: 2,
        pcm16Samples: [0, 0, 100, -100, 200, -200],
      );
      final result = MeasurementWavParser.parse(bytes);
      expect(result.isSuccess, isTrue);
      expect(result.sampleRate, 44100);
      expect(result.channelCount, 2);
    });

    test(
        'extractNormalizedSamples throws on a failed parse result rather '
        'than guessing', () {
      final failed = MeasurementWavParseResult.failure(['x']);
      expect(
          () => MeasurementWavParser.extractNormalizedSamples(
              Uint8List(0), failed),
          throwsStateError);
    });
  });

  group('WAVE_FORMAT_EXTENSIBLE (P0-1 — real UMIK-1/macOS capture shape)', () {
    test(
        'extensible + PCM SubFormat GUID + 16-bit -> parses exactly like '
        'classic PCM16', () {
      final bytes = _buildExtensibleWav();
      final result = MeasurementWavParser.parse(bytes);
      expect(result.isSuccess, isTrue);
      expect(result.sampleRate, 48000);
      expect(result.channelCount, 1);
      expect(result.bitsPerSample, 16);
      expect(result.dataLength, 10);
    });

    test(
        'extensible + PCM SubFormat decodes via the SAME PCM16 path — '
        'sample values match a classic-tag file with identical bytes', () {
      final samples = [0, 16384, -16384, 32767, -32768];
      final classic = MeasurementWavParser.parse(
          _buildWav(audioFormatTag: kWavFormatTagPcm, pcm16Samples: samples));
      final extensible = MeasurementWavParser.parse(
          _buildExtensibleWav(pcm16Samples: samples));
      final classicSamples = MeasurementWavParser.extractNormalizedSamples(
          _buildWav(audioFormatTag: kWavFormatTagPcm, pcm16Samples: samples),
          classic);
      final extensibleSamples = MeasurementWavParser.extractNormalizedSamples(
          _buildExtensibleWav(pcm16Samples: samples), extensible);
      expect(extensibleSamples, classicSamples);
    });

    test(
        'extensible + wrong SubFormat GUID (IEEE float) is rejected — '
        'never mis-decoded as PCM', () {
      final bytes = _buildExtensibleWav(subFormatGuid: _ieeeFloatGuid);
      final result = MeasurementWavParser.parse(bytes);
      expect(result.isSuccess, isFalse);
      expect(result.errors.any((e) => e.contains('SubFormat')), isTrue);
    });

    test('extensible + non-16-bit is rejected exactly like classic PCM', () {
      final bytes =
          _buildExtensibleWav(bitsPerSample: 24, validBitsPerSample: 24);
      final result = MeasurementWavParser.parse(bytes);
      expect(result.isSuccess, isFalse);
      expect(result.errors.any((e) => e.contains('bits-per-sample')), isTrue);
    });

    test('extensible with cbSize too small to carry a GUID is rejected', () {
      final bytes = _buildExtensibleWav(overrideCbSize: 2);
      final result = MeasurementWavParser.parse(bytes);
      expect(result.isSuccess, isFalse);
      expect(
          result.errors
              .any((e) => e.contains('Malformed') || e.contains('cbSize')),
          isTrue);
    });

    test(
        'extensible truncated before cbSize field is rejected, not '
        'silently treated as classic PCM', () {
      // Only the base 16-byte fmt fields, tag says extensible but no cbSize
      // at all — this exercises the "chunkDataStart + 18 > bytes.length"
      // guard directly (declaredSize deliberately too small).
      final full = _buildExtensibleWav();
      // Truncate the file right after the base 16-byte fmt fields (offset
      // 12 RIFF header + 8 chunk header + 16 base fields = 36).
      final truncated = Uint8List.fromList(full.sublist(0, 36));
      final result = MeasurementWavParser.parse(truncated);
      expect(result.isSuccess, isFalse);
    });
  });
}
