import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/acoustic_problem_classifier.dart';
import 'package:tunai_pro/core/acoustic/correction_plan.dart';
import 'package:tunai_pro/core/acoustic/correction_policy.dart';

final _policy = CorrectionPolicy.proProvisional();

AcousticObservedFeature _feat({
  required AcousticFeatureType type,
  required AcousticActionability action,
  AcousticFeatureQuality quality = AcousticFeatureQuality.confident,
  String id = 'f1',
}) =>
    AcousticObservedFeature(
      featureId: id,
      type: type,
      startHz: 90,
      centerHz: 100,
      endHz: 110,
      deviationDb: type == AcousticFeatureType.deepNull ? -15 : 5,
      prominenceDb: 5,
      bandwidthHz: 20,
      bandwidthOctaves: 0.3,
      estimatedQ: 5,
      quality: quality,
      actionability: action,
    );

AcousticClassificationResult _result(
  List<AcousticObservedFeature> features, {
  AcousticClassificationStatus status = AcousticClassificationStatus.ok,
  MeasurementConfidenceInterpretation interp =
      MeasurementConfidenceInterpretation.correctableAllowed,
  List<AcousticFeatureType> blocked = const [],
}) =>
    AcousticClassificationResult(
      status: status,
      residualSummary: null,
      observedFeatures: features,
      analysisMinHz: 20,
      analysisMaxHz: 20000,
      confidenceInterpretation: interp,
      blockedAutomaticCorrections: blocked,
      suggestedNextActions: const [],
      reasons: const [],
      warnings: const [],
      policyId: 'cls',
      policyVersion: 1,
      evidenceRefs: const ['ev1'],
    );

CorrectionPlan _plan(AcousticClassificationResult r, [CorrectionPolicy? p]) =>
    CorrectionPlanner.plan(r, p ?? _policy);

CorrectionDirective _one(CorrectionPlan p) => p.directives.single;

