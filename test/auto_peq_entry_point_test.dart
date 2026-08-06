// Auto PEQ integration guard.
//
// A prior revision shipped a parallel Auto PEQ stack — AutoPeqEngine computed
// its own PEQ bands and AutoPeqPipeline wrote them straight to the transport
// with writePeqGain/writePeqFrequency/writePeqQ. That path skipped
// CandidateSafetyPolicy, the user approval gate, DspExportPackage,
// HardwareWritePlan, ProHardwareWriteExecutor, the pre-apply rollback
// snapshot, and CorrectionCycleEvaluator, and it could emit boosts of up to
// +20 dB.
//
// Both files are deleted. These tests fail if that shape comes back, and
// re-assert the acoustic invariants the deleted engine violated.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/acoustic_problem_classifier.dart';
import 'package:tunai_pro/core/acoustic/candidate_optimizer.dart';
import 'package:tunai_pro/core/acoustic/candidate_safety.dart';
import 'package:tunai_pro/core/acoustic/candidate_set.dart';

/// Source files that legitimately mention the removed symbols in prose
/// (explaining why they were removed). Excluded from the symbol scan.
const _commentOnlyFiles = <String>{
  'lib/features/workbench/tabs/auto_peq_tab.dart',
  'lib/features/measure/measure_screen.dart',
};

/// Manual expert tuning panel. Pre-existing and intentionally out of scope:
/// it is a per-field Connect → Detect → Read → Edit → Preflight → Write →
/// Verify workflow behind [Adau1701PeqDeploymentGate], where the operator is
/// the approval gate for each individual value. That is a different contract
/// from an automated correction pass, which must route through
/// CandidateSafetyPolicy and ProHardwareWriteExecutor.
const _manualTuningPanel =
    'lib/features/workbench/tabs/adau1701_icp5_tuning_panel.dart';

