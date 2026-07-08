import 'dart:math';
import 'dart:typed_data';

/// 순수 사인파 테스트 톤 WAV 생성 — CONNECT 완료 후 "들리나요?" 확인용.
/// PinkNoiseGenerator와 동일한 WAV 헤더 구조, 파형만 사인파로 교체.
class ToneGenerator {
  static const int sampleRate = 44100;
  static const int channels = 1; // mono

  final double frequencyHz;
  final double durationSeconds;
  final double amplitude; // 0.0~1.0 — 테스트 톤이라 과하게 크지 않도록 기본 낮춤

  const ToneGenerator({
    this.frequencyHz = 1000,
    this.durationSeconds = 1.0,
    this.amplitude = 0.3,
  });

  /// 16-bit PCM WAV 바이트 생성
  Uint8List generateWav() {
    final totalSamples = (sampleRate * durationSeconds).round();
    final dataSize = totalSamples * 2; // 16bit = 2bytes per sample
    final fileSize = 44 + dataSize;

    final buf = ByteData(fileSize);

    // WAV Header
    // RIFF
    buf.setUint8(0, 0x52); buf.setUint8(1, 0x49);
    buf.setUint8(2, 0x46); buf.setUint8(3, 0x46);
    buf.setUint32(4, fileSize - 8, Endian.little);
    // WAVE
    buf.setUint8(8, 0x57); buf.setUint8(9, 0x41);
    buf.setUint8(10, 0x56); buf.setUint8(11, 0x45);
    // fmt chunk
    buf.setUint8(12, 0x66); buf.setUint8(13, 0x6D);
    buf.setUint8(14, 0x74); buf.setUint8(15, 0x20);
    buf.setUint32(16, 16, Endian.little);       // chunk size
    buf.setUint16(20, 1, Endian.little);         // PCM
    buf.setUint16(22, channels, Endian.little);  // channels
    buf.setUint32(24, sampleRate, Endian.little);
    buf.setUint32(28, sampleRate * channels * 2, Endian.little); // byte rate
    buf.setUint16(32, channels * 2, Endian.little); // block align
    buf.setUint16(34, 16, Endian.little);        // bits per sample
    // data chunk
    buf.setUint8(36, 0x64); buf.setUint8(37, 0x61);
    buf.setUint8(38, 0x74); buf.setUint8(39, 0x61);
    buf.setUint32(40, dataSize, Endian.little);

    // PCM samples — 짧은 페이드인/아웃으로 클릭음 방지
    final fadeSamples = (sampleRate * 0.01).round(); // 10ms
    for (int i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      var env = 1.0;
      if (i < fadeSamples) env = i / fadeSamples;
      if (i > totalSamples - fadeSamples) env = (totalSamples - i) / fadeSamples;
      final value = sin(2 * pi * frequencyHz * t) * amplitude * env;
      final sample = (value * 32767).round().clamp(-32768, 32767);
      buf.setInt16(44 + i * 2, sample, Endian.little);
    }

    return buf.buffer.asUint8List();
  }
}
