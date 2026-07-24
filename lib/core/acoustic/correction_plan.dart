import 'acoustic_problem_classifier.dart';
import 'correction_policy.dart';

/// Correction Plan v1 — interprets classifier output into WHAT MAY BE CORRECTED,
/// WHAT MUST NOT, and WHAT NEEDS A HUMAN.
///
/// It maps each observed feature's actionability to a disposition and a coarse
/// intent (cut / broad shape / none). It NEVER produces a DSP value: no
/// frequency-as-command, gain, Q, biquad, PEQ band, address, payload, or
/// optimizer suggestion. Region bounds (Hz) are OBSERVATION references carried
/// over from the feature, not correction commands. Pure and deterministic.

/// Coarse correction direction. Never a number.
enum CorrectionIntent { cut, broadShape, none }

/// What may happen to a feature.
enum CorrectionDisposition {
  correctable,
  prohibitedBoost,
  inspectOnly,
  manualReview,
  remeasure,
}

enum CorrectionPlanStatus { ok, insufficientEvidence, invalidMeasurement }

/// Observation bounds of a feature (Hz). Not a DSP correction — the same bounds
/// the classifier already reported.
class CorrectionRegion {
  final double startHz;
  final double centerHz;
  final double endHz;
  const CorrectionRegion({
    required this.startHz,
    required this.centerHz,
    required this.endHz,
  });

  Map<String, dynamic> toJson() =>
      {'startHz': startHz, 'centerHz': centerHz, 'endHz': endHz};
}

/// One feature's correction disposition.
class CorrectionDirective {
  final String featureId;
  final AcousticFeatureType featureType;
  final CorrectionRegion region;
  final CorrectionIntent intent;
  final CorrectionDisposition disposition;
  final AcousticActionability sourceActionability;
  final String reason;

