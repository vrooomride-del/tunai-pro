// Regression guard for the BLE warm-up ordering bug.
//
// A prior change made MicMeasurementController.startMeasurement() and
// _measureOnce() call player.play() before recorder.start() UNCONDITIONALLY —
// including in normal (non-BLE, e.g. USB) measurement, where bleWarmup is
// false. That silently changed a code path the change wasn't supposed to
// touch, and broke the pre-existing ordering (recorder.start() first, then
// player.setFilePath()/play()) that normal measurement relied on.
//
// Two things are verified here:
//
//   1. WAV length is a pure function of totalSec — buildPinkNoiseWavBytes is
//      an @visibleForTesting extract of the exact byte-building code inside
//      _generatePinkNoise (same bytes, no I/O), so it's testable without
//      path_provider or any platform channel.
//
//   2. Call order — _recorder and _player are concrete `record`/`just_audio`
//      plugin instances with no injection seam, so their real call order
//      can't be observed by invoking the methods in a widget test without a
//      much larger DI refactor than this fix calls for. The regression this
//      guards against is literally a source-order swap of two await
//      statements, so a structural check of the source — "does
//      recorder.start( appear before player.play( inside the bleWarmup==false
//      branch, and after it in the bleWarmup==true branch" — is a precise,
//      low-risk guard for exactly this class of bug. Purely textual checks
//      elsewhere in this test suite (see auto_peq_entry_point_test.dart) use
//      the same technique for the same reason.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/features/mic/mic_measurement_controller.dart';

const _sourcePath = 'lib/features/mic/mic_measurement_controller.dart';

/// Extracts the source text between two method signatures (up to the next
/// top-level method at the same indentation), so branch bodies can be
/// inspected independently of each other.
String _methodBody(String src, String signatureStart) {
  final start = src.indexOf(signatureStart);
  if (start < 0) {
    throw StateError('Could not find "$signatureStart" in $_sourcePath — '
        'has the method been renamed or removed?');
  }
  // Skip past the parameter list first — it may itself contain a `{ ... }`
  // block for named parameters, which is not the method body.
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
  // Now walk forward to the matching closing brace of the method body by
  // simple brace counting from the first '{' after the parameter list.
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

/// Extracts the `if (bleWarmup) { ... } else { ... }` branches from a method
/// body and returns (trueBranch, falseBranch) source text.
(String, String) _warmupBranches(String methodBody) {
  final ifStart = methodBody.indexOf('if (bleWarmup)');
  if (ifStart < 0) {
    throw StateError('Expected an `if (bleWarmup)` branch in:\n$methodBody');
  }

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
  group('BLE warm-up ordering — startMeasurement', () {
    late String bleTrue;
    late String bleFalse;

    setUpAll(() {
      final src = File(_sourcePath).readAsStringSync();
      final body = _methodBody(src, 'Future<void> startMeasurement(');
      (bleTrue, bleFalse) = _warmupBranches(body);
    });

    test('bleWarmup=false preserves the pre-existing order: '
        'recorder.start before player.play', () {
      final recorderIdx = bleFalse.indexOf('_recorder.start(');
      final playerIdx = bleFalse.indexOf('_player.play(');
      expect(recorderIdx, greaterThanOrEqualTo(0));
      expect(playerIdx, greaterThanOrEqualTo(0));
      expect(recorderIdx, lessThan(playerIdx),
          reason: 'Normal (non-BLE) measurement must start the recorder '
              'before playback — this is the exact ordering the regression '
              'inverted.');
    });

    test('bleWarmup=true plays first, then starts the recorder '
        'after the warm-up delay', () {
      final playerIdx = bleTrue.indexOf('_player.play(');
      final delayIdx = bleTrue.indexOf('Future.delayed(Duration(seconds: warmup))');
      final recorderIdx = bleTrue.indexOf('_recorder.start(');
      expect(playerIdx, greaterThanOrEqualTo(0));
      expect(delayIdx, greaterThanOrEqualTo(0));
      expect(recorderIdx, greaterThanOrEqualTo(0));
      expect(playerIdx, lessThan(delayIdx));
      expect(delayIdx, lessThan(recorderIdx));
    });
  });

  group('BLE warm-up ordering — _measureOnce (channel measurement)', () {
    late String bleTrue;
    late String bleFalse;

    setUpAll(() {
      final src = File(_sourcePath).readAsStringSync();
      final body = _methodBody(src, '_measureOnce({');
      (bleTrue, bleFalse) = _warmupBranches(body);
    });

    test('bleWarmup=false preserves the pre-existing order: '
        'recorder.start before player.play', () {
      final recorderIdx = bleFalse.indexOf('_recorder.start(');
      final playerIdx = bleFalse.indexOf('_player.play(');
      expect(recorderIdx, greaterThanOrEqualTo(0));
      expect(playerIdx, greaterThanOrEqualTo(0));
      expect(recorderIdx, lessThan(playerIdx),
          reason: 'Multi-channel measurement must not diverge from '
              'startMeasurement\'s normal-path ordering.');
    });

    test('bleWarmup=true plays first, then starts the recorder '
        'after the warm-up delay', () {
      final playerIdx = bleTrue.indexOf('_player.play(');
      final delayIdx = bleTrue.indexOf('Future.delayed(Duration(seconds: warmup))');
      final recorderIdx = bleTrue.indexOf('_recorder.start(');
      expect(playerIdx, greaterThanOrEqualTo(0));
      expect(delayIdx, greaterThanOrEqualTo(0));
      expect(recorderIdx, greaterThanOrEqualTo(0));
      expect(playerIdx, lessThan(delayIdx));
      expect(delayIdx, lessThan(recorderIdx));
    });
  });

  group('generated WAV length', () {
    test('normal (bleWarmup=false) measurement generates a 10s file', () {
      final bytes = MicMeasurementController.buildPinkNoiseWavBytes(
        totalSec: MicMeasurementController.durationSec,
      );
      const expectedLen =
          44 + MicMeasurementController.sampleRate * 10 * 2; // header + PCM16 mono
      expect(MicMeasurementController.durationSec, 10);
      expect(bytes.length, expectedLen);
    });

    test('BLE warm-up measurement generates a 12s file '
        '(2s warm-up + 10s duration)', () {
      const totalSec = 12; // _bleWarmupSec(2) + durationSec(10)
      final bytes =
          MicMeasurementController.buildPinkNoiseWavBytes(totalSec: totalSec);
      const expectedLen = 44 + MicMeasurementController.sampleRate * totalSec * 2;
      expect(bytes.length, expectedLen);
      expect(bytes.length,
          greaterThan(44 + MicMeasurementController.sampleRate * 10 * 2),
          reason: 'The BLE file must be strictly longer than the normal '
              '10s file — it carries the extra warm-up seconds.');
    });

    test('default call (no totalSec) matches the normal 10s length', () {
      final bytes = MicMeasurementController.buildPinkNoiseWavBytes();
      const expectedLen = 44 + MicMeasurementController.sampleRate * 10 * 2;
      expect(bytes.length, expectedLen);
    });
  });
}
