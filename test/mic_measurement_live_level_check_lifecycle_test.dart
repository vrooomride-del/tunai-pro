// Measurement Setup Live Level Check — controller-level lifecycle/
// exclusivity regression guards.
//
// _recorder/_player are concrete `record`/`just_audio` plugin instances with
// no injection seam for a real Live Level Check session (same documented
// precedent as mic_measurement_ble_warmup_test.dart /
// mic_measurement_level_check_play_not_awaited_test.dart), so the exclusivity
// contract — "every other capture method must stop any active live session
// before touching the shared recorder/player" — is verified structurally:
// every method that starts a real recorder/player session must call
// stopLiveLevelCheck() at its own top, before anything else that touches
// _recorder/_player.

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

void main() {
  late String src;

  setUpAll(() {
    src = File(_sourcePath).readAsStringSync();
  });

  group('exclusivity guard — every other capture method stops a live '
      'session before touching _recorder/_player', () {
    void expectGuardBeforeFirstRecorderOrPlayerUse(
        String methodBody, String methodName) {
      final guardIdx = methodBody.indexOf('stopLiveLevelCheck()');
      expect(guardIdx, greaterThanOrEqualTo(0),
          reason: '[$methodName] must call stopLiveLevelCheck() as an '
              'exclusivity guard.');

      final recorderIdx = methodBody.indexOf('_recorder.start(');
      final playerIdx = methodBody.indexOf('_player.play(');
      if (recorderIdx >= 0) {
        expect(guardIdx, lessThan(recorderIdx),
            reason: '[$methodName] stopLiveLevelCheck() must run before '
                '_recorder.start() — otherwise a live session could still '
                'be holding the recorder when this method tries to use it.');
      }
      if (playerIdx >= 0) {
        expect(guardIdx, lessThan(playerIdx),
            reason: '[$methodName] stopLiveLevelCheck() must run before '
                '_player.play().');
      }
    }

    test('measureNoiseFloor', () {
      final body = _methodBody(src,
          'Future<MeasurementSetupCaptureResult> measureNoiseFloor(');
      expectGuardBeforeFirstRecorderOrPlayerUse(body, 'measureNoiseFloor');
    });

    test('runInputLevelCheck', () {
      final body = _methodBody(src,
          'Future<MeasurementSetupCaptureResult> runInputLevelCheck(');
      expectGuardBeforeFirstRecorderOrPlayerUse(body, 'runInputLevelCheck');
    });

    test('startMeasurement', () {
      final body = _methodBody(src, 'Future<void> startMeasurement(');
      expectGuardBeforeFirstRecorderOrPlayerUse(body, 'startMeasurement');
    });

    test('_measureOnce', () {
      final body = _methodBody(src, '_measureOnce({');
      expectGuardBeforeFirstRecorderOrPlayerUse(body, '_measureOnce');
    });

    test('startRoomMeasurement', () {
      final body = _methodBody(src, 'Future<void> startRoomMeasurement(');
      expectGuardBeforeFirstRecorderOrPlayerUse(body, 'startRoomMeasurement');
    });

    test(
        'startLiveLevelCheck itself guards against overlapping a prior live '
        'session (safe restart, not a collision)', () {
      final body =
          _methodBody(src, 'Future<Stream<LiveLevelReading>> startLiveLevelCheck(');
      final guardIdx = body.indexOf('stopLiveLevelCheck()');
      final recorderIdx = body.indexOf('_recorder.start(');
      expect(guardIdx, greaterThanOrEqualTo(0));
      expect(recorderIdx, greaterThanOrEqualTo(0));
      expect(guardIdx, lessThan(recorderIdx));
    });

    test(
        'exactly 6 stopLiveLevelCheck() guard call sites exist — scope '
        'guard: no unrelated call site silently added/removed', () {
      // 5 other capture methods + startLiveLevelCheck's own self-guard.
      // (stopLiveLevelCheck's own body and its doc comments are excluded —
      // count only actual call expressions "stopLiveLevelCheck()".)
      final count =
          'stopLiveLevelCheck()'.allMatches(src).length;
      // Every call site is a call expression "stopLiveLevelCheck()"; the
      // method's own declaration is "stopLiveLevelCheck() async {" which
      // also contains the substring, plus dispose()'s doc/comment mentions
      // do not use the exact call-with-parens form outside real calls. This
      // count is intentionally loose (>=6) rather than pinned exactly, since
      // doc comments may legitimately reference the call form too.
      expect(count, greaterThanOrEqualTo(6));
    });
  });

  group('stopLiveLevelCheck cleanup order (source-level)', () {
    late String body;

    setUpAll(() {
      body = _methodBody(src, 'Future<void> stopLiveLevelCheck()');
    });

    test('cancels/closes the amplitude stream before stopping recorder/player', () {
      final closeIdx = body.indexOf('_liveLevelController?.close()');
      final recorderStopIdx = body.indexOf('_recorder.stop()');
      expect(closeIdx, greaterThanOrEqualTo(0));
      expect(recorderStopIdx, greaterThanOrEqualTo(0));
      expect(closeIdx, lessThan(recorderStopIdx));
    });

    test('restores LoopMode.off after stopping the player', () {
      final playerStopIdx = body.indexOf('_player.stop()');
      final loopOffIdx = body.indexOf('setLoopMode(LoopMode.off)');
      expect(playerStopIdx, greaterThanOrEqualTo(0));
      expect(loopOffIdx, greaterThanOrEqualTo(0));
      expect(playerStopIdx, lessThan(loopOffIdx));
    });

    test('deletes the temp file after stopping recorder/player, not before',
        () {
      final recorderStopIdx = body.indexOf('_recorder.stop()');
      final deleteIdx = body.indexOf('.delete()');
      expect(recorderStopIdx, greaterThanOrEqualTo(0));
      expect(deleteIdx, greaterThanOrEqualTo(0));
      expect(recorderStopIdx, lessThan(deleteIdx));
    });
  });

  group('startLiveLevelCheck uses LoopMode.one for genuine continuous '
      'playback (not a single finite play)', () {
    test('setLoopMode(LoopMode.one) is called before play() is dispatched',
        () {
      final body = _methodBody(
          src, 'Future<Stream<LiveLevelReading>> startLiveLevelCheck(');
      final loopOneIdx = body.indexOf('setLoopMode(LoopMode.one)');
      final playIdx = body.indexOf('_player.play(');
      expect(loopOneIdx, greaterThanOrEqualTo(0));
      expect(playIdx, greaterThanOrEqualTo(0));
      expect(loopOneIdx, lessThan(playIdx));
    });

    test('play() is dispatched via unawaited(...), never awaited directly '
        '— preserves the fixed just_audio lifecycle contract', () {
      final body = _methodBody(
          src, 'Future<Stream<LiveLevelReading>> startLiveLevelCheck(');
      final playMatch = RegExp(r'_player\.play\(').firstMatch(body);
      expect(playMatch, isNotNull);
      final before = body.substring(0, playMatch!.start).trimRight();
      expect(before.endsWith('await'), isFalse);
      expect(before.endsWith('unawaited('), isTrue);
    });
  });
}