  const CorrectionDirective({
    required this.featureId,
    required this.featureType,
    required this.region,
    required this.intent,
    required this.disposition,
    required this.sourceActionability,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {
        'featureId': featureId,
        'featureType': featureType.name,
        'region': region.toJson(),
        'intent': intent.name,
        'disposition': disposition.name,
        'sourceActionability': sourceActionability.name,
        'reason': reason,
      };
}

class CorrectionPlan {
  final CorrectionPlanStatus status;
  final List<CorrectionDirective> directives;
  final List<CorrectionRegion> correctableRegions;
  final List<CorrectionRegion> prohibitedBoostRegions;
  final List<CorrectionRegion> inspectOnlyRegions;
  final bool manualReviewRequired;
  final MeasurementConfidenceInterpretation confidenceInterpretation;
  final List<AcousticFeatureType> blockedFeatureTypes;
  final List<String> reasons;
  final List<String> warnings;
  final String policyId;
  final int policyVersion;
  final List<String> evidenceRefs;

  const CorrectionPlan({
    required this.status,
    required this.directives,
    required this.correctableRegions,
    required this.prohibitedBoostRegions,
    required this.inspectOnlyRegions,
    required this.manualReviewRequired,
    required this.confidenceInterpretation,
    required this.blockedFeatureTypes,
    required this.reasons,
    required this.warnings,
    required this.policyId,
    required this.policyVersion,
    required this.evidenceRefs,
  });

  Map<String, dynamic> toJson() => {
        'status': status.name,
        'directives': [for (final d in directives) d.toJson()],
        'correctableRegions': [for (final r in correctableRegions) r.toJson()],
        'prohibitedBoostRegions': [
          for (final r in prohibitedBoostRegions) r.toJson()
        ],
        'inspectOnlyRegions': [for (final r in inspectOnlyRegions) r.toJson()],
        'manualReviewRequired': manualReviewRequired,
        'confidenceInterpretation': confidenceInterpretation.name,
        'blockedFeatureTypes': [for (final t in blockedFeatureTypes) t.name],
        'reasons': reasons,
        'warnings': warnings,
        'policyId': policyId,
        'policyVersion': policyVersion,
        'evidenceRefs': evidenceRefs,
      };
}

abstract final class CorrectionPlanner {
  static CorrectionPlan plan(
    AcousticClassificationResult result,
    CorrectionPolicy policy,
  ) {
    policy.validate();
    final interp = result.confidenceInterpretation;

    final planStatus = switch (result.status) {
      AcousticClassificationStatus.ok => CorrectionPlanStatus.ok,
      AcousticClassificationStatus.insufficientEvidence =>
        CorrectionPlanStatus.insufficientEvidence,
      AcousticClassificationStatus.invalidMeasurement =>
        CorrectionPlanStatus.invalidMeasurement,
    };

    // Non-ok classifications carry no correctable directives.
    if (planStatus != CorrectionPlanStatus.ok) {
      return CorrectionPlan(
        status: planStatus,
        directives: const [],
        correctableRegions: const [],
        prohibitedBoostRegions: const [],
        inspectOnlyRegions: const [],
        manualReviewRequired: false,
        confidenceInterpretation: interp,
        blockedFeatureTypes: const [],
        reasons: [
          planStatus == CorrectionPlanStatus.invalidMeasurement
              ? 'measurement is not analysable — remeasure required.'
              : 'insufficient in-band evidence — no correction directives.',
        ],
        warnings: const [],
        policyId: policy.id,
        policyVersion: policy.version,
        evidenceRefs: result.evidenceRefs,
      );
    }

    final directives = <CorrectionDirective>[];
    for (final f in result.observedFeatures) {
      directives.add(_directiveFor(f, interp, policy));
    }

    final correctable = <CorrectionRegion>[];
    final prohibited = <CorrectionRegion>[];
    final inspect = <CorrectionRegion>[];
    var manualReview = false;
    final blocked = <AcousticFeatureType>{
      ...result.blockedAutomaticCorrections
    };

    for (final d in directives) {
      switch (d.disposition) {
        case CorrectionDisposition.correctable:
          correctable.add(d.region);
        case CorrectionDisposition.prohibitedBoost:
          prohibited.add(d.region);
          blocked.add(d.featureType);
        case CorrectionDisposition.inspectOnly:
          inspect.add(d.region);
          blocked.add(d.featureType);
        case CorrectionDisposition.manualReview:
          manualReview = true;
          blocked.add(d.featureType);
        case CorrectionDisposition.remeasure:
          manualReview = true;
          blocked.add(d.featureType);
      }
    }

    return CorrectionPlan(
      status: CorrectionPlanStatus.ok,
      directives: directives,
      correctableRegions: correctable,
      prohibitedBoostRegions: prohibited,
      inspectOnlyRegions: inspect,
      manualReviewRequired: manualReview,
      confidenceInterpretation: interp,
      blockedFeatureTypes: blocked.toList()
        ..sort((a, b) => a.index.compareTo(b.index)),
      reasons: [
        '${directives.length} directive(s) from ${result.observedFeatures.length} feature(s).',
      ],
      warnings: const [],
      policyId: policy.id,
      policyVersion: policy.version,
      evidenceRefs: result.evidenceRefs,
    );
  }

  static CorrectionDirective _directiveFor(
    AcousticObservedFeature f,
    MeasurementConfidenceInterpretation interp,
    CorrectionPolicy policy,
  ) {
    // deepNull ALWAYS prohibited-boost, regardless of anything else.
    if (f.type == AcousticFeatureType.deepNull) {
      return _make(f, CorrectionDisposition.prohibitedBoost,
          CorrectionIntent.none, 'deep null — never boosted.');
    }

    // remeasure interpretation forces everything to remeasure.
    if (interp == MeasurementConfidenceInterpretation.remeasure) {
      return _make(f, CorrectionDisposition.remeasure, CorrectionIntent.none,
          'measurement confidence invalid — remeasure before correcting.');
    }

    var disposition = _dispositionFor(f.actionability);
    var intent = _intentFor(f.actionability, disposition);

    // Review escalations by policy.
    if (disposition == CorrectionDisposition.correctable) {
      if (policy.treatTentativeAsManualReview &&
          f.quality == AcousticFeatureQuality.tentative) {
        disposition = CorrectionDisposition.manualReview;
        intent = CorrectionIntent.none;
      } else if (policy.treatBroadCorrectionAsManualReview &&
          intent == CorrectionIntent.broadShape) {
        disposition = CorrectionDisposition.manualReview;
        intent = CorrectionIntent.none;
      }
    }

    return _make(
        f, disposition, intent, 'from actionability ${f.actionability.name}.');
  }

  static CorrectionDisposition _dispositionFor(AcousticActionability a) =>
      switch (a) {
        AcousticActionability.safePeqCutCandidate =>
          CorrectionDisposition.correctable,
        AcousticActionability.cautiousBroadCorrection =>
          CorrectionDisposition.correctable,
        AcousticActionability.informationalOnly =>
          CorrectionDisposition.inspectOnly,
        AcousticActionability.inspectPlacementOrPhase =>
          CorrectionDisposition.inspectOnly,
        AcousticActionability.doNotBoost =>
          CorrectionDisposition.prohibitedBoost,
        AcousticActionability.requiresExpertReview =>
          CorrectionDisposition.manualReview,
        AcousticActionability.noAutomaticCorrection =>
          CorrectionDisposition.manualReview,
        AcousticActionability.remeasureRequired =>
          CorrectionDisposition.remeasure,
      };

  static CorrectionIntent _intentFor(
      AcousticActionability a, CorrectionDisposition d) {
    if (d != CorrectionDisposition.correctable) return CorrectionIntent.none;
    return a == AcousticActionability.safePeqCutCandidate
        ? CorrectionIntent.cut
        : CorrectionIntent.broadShape;
  }

  static CorrectionDirective _make(
    AcousticObservedFeature f,
    CorrectionDisposition disposition,
    CorrectionIntent intent,
    String reason,
  ) =>
      CorrectionDirective(
        featureId: f.featureId,
        featureType: f.type,
        region: CorrectionRegion(
            startHz: f.startHz, centerHz: f.centerHz, endHz: f.endHz),
        intent: intent,
        disposition: disposition,
        sourceActionability: f.actionability,
        reason: reason,
      );
}
