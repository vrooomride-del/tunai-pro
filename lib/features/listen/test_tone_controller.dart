import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../../core/tone_generator.dart';
import '../dsp/master_volume_controller.dart';

final testToneProvider =
    StateNotifierProvider.autoDispose<TestToneController, bool>(
  (ref) => TestToneController(ref),
);

class TestToneController extends StateNotifier<bool> {
  TestToneController(this._ref) : super(false) {
    _player = AudioPlayer();
    _volumeSub = _ref.listen<double>(masterVolumeProvider, (_, dB) {
      if (state) _syncVolume(dB);
    });
  }

  final Ref _ref;
  late final AudioPlayer _player;
  late final ProviderSubscription<double> _volumeSub;

  bool get isPlaying => state;

  Future<void> toggle() async {
    if (state) {
      await _player.stop();
      state = false;
    } else {
      await _start();
    }
  }

  Future<void> _start() async {
    final wav = const ToneGenerator(
      frequencyHz: 1000,
      durationSeconds: 2.0,
      amplitude: 0.3,
    ).generateWav();

    await _player.setAudioSource(
      _BytesAudioSource(wav),
      preload: true,
    );
    await _player.setLoopMode(LoopMode.one);
    _syncVolume(_ref.read(masterVolumeProvider));
    await _player.play();
    state = true;
  }

  void _syncVolume(double dB) {
    final linear = (dB <= -70 ? 0.0 : pow(10.0, dB / 20.0).toDouble())
        .clamp(0.0, 1.0);
    _player.setVolume(linear);
  }

  @override
  void dispose() {
    _volumeSub.close();
    _player.dispose();
    super.dispose();
  }
}

class _BytesAudioSource extends StreamAudioSource {
  final Uint8List _bytes;

  _BytesAudioSource(this._bytes) : super(tag: 'test_tone_1khz');

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final s = start ?? 0;
    final e = end ?? _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: e - s,
      offset: s,
      stream: Stream.value(_bytes.sublist(s, e)),
      contentType: 'audio/wav',
    );
  }
}
