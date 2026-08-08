// ── TUNAI PRO Phase 3-D1 — pure WAV/RIFF metadata parser ────────────────────
//
// Replaces the hardcoded "data starts at byte 44" assumption used elsewhere
// in this codebase's live-capture path. A canonical minimal WAV (fmt chunk
// immediately followed by data chunk, no extra metadata) does happen to put
// data at byte 44, which is why that assumption worked so far — but any
// recorder/OS that inserts an extra chunk (LIST/INFO, fact, etc.) breaks it
// silently. This module walks the actual RIFF chunk structure instead.
//
// Pure: no file I/O (caller reads bytes), no FFT, no dependency on
// pro_acoustic_data.dart or any acoustic-domain type — a WAV file's
// structure has nothing to do with what it measures.
library;

import 'dart:typed_data';

/// PCM audio format tag value inside a WAV fmt chunk (WAVE_FORMAT_PCM).
const int kWavFormatTagPcm = 1;

/// WAVE_FORMAT_EXTENSIBLE — used instead of [kWavFormatTagPcm] whenever the
/// writer attaches channel-layout metadata (channelMask), which macOS
/// CoreAudio's WAV writer does routinely for USB audio interfaces/mics that
/// report a specific channel layout (observed in production with UMIK-1)
/// even though the underlying samples are still plain linear PCM. The real
/// format lives in the extension's SubFormat GUID, not this tag — this
/// parser never assumes PCM just because the tag is 65534; it reads and
/// checks the GUID (see [_pcmSubFormatGuid]).
const int kWavFormatTagExtensible = 0xFFFE;

/// Only 16-bit PCM is supported this phase — matches the format this
/// codebase's recorder already requests (`AudioEncoder.wav`, effectively
/// PCM16 on every supported platform for that encoder). A different bit
/// depth is rejected with a specific error rather than silently
/// misinterpreted as PCM16. Applies identically whether the fmt chunk used
/// the classic PCM tag or WAVE_FORMAT_EXTENSIBLE with a PCM SubFormat.
const int kSupportedBitsPerSample = 16;

/// KSDATAFORMAT_SUBTYPE_PCM — the SubFormat GUID a WAVE_FORMAT_EXTENSIBLE
/// fmt chunk must carry for this parser to treat it as PCM. Any other
/// SubFormat (e.g. KSDATAFORMAT_SUBTYPE_IEEE_FLOAT) is rejected — this
/// parser never mis-decodes a non-PCM stream as if it were PCM.
const List<int> _pcmSubFormatGuid = [
  0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x00, //
  0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71,
];

class MeasurementWavParseResult {
  final bool isSuccess;
  final int? audioFormatTag;
  final int? sampleRate;
  final int? channelCount;
  final int? bitsPerSample;

  /// Byte offset of the data chunk's payload (NOT the chunk header) within
  /// the original byte buffer.
  final int? dataOffset;

  /// Length of the data chunk's payload in bytes.
  final int? dataLength;

  final Duration? duration;
  final List<String> errors;
  final List<String> warnings;

  const MeasurementWavParseResult({
    this.isSuccess = false,
    this.audioFormatTag,
    this.sampleRate,
    this.channelCount,
    this.bitsPerSample,
    this.dataOffset,
    this.dataLength,
    this.duration,
    this.errors = const [],
    this.warnings = const [],
  });

  static MeasurementWavParseResult failure(List<String> errors,
          {List<String> warnings = const []}) =>
      MeasurementWavParseResult(
          isSuccess: false, errors: errors, warnings: warnings);
}

