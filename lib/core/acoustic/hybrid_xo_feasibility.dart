import '../pro_impedance_analysis.dart';
import '../pro_project.dart';

enum HybridXoVerdict { dspOnlySuitable, hybridRecommended, insufficientEvidence }

class HybridXoPairAssessment {
  final String side;
  final HybridXoVerdict verdict;
  final double? overlapMinHz;
  final double? overlapMaxHz;
  final bool phaseCoherent;
  final ImpedanceRiskLevel impedanceRisk;
  final List<String> evidence;
  final List<String> missingEvidence;

  const HybridXoPairAssessment({
    required this.side,
    required this.verdict,
    required this.overlapMinHz,
    required this.overlapMaxHz,
    required this.phaseCoherent,
    required this.impedanceRisk,
    this.evidence = const [],
    this.missingEvidence = const [],
  });

  String get summary => '$side: ${verdict.name}; '
      'XO ${overlapMinHz?.toStringAsFixed(0) ?? "?"}–'
      '${overlapMaxHz?.toStringAsFixed(0) ?? "?"} Hz';
}

class HybridXoFeasibility {
  final HybridXoVerdict verdict;
  final List<HybridXoPairAssessment> pairs;
  final List<String> evidence;
  final List<String> missingEvidence;

  const HybridXoFeasibility({
    required this.verdict,
    required this.pairs,
    this.evidence = const [],
    this.missingEvidence = const [],
  });

  String get displaySummary => [
        '시스템 한계 및 XO 권고: ${verdict.name}',
        for (final pair in pairs) pair.summary,
        if (missingEvidence.isNotEmpty)
          '근거 부족: ${missingEvidence.join(', ')}',
      ].join('\n');
}

abstract final class HybridXoFeasibilityEvaluator {
  static HybridXoFeasibility evaluate({required ProProject project}) {
    final impedance = ProImpedanceAnalyzer.analyze(
        acousticState: project.acousticState);
    final pairs = <HybridXoPairAssessment>[];
    for (final side in ['L', 'R']) {
      final tw = project.acousticState.driverChannels
          .where((d) => d.id == (side == 'L' ? 'ch_tw_l' : 'ch_tw_r'))
          .firstOrNull;
      final wf = project.acousticState.driverChannels
          .where((d) => d.id == (side == 'L' ? 'ch_wf_l' : 'ch_wf_r'))
          .firstOrNull;
      final missing = <String>[];
      if (tw?.frdData == null) missing.add('$side tweeter FRD');
      if (wf?.frdData == null) missing.add('$side woofer FRD');
      if (tw?.zmaData == null) missing.add('$side tweeter ZMA');
      if (wf?.zmaData == null) missing.add('$side woofer ZMA');
      if (tw?.frdData?.hasPhase != true || wf?.frdData?.hasPhase != true) {
        missing.add('$side phase');
      }
      if (tw == null || wf == null || missing.isNotEmpty) {
        pairs.add(HybridXoPairAssessment(
          side: side,
          verdict: HybridXoVerdict.insufficientEvidence,
          overlapMinHz: null,
          overlapMaxHz: null,
          phaseCoherent: false,
          impedanceRisk: ImpedanceRiskLevel.unknown,
          missingEvidence: List.unmodifiable(missing),
        ));
        continue;
      }
      final min = tw.frdData!.minFrequencyHz > wf.frdData!.minFrequencyHz
          ? tw.frdData!.minFrequencyHz
          : wf.frdData!.minFrequencyHz;
      final max = tw.frdData!.maxFrequencyHz < wf.frdData!.maxFrequencyHz
          ? tw.frdData!.maxFrequencyHz
          : wf.frdData!.maxFrequencyHz;
      final overlap = max > min * 1.15;
      final phase = tw.frdData!.hasPhase && wf.frdData!.hasPhase;
      final risks = impedance.summaries
          .where((s) => s.channelId == tw.id || s.channelId == wf.id)
          .map((s) => s.riskLevel)
          .toList();
      final risk = risks.isEmpty
          ? ImpedanceRiskLevel.unknown
          : risks.reduce((a, b) => a.severity >= b.severity ? a : b);
      final verdict = !overlap || !phase || risk.severity >= ImpedanceRiskLevel.medium.severity
          ? HybridXoVerdict.hybridRecommended
          : HybridXoVerdict.dspOnlySuitable;
      pairs.add(HybridXoPairAssessment(
        side: side,
        verdict: verdict,
        overlapMinHz: min,
        overlapMaxHz: max,
        phaseCoherent: phase,
        impedanceRisk: risk,
        evidence: ['FRD overlap', 'phase', 'ZMA risk'],
      ));
    }
    final verdict = pairs.any((p) => p.verdict == HybridXoVerdict.insufficientEvidence)
        ? HybridXoVerdict.insufficientEvidence
        : pairs.any((p) => p.verdict == HybridXoVerdict.hybridRecommended)
            ? HybridXoVerdict.hybridRecommended
            : HybridXoVerdict.dspOnlySuitable;
    return HybridXoFeasibility(verdict: verdict, pairs: List.unmodifiable(pairs));
  }
}
