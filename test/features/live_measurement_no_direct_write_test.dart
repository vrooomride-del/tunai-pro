// TUNAI PRO Measurement Flow Completion — structural regression guards.
//
// Covers what live_measurement_controller_test.dart can't at the runtime
// level:
//  13. Exception cleanup — recorder/player lifecycle in
//      MicMeasurementController is wrapped in try/finally (a runtime test
//      would need real record/just_audio platform channels; this codebase
//      has no fake for them, per the earlier BLE-warmup regression work —
//      see test/mic_measurement_ble_warmup_test.dart for the same technique).
//  14. No direct DSP/transport write reference anywhere in the new live
//      measurement files.
//  15. No automatic mute/output-gain write anywhere in the new files —
//      channel isolation for this phase is manual only.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _controllerPath =
    'lib/features/workbench/tabs/live_measurement_controller.dart';
const _sectionPath =
    'lib/features/workbench/tabs/live_measurement_section.dart';
const _micControllerPath = 'lib/features/mic/mic_measurement_controller.dart';

String _stripLineComments(String src) => src.split('\n').map((line) {
      final i = line.indexOf('//');
      return i < 0 ? line : line.substring(0, i);
    }).join('\n');

void main() {
  group('14. No direct DSP/transport write in the new live measurement files',
      () {
    test('no write/mute call names appear', () {
      final offenders = <String>[];
      for (final path in [_controllerPath, _sectionPath]) {
        final src = _stripLineComments(File(path).readAsStringSync());
        for (final banned in const [
          'writePeqGain',
          'writePeqFrequency',
          'writePeqQ',
          'writeFilterFrequency',
          'writeOutputGain',
          'writeMasterMute',
          'HardwareWriteExecutor',
          'HardwareWriteApproval',
          '.writePort',
          '.transport.',
        ]) {
          if (src.contains(banned)) offenders.add('$path -> $banned');
        }
      }
      expect(offenders, isEmpty,
          reason: 'Live measurement is capture+storage only; any hardware '
              'write must go through the existing Guided AI approval/deploy '
              'path, never from here.\n${offenders.join('\n')}');
    });

    test('no import of transport/write-plan/executor modules', () {
      final offenders = <String>[];
      for (final path in [_controllerPath, _sectionPath]) {
        final src = File(path).readAsStringSync();
        for (final bannedImport in const [
          'transport/adau1701_tuning_transport.dart',
          'transport/icp5_transports.dart',
          'deploy/pro_hardware_write_executor.dart',
          'deploy/pro_hardware_write_approval.dart',
          'deploy/pro_hardware_write_plan.dart',
        ]) {
          if (src.contains(bannedImport)) {
            offenders.add('$path -> $bannedImport');
          }
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });
  });

  group('15. No automatic channel isolation write', () {
    test('no mute/solo write call names appear', () {
      final offenders = <String>[];
      for (final path in [_controllerPath, _sectionPath]) {
        final src = _stripLineComments(File(path).readAsStringSync());
        for (final banned in const [
          'setMute',
          'muteAllExcept',
          'unmuteAll',
          'startChannelMeasurement',
        ]) {
          if (src.contains(banned)) offenders.add('$path -> $banned');
        }
      }
      expect(offenders, isEmpty,
          reason: 'Channel isolation for this phase is manual — the app '
              'must never drive mute/solo, including MicMeasurementController\'s '
              'own DSP-mute-based startChannelMeasurement() path.\n'
              '${offenders.join('\n')}');
    });
  });

  group('13. MicMeasurementController recorder/player cleanup is guaranteed',
      () {
    final src = File(_micControllerPath).readAsStringSync();

    /// Extracts one method's body by simple brace counting, skipping past
    /// the parameter list first (named-parameter blocks contain their own
    /// braces that are not the method body).
    String methodBody(String signatureStart) {
      final start = src.indexOf(signatureStart);
      expect(start, greaterThanOrEqualTo(0),
          reason: 'Could not find "$signatureStart" — has it been renamed?');
      final parenOpen = src.indexOf('(', start);
      var parenDepth = 0;
      var i = parenOpen;
      for (; i < src.length; i++) {
        if (src[i] == '(') parenDepth++;
        if (src[i] == ')') {
          parenDepth--;
          if (parenDepth == 0) break;
        }
      }
      final openBrace = src.indexOf('{', i);
      var depth = 0;
      var j = openBrace;
      for (; j < src.length; j++) {
        if (src[j] == '{') depth++;
        if (src[j] == '}') {
          depth--;
          if (depth == 0) break;
        }
      }
      return src.substring(start, j + 1);
    }

    test('startMeasurement() wraps recording in try/finally with a stop call',
        () {
      final body = methodBody('Future<void> startMeasurement(');
      final tryIdx = body.indexOf('try {');
      final recorderStartIdx = body.indexOf('_recorder.start(');
      final finallyIdx = body.indexOf('} finally {');
      final stopCallIdx = body.indexOf('_safeStopRecorderAndPlayer()');
      expect(tryIdx, greaterThanOrEqualTo(0));
      expect(recorderStartIdx, greaterThanOrEqualTo(0));
      expect(finallyIdx, greaterThanOrEqualTo(0));
      expect(stopCallIdx, greaterThanOrEqualTo(0));
      expect(tryIdx, lessThan(recorderStartIdx),
          reason: 'recorder.start() must be inside the try block');
      expect(recorderStartIdx, lessThan(finallyIdx));
      expect(finallyIdx, lessThan(stopCallIdx),
          reason: 'the stop helper must run in finally, not only on success');
    });

    test('_measureOnce() wraps recording in try/finally with a stop call', () {
      final body =
          methodBody('Future<List<Map<String, double>>> _measureOnce(');
      final tryIdx = body.indexOf('try {');
      final recorderStartIdx = body.indexOf('_recorder.start(');
      final finallyIdx = body.indexOf('} finally {');
      final stopCallIdx = body.indexOf('_safeStopRecorderAndPlayer()');
      expect(tryIdx, greaterThanOrEqualTo(0));
      expect(recorderStartIdx, greaterThanOrEqualTo(0));
      expect(finallyIdx, greaterThanOrEqualTo(0));
      expect(stopCallIdx, greaterThanOrEqualTo(0));
      expect(tryIdx, lessThan(recorderStartIdx));
      expect(recorderStartIdx, lessThan(finallyIdx));
      expect(finallyIdx, lessThan(stopCallIdx));
    });

    test(
        'startChannelMeasurement() still restores mute state on failure '
        '(unchanged — channel isolation stays DSP-mute-based only for '
        'callers that explicitly opt into it, e.g. the orphaned Consumer '
        'screen; live measurement in this phase never calls this method)', () {
      final body = methodBody('Future<void> startChannelMeasurement(');
      final catchIdx = body.indexOf('} catch (e) {');
      final unmuteIdx = body.indexOf('await unmuteAll();', catchIdx);
      expect(catchIdx, greaterThanOrEqualTo(0));
      expect(unmuteIdx, greaterThanOrEqualTo(0));
    });

    test('_safeStopRecorderAndPlayer swallows individual stop failures', () {
      final body = methodBody('Future<void> _safeStopRecorderAndPlayer(');
      expect(body.contains('_recorder.stop()'), isTrue);
      expect(body.contains('_player.stop()'), isTrue);
      expect(RegExp(r'catch\s*\(_\)').allMatches(body).length,
          greaterThanOrEqualTo(2),
          reason: 'each stop call must be isolated so one failing does not '
              'block the other');
    });
  });
}