abstract final class MeasurementWavParser {
  /// Parses [bytes] as a RIFF/WAVE file, walking chunks rather than
  /// assuming any fixed layout. Never assumes fmt precedes data, never
  /// assumes data starts at a fixed offset, skips unknown chunks (padded to
  /// an even boundary per the RIFF spec), and fails closed — never returns
  /// `isSuccess: true` with a nonsensical/partial result.
  static MeasurementWavParseResult parse(Uint8List bytes) {
    final warnings = <String>[];

    if (bytes.length < 12) {
      return MeasurementWavParseResult.failure(
          ['File too short to contain a RIFF header (${bytes.length} bytes).']);
    }

    final view = ByteData.sublistView(bytes);
    final riffTag = _ascii(bytes, 0, 4);
    final waveTag = _ascii(bytes, 8, 4);
    if (riffTag != 'RIFF') {
      return MeasurementWavParseResult.failure(['Missing RIFF header.']);
    }
    if (waveTag != 'WAVE') {
      return MeasurementWavParseResult.failure(['Missing WAVE tag.']);
    }

    int? audioFormatTag;
    int? sampleRate;
    int? channelCount;
    int? bitsPerSample;
    int? dataOffset;
    int? dataLength;

    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final chunkId = _ascii(bytes, offset, 4);
      final declaredSize = view.getUint32(offset + 4, Endian.little);
      final chunkDataStart = offset + 8;

      if (chunkId == 'fmt ') {
        if (chunkDataStart + 16 > bytes.length) {
          return MeasurementWavParseResult.failure(['Truncated fmt chunk.'],
              warnings: warnings);
        }
        audioFormatTag = view.getUint16(chunkDataStart, Endian.little);
        channelCount = view.getUint16(chunkDataStart + 2, Endian.little);
        sampleRate = view.getUint32(chunkDataStart + 4, Endian.little);
        bitsPerSample = view.getUint16(chunkDataStart + 14, Endian.little);

        if (audioFormatTag == kWavFormatTagExtensible) {
          // WAVE_FORMAT_EXTENSIBLE — the real format lives in the
          // extension's SubFormat GUID, not this tag. Layout after the
          // 16-byte base fields: cbSize(2) + validBitsPerSample(2) +
          // channelMask(4) + SubFormat GUID(16) = 24 more bytes, cbSize
          // itself must be >= 22 for the GUID to be present at all.
          if (chunkDataStart + 18 > bytes.length) {
            return MeasurementWavParseResult.failure([
              'Truncated WAVE_FORMAT_EXTENSIBLE fmt chunk (missing cbSize).'
            ], warnings: warnings);
          }
          final cbSize = view.getUint16(chunkDataStart + 16, Endian.little);
          if (cbSize < 22 || chunkDataStart + 18 + cbSize > bytes.length) {
            return MeasurementWavParseResult.failure([
              'Malformed WAVE_FORMAT_EXTENSIBLE fmt chunk — cbSize=$cbSize '
                  'does not carry a SubFormat GUID.'
            ], warnings: warnings);
          }
          final guidOffset = chunkDataStart + 24;
          final guid = bytes.sublist(guidOffset, guidOffset + 16);
          if (!_bytesEqual(guid, _pcmSubFormatGuid)) {
            return MeasurementWavParseResult.failure([
              'Unsupported WAVE_FORMAT_EXTENSIBLE SubFormat — only the PCM '
                  'SubFormat GUID is supported.'
            ], warnings: warnings);
          }
          // SubFormat confirmed PCM — falls through to the same PCM /
          // bit-depth validation below and the same PCM16 decode path in
          // extractNormalizedSamples as a classic tag-1 file.
        }
      } else if (chunkId == 'data') {
        if (chunkDataStart + declaredSize > bytes.length) {
          return MeasurementWavParseResult.failure([
            'data chunk declares $declaredSize bytes but only '
                '${bytes.length - chunkDataStart} are present '
                '(truncated file).'
          ], warnings: warnings);
        }
        dataOffset = chunkDataStart;
        dataLength = declaredSize;
      } else {
        warnings.add('Skipped unrecognized chunk "$chunkId" '
            '($declaredSize bytes).');
      }

      // RIFF chunks are padded to an even byte boundary.
      final paddedSize = declaredSize.isOdd ? declaredSize + 1 : declaredSize;
      final next = chunkDataStart + paddedSize;
      if (next <= offset) {
        break; // guard against a malformed zero/negative advance
      }
      offset = next;
    }

