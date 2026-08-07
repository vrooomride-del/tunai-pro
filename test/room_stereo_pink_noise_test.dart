// Phase 2 — Stereo Room Measurement test WAV.
//
// buildStereoPinkNoiseWavBytes is a pure function (no I/O, no platform
// channel) so it's testable directly. Verifies:
//   1. Left-only capture: every Right PCM sample is exactly 0
//   2. Right-only capture: every Left PCM sample is exactly 0
//   3. Active-channel RMS is equal between a Left-only and a Right-only run
//   4. Normal 10s / BLE 12s stereo file lengths
//   5. startRoomMeasurement preserves the same BLE-warmup / Local-USB
//      recorder-vs-player call order as startMeasurement (source-level
//      check — no plugin injection seam, same technique as
//      mic_measurement_ble_warmup_test.dart)

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/features/mic/mic_measurement_controller.dart';

const _sourcePath = 'lib/features/mic/mic_measurement_controller.dart';

({List<int> left, List<int> right}) _deinterleave(Uint8List wavBytes) {
  final pcm = Uint8List.sublistView(wavBytes, 44);
  final view = ByteData.sublistView(pcm);
  final frameCount = pcm.length ~/ 4; // 2 channels * 2 bytes
  final left = <int>[];
  final right = <int>[];
  for (var i = 0; i < frameCount; i++) {
    left.add(view.getInt16(i * 4, Endian.little));
    right.add(view.getInt16(i * 4 + 2, Endian.little));
  }
  return (left: left, right: right);
}

double _rms(List<int> samples) {
  if (samples.isEmpty) return 0;
  final sumSquares = samples.fold<double>(0, (acc, s) => acc + s * s);
  return sqrt(sumSquares / samples.length);
}

String _methodBody(String src, String signatureStart) {
  final start = src.indexOf(signatureStart);
  if (start < 0) {
    throw StateError('Could not find "$signatureStart" in $_sourcePath');
  }
  final parenOpen = src.indexOf('(', start);
  var parenDepth = 0;
  var afterParams = parenOpen;
  for (; afterParams < src.length; afterParams++) {
    if (src[afterParams] == '(') parenDepth++;
    if (src[afterParams] == ')') {
      parenDepth--;
      if (parenDepth == 0) break;
    }
  }
  final openBrace = src.indexOf('{', afterParams);
  var depth = 0;
  var i = openBrace;
  for (; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) break;
    }
  }
  return src.substring(start, i + 1);
}

(String, String) _warmupBranches(String methodBody) {
  final ifStart = methodBody.indexOf('if (bleWarmup)');
  final trueOpen = methodBody.indexOf('{', ifStart);
  var depth = 0;
  var i = trueOpen;
  for (; i < methodBody.length; i++) {
    if (methodBody[i] == '{') depth++;
    if (methodBody[i] == '}') {
      depth--;
      if (depth == 0) break;
    }
  }
  final trueBranch = methodBody.substring(trueOpen, i + 1);

  final elseOpen = methodBody.indexOf('{', methodBody.indexOf('else', i));
  depth = 0;
  var j = elseOpen;
  for (; j < methodBody.length; j++) {
    if (methodBody[j] == '{') depth++;
    if (methodBody[j] == '}') {
      depth--;
      if (depth == 0) break;
    }
  }
  final falseBranch = methodBody.substring(elseOpen, j + 1);
  return (trueBranch, falseBranch);
}

