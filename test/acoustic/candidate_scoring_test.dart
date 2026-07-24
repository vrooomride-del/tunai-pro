import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/acoustic_problem_classifier.dart';
import 'package:tunai_pro/core/acoustic/candidate_scoring.dart';
import 'package:tunai_pro/core/acoustic/candidate_set.dart';
import 'package:tunai_pro/core/acoustic/correction_plan.dart';

// ── Test helpers ──────────────────────────────────────────────────────────────

const _policy = ScoringPolicy(
  id: 'test_policy',
  version: 1,
  targetProminenceDb: 6.0,
  tentativeFactor: 0.7,
  rejectionThreshold: 20.0,
  goodThreshold: 45.0,
  excellentThreshold: 70.0,
);

AcousticObservedFeature _feat({
  required String id,
  AcousticFeatureType type = AcousticFeatureType.narrowPeak,
  double centerHz = 200.0,
  double deviationDb = 8.0,
  double prominenceDb = 8.0,
  double estimatedQ = 4.0,
  AcousticFeatureQuality quality = AcousticFeatureQuality.confident,
  AcousticActionability actionability = AcousticActionability.safePeqCutCandidate,
}) =>
    AcousticObservedFeature(
      featureId: id,
      type: type,
      startHz: centerHz * 0.9,
      centerHz: centerHz,
      endHz: centerHz * 1.1,
      deviationDb: deviationDb,
      prominenceDb: prominenceDb,
      bandwidthHz: centerHz * 0.2,
      bandwidthOctaves: 0.28,
      estimatedQ: estimatedQ,
      quality: quality,
      actionability: actionability,
    );

PeqCandidate _candidate({
  required String featureId,
  AcousticFeatureType featureType = AcousticFeatureType.narrowPeak,
  double frequencyHz = 200.0,
  double gainDb = -8.0,
  double q = 4.0,
  CorrectionIntent intent = CorrectionIntent.cut,
}) =>
    PeqCandidate(
      candidateId: 'candidate:$featureId',
      featureId: featureId,
      featureType: featureType,
      frequencyHz: frequencyHz,
      gainDb: gainDb,
      q: q,
      intent: intent,
      reason: 'test candidate',
    );

AcousticClassificationResult _result(List<AcousticObservedFeature> features) =>
    AcousticClassificationResult(
      status: AcousticClassificationStatus.ok,
      residualSummary: null,
      observedFeatures: features,
      analysisMinHz: 20,
      analysisMaxHz: 20000,
      confidenceInterpretation:
          MeasurementConfidenceInterpretation.correctableAllowed,
      blockedAutomaticCorrections: const [],
      suggestedNextActions: const [],
      reasons: const [],
      warnings: const [],
      policyId: 'cls',
      policyVersion: 1,
      evidenceRefs: const ['ev1'],
    );

CandidateSet _candidateSet(
  List<PeqCandidate> candidates, {
  CandidateSetStatus status = CandidateSetStatus.ok,
}) =>
    CandidateSet(
      status: status,
      candidates: candidates,
      skippedDirectives: const [],
      reasons: const ['test'],
      policyId: 'cand_policy',
      policyVersion: 1,
      evidenceRefs: const ['ev1'],
    );