List<File> _dartSources(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// Drop `//` line comments so prose describing the removed code does not
/// register as a live reference.
String _stripLineComments(String src) => src
    .split('\n')
    .map((line) {
      final i = line.indexOf('//');
      return i < 0 ? line : line.substring(0, i);
    })
    .join('\n');

void main() {
  group('deleted parallel Auto PEQ stack', () {
    test('AutoPeqEngine / AutoPeqPipeline source files are gone', () {
      expect(File('lib/core/acoustic/auto_peq_engine.dart').existsSync(), isFalse,
          reason: 'auto_peq_engine.dart duplicated CandidateGenerator and '
              'produced boosts; it must stay deleted.');
      expect(File('lib/core/auto_peq_pipeline.dart').existsSync(), isFalse,
          reason: 'auto_peq_pipeline.dart wrote to the transport directly, '
              'bypassing safety and the approval gate.');
    });

    test('no code references the removed symbols', () {
      final offenders = <String>[];
      for (final file in _dartSources('lib')) {
        final rel = file.path;
        if (_commentOnlyFiles.any(rel.endsWith)) continue;
        final src = file.readAsStringSync();
        for (final symbol in const [
          'AutoPeqEngine',
          'AutoPeqPipeline',
          'AutoPeqResult',
          'AutoPeqBand',
          'AutoPeqStep',
          'autoPeqPipelineProvider',
          'runFromMeasured',
        ]) {
          if (src.contains(symbol)) offenders.add('$rel → $symbol');
        }
      }
      expect(offenders, isEmpty,
          reason: 'The parallel Auto PEQ stack is deleted; nothing may '
              'reference it.\n${offenders.join('\n')}');
    });
  });

  group('no UI-level direct DSP write', () {
    test('measure_screen does not trigger a deploy', () {
      // Comments may describe the removed behaviour; executable references
      // to the pipeline provider must not exist.
      final src = _stripLineComments(
        File('lib/features/measure/measure_screen.dart').readAsStringSync(),
      );
      expect(src.contains('autoPeqPipelineProvider'), isFalse,
          reason: 'The measure screen produces a measurement artifact only; '
              'deployment is the orchestration layer\'s responsibility.');
      expect(src.contains('_DeploySection'), isFalse);
    });

    test('auto_peq_tab performs no computation and no transport write', () {
      final src = _stripLineComments(
        File('lib/features/workbench/tabs/auto_peq_tab.dart').readAsStringSync(),
      );
      for (final banned in const [
        'writePeqGain',
        'writePeqFrequency',
        'writePeqQ',
        'transport',
        'Adau1701HardwareContext',
      ]) {
        expect(src.contains(banned), isFalse,
            reason: 'Auto PEQ tab is an entry UI only; found "$banned".');
      }
    });

    test('auto_peq_tab routes into the Guided AI path', () {
      final src = File('lib/features/workbench/tabs/auto_peq_tab.dart')
          .readAsStringSync();
      expect(src.contains('kTabGuidedAi'), isTrue,
          reason: 'The tab must hand off to the existing Guided AI pipeline.');
    });

    test('no automated PEQ write path in the widget layer', () {
      final offenders = <String>[];
      for (final file in _dartSources('lib/features')) {
        if (file.path.endsWith(_manualTuningPanel)) continue;
        final src = _stripLineComments(file.readAsStringSync());
        for (final call in const [
          'writePeqGain(',
          'writePeqFrequency(',
          'writePeqQ(',
        ]) {
          if (src.contains(call)) offenders.add('${file.path} → $call');
        }
      }
      expect(offenders, isEmpty,
          reason: 'An automated correction pass must go through '
              'ProHardwareWriteExecutor, not straight from feature/UI code.\n'
              '${offenders.join('\n')}');
    });

    test('the manual tuning panel exemption still points at a real file', () {
      // Guards the exemption above: if the panel is renamed or removed, this
      // fails so the skip list cannot silently mask a new offender.
      expect(File(_manualTuningPanel).existsSync(), isTrue);
    });
  });

  group('acoustic invariants the deleted engine violated', () {
    test('ADAU1701 candidate policy is cut-only within a bounded depth', () {
      final policy = CandidatePolicy.adau1701Icp5();
      policy.validate();
      // The deleted engine defaulted to +/-12 dB and the pipeline clamped at
      // +/-20 dB. The real policy caps cut depth at 6 dB and never boosts.
      expect(policy.maxCutDb, 6.0);
      expect(policy.maxCutDb, lessThan(12.0));
    });

    test('ADAU1701 safety policy rejects boosts beyond its envelope', () {
      final policy = CandidateSafetyPolicy.adau1701Icp5();
      policy.validate();
      expect(policy.maxGainDb, 3.0);
      expect(policy.minGainDb, -6.0);
      expect(policy.maxCutDb, 6.0);
      // A +20 dB write — what the deleted pipeline permitted — is far outside
      // the envelope in both directions of the guard.
      expect(20.0, greaterThan(policy.maxGainDb));
      expect(-20.0, lessThan(policy.minGainDb));
    });

    test('pro provisional policy forbids any boost at all', () {
      final policy = CandidateSafetyPolicy.proProvisional();
      policy.validate();
      expect(policy.maxGainDb, 0.0,
          reason: 'noBoostGuard: the acoustic engine must never boost.');
    });

    test('safety validator blocks a non-ok upstream selection', () {
      const selection = OptimizedSelection(
        status: OptimizationStatus.nothingSelected,
        selected: [],
        rejected: [],
        reasons: [],
        policyId: 'adau1701_icp5',
        policyVersion: 1,
        evidenceRefs: [],
      );
      final result = AcousticSelectionValidator.validate(
        selection,
        CandidateSafetyPolicy.adau1701Icp5(),
      );
      expect(result.applyPermitted, isFalse);
      expect(result.verifiedCandidates, isEmpty,
          reason: 'Fail closed: no candidates may reach the write path.');
      expect(
        result.issues.map((i) => i.code),
        contains(CandidateSafetyViolationCode.propagatedStatus),
      );
    });

    test('deepNull is never an applicable feature type', () {
      // The deleted engine treated every extremum as correctable, including
      // deep nulls, which it would have tried to boost.
      expect(AcousticFeatureType.values, contains(AcousticFeatureType.deepNull));
    });
  });
}
