// FINAL QA CLOSURE #3 §1/§2/§3 — real-hardware root cause regression guard.
//
// A real Mac + UMIK-1 temporal trace showed `player.play() returned` firing
// ~3.8s after `recorder.start() returned`, almost exactly matching the test
// tone's own duration. Cross-checked against just_audio-0.10.5's source
// (AudioPlayer.play() awaits an internal playCompleter that only completes
// when playback FINISHES, not when it starts — see just_audio.dart:1082-1122),
// this proved `runInputLevelCheck`'s `await _player.play();` blocked the
// whole capture routine until the tone had already fully played out. On the
// non-BLE path that meant the subsequent record-duration wait recorded a
// second, fully silent segment AFTER the tone ended, diluting the analyzed
// window with ~50% silence (SNR/RMS dilution). On the BLE path it was worse:
// the recorder only started AFTER playback had already fully finished, so it
// never overlapped with the audible tone at all.
//
// The fix is to stop awaiting player.play() (fire-and-forget), matching the
// method's own intent ("record while the tone plays"). `_player`/`_recorder`
// are concrete plugin instances with no injection seam, so — per the same
// precedent as mic_measurement_ble_warmup_test.dart — this is a precise,
// low-risk structural check of the source: `player.play(` must never be
// preceded by `await ` inside `runInputLevelCheck`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _sourcePath = 'lib/features/mic/mic_measurement_controller.dart';

/// Extracts the source text of a method body (up to its matching closing
/// brace), so runInputLevelCheck can be inspected independently of every
/// other method in the file.
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

void main() {
  late String body;

  setUpAll(() {
    final src = File(_sourcePath).readAsStringSync();
    body = _methodBody(src, 'Future<MeasurementSetupCaptureResult> '
        'runInputLevelCheck(');
  });

  test('player.play() is never awaited inside runInputLevelCheck — '
      'awaiting it blocks until playback FINISHES, not starts', () {
    // Every occurrence of `_player.play(` must be immediately preceded
    // (ignoring whitespace) by `unawaited(`, never by `await `.
    final playCalls = RegExp(r'_player\.play\(').allMatches(body).toList();
    expect(playCalls, isNotEmpty,
        reason: 'Expected at least one _player.play( call in '
            'runInputLevelCheck — has the method been restructured?');

    for (final match in playCalls) {
      final before = body.substring(0, match.start);
      final trimmedBefore = before.trimRight();
      expect(trimmedBefore.endsWith('await'), isFalse,
          reason: 'Found `await _player.play(` in runInputLevelCheck. '
              'just_audio\'s play() Future only completes when playback '
              'finishes, not when it starts — awaiting it here silently '
              'reintroduces the Closure #3 root-cause bug (recorder never '
              'overlaps with the audible tone). Use unawaited(...) instead.');
      expect(trimmedBefore.endsWith('unawaited('), isTrue,
          reason: 'Expected `unawaited(_player.play()` — found '
              'something else immediately before the call:\n'
              '...${trimmedBefore.substring(
                trimmedBefore.length > 40 ? trimmedBefore.length - 40 : 0,
              )}');
    }
  });

  test('the bleWarmup=true branch still plays before the warmup delay and '
      'recorder.start (unawaited dispatch preserves ordering)', () {
    final ifStart = body.indexOf('if (bleWarmup)');
    expect(ifStart, greaterThanOrEqualTo(0));
    final trueOpen = body.indexOf('{', ifStart);
    var depth = 0;
    var i = trueOpen;
    for (; i < body.length; i++) {
      if (body[i] == '{') depth++;
      if (body[i] == '}') {
        depth--;
        if (depth == 0) break;
      }
    }
    final trueBranch = body.substring(trueOpen, i + 1);

    final playIdx = trueBranch.indexOf('_player.play(');
    final delayIdx =
        trueBranch.indexOf('Future.delayed(Duration(seconds: warmup))');
    final recorderIdx = trueBranch.indexOf('_recorder.start(');
    expect(playIdx, greaterThanOrEqualTo(0));
    expect(delayIdx, greaterThanOrEqualTo(0));
    expect(recorderIdx, greaterThanOrEqualTo(0));
    expect(playIdx, lessThan(delayIdx));
    expect(delayIdx, lessThan(recorderIdx));
  });

  test('the bleWarmup=false branch still starts the recorder before '
      'dispatching playback (unawaited dispatch preserves ordering)', () {
    final ifStart = body.indexOf('if (bleWarmup)');
    final trueOpen = body.indexOf('{', ifStart);
    var depth = 0;
    var i = trueOpen;
    for (; i < body.length; i++) {
      if (body[i] == '{') depth++;
      if (body[i] == '}') {
        depth--;
        if (depth == 0) break;
      }
    }
    final elseOpen = body.indexOf('{', body.indexOf('else', i));
    depth = 0;
    var j = elseOpen;
    for (; j < body.length; j++) {
      if (body[j] == '{') depth++;
      if (body[j] == '}') {
        depth--;
        if (depth == 0) break;
      }
    }
    final falseBranch = body.substring(elseOpen, j + 1);

    final recorderIdx = falseBranch.indexOf('_recorder.start(');
    final playIdx = falseBranch.indexOf('_player.play(');
    expect(recorderIdx, greaterThanOrEqualTo(0));
    expect(playIdx, greaterThanOrEqualTo(0));
    expect(recorderIdx, lessThan(playIdx));
  });
}