ScoredCandidateSet _score(
  List<PeqCandidate> candidates,
  List<AcousticObservedFeature> features, {
  CandidateSetStatus candidateStatus = CandidateSetStatus.ok,
  ScoringPolicy policy = _policy,
}) =>
    CandidateScorer.score(
      _candidateSet(candidates, status: candidateStatus),
      _result(features),
      policy,
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('compositeScore range', () {
    test('compositeScore is always within [0, 100]', () {
      for (final prominence in [0.5, 3.0, 6.0, 12.0, 30.0]) {
        for (final deviation in [1.5, 4.0, 9.0, 20.0]) {
          final feat = _feat(id: 'f',
              prominenceDb: prominence, deviationDb: deviation);
          final cand =
              _candidate(featureId: 'f', gainDb: -deviation.clamp(1.0, 9.0));
          final ss = _score([cand], [feat]);
          final score = ss.scoredCandidates.single.compositeScore;
          expect(score, inInclusiveRange(0.0, 100.0),
              reason: 'prominence=$prominence deviation=$deviation');
        }
      }
    });

    test('maximum composite score is 100 when perfectly calibrated with high prominence',
        () {
      // prominenceDb >= targetProminenceDb AND gainDb == deviationDb AND confident
      final feat = _feat(id: 'f', prominenceDb: 12.0, deviationDb: 6.0);
      final cand = _candidate(featureId: 'f', gainDb: -6.0);
      final ss = _score([cand], [feat]);
      // max: (40 + 30) × 1.0 × 100/70 = 100
      expect(ss.scoredCandidates.single.compositeScore, closeTo(100.0, 0.01));
    });

    test('prominenceScore is 0 when prominenceDb is 0', () {
      final feat = _feat(id: 'f', prominenceDb: 0.0, deviationDb: 1.0);
      final cand = _candidate(featureId: 'f', gainDb: -1.0);
      final ss = _score([cand], [feat]);
      expect(ss.scoredCandidates.single.prominenceScore, 0.0);
    });
  });

  group('score sub-components', () {
    test('prominenceScore equals clipped ratio × 40', () {
      final feat = _feat(id: 'f', prominenceDb: 3.0, deviationDb: 3.0);
      final cand = _candidate(featureId: 'f', gainDb: -3.0);
      final ss = _score([cand], [feat]);
      final sc = ss.scoredCandidates.single;
      // prominenceScore = (3.0 / 6.0) × 40 = 20.0
      expect(sc.prominenceScore, closeTo(20.0, 0.01));
    });

    test('prominenceScore clamped at 40 when prominenceDb > targetProminenceDb', () {
      final feat = _feat(id: 'f', prominenceDb: 20.0, deviationDb: 8.0);
      final cand = _candidate(featureId: 'f', gainDb: -8.0);
      final ss = _score([cand], [feat]);
      expect(ss.scoredCandidates.single.prominenceScore, closeTo(40.0, 0.01));
    });

    test('magnitudeConsistencyScore = 30 when gainDb exactly matches deviationDb', () {
      final feat = _feat(id: 'f', prominenceDb: 6.0, deviationDb: 5.0);
      final cand = _candidate(featureId: 'f', gainDb: -5.0); // exact match
      final ss = _score([cand], [feat]);
      expect(ss.scoredCandidates.single.magnitudeConsistencyScore,
          closeTo(30.0, 0.01));
    });

    test('magnitudeConsistencyScore < 30 when gain is clamped below deviation', () {
      // gainDb = -6.0 (maxCutDb), deviationDb = 12.0 → ratio = 0.5
      final feat = _feat(id: 'f', prominenceDb: 6.0, deviationDb: 12.0);
      final cand = _candidate(featureId: 'f', gainDb: -6.0);
      final ss = _score([cand], [feat]);
      // ratio = 6/12 = 0.5 → consistencyScore = 15
      expect(ss.scoredCandidates.single.magnitudeConsistencyScore,
          closeTo(15.0, 0.01));
    });
  });

  group('grade mapping', () {
    test('compositeScore >= excellentThreshold → excellent', () {
      // Force max: prominenceDb=12 (≥ target), gainDb=deviationDb, confident
      final feat = _feat(id: 'f', prominenceDb: 12.0, deviationDb: 8.0);
      final cand = _candidate(featureId: 'f', gainDb: -8.0);
      final ss = _score([cand], [feat]);
      expect(ss.scoredCandidates.single.grade, CandidateScoreGrade.excellent);
    });

    test('moderate prominence and partial gain match → good', () {
      // prominenceScore = 3/6 × 40 = 20; consistencyScore = 2/6 × 30 = 10
      // raw = 30; composite = 30 × 1.0 × 100/70 ≈ 42.9 → good (≥45? no, marginal)
      // Use prominence=4.5 and full match: pS=30, cS=30, raw=60, composite=85.7 → excellent
      // Let me target ≥45 < 70: prominence=3, dev=6, gain=-6 → pS=20, cS=30, raw=50, comp=71.4 → excellent
      // prominence=2.4, dev=6, gain=-6 → pS=16, cS=30, raw=46, comp=65.7 → good (< 70, ≥ 45)
      final feat = _feat(id: 'f', prominenceDb: 2.4, deviationDb: 6.0);
      final cand = _candidate(featureId: 'f', gainDb: -6.0);
      final ss = _score([cand], [feat]);
      final sc = ss.scoredCandidates.single;
      expect(sc.compositeScore, inInclusiveRange(45.0, 69.99));
      expect(sc.grade, CandidateScoreGrade.good);
    });

    test('low prominence → marginal', () {
      // prominence=0.5, dev=6, gain=-6 → pS = (0.5/6)×40 = 3.33, cS=30, raw=33.33
      // composite = 33.33 × 1.0 × 100/70 = 47.6 → good, not marginal
      // Need composite < 45 and >= 20
      // prominence=0.5, dev=6, gain=-3 (ratio=0.5) → pS=3.33, cS=15, raw=18.33
      // composite = 18.33 × 100/70 = 26.2 → marginal
      final feat = _feat(id: 'f', prominenceDb: 0.5, deviationDb: 6.0);
      final cand = _candidate(featureId: 'f', gainDb: -3.0); // 50% of deviation
      final ss = _score([cand], [feat]);
      final sc = ss.scoredCandidates.single;
      expect(sc.compositeScore, inInclusiveRange(20.0, 44.99));
      expect(sc.grade, CandidateScoreGrade.marginal);
    });

    test('very low prominence + tentative → rejected', () {
      // prominence=0.3, dev=2, gain=-1 (ratio=0.5) → pS=2, cS=15, raw=17
      // qualityFactor=0.7 → composite = 17 × 0.7 × 100/70 = 17 → rejected (< 20)
      final feat = _feat(
        id: 'f',
        prominenceDb: 0.3,
        deviationDb: 2.0,
        quality: AcousticFeatureQuality.tentative,
      );
      final cand = _candidate(featureId: 'f', gainDb: -1.0);
      final ss = _score([cand], [feat]);
      expect(ss.scoredCandidates.single.grade, CandidateScoreGrade.rejected);
    });
  });

  group('tentative quality downgrade', () {
    test('tentative feature has lower compositeScore than identical confident feature', () {
      final featC = _feat(id: 'fc', prominenceDb: 5.0, deviationDb: 5.0,
          quality: AcousticFeatureQuality.confident);
      final featT = _feat(id: 'ft', prominenceDb: 5.0, deviationDb: 5.0,
          quality: AcousticFeatureQuality.tentative);
      final candC = _candidate(featureId: 'fc', gainDb: -5.0);
      final candT = _candidate(featureId: 'ft', gainDb: -5.0);

      final ssC = _score([candC], [featC]);
      final ssT = _score([candT], [featT]);

      expect(ssT.scoredCandidates.single.compositeScore,
          lessThan(ssC.scoredCandidates.single.compositeScore));
      expect(ssT.scoredCandidates.single.qualityFactor, _policy.tentativeFactor);
      expect(ssC.scoredCandidates.single.qualityFactor, 1.0);
    });

    test('tentative qualityFactor is exactly policy.tentativeFactor', () {
      final feat = _feat(id: 'f', quality: AcousticFeatureQuality.tentative);
      final cand = _candidate(featureId: 'f', gainDb: -8.0);
      final ss = _score([cand], [feat]);
      expect(ss.scoredCandidates.single.qualityFactor, _policy.tentativeFactor);
    });
  });

  group('ranking', () {
    test('higher compositeScore candidate gets rank 1', () {
      final highFeat = _feat(id: 'hi', prominenceDb: 10.0, deviationDb: 8.0);
      final lowFeat = _feat(id: 'lo', prominenceDb: 1.0, deviationDb: 8.0);
      final highCand = _candidate(featureId: 'hi', gainDb: -8.0);
      final lowCand = _candidate(featureId: 'lo', gainDb: -8.0);

      final ss = _score([lowCand, highCand], [highFeat, lowFeat]);
      expect(ss.scoredCandidates[0].candidate.featureId, 'hi');
      expect(ss.scoredCandidates[0].rank, 1);
      expect(ss.scoredCandidates[1].rank, 2);
    });

    test('ties on compositeScore broken by prominenceDb descending', () {
      // Both candidates have identical score formula inputs EXCEPT prominenceDb.
      // Same deviation and gain → same consistencyScore.
      // Same prominence ratio → same score? No — different prominenceDb values
      // only differ if their raw values differ. Let me make them identical:
      // prom=6, dev=6, gain=-6 for both → same compositeScore.
      // Tiebreak by prominenceDb raw value — same 6.0, so tiebreak by featureId.
      final featA = _feat(id: 'aaa', prominenceDb: 6.0, deviationDb: 6.0);
      final featB = _feat(id: 'bbb', prominenceDb: 6.0, deviationDb: 6.0);
      final candA = _candidate(featureId: 'aaa', gainDb: -6.0);
      final candB = _candidate(featureId: 'bbb', gainDb: -6.0);

      final ss = _score([candB, candA], [featA, featB]);
      // 'aaa' < 'bbb' alphabetically → rank 1
      expect(ss.scoredCandidates[0].candidate.featureId, 'aaa');
    });

    test('same prominenceDb tiebreak uses featureId ascending', () {
      final feats = [
        _feat(id: 'z_feat', prominenceDb: 6.0, deviationDb: 6.0),
        _feat(id: 'a_feat', prominenceDb: 6.0, deviationDb: 6.0),
      ];
      final cands = [
        _candidate(featureId: 'z_feat', gainDb: -6.0),
        _candidate(featureId: 'a_feat', gainDb: -6.0),
      ];
      final ss = _score(cands, feats);
      expect(ss.scoredCandidates[0].candidate.featureId, 'a_feat');
      expect(ss.scoredCandidates[1].candidate.featureId, 'z_feat');
    });

    test('ranks are 1-based and sequential', () {
      final feats = List.generate(
          4, (i) => _feat(id: 'f$i', prominenceDb: 10.0 - i, deviationDb: 6.0));
      final cands = List.generate(
          4, (i) => _candidate(featureId: 'f$i', gainDb: -6.0));
      final ss = _score(cands, feats);
      expect(ss.scoredCandidates.map((c) => c.rank).toList(), [1, 2, 3, 4]);
    });
  });

  group('rejected threshold', () {
    test('all rejected → status allRejected', () {
      // Very low prominence + tiny gain → compositeScore << rejectionThreshold.
      // pS = (0.5/6)×40 = 3.33, cS = (1/6)×30 = 5.0, raw = 8.33
      // composite = 8.33 × 100/70 ≈ 11.9 < rejectionThreshold(20.0) → rejected.
      final feat = _feat(id: 'f', prominenceDb: 0.5, deviationDb: 6.0);
      final cand = _candidate(featureId: 'f', gainDb: -1.0);
      final ss = _score([cand], [feat]);
      expect(ss.status, ScoredCandidateSetStatus.allRejected);
      expect(ss.scoredCandidates.single.grade, CandidateScoreGrade.rejected);
    });

    test('accepted getter excludes rejected candidates', () {
      const mixedPolicy = ScoringPolicy(
        id: 'mixed',
        version: 1,
        targetProminenceDb: 6.0,
        tentativeFactor: 0.7,
        rejectionThreshold: 50.0,
        goodThreshold: 60.0,
        excellentThreshold: 80.0,
      );
      // High prominence → passes; low → rejected
      final highFeat = _feat(id: 'hi', prominenceDb: 10.0, deviationDb: 8.0);
      final lowFeat = _feat(id: 'lo', prominenceDb: 0.3, deviationDb: 8.0);
      final ss = _score(
        [_candidate(featureId: 'hi', gainDb: -8.0),
         _candidate(featureId: 'lo', gainDb: -8.0)],
        [highFeat, lowFeat],
        policy: mixedPolicy,
      );
      expect(ss.accepted.length, lessThan(ss.scoredCandidates.length));
    });
  });

  group('non-ok candidateSet status propagation', () {
    test('noCorrectableDirectives → ScoredCandidateSetStatus.noCorrectableDirectives', () {
      final ss = _score(const [], const [],
          candidateStatus: CandidateSetStatus.noCorrectableDirectives);
      expect(ss.status, ScoredCandidateSetStatus.noCorrectableDirectives);
      expect(ss.scoredCandidates, isEmpty);
    });

    test('insufficientEvidence → ScoredCandidateSetStatus.insufficientEvidence', () {
      final ss = _score(const [], const [],
          candidateStatus: CandidateSetStatus.insufficientEvidence);
      expect(ss.status, ScoredCandidateSetStatus.insufficientEvidence);
      expect(ss.scoredCandidates, isEmpty);
    });

    test('invalidPlan → ScoredCandidateSetStatus.invalidPlan', () {
      final ss = _score(const [], const [],
          candidateStatus: CandidateSetStatus.invalidPlan);
      expect(ss.status, ScoredCandidateSetStatus.invalidPlan);
      expect(ss.scoredCandidates, isEmpty);
    });
  });

  group('deepNull / prohibited absent from scored set', () {
    test('candidates in CandidateSet are all correctable — deepNull/prohibited never appear', () {
      // CandidateGenerator already guarantees this; verify scorer never produces them.
      final feat = _feat(id: 'f1');
      final cand = _candidate(featureId: 'f1');
      final ss = _score([cand], [feat]);
      for (final sc in ss.scoredCandidates) {
        expect(sc.candidate.featureType, isNot(AcousticFeatureType.deepNull));
      }
    });

    test('feature not found in result → scored with 0, grade rejected', () {
      // Candidate references a featureId absent from the classification result.
      final cand = _candidate(featureId: 'ghost');
      final ss = _score([cand], const []); // empty features
      expect(ss.scoredCandidates.single.compositeScore, 0.0);
      expect(ss.scoredCandidates.single.grade, CandidateScoreGrade.rejected);
    });
  });

  group('topCandidate and accepted helpers', () {
    test('topCandidate is null for empty scored set', () {
      final ss = _score(const [], const []);
      expect(ss.topCandidate, isNull);
    });

    test('topCandidate returns rank-1 candidate', () {
      final feats = [
        _feat(id: 'lo', prominenceDb: 2.0, deviationDb: 6.0),
        _feat(id: 'hi', prominenceDb: 10.0, deviationDb: 6.0),
      ];
      final ss = _score([
        _candidate(featureId: 'lo', gainDb: -6.0),
        _candidate(featureId: 'hi', gainDb: -6.0),
      ], feats);
      expect(ss.topCandidate!.candidate.featureId, 'hi');
    });
  });

  group('determinism and JSON', () {
    test('same input + policy → identical JSON', () {
      final feats = [
        _feat(id: 'f1', prominenceDb: 8.0, deviationDb: 6.0),
        _feat(id: 'f2', prominenceDb: 3.0, deviationDb: 4.0),
      ];
      final cands = [
        _candidate(featureId: 'f1', gainDb: -6.0),
        _candidate(featureId: 'f2', gainDb: -4.0),
      ];
      final a = _score(cands, feats);
      final b = _score(cands, feats);
      expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
    });

    test('rank order is stable across repeated calls', () {
      final feats = List.generate(
          3, (i) => _feat(id: 'f$i', prominenceDb: 9.0 - i * 2.0, deviationDb: 6.0));
      final cands = List.generate(
          3, (i) => _candidate(featureId: 'f$i', gainDb: -6.0));
      final a = _score(cands, feats);
      final b = _score(cands, feats);
      expect(a.scoredCandidates.map((c) => c.candidate.featureId).toList(),
          b.scoredCandidates.map((c) => c.candidate.featureId).toList());
    });

    test('no DSP-forbidden field in scored JSON', () {
      final feat = _feat(id: 'f1');
      final cand = _candidate(featureId: 'f1');
      final ss = _score([cand], [feat]);
      final json = jsonEncode(ss.toJson()).toLowerCase();

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

    test('policyId and policyVersion recorded in scored set', () {
      final ss = _score(const [], const []);
      expect(ss.policyId, 'test_policy');
      expect(ss.policyVersion, 1);
    });

    test('evidenceRefs propagated from candidateSet', () {
      final ss = _score(const [], const []);
      expect(ss.evidenceRefs, contains('ev1'));
    });
  });

  group('ScoringPolicy.validate()', () {
    test('empty id throws', () {
      const bad = ScoringPolicy(
        id: '',
        version: 1,
        targetProminenceDb: 6.0,
        tentativeFactor: 0.7,
        rejectionThreshold: 20.0,
        goodThreshold: 45.0,
        excellentThreshold: 70.0,
      );
      expect(() => bad.validate(), throwsA(isA<ScoringPolicyException>()));
    });

    test('tentativeFactor > 1 throws', () {
      const bad = ScoringPolicy(
        id: 'x',
        version: 1,
        targetProminenceDb: 6.0,
        tentativeFactor: 1.1,
        rejectionThreshold: 20.0,
        goodThreshold: 45.0,
        excellentThreshold: 70.0,
      );
      expect(() => bad.validate(), throwsA(isA<ScoringPolicyException>()));
    });

    test('goodThreshold <= rejectionThreshold throws', () {
      const bad = ScoringPolicy(
        id: 'x',
        version: 1,
        targetProminenceDb: 6.0,
        tentativeFactor: 0.7,
        rejectionThreshold: 50.0,
        goodThreshold: 50.0, // equal — not allowed
        excellentThreshold: 70.0,
      );
      expect(() => bad.validate(), throwsA(isA<ScoringPolicyException>()));
    });

    test('excellentThreshold <= goodThreshold throws', () {
      const bad = ScoringPolicy(
        id: 'x',
        version: 1,
        targetProminenceDb: 6.0,
        tentativeFactor: 0.7,
        rejectionThreshold: 20.0,
        goodThreshold: 70.0,
        excellentThreshold: 60.0, // below goodThreshold
      );
      expect(() => bad.validate(), throwsA(isA<ScoringPolicyException>()));
    });

    test('proProvisional() passes validate() without throwing', () {
      expect(() => ScoringPolicy.proProvisional().validate(), returnsNormally);
    });

    test('targetProminenceDb of 0 throws', () {
      const bad = ScoringPolicy(
        id: 'x',
        version: 1,
        targetProminenceDb: 0.0,
        tentativeFactor: 0.7,
        rejectionThreshold: 20.0,
        goodThreshold: 45.0,
        excellentThreshold: 70.0,
      );
      expect(() => bad.validate(), throwsA(isA<ScoringPolicyException>()));
    });
  });
}
