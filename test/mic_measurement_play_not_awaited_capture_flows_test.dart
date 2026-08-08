// FINAL QA CLOSURE #3 follow-up (user-approved scope: startMeasurement,
// _measureOnce, startRoomMeasurement) — the same play()-blocks-until-finish
// bug fixed in runInputLevelCheck (see
// mic_measurement_level_check_play_not_awaited_test.dart) also existed in
// these 3 real capture flows. just_audio-0.10.5's AudioPlayer.play() awaits
// an internal playCompleter that only completes when playback FINISHES (or
// is paused/stopped/superseded), never when it starts. Awaiting it here
// previously meant:
//   - bleWarmup=true: the recorder only started AFTER the tone had already
//     fully finished playing — zero overlap with the audible tone.
//   - bleWarmup=false: the recorder started correctly, but the code then
//     waited an ADDITIONAL full durationSec after playback had already
//     ended, recording a second, fully silent segment that dilutes the
//     analyzed window.
//
// _recorder/_player are concrete plugin instances with no injection seam
// (documented precedent: mic_measurement_ble_warmup_test.dart), so this is a
// structural check of the source: player.play( must never be preceded by
// `await ` in any of the three flows, and the record/play ordering each
// flow's own doc comments promise must still hold.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _sourcePath = 'lib/features/mic/mic_measurement_controller.dart';