void main() {
  group('actionability → disposition mapping (exhaustive)', () {
    final cases = <AcousticActionability, CorrectionDisposition>{
      AcousticActionability.safePeqCutCandidate:
          CorrectionDisposition.correctable,
      AcousticActionability.cautiousBroadCorrection:
          CorrectionDisposition.correctable,
      AcousticActionability.informationalOnly:
          CorrectionDisposition.inspectOnly,
      AcousticActionability.inspectPlacementOrPhase:
          CorrectionDisposition.inspectOnly,
      AcousticActionability.doNotBoost: CorrectionDisposition.prohibitedBoost,
      AcousticActionability.requiresExpertReview:
          CorrectionDisposition.manualReview,
      AcousticActionability.noAutomaticCorrection:
          CorrectionDisposition.manualReview,
      AcousticActionability.remeasureRequired: CorrectionDisposition.remeasure,
    };
    cases.forEach((action, expected) {
      test('$action → $expected', () {
        final p = _plan(_result(
            [_feat(type: AcousticFeatureType.narrowPeak, action: action)]));
        expect(_one(p).disposition, expected);
      });
    });

    test('cut intent only for safePeqCutCandidate; broad for cautious', () {
      final cut = _plan(_result([
        _feat(
            type: AcousticFeatureType.narrowPeak,
            action: AcousticActionability.safePeqCutCandidate)
      ]));
      final broad = _plan(_result([
        _feat(
            type: AcousticFeatureType.broadPeak,
            action: AcousticActionability.cautiousBroadCorrection)
      ]));
      expect(_one(cut).intent, CorrectionIntent.cut);
      expect(_one(broad).intent, CorrectionIntent.broadShape);
    });
  });

  group('deepNull protection', () {
    test('deepNull is always prohibitedBoost, even if actionability differs',
        () {
      // Even a (nonsensical) cut actionability must be overridden.
      final p = _plan(_result([
        _feat(
            type: AcousticFeatureType.deepNull,
            action: AcousticActionability.safePeqCutCandidate)
      ]));
      expect(_one(p).disposition, CorrectionDisposition.prohibitedBoost);
      expect(_one(p).intent, CorrectionIntent.none);
      expect(p.prohibitedBoostRegions, hasLength(1));
      expect(p.blockedFeatureTypes, contains(AcousticFeatureType.deepNull));
    });
  });

  group('confidence / policy escalation', () {
    test('remeasure interpretation forces every directive to remeasure', () {
      final p = _plan(_result([
        _feat(
            type: AcousticFeatureType.narrowPeak,
            action: AcousticActionability.safePeqCutCandidate)
      ], interp: MeasurementConfidenceInterpretation.remeasure));
      expect(_one(p).disposition, CorrectionDisposition.remeasure);
      expect(p.manualReviewRequired, isTrue);
    });
    test('tentative feature is escalated to manualReview by default policy',
        () {
      final p = _plan(_result([
        _feat(
            type: AcousticFeatureType.narrowPeak,
            action: AcousticActionability.safePeqCutCandidate,
            quality: AcousticFeatureQuality.tentative)
      ]));
      expect(_one(p).disposition, CorrectionDisposition.manualReview);
    });
    test('broad-correction escalation is off by default, on when policy set',
        () {
      final feat = _feat(
          type: AcousticFeatureType.broadPeak,
          action: AcousticActionability.cautiousBroadCorrection);
      expect(_one(_plan(_result([feat]))).disposition,
          CorrectionDisposition.correctable);
      const strict = CorrectionPolicy(
          id: 'strict',
          version: 1,
          treatTentativeAsManualReview: true,
          treatBroadCorrectionAsManualReview: true);
      expect(_one(_plan(_result([feat]), strict)).disposition,
          CorrectionDisposition.manualReview);
    });
  });

  group('status propagation', () {
    test('invalidMeasurement → plan invalid, no directives', () {
      final p = _plan(_result(const [],
          status: AcousticClassificationStatus.invalidMeasurement));
      expect(p.status, CorrectionPlanStatus.invalidMeasurement);
      expect(p.directives, isEmpty);
    });
    test('insufficientEvidence → plan insufficient, no directives', () {
      final p = _plan(_result(const [],
          status: AcousticClassificationStatus.insufficientEvidence));
      expect(p.status, CorrectionPlanStatus.insufficientEvidence);
      expect(p.directives, isEmpty);
    });
    test('classifier blockedAutomaticCorrections is carried over', () {
      final p = _plan(_result([
        _feat(
            type: AcousticFeatureType.narrowPeak,
            action: AcousticActionability.safePeqCutCandidate)
      ], blocked: [
        AcousticFeatureType.deepNull
      ]));
      expect(p.blockedFeatureTypes, contains(AcousticFeatureType.deepNull));
    });
  });

  group('boundary / determinism', () {
    test('no DSP command field appears in the plan JSON', () {
      final p = _plan(_result([
        _feat(
            type: AcousticFeatureType.narrowPeak,
            action: AcousticActionability.safePeqCutCandidate),
        _feat(
            type: AcousticFeatureType.deepNull,
            action: AcousticActionability.doNotBoost,
            id: 'f2'),
      ]));
      final json = jsonEncode(p.toJson()).toLowerCase();
      for (final t in [
        'proposedgain',
        'gaindb',
        '"gain"',
        'correctionq',
        '"q"',
        'biquad',
        'coefficient',
        'peqband',
        'address',
        'payload',
        'suggestion'
      ]) {
        expect(json.contains(t), isFalse, reason: t);
      }
    });
    test('no cause enum (roomMode/boundary/crossover/polarity) in JSON', () {
      final p = _plan(_result([
        _feat(
            type: AcousticFeatureType.narrowPeak,
            action: AcousticActionability.safePeqCutCandidate)
      ]));
      final json = jsonEncode(p.toJson()).toLowerCase();
      for (final t in [
        'roommode',
        'boundarygain',
        'crossovermismatch',
        'polarity'
      ]) {
        expect(json.contains(t), isFalse, reason: t);
      }
    });
    test('deterministic: same input+policy → identical JSON and ids', () {
      final feats = [
        _feat(
            type: AcousticFeatureType.narrowPeak,
            action: AcousticActionability.safePeqCutCandidate),
        _feat(
            type: AcousticFeatureType.broadDip,
            action: AcousticActionability.requiresExpertReview,
            id: 'f2'),
      ];
      final a = _plan(_result(feats));
      final b = _plan(_result(feats));
      expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
      expect(a.directives.map((d) => d.featureId),
          b.directives.map((d) => d.featureId));
    });
    test('policy id/version recorded', () {
      final p = _plan(_result(const []));
      expect(p.policyId, 'pro_provisional');
      expect(p.policyVersion, 1);
    });
    test('region bucketing matches dispositions', () {
      final p = _plan(_result([
        _feat(
            type: AcousticFeatureType.narrowPeak,
            action: AcousticActionability.safePeqCutCandidate,
            id: 'c'),
        _feat(
            type: AcousticFeatureType.deepNull,
            action: AcousticActionability.doNotBoost,
            id: 'p'),
        _feat(
            type: AcousticFeatureType.narrowDip,
            action: AcousticActionability.informationalOnly,
            id: 'i'),
      ]));
      expect(p.correctableRegions, hasLength(1));
      expect(p.prohibitedBoostRegions, hasLength(1));
      expect(p.inspectOnlyRegions, hasLength(1));
    });
  });
}
