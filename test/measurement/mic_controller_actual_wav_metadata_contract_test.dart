// Phase 3-D3A-3 §14 — production actual-WAV-metadata contract guard.
//
// MicMeasurementState.actualSampleRate/actualChannelCount default to the
// nominal 48000/1 ONLY so legacy test fakes that stub startMeasurement/
// startRoomMeasurement without touching a real WAV keep behaving as before
// (Phase 3-D3A-2 §2/§14 explicitly warns against mistaking that default for
// a production guarantee). The real recorder path
// (MicMeasurementController.startMeasurement/startRoomMeasurement) cannot be
// driven end-to-end in a unit test without a real platform recorder/player,
// so this is a source-contract check instead: it proves the exact success
// state-update call sites always thread the ACTUAL parsed
// wavResult.actualSampleRate/actualChannelCount through, rather than ever
// silently falling back to the nominal default or omitting the fields (which
// would silently re-open the "provenance built from nominal defaults, not
// the real capture" gap this phase closes).
//
// If this test ever needs to change because the source shape legitimately
// changed, that change itself is exactly the kind of regression this test
// exists to catch — verify by hand that the new code still threads the real
// parsed values before updating the expected pattern.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'startMeasurement/startRoomMeasurement success paths set '
      'actualSampleRate/actualChannelCount from the parsed WAV result, '
      'never a bare nominal default', () {
    final source = File('lib/features/mic/mic_measurement_controller.dart')
        .readAsStringSync();

    // Every `_readAndParseRecordedWav` call site's result variable name.
    const resultVar = 'wavResult';
    expect(source.contains('final $resultVar = await _readAndParseRecordedWav'),
        isTrue,
        reason: '_readAndParseRecordedWav must still be the one WAV-parsing '
            'chokepoint whose actual result feeds capture state.');

    // Both success-path state.copyWith(...) blocks that set status: done
    // must explicitly thread the real parsed values.
    final doneBlocks = RegExp(
            r'status:\s*MeasurementStatus\.done,[\s\S]{0,600}?\);',
            multiLine: true)
        .allMatches(source)
        .map((m) => m.group(0)!)
        .toList();

    // startMeasurement + startRoomMeasurement each produce one such block
    // (a third, unrelated `status: MeasurementStatus.done` block exists for
    // the per-channel startChannelMeasurement path, which does not carry
    // actual WAV metadata forward today — only the two capture paths this
    // phase's Accept gate actually consumes are asserted here).
    final withActualMetadata = doneBlocks
        .where((b) =>
            b.contains('actualSampleRate: $resultVar.actualSampleRate') &&
            b.contains('actualChannelCount: $resultVar.actualChannelCount'))
        .toList();

    expect(withActualMetadata.length, 2,
        reason: 'Expected exactly startMeasurement + startRoomMeasurement to '
            'set actualSampleRate/actualChannelCount from the parsed WAV '
            'result on their success path. Found ${withActualMetadata.length} '
            'such blocks out of ${doneBlocks.length} total "done" blocks — '
            'if this legitimately changed, verify by hand that actual '
            '(not nominal-default) values still reach MicMeasurementState '
            'before updating this test.');
  });

  test(
      'MicMeasurementState nominal defaults are for test-fake compatibility '
      'only, documented as such', () {
    final source = File('lib/features/mic/mic_measurement_controller.dart')
        .readAsStringSync();
    expect(
        source.contains(
            'this.actualSampleRate = MicMeasurementController.sampleRate'),
        isTrue);
    expect(source.contains('this.actualChannelCount = 1'), isTrue);
    // The doc comment explaining WHY the default exists must still be present
    // — this is the guard against a future reader assuming the default is a
    // production guarantee rather than a test-compatibility fallback.
    expect(source.contains('fakes/tests that stub'), isTrue);
  });
}