    if (audioFormatTag == null ||
        sampleRate == null ||
        channelCount == null ||
        bitsPerSample == null) {
      return MeasurementWavParseResult.failure(['No fmt chunk found.'],
          warnings: warnings);
    }
    if (dataOffset == null || dataLength == null) {
      return MeasurementWavParseResult.failure(['No data chunk found.'],
          warnings: warnings);
    }
    // audioFormatTag == kWavFormatTagExtensible only survives to this point
    // if the SubFormat GUID was already confirmed PCM above — any other
    // SubFormat already returned failure inside the chunk-walk loop.
    if (audioFormatTag != kWavFormatTagPcm &&
        audioFormatTag != kWavFormatTagExtensible) {
      return MeasurementWavParseResult.failure([
        'Unsupported audio format tag $audioFormatTag — only PCM (1) or '
            'WAVE_FORMAT_EXTENSIBLE with a PCM SubFormat is supported.'
      ], warnings: warnings);
    }
    if (bitsPerSample != kSupportedBitsPerSample) {
      return MeasurementWavParseResult.failure([
        'Unsupported bits-per-sample $bitsPerSample — only '
            '$kSupportedBitsPerSample-bit PCM is supported this phase.'
      ], warnings: warnings);
    }
    if (sampleRate <= 0 || channelCount <= 0) {
      return MeasurementWavParseResult.failure(
          ['Invalid sampleRate/channelCount in fmt chunk.'],
          warnings: warnings);
    }
    if (dataLength <= 0) {
      return MeasurementWavParseResult.failure(
          ['data chunk is empty (zero-length).'],
          warnings: warnings);
    }
    final bytesPerFrame = channelCount * (bitsPerSample ~/ 8);
    if (dataLength % bytesPerFrame != 0) {
      warnings.add('data length ($dataLength bytes) is not an exact '
          'multiple of the frame size ($bytesPerFrame bytes) — trailing '
          'partial frame will be ignored.');
    }
    final frameCount = dataLength ~/ bytesPerFrame;
    final durationSeconds = frameCount / sampleRate;
    if (!durationSeconds.isFinite) {
      return MeasurementWavParseResult.failure(
          ['Computed duration is not finite.'],
          warnings: warnings);
    }

    return MeasurementWavParseResult(
      isSuccess: true,
      audioFormatTag: audioFormatTag,
      sampleRate: sampleRate,
      channelCount: channelCount,
      bitsPerSample: bitsPerSample,
      dataOffset: dataOffset,
      dataLength: dataLength,
      duration: Duration(
          microseconds:
              (durationSeconds * Duration.microsecondsPerSecond).round()),
      warnings: warnings,
    );
  }

  /// Extracts interleaved PCM16 samples normalized to `[-1.0, 1.0]` from a
  /// successful [MeasurementWavParseResult]. Never called with a failed
  /// result — callers must check [MeasurementWavParseResult.isSuccess]
  /// first; this throws [StateError] otherwise rather than guessing.
  static List<double> extractNormalizedSamples(
    Uint8List bytes,
    MeasurementWavParseResult result,
  ) {
    if (!result.isSuccess) {
      throw StateError(
          'extractNormalizedSamples called with a failed parse result.');
    }
    final offset = result.dataOffset!;
    final length = result.dataLength!;
    final view = ByteData.sublistView(bytes, offset, offset + length);
    final sampleCount = length ~/ 2; // 16-bit = 2 bytes/sample
    final out = List<double>.filled(sampleCount, 0.0);
    for (var i = 0; i < sampleCount; i++) {
      final raw = view.getInt16(i * 2, Endian.little);
      out[i] = raw / 32768.0;
    }
    return out;
  }

  static String _ascii(Uint8List bytes, int offset, int length) {
    if (offset + length > bytes.length) return '';
    return String.fromCharCodes(bytes.sublist(offset, offset + length));
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
