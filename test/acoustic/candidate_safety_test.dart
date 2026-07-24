import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/acoustic_problem_classifier.dart';
import 'package:tunai_pro/core/acoustic/candidate_optimizer.dart';
import 'package:tunai_pro/core/acoustic/candidate_safety.dart';
import 'package:tunai_pro/core/acoustic/candidate_scoring.dart';
import 'package:tunai_pro/core/acoustic/candidate_set.dart';
import 'package:tunai_pro/core/acoustic/correction_plan.dart';

// ── Test helpers ──────────────────────────────────────────────────────────────

const _defaultPolicy = CandidateSafetyPolicy(
  id: 'test_policy',
  version: 1,
  maxCutDb: 9.0,
  minFrequencyHz: 20.0,
  maxFrequencyHz: 20000.0,
  availableSlots: 10,
);

PeqCandidate _peq({
  required String featureId,
  double frequencyHz = 1000.0,
  double gainDb = -6.0,
  double q = 4.0,
  AcousticFeatureType featureType = AcousticFeatureType.narrowPeak,
}) =>
    PeqCandidate(
      candidateId: 'candidate:$featureId',
      featureId: featureId,
      featureType: featureType,
      frequencyHz: frequencyHz,
      gainDb: gainDb,
      q: q,
      intent: CorrectionIntent.cut,
      reason: 'test',
    );

ScoredCandidate _scoredFrom(PeqCandidate peq, {int rank = 1}) =>
    ScoredCandidate(
      candidate: peq,
      prominenceDb: 6.0,
      prominenceScore: 40.0,
      magnitudeConsistencyScore: 30.0,
      qualityFactor: 1.0,
      compositeScore: 70.0,
      rank: rank,
      grade: CandidateScoreGrade.excellent,
      reasons: const ['test'],
    );

SelectedCandidate _sel(
  ScoredCandidate scored, {
  int applicationOrder = 1,
}) =>
    SelectedCandidate(
      scoredCandidate: scored,
      applicationOrder: applicationOrder,
      selectionReason: 'test selection',
    );

OptimizedSelection _optimized(
  List<SelectedCandidate> selected, {
  OptimizationStatus status = OptimizationStatus.ok,
}) =>
    OptimizedSelection(
      status: status,
      selected: selected,
      rejected: const [],
      reasons: const ['test'],
      policyId: 'optimizer_policy',
      policyVersion: 1,
      evidenceRefs: const ['ev1'],
    );

