import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/speaker_profile.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:fftea/fftea.dart';

enum MeasurementStatus { idle, playing, recording, analyzing, done, error }

class MicMeasurementState {
  final MeasurementStatus status;
  final String message;
  final List<Map<String, double>> frequencyResponse; // {freq, db}
  final String? error;

  const MicMeasurementState({
    this.status = MeasurementStatus.idle,
    this.message = '',
    this.frequencyResponse = const [],
    this.error,
  });

  MicMeasurementState copyWith({
    MeasurementStatus? status,
    String? message,
    List<Map<String, double>>? frequencyResponse,
    String? error,
  }) => MicMeasurementState(
    status: status ?? this.status,
    message: message ?? this.message,
    frequencyResponse: frequencyResponse ?? this.frequencyResponse,
    error: error ?? this.error,
  );
}

final micMeasurementProvider = StateNotifierProvider<MicMeasurementController, MicMeasurementState>(
  (ref) => MicMeasurementController(),
);

class MicMeasurementController extends StateNotifier<MicMeasurementState> {
  MicMeasurementController() : super(const MicMeasurementState());

  final _recorder = AudioRecorder();
  final _player = AudioPlayer();

  static const int sampleRate = 48000;
  static const int fftSize = 65536;
  static const int durationSec = 10;

  Future<void> startMeasurement({List<double>? scfCorrection, SpeakerProfile? speakerProfile}) async {
    try {
      // 권한 확인
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        state = state.copyWith(
          status: MeasurementStatus.error,
          error: '마이크 권한이 필요합니다.',
        );
        return;
      }

      // 핑크노이즈 생성 + 저장
      state = state.copyWith(status: MeasurementStatus.playing, message: '핑크노이즈 생성 중...');
      final wavFile = await _generatePinkNoise();

      // 녹음 시작
      final dir = await getTemporaryDirectory();
      final recPath = '${dir.path}/tunai_pro_measurement.wav';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: sampleRate,
          numChannels: 1,
        ),
        path: recPath,
      );

      // 핑크노이즈 재생
      state = state.copyWith(message: '측정 중... ($durationSec초)');
      await _player.setFilePath(wavFile.path);
      await _player.play();
      await Future.delayed(const Duration(seconds: durationSec));

      // 정지
      await _recorder.stop();
      await _player.stop();

      // FFT 분석
      state = state.copyWith(status: MeasurementStatus.analyzing, message: 'FFT 분석 중...');
      final pcmBytes = await File(recPath).readAsBytes();
      final rawPcm = Uint8List.sublistView(pcmBytes, 44);
      final samples = _pcmToFloat(rawPcm);
      final response = _analyzeFFT(samples, scfCorrection: scfCorrection, speakerProfile: speakerProfile);

      state = state.copyWith(
        status: MeasurementStatus.done,
        message: '측정 완료',
        frequencyResponse: response,
      );
    } catch (e) {
      state = state.copyWith(
        status: MeasurementStatus.error,
        error: e.toString(),
      );
    }
  }

  void reset() => state = const MicMeasurementState();

  Float64List _pcmToFloat(Uint8List pcmBytes) {
    final samples = Float64List(pcmBytes.length ~/ 2);
    final view = ByteData.sublistView(pcmBytes);
    for (int i = 0; i < samples.length; i++) {
      samples[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return samples;
  }

  List<Map<String, double>> _analyzeFFT(Float64List samples,
      {List<double>? scfCorrection, SpeakerProfile? speakerProfile}) {
    final input = Float64List(fftSize);
    final copyLen = min(samples.length, fftSize);
    for (int i = 0; i < copyLen; i++) {
      final window = 0.5 * (1 - cos(2 * pi * i / (copyLen - 1)));
      input[i] = samples[i] * window;
    }

    final fft = FFT(fftSize);
    final freq = fft.realFft(input);
    final result = <Map<String, double>>[];
    const nyquist = fftSize ~/ 2;

    // 1/3 옥타브 밴딩으로 스무딩
    final bands = <double, List<double>>{};
    for (int i = 1; i < nyquist; i++) {
      final f = i * sampleRate / fftSize.toDouble();
      if (f < 20 || f > 20000) continue;
      final re = freq[i].x;
      final im = freq[i].y;
      final mag = sqrt(re * re + im * im) / fftSize;
      if (mag <= 0) continue;
      final db = 20 * log(mag) / ln10;

      // 1/3 옥타브 밴드 중심 주파수로 그룹화
      final band = _nearestThirdOctave(f);
      bands.putIfAbsent(band, () => []).add(db);
    }

    final sortedBands = bands.keys.toList()..sort();
    for (int i = 0; i < sortedBands.length; i++) {
      final f = sortedBands[i];
      final dbs = bands[f]!;
      double avgDb = dbs.reduce((a, b) => a + b) / dbs.length;

      // SCF 보정 적용
      if (scfCorrection != null && i < scfCorrection.length) {
        avgDb += scfCorrection[i];
      }

      result.add({'frequency': f, 'db': avgDb});
    }

    return result;
  }

  double _nearestThirdOctave(double freq) {
    // 1/3 옥타브 밴드 중심 주파수 (ISO 표준)
    const centers = [
      20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160,
      200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600,
      2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000
    ];
    double nearest = centers[0].toDouble();
    double minDist = (freq - nearest).abs();
    for (final c in centers) {
      final dist = (freq - c).abs();
      if (dist < minDist) {
        minDist = dist;
        nearest = c.toDouble();
      }
    }
    return nearest;
  }

  Future<File> _generatePinkNoise() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/pink_noise_pro.wav');
    const totalSamples = sampleRate * durationSec;
    final pcm = Int16List(totalSamples);

    // Paul Kellet 핑크노이즈
    double b0=0, b1=0, b2=0, b3=0, b4=0, b5=0, b6=0;
    final rng = Random();
    for (int i = 0; i < totalSamples; i++) {
      final white = rng.nextDouble() * 2 - 1;
      b0 = 0.99886*b0 + white*0.0555179;
      b1 = 0.99332*b1 + white*0.0750759;
      b2 = 0.96900*b2 + white*0.1538520;
      b3 = 0.86650*b3 + white*0.3104856;
      b4 = 0.55000*b4 + white*0.5329522;
      b5 = -0.7616*b5 - white*0.0168980;
      final pink = (b0+b1+b2+b3+b4+b5+b6+white*0.5362) * 0.11;
      b6 = white * 0.115926;
      pcm[i] = (pink.clamp(-1.0, 1.0) * 32767).round();
    }

    // WAV 헤더 생성
    const dataSize = totalSamples * 2;
    final header = ByteData(44);
    void setStr(int offset, String s) {
      for (int i = 0; i < s.length; i++) { header.setUint8(offset + i, s.codeUnitAt(i)); }
    }
    setStr(0, 'RIFF'); header.setUint32(4, 36 + dataSize, Endian.little);
    setStr(8, 'WAVE'); setStr(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    setStr(36, 'data'); header.setUint32(40, dataSize, Endian.little);

    final wavBytes = BytesBuilder();
    wavBytes.add(header.buffer.asUint8List());
    wavBytes.add(pcm.buffer.asUint8List());
    await file.writeAsBytes(wavBytes.toBytes());
    return file;
  }

  @override
  void dispose() {
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }
}