void main() {
  group('Stereo Room WAV — channel isolation', () {
    test('Left-only: every Right PCM sample is exactly 0', () {
      final bytes = MicMeasurementController.buildStereoPinkNoiseWavBytes(
        leftActive: true,
        totalSec: 1,
      );
      final (:left, :right) = _deinterleave(bytes);
      expect(right.every((s) => s == 0), isTrue);
      expect(left.any((s) => s != 0), isTrue,
          reason: 'Left must actually carry pink noise, not also be silent.');
    });

    test('Right-only: every Left PCM sample is exactly 0', () {
      final bytes = MicMeasurementController.buildStereoPinkNoiseWavBytes(
        leftActive: false,
        totalSec: 1,
      );
      final (:left, :right) = _deinterleave(bytes);
      expect(left.every((s) => s == 0), isTrue);
      expect(right.any((s) => s != 0), isTrue,
          reason: 'Right must actually carry pink noise, not also be silent.');
    });

    test('no clipping: active channel never reaches +-32768', () {
      final bytes = MicMeasurementController.buildStereoPinkNoiseWavBytes(
        leftActive: true,
        totalSec: 1,
      );
      final (:left, :right) = _deinterleave(bytes);
      expect(left.every((s) => s.abs() <= 32767), isTrue);
      expect(right.every((s) => s.abs() <= 32767), isTrue);
    });

    test(
        'active-channel RMS is equal (same algorithm/gain) between '
        'a Left-only and a Right-only run', () {
      final leftBytes = MicMeasurementController.buildStereoPinkNoiseWavBytes(
        leftActive: true,
        totalSec: 5,
      );
      final rightBytes = MicMeasurementController.buildStereoPinkNoiseWavBytes(
        leftActive: false,
        totalSec: 5,
      );
      final leftRms = _rms(_deinterleave(leftBytes).left);
      final rightRms = _rms(_deinterleave(rightBytes).right);
      // Same pink-noise algorithm/gain on both sides — random per-run but
      // statistically equal RMS over 5s of audio. A generous relative
      // tolerance avoids flakiness while still catching a real gain bug
      // (e.g. one side using a different scale factor).
      expect((leftRms - rightRms).abs() / rightRms, lessThan(0.05));
    });
  });

  group('Stereo Room WAV — length', () {
    test('normal (bleWarmup=false) measurement generates a 10s stereo file',
        () {
      final bytes = MicMeasurementController.buildStereoPinkNoiseWavBytes(
        leftActive: true,
        totalSec: MicMeasurementController.durationSec,
      );
      const expectedLen =
          44 + MicMeasurementController.sampleRate * 10 * 2 * 2; // stereo PCM16
      expect(bytes.length, expectedLen);
    });

    test(
        'BLE warm-up measurement generates a 12s stereo file '
        '(2s warm-up + 10s duration)', () {
      const totalSec = 12;
      final bytes = MicMeasurementController.buildStereoPinkNoiseWavBytes(
        leftActive: true,
        totalSec: totalSec,
      );
      const expectedLen =
          44 + MicMeasurementController.sampleRate * totalSec * 2 * 2;
      expect(bytes.length, expectedLen);
    });
  });

  group('BLE warm-up ordering — startRoomMeasurement', () {
    late String bleTrue;
    late String bleFalse;

    setUpAll(() {
      final src = File(_sourcePath).readAsStringSync();
      final body = _methodBody(src, 'Future<void> startRoomMeasurement(');
      (bleTrue, bleFalse) = _warmupBranches(body);
    });

    test('bleWarmup=false preserves recorder.start before player.play', () {
      final recorderIdx = bleFalse.indexOf('_recorder.start(');
      final playerIdx = bleFalse.indexOf('_player.play(');
      expect(recorderIdx, greaterThanOrEqualTo(0));
      expect(playerIdx, greaterThanOrEqualTo(0));
      expect(recorderIdx, lessThan(playerIdx));
    });

    test(
        'bleWarmup=true plays first, then starts the recorder after '
        'the warm-up delay', () {
      final playerIdx = bleTrue.indexOf('_player.play(');
      final delayIdx =
          bleTrue.indexOf('Future.delayed(Duration(seconds: warmup))');
      final recorderIdx = bleTrue.indexOf('_recorder.start(');
      expect(playerIdx, greaterThanOrEqualTo(0));
      expect(delayIdx, greaterThanOrEqualTo(0));
      expect(recorderIdx, greaterThanOrEqualTo(0));
      expect(playerIdx, lessThan(delayIdx));
      expect(delayIdx, lessThan(recorderIdx));
    });
  });
}