String _methodBody(String src, String signatureStart) {
  final start = src.indexOf(signatureStart);
  if (start < 0) {
    throw StateError('Could not find "$signatureStart" in $_sourcePath — '
        'has the method been renamed or removed?');
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

/// Asserts every `_player.play(` call inside [body] is fired via
/// `unawaited(...)`, never `await `.
void _expectPlayNeverAwaited(String body, String flowName) {
  final playCalls = RegExp(r'_player\.play\(').allMatches(body).toList();
  expect(playCalls, isNotEmpty,
      reason: 'Expected at least one _player.play( call in $flowName — '
          'has the method been restructured?');
  for (final match in playCalls) {
    final before = body.substring(0, match.start).trimRight();
    expect(before.endsWith('await'), isFalse,
        reason: '[$flowName] Found `await _player.play(`. just_audio\'s '
            'play() Future only completes when playback finishes, not when '
            'it starts — awaiting it here reintroduces the Closure #3 '
            'root-cause bug (recorder/measurement window loses overlap '
            'with the audible tone). Use unawaited(...) instead.');
    expect(before.endsWith('unawaited('), isTrue,
        reason: '[$flowName] Expected `unawaited(_player.play(...)` — '
            'found something else immediately before the call:\n'
            '...${before.substring(before.length > 40 ? before.length - 40 : 0)}');
  }
}

void main() {
  late String src;

  setUpAll(() {
    src = File(_sourcePath).readAsStringSync();
  });

  group('startMeasurement (Factory measurement)', () {
    late String body;
    late String bleTrue;
    late String bleFalse;

    setUpAll(() {
      body = _methodBody(src, 'Future<void> startMeasurement(');
      (bleTrue, bleFalse) = _warmupBranches(body);
    });

    test('player.play() is never awaited', () {
      _expectPlayNeverAwaited(body, 'startMeasurement');
    });

    test('bleWarmup=true still plays before the warmup delay and '
        'recorder.start (unawaited dispatch preserves ordering)', () {
      final playIdx = bleTrue.indexOf('_player.play(');
      final delayIdx =
          bleTrue.indexOf('Future.delayed(Duration(seconds: warmup))');
      final recorderIdx = bleTrue.indexOf('_recorder.start(');
      expect(playIdx, greaterThanOrEqualTo(0));
      expect(delayIdx, greaterThanOrEqualTo(0));
      expect(recorderIdx, greaterThanOrEqualTo(0));
      expect(playIdx, lessThan(delayIdx));
      expect(delayIdx, lessThan(recorderIdx));
    });

    test('bleWarmup=false still starts the recorder before dispatching '
        'playback', () {
      final recorderIdx = bleFalse.indexOf('_recorder.start(');
      final playIdx = bleFalse.indexOf('_player.play(');
      expect(recorderIdx, greaterThanOrEqualTo(0));
      expect(playIdx, greaterThanOrEqualTo(0));
      expect(recorderIdx, lessThan(playIdx));
    });

    test('the measurement-duration wait still exists after the '
        'record/play block (overlap window unchanged in length)', () {
      final blockEnd = body.indexOf('} finally {');
      expect(blockEnd, greaterThan(0));
      final tail = body.substring(0, blockEnd);
      expect(tail, contains('Future.delayed(const Duration(seconds: durationSec))'));
    });
  });

  group('_measureOnce (per-channel measurement)', () {
    late String body;
    late String bleTrue;
    late String bleFalse;

    setUpAll(() {
      body = _methodBody(src, '_measureOnce({');
      (bleTrue, bleFalse) = _warmupBranches(body);
    });

    test('player.play() is never awaited', () {
      _expectPlayNeverAwaited(body, '_measureOnce');
    });

    test('bleWarmup=true still plays before the warmup delay and '
        'recorder.start', () {
      final playIdx = bleTrue.indexOf('_player.play(');
      final delayIdx =
          bleTrue.indexOf('Future.delayed(Duration(seconds: warmup))');
      final recorderIdx = bleTrue.indexOf('_recorder.start(');
      expect(playIdx, greaterThanOrEqualTo(0));
      expect(delayIdx, greaterThanOrEqualTo(0));
      expect(recorderIdx, greaterThanOrEqualTo(0));
      expect(playIdx, lessThan(delayIdx));
      expect(delayIdx, lessThan(recorderIdx));
    });

    test('bleWarmup=false still starts the recorder before dispatching '
        'playback', () {
      final recorderIdx = bleFalse.indexOf('_recorder.start(');
      final playIdx = bleFalse.indexOf('_player.play(');
      expect(recorderIdx, greaterThanOrEqualTo(0));
      expect(playIdx, greaterThanOrEqualTo(0));
      expect(recorderIdx, lessThan(playIdx));
    });
  });

  group('startRoomMeasurement (Room Before/After capture)', () {
    late String body;
    late String bleTrue;
    late String bleFalse;

    setUpAll(() {
      body = _methodBody(src, 'Future<void> startRoomMeasurement(');
      (bleTrue, bleFalse) = _warmupBranches(body);
    });

    test('player.play() is never awaited', () {
      _expectPlayNeverAwaited(body, 'startRoomMeasurement');
    });

    test('bleWarmup=true still plays before the warmup delay and '
        'recorder.start', () {
      final playIdx = bleTrue.indexOf('_player.play(');
      final delayIdx =
          bleTrue.indexOf('Future.delayed(Duration(seconds: warmup))');
      final recorderIdx = bleTrue.indexOf('_recorder.start(');
      expect(playIdx, greaterThanOrEqualTo(0));
      expect(delayIdx, greaterThanOrEqualTo(0));
      expect(recorderIdx, greaterThanOrEqualTo(0));
      expect(playIdx, lessThan(delayIdx));
      expect(delayIdx, lessThan(recorderIdx));
    });

    test('bleWarmup=false still starts the recorder before dispatching '
        'playback', () {
      final recorderIdx = bleFalse.indexOf('_recorder.start(');
      final playIdx = bleFalse.indexOf('_player.play(');
      expect(recorderIdx, greaterThanOrEqualTo(0));
      expect(playIdx, greaterThanOrEqualTo(0));
      expect(recorderIdx, lessThan(playIdx));
    });

    test('the Left/Right inactive-channel-zero stereo generation call is '
        'unchanged by this fix', () {
      expect(body, contains('_generateStereoPinkNoise('));
      expect(body, contains('leftActive: leftActive'));
    });
  });

  group('unawaited play() calls swallow async errors (no unhandled '
      'zone exception if activation/playback fails)', () {
    test('every unawaited(_player.play() call chains .catchError', () {
      final matches =
          RegExp(r'unawaited\(_player\.play\(\)([^;]*)\);').allMatches(src);
      expect(matches, isNotEmpty);
      for (final m in matches) {
        expect(m.group(1), contains('.catchError('),
            reason: 'unawaited(_player.play()...) must swallow async '
                'errors the same way _safeStopRecorderAndPlayer already '
                'does, so a session-activation failure cannot surface as '
                'an unhandled Future error since nothing awaits it.');
      }
    });
  });

  test('exactly 5 capture flows use the unawaited(play()) pattern — '
      'runInputLevelCheck, startMeasurement, _measureOnce, '
      'startRoomMeasurement, startLiveLevelCheck (scope guard: no unrelated '
      'call site silently changed)', () {
    final count = RegExp(r'unawaited\(_player\.play\(').allMatches(src).length;
    expect(count, 9,
        reason: '4 flows x 2 branches (bleWarmup true/false) each = 8, '
            'plus startLiveLevelCheck\'s single (no bleWarmup split) call = '
            '9. If this changes, a call site was added/removed outside the '
            'explicitly approved scope.');
  });
}