CandidateSafetyResult _validate(
  List<SelectedCandidate> selected, {
  OptimizationStatus status = OptimizationStatus.ok,
  CandidateSafetyPolicy policy = _defaultPolicy,
}) =>
    AcousticSelectionValidator.validate(
      _optimized(selected, status: status),
      policy,
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('valid selection', () {
    test('single valid candidate → applyPermitted=true', () {
      final sc = _sel(_scoredFrom(_peq(featureId: 'f1')));
      final result = _validate([sc]);

      expect(result.applyPermitted, isTrue);
      expect(result.issues, isEmpty);
      expect(result.verifiedCandidates, hasLength(1));
      expect(result.verifiedCandidates.single.scoredCandidate.candidate.featureId,
          'f1');
    });

    test('three valid candidates → all verified', () {
      final selected = [
        _sel(_scoredFrom(_peq(featureId: 'f1', frequencyHz: 100.0)), applicationOrder: 1),
        _sel(_scoredFrom(_peq(featureId: 'f2', frequencyHz: 500.0)), applicationOrder: 2),
        _sel(_scoredFrom(_peq(featureId: 'f3', frequencyHz: 4000.0)), applicationOrder: 3),
      ];
      final result = _validate(selected);

      expect(result.applyPermitted, isTrue);
      expect(result.verifiedCandidates, hasLength(3));
      expect(result.issues, isEmpty);
    });

    test('verifiedCandidates equals selected list on success', () {
      final sc = _sel(_scoredFrom(_peq(featureId: 'f1')));
      final selection = _optimized([sc]);
      final result = AcousticSelectionValidator.validate(selection, _defaultPolicy);

      expect(result.verifiedCandidates, equals(selection.selected));
    });

    test('gainDb exactly at -maxCutDb → permitted (boundary)', () {
      final sc = _sel(_scoredFrom(
          _peq(featureId: 'f1', gainDb: -_defaultPolicy.maxCutDb)));
      final result = _validate([sc]);
      expect(result.applyPermitted, isTrue);
    });

    test('frequencyHz exactly at minFrequencyHz → permitted (boundary)', () {
      final sc = _sel(_scoredFrom(
          _peq(featureId: 'f1', frequencyHz: _defaultPolicy.minFrequencyHz)));
      final result = _validate([sc]);
      expect(result.applyPermitted, isTrue);
    });

    test('frequencyHz exactly at maxFrequencyHz → permitted (boundary)', () {
      final sc = _sel(_scoredFrom(
          _peq(featureId: 'f1', frequencyHz: _defaultPolicy.maxFrequencyHz)));
      final result = _validate([sc]);
      expect(result.applyPermitted, isTrue);
    });
  });

  group('noBoostGuard — positive gainDb', () {
    test('gainDb > 0 → applyPermitted=false, noBoostGuard issue', () {
      final sc = _sel(_scoredFrom(_peq(featureId: 'f1', gainDb: 3.0)));
      final result = _validate([sc]);

      expect(result.applyPermitted, isFalse);
      expect(result.verifiedCandidates, isEmpty);
      expect(result.issues, hasLength(1));
      expect(result.issues.single.code,
          CandidateSafetyViolationCode.noBoostGuard);
      expect(result.issues.single.candidateId, 'candidate:f1');
    });

    test('gainDb = 0.0 → permitted (exact zero is a cut of 0)', () {
      final sc = _sel(_scoredFrom(_peq(featureId: 'f1', gainDb: 0.0)));
      final result = _validate([sc]);
      expect(result.applyPermitted, isTrue);
    });
  });

  group('cutTooDeep — excessive cut', () {
    test('gainDb below -maxCutDb → applyPermitted=false, cutTooDeep', () {
      final sc = _sel(_scoredFrom(
          _peq(featureId: 'f1', gainDb: -15.0))); // -15 < -9
      final result = _validate([sc]);

      expect(result.applyPermitted, isFalse);
      expect(result.verifiedCandidates, isEmpty);
      expect(result.issues.single.code,
          CandidateSafetyViolationCode.cutTooDeep);
      expect(result.issues.single.candidateId, 'candidate:f1');
      expect(result.issues.single.detail, contains('−9.0 dB'));
    });

    test('cutTooDeep issue detail contains the actual gainDb value', () {
      final sc = _sel(_scoredFrom(_peq(featureId: 'f1', gainDb: -12.5)));
      final result = _validate([sc]);
      expect(result.issues.single.detail, contains('-12.50'));
    });
  });

  group('frequencyOutOfRange', () {
    test('frequencyHz below minFrequencyHz → frequencyOutOfRange', () {
      final sc = _sel(_scoredFrom(
          _peq(featureId: 'f1', frequencyHz: 10.0))); // < 20 Hz
      final result = _validate([sc]);

      expect(result.applyPermitted, isFalse);
      expect(result.issues.single.code,
          CandidateSafetyViolationCode.frequencyOutOfRange);
      expect(result.issues.single.candidateId, 'candidate:f1');
    });

    test('frequencyHz above maxFrequencyHz → frequencyOutOfRange', () {
      final sc = _sel(_scoredFrom(
          _peq(featureId: 'f1', frequencyHz: 25000.0))); // > 20000 Hz
      final result = _validate([sc]);

      expect(result.applyPermitted, isFalse);
      expect(result.issues.single.code,
          CandidateSafetyViolationCode.frequencyOutOfRange);
    });

    test('frequency issue detail contains both bounds', () {
      final sc = _sel(_scoredFrom(
          _peq(featureId: 'f1', frequencyHz: 1.0)));
      final result = _validate([sc]);
      expect(result.issues.single.detail, contains('20.0'));
      expect(result.issues.single.detail, contains('20000.0'));
    });
  });

  group('deepNullGuard', () {
    test('featureType deepNull → applyPermitted=false, deepNullGuard', () {
      final sc = _sel(_scoredFrom(_peq(
        featureId: 'dn',
        featureType: AcousticFeatureType.deepNull,
        gainDb: -6.0,
      )));
      final result = _validate([sc]);

      expect(result.applyPermitted, isFalse);
      expect(result.issues.any((i) =>
              i.code == CandidateSafetyViolationCode.deepNullGuard),
          isTrue);
      expect(result.verifiedCandidates, isEmpty);
    });

    test('deepNull mixed with valid → all blocked', () {
      final valid = _sel(_scoredFrom(
          _peq(featureId: 'f1', frequencyHz: 200.0)), applicationOrder: 1);
      final dn = _sel(_scoredFrom(_peq(
        featureId: 'dn',
        featureType: AcousticFeatureType.deepNull,
        gainDb: -6.0,
      )), applicationOrder: 2);
      final result = _validate([valid, dn]);

      expect(result.applyPermitted, isFalse);
      expect(result.verifiedCandidates, isEmpty);
      expect(result.issues.any((i) =>
              i.code == CandidateSafetyViolationCode.deepNullGuard),
          isTrue);
    });
  });

  group('bandBudgetExceeded', () {
    test('selected.length > availableSlots → bandBudgetExceeded', () {
      const tightPolicy = CandidateSafetyPolicy(
        id: 'tight',
        version: 1,
        maxCutDb: 9.0,
        minFrequencyHz: 20.0,
        maxFrequencyHz: 20000.0,
        availableSlots: 1,
      );
      final selected = [
        _sel(_scoredFrom(_peq(featureId: 'f1', frequencyHz: 200.0)),
            applicationOrder: 1),
        _sel(_scoredFrom(_peq(featureId: 'f2', frequencyHz: 2000.0)),
            applicationOrder: 2),
      ];
      final result = _validate(selected, policy: tightPolicy);

      expect(result.applyPermitted, isFalse);
      expect(result.issues.any((i) =>
              i.code == CandidateSafetyViolationCode.bandBudgetExceeded),
          isTrue);
      final budgetIssue = result.issues.firstWhere(
          (i) => i.code == CandidateSafetyViolationCode.bandBudgetExceeded);
      expect(budgetIssue.candidateId, isNull); // selection-level issue
      expect(budgetIssue.detail, contains('availableSlots limit of 1'));
    });

    test('selected.length == availableSlots → permitted', () {
      const tightPolicy = CandidateSafetyPolicy(
        id: 'tight',
        version: 1,
        maxCutDb: 9.0,
        minFrequencyHz: 20.0,
        maxFrequencyHz: 20000.0,
        availableSlots: 2,
      );
      final selected = [
        _sel(_scoredFrom(_peq(featureId: 'f1', frequencyHz: 200.0)),
            applicationOrder: 1),
        _sel(_scoredFrom(_peq(featureId: 'f2', frequencyHz: 2000.0)),
            applicationOrder: 2),
      ];
      final result = _validate(selected, policy: tightPolicy);
      expect(result.applyPermitted, isTrue);
    });
  });

  group('propagated status', () {
    test('nothingSelected → applyPermitted=false, propagatedStatus', () {
      final result = _validate(
        [],
        status: OptimizationStatus.nothingSelected,
      );

      expect(result.applyPermitted, isFalse);
      expect(result.verifiedCandidates, isEmpty);
      expect(result.issues, hasLength(1));
      expect(result.issues.single.code,
          CandidateSafetyViolationCode.propagatedStatus);
      expect(result.issues.single.detail, contains('nothingSelected'));
    });

    test('propagated → applyPermitted=false, propagatedStatus', () {
      final result = _validate(
        [],
        status: OptimizationStatus.propagated,
      );

      expect(result.applyPermitted, isFalse);
      expect(result.issues.single.code,
          CandidateSafetyViolationCode.propagatedStatus);
      expect(result.issues.single.detail, contains('propagated'));
    });

    test('propagated status skips per-candidate checks', () {
      // Even if we somehow had a candidate with bad gain, the propagated-status
      // path exits early and produces exactly one issue.
      final badCandidate = _sel(_scoredFrom(
          _peq(featureId: 'bad', gainDb: 5.0)));
      final result = _validate(
        [badCandidate],
        status: OptimizationStatus.nothingSelected,
      );
      expect(result.issues, hasLength(1));
      expect(result.issues.single.code,
          CandidateSafetyViolationCode.propagatedStatus);
    });
  });

  group('multiple violations', () {
    test('two per-candidate violations produce two issues', () {
      final sc = _sel(_scoredFrom(_peq(
        featureId: 'f1',
        gainDb: 2.0,            // noBoostGuard
        frequencyHz: 50000.0,   // frequencyOutOfRange
      )));
      final result = _validate([sc]);

      expect(result.applyPermitted, isFalse);
      expect(result.issues, hasLength(2));
      final codes = result.issues.map((i) => i.code).toSet();
      expect(codes, contains(CandidateSafetyViolationCode.noBoostGuard));
      expect(codes, contains(CandidateSafetyViolationCode.frequencyOutOfRange));
    });

    test('per-candidate + budget violation both reported', () {
      // availableSlots=1 → band budget exceeded by 2 selected; f2 also cutTooDeep:
      const policy1 = CandidateSafetyPolicy(
        id: 'p1',
        version: 1,
        maxCutDb: 9.0,
        minFrequencyHz: 20.0,
        maxFrequencyHz: 20000.0,
        availableSlots: 1,
      );
      final selected = [
        _sel(_scoredFrom(_peq(featureId: 'f1', gainDb: -6.0, frequencyHz: 200.0)),
            applicationOrder: 1),
        _sel(_scoredFrom(_peq(featureId: 'f2', gainDb: -20.0, frequencyHz: 500.0)),
            applicationOrder: 2), // cutTooDeep
      ];
      final result = _validate(selected, policy: policy1);

      expect(result.applyPermitted, isFalse);
      final codes = result.issues.map((i) => i.code).toSet();
      // cutTooDeep for f2, bandBudgetExceeded for selection
      expect(codes, contains(CandidateSafetyViolationCode.cutTooDeep));
      expect(codes, contains(CandidateSafetyViolationCode.bandBudgetExceeded));
    });
  });

  group('policy metadata', () {
    test('policyId and policyVersion recorded in result', () {
      const p = CandidateSafetyPolicy(
        id: 'my_safety_policy',
        version: 7,
        maxCutDb: 9.0,
        minFrequencyHz: 20.0,
        maxFrequencyHz: 20000.0,
        availableSlots: 10,
      );
      final result = _validate([], status: OptimizationStatus.nothingSelected,
          policy: p);
      expect(result.policyId, 'my_safety_policy');
      expect(result.policyVersion, 7);
    });

    test('evidenceRefs propagated from OptimizedSelection', () {
      const selection = OptimizedSelection(
        status: OptimizationStatus.ok,
        selected: [],
        rejected: [],
        reasons: [],
        policyId: 'op',
        policyVersion: 1,
        evidenceRefs: ['sweep-001', 'ref-abc'],
      );
      final result = AcousticSelectionValidator.validate(
          selection, _defaultPolicy);
      expect(result.evidenceRefs, containsAll(['sweep-001', 'ref-abc']));
    });
  });

  group('JSON — no DSP-forbidden fields', () {
    test('toJson() contains no address/payload/biquad/hardware fields', () {
      final sc = _sel(_scoredFrom(_peq(featureId: 'f1')));
      final result = _validate([sc]);
      final json = jsonEncode(result.toJson()).toLowerCase();

      for (final forbidden in [
        'address',
        'payload',
        'biquad',
        'coefficient',
        'register',
        'safeload',
        'hardware',
        'suggestion',
        'proposedgain',
      ]) {
        expect(json.contains(forbidden), isFalse,
            reason: 'forbidden field "$forbidden" found in JSON');
      }
    });

    test('failed result toJson has empty verifiedCandidates list', () {
      final sc = _sel(_scoredFrom(_peq(featureId: 'f1', gainDb: 1.0)));
      final result = _validate([sc]);
      final map = result.toJson();
      expect(map['applyPermitted'], isFalse);
      expect(map['verifiedCandidates'], isEmpty);
    });
  });

  group('determinism', () {
    test('same inputs → identical JSON output', () {
      final sc = _sel(_scoredFrom(_peq(featureId: 'f1', gainDb: -5.0)));
      final a = _validate([sc]);
      final b = _validate([sc]);
      expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
    });
  });

  group('empty selection (ok status)', () {
    test('ok status with empty selected → applyPermitted=true', () {
      // An optimizer result with status=ok but 0 candidates (edge case).
      // No per-candidate violations. Band budget: 0 ≤ availableSlots.
      final result = AcousticSelectionValidator.validate(
        _optimized(const []),
        _defaultPolicy,
      );
      expect(result.applyPermitted, isTrue);
      expect(result.verifiedCandidates, isEmpty);
      expect(result.issues, isEmpty);
    });
  });

  group('CandidateSafetyPolicy.validate()', () {
    test('empty id throws', () {
      const bad = CandidateSafetyPolicy(
        id: '',
        version: 1,
        maxCutDb: 9.0,
        minFrequencyHz: 20.0,
        maxFrequencyHz: 20000.0,
        availableSlots: 10,
      );
      expect(
          () => bad.validate(), throwsA(isA<CandidateSafetyPolicyException>()));
    });

    test('version < 1 throws', () {
      const bad = CandidateSafetyPolicy(
        id: 'x',
        version: 0,
        maxCutDb: 9.0,
        minFrequencyHz: 20.0,
        maxFrequencyHz: 20000.0,
        availableSlots: 10,
      );
      expect(
          () => bad.validate(), throwsA(isA<CandidateSafetyPolicyException>()));
    });

    test('maxCutDb <= 0 throws', () {
      const bad = CandidateSafetyPolicy(
        id: 'x',
        version: 1,
        maxCutDb: -3.0,
        minFrequencyHz: 20.0,
        maxFrequencyHz: 20000.0,
        availableSlots: 10,
      );
      expect(
          () => bad.validate(), throwsA(isA<CandidateSafetyPolicyException>()));
    });

    test('minFrequencyHz <= 0 throws', () {
      const bad = CandidateSafetyPolicy(
        id: 'x',
        version: 1,
        maxCutDb: 9.0,
        minFrequencyHz: 0.0,
        maxFrequencyHz: 20000.0,
        availableSlots: 10,
      );
      expect(
          () => bad.validate(), throwsA(isA<CandidateSafetyPolicyException>()));
    });

    test('maxFrequencyHz <= minFrequencyHz throws', () {
      const bad = CandidateSafetyPolicy(
        id: 'x',
        version: 1,
        maxCutDb: 9.0,
        minFrequencyHz: 1000.0,
        maxFrequencyHz: 500.0,
        availableSlots: 10,
      );
      expect(
          () => bad.validate(), throwsA(isA<CandidateSafetyPolicyException>()));
    });

    test('availableSlots < 1 throws', () {
      const bad = CandidateSafetyPolicy(
        id: 'x',
        version: 1,
        maxCutDb: 9.0,
        minFrequencyHz: 20.0,
        maxFrequencyHz: 20000.0,
        availableSlots: 0,
      );
      expect(
          () => bad.validate(), throwsA(isA<CandidateSafetyPolicyException>()));
    });

    test('proProvisional() passes validate()', () {
      expect(
          () => CandidateSafetyPolicy.proProvisional().validate(),
          returnsNormally);
    });
  });
}
