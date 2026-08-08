// Live Level Check double-verification bug fix — structural regression
// guard, plus the P0 follow-up: single-commit-path / explicit-confirm
// redesign.
//
// Root cause (first pass): _onStableGoodConfirmed() used to stop the live
// session and then automatically call _runLevelCheck() (-> the legacy, real
// WAV-based runInputLevelCheck()) as a SECOND independent truth source —
// which, on real hardware, silently overwrote a genuine live PASS with a
// fresh WAV check's result (sometimes a fail), flipping Setup Ready back to
// FAIL right after the meter showed "적정". That fix replaced the automatic
// re-run with a direct evidence-build (buildLiveLevelPassEvidence).
//
// P0 follow-up: real-hardware evidence showed the auto-confirm still
// sometimes never fired, so this pass adds an explicit "이 레벨로 확인"
// button and unifies BOTH the auto-trigger and the explicit button onto a
// SINGLE commit helper (_confirmLiveLevelPass, renamed from
// _onStableGoodConfirmed) — never two divergent save paths.
//
// This method's body can't be exercised end-to-end without a real
// recorder/player success path (same documented precedent as elsewhere in
// this test suite), so this is a structural source check.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _sourcePath = 'lib/features/mic/guided_measurement_setup_dialog.dart';

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
  late String confirmBody;

  setUpAll(() {
    src = File(_sourcePath).readAsStringSync();
    confirmBody = _methodBody(src, 'Future<void> _confirmLiveLevelPass()');
  });

  test('_confirmLiveLevelPass never calls _runLevelCheck() — the old '
      'auto-trigger of the legacy WAV-based check is gone', () {
    expect(confirmBody.contains('_runLevelCheck()'), isFalse,
        reason: 'A sustained-GOOD live confirmation must never re-run the '
            'legacy WAV-based check automatically — that was the exact '
            'double-verification bug (legacy result silently overwriting '
            'the live PASS).');
  });

  test('_confirmLiveLevelPass never calls runInputLevelCheck directly '
      'either', () {
    expect(confirmBody.contains('runInputLevelCheck('), isFalse);
  });

  test('_confirmLiveLevelPass builds evidence via buildLiveLevelPassEvidence '
      'and persists it via _maybePersistReadiness — the actual fix', () {
    expect(confirmBody.contains('buildLiveLevelPassEvidence('), isTrue);
    expect(confirmBody.contains('_maybePersistReadiness()'), isTrue);
    // Assigns the built evidence to the SAME _levelCheckResult field the
    // legacy manual check has always used — one evidence slot, not a
    // parallel one.
    expect(confirmBody.contains('_levelCheckResult ='), isTrue);
  });

  test('_confirmLiveLevelPass re-checks isStableGood itself (defensive '
      're-verification, not just trusting the caller)', () {
    expect(confirmBody.contains('tracker.isStableGood'), isTrue);
  });

  test('_confirmLiveLevelPass has a re-entry guard (_confirmingLivePass) so '
      'a duplicate call — auto-fire racing an explicit button tap — commits '
      'evidence at most once', () {
    expect(confirmBody.contains('_confirmingLivePass'), isTrue);
    final guardIdx = confirmBody.indexOf('if (_confirmingLivePass)');
    expect(guardIdx, greaterThanOrEqualTo(0));
    expect(guardIdx, lessThan(confirmBody.indexOf('buildLiveLevelPassEvidence(')),
        reason: 're-entry guard must be checked before any evidence work '
            'begins');
  });

  test('_confirmLiveLevelPass stops the live session before building '
      'evidence — snapshot-then-stop ordering (tracker data captured '
      'before teardown)', () {
    final trackerReadIdx = confirmBody.indexOf('tracker.latestDbFs');
    final stopIdx = confirmBody.indexOf('_stopLiveLevelCheckSession()');
    final buildIdx = confirmBody.indexOf('buildLiveLevelPassEvidence(');
    expect(trackerReadIdx, greaterThanOrEqualTo(0));
    expect(stopIdx, greaterThanOrEqualTo(0));
    expect(buildIdx, greaterThanOrEqualTo(0));
    expect(trackerReadIdx, lessThan(stopIdx),
        reason: 'tracker data must be read before the session (and its '
            'tracker) is torn down');
    expect(stopIdx, lessThan(buildIdx),
        reason: 'exclusivity: the live session must be fully stopped before '
            'evidence-building');
  });

  test('BOTH the auto-trigger and the explicit "이 레벨로 확인" button call '
      'the SAME _confirmLiveLevelPass() helper — no second, divergent save '
      'path', () {
    final startBody =
        _methodBody(src, 'Future<void> _startLiveLevelCheck()');
    final sectionBody =
        _methodBody(src, 'Widget _liveLevelCheckSection()');
    expect(startBody.contains('_confirmLiveLevelPass()'), isTrue,
        reason: 'auto-trigger call site');
    expect(sectionBody.contains('_confirmLiveLevelPass()'), isTrue,
        reason: 'explicit confirm button call site');
    expect(sectionBody.contains("Text('이 레벨로 확인')"), isTrue);
  });

  test('중지 (cancel) calls a DIFFERENT method than confirm — cancelling is '
      'never treated as a PASS', () {
    final sectionBody = _methodBody(src, 'Widget _liveLevelCheckSection()');
    final cancelBody =
        _methodBody(src, 'Future<void> _cancelLiveLevelCheck()');
    expect(sectionBody.contains('_cancelLiveLevelCheck()'), isTrue);
    expect(cancelBody.contains('buildLiveLevelPassEvidence'), isFalse,
        reason: 'cancel must never build/persist evidence');
    expect(cancelBody.contains('_maybePersistReadiness'), isFalse);
  });

  test('the confirm button is only enabled once isStableGood is true — '
      'never on a single tick', () {
    final sectionBody = _methodBody(src, 'Widget _liveLevelCheckSection()');
    final buttonIdx = sectionBody.indexOf("Text('이 레벨로 확인')");
    expect(buttonIdx, greaterThanOrEqualTo(0));
    // The nearest onPressed above the button text must reference
    // isStableNow (derived from _stabilityTracker.isStableGood).
    final onPressedIdx = sectionBody.lastIndexOf('onPressed:', buttonIdx);
    final segment = sectionBody.substring(onPressedIdx, buttonIdx);
    expect(segment.contains('isStableNow'), isTrue);
  });

  test('the manual/legacy check (_runLevelCheck, Expert Details button) is '
      'still present in the source — not deleted', () {
    expect(src.contains('Future<void> _runLevelCheck()'), isTrue);
    expect(src.contains("'Play Test Signal & Measure'"), isTrue);
  });

  group('presentation-layer stale-card hiding (item 4)', () {
    test('_buildPreview never nulls out levelCheckEvaluation — the real '
        'evaluation always flows into persistence', () {
      final previewBody = _methodBody(src, 'MeasurementSetupReadinessSnapshot? _buildPreview()');
      expect(previewBody.contains('_liveCheckActive ? null'), isFalse,
          reason: 'the persisted/computed preview must never fake its '
              'evaluation based on live-active state — that was rejected '
              'as a fix approach explicitly (still produced a "not run '
              'yet" blocker, and could taint persistence).');
    });

    test('_displayBlockers filters input-level-specific blocker strings '
        'only while a live session is active', () {
      final filterBody = _methodBody(src, 'List<String> _displayBlockers(');
      expect(filterBody.contains('_liveCheckActive'), isTrue);
      expect(filterBody.contains('_inputLevelBlockerStrings'), isTrue);
    });

    test('the exact blocker strings from the real builder are all covered',
        () {
      const expected = [
        "'Input signal is too low.'",
        "'Input signal is too loud, causing distortion.'",
        "'Input level capture was too short.'",
        "'Input level signal is clipping.'",
        "'Input-level check has not been run yet.'",
        "'Signal-to-noise ratio is too low.'",
      ];
      final setDeclIdx = src.indexOf('_inputLevelBlockerStrings = {');
      final setEnd = src.indexOf('};', setDeclIdx);
      final setBody = src.substring(setDeclIdx, setEnd);
      for (final s in expected) {
        expect(setBody.contains(s), isTrue, reason: 'missing $s');
      }
    });

    test('_resultSection renders via _displayBlockers, not preview.blockers '
        'directly', () {
      final resultBody = _methodBody(src, 'Widget _resultSection(');
      expect(resultBody.contains('_displayBlockers(preview)'), isTrue);
    });

    test('warnings (e.g. background-noise-near-limit) are NEVER filtered — '
        'only the blockers list goes through _displayBlockers, so a '
        'background warning can legitimately stay visible during a live '
        'session', () {
      final resultBody = _methodBody(src, 'Widget _resultSection(');
      // The warnings loop must iterate preview.warnings directly, not a
      // filtered variant.
      expect(resultBody.contains('for (final w in preview.warnings)'),
          isTrue);
    });
  });
}
