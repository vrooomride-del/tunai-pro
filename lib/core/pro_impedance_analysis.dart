// ── TUNAI PRO Phase O — Impedance / Load Analysis ────────────────────────────
// Advisory load-risk analysis from parsed ZMA data.
// Not certified amplifier safety calculation. No hardware write.
// AOS protects. AI suggests. Expert verifies. DSP executes.

import 'pro_acoustic_data.dart';

// ── Enums ─────────────────────────────────────────────────────────────────────

enum ImpedanceRiskLevel {
  none,
  low,
  medium,
  high,
  critical,
  unknown;

  String get label => switch (this) {
    ImpedanceRiskLevel.none     => 'None',
    ImpedanceRiskLevel.low      => 'Low',
    ImpedanceRiskLevel.medium   => 'Medium',
    ImpedanceRiskLevel.high     => 'High',
    ImpedanceRiskLevel.critical => 'Critical',
    ImpedanceRiskLevel.unknown  => 'Unknown',
  };

  /// Higher ordinal = more severe.
  int get severity => index;

  String toJson() => name;
  static ImpedanceRiskLevel fromJson(String s) =>
      ImpedanceRiskLevel.values.firstWhere((e) => e.name == s,
          orElse: () => ImpedanceRiskLevel.unknown);
}

enum ImpedanceIssueType {
  missingZma,
  lowMinimumImpedance,
  severePhaseAngle,
  lowImpedanceWithPhaseAngle,
  sparseData,
  outOfRangeData,
  nonFiniteData,
  analysisPlaceholder;

  String get label => switch (this) {
    ImpedanceIssueType.missingZma                  => 'Missing ZMA',
    ImpedanceIssueType.lowMinimumImpedance         => 'Low Minimum Impedance',
    ImpedanceIssueType.severePhaseAngle            => 'Severe Phase Angle',
    ImpedanceIssueType.lowImpedanceWithPhaseAngle  => 'Low Z + Phase Angle',
    ImpedanceIssueType.sparseData                  => 'Sparse Data',
    ImpedanceIssueType.outOfRangeData              => 'Out-of-range Data',
    ImpedanceIssueType.nonFiniteData               => 'Non-finite Data',
    ImpedanceIssueType.analysisPlaceholder         => 'Analysis Placeholder',
  };

  String toJson() => name;
  static ImpedanceIssueType fromJson(String s) =>
      ImpedanceIssueType.values.firstWhere((e) => e.name == s,
          orElse: () => ImpedanceIssueType.analysisPlaceholder);
}

// ── Models ────────────────────────────────────────────────────────────────────

class ImpedanceIssue {
  final String id;
  final ImpedanceIssueType type;
  final ImpedanceRiskLevel riskLevel;
  final String? channelId;
  final double? frequencyHz;
  final String title;
  final String description;
  final String recommendation;
  final DateTime createdAt;

  ImpedanceIssue({
    required this.id,
    required this.type,
    required this.riskLevel,
    this.channelId,
    this.frequencyHz,
    required this.title,
    required this.description,
    required this.recommendation,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.toJson(),
    'riskLevel': riskLevel.toJson(),
    if (channelId != null) 'channelId': channelId,
    if (frequencyHz != null) 'frequencyHz': frequencyHz,
    'title': title,
    'description': description,
    'recommendation': recommendation,
    'createdAt': createdAt.toIso8601String(),
  };

  factory ImpedanceIssue.fromJson(Map<String, dynamic> j) => ImpedanceIssue(
    id: j['id'] as String? ?? '',
    type: ImpedanceIssueType.fromJson(j['type'] as String? ?? 'analysisPlaceholder'),
    riskLevel: ImpedanceRiskLevel.fromJson(j['riskLevel'] as String? ?? 'unknown'),
    channelId: j['channelId'] as String?,
    frequencyHz: (j['frequencyHz'] as num?)?.toDouble(),
    title: j['title'] as String? ?? '',
    description: j['description'] as String? ?? '',
    recommendation: j['recommendation'] as String? ?? '',
    createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}

class DriverImpedanceSummary {
  final String channelId;
  final String driverName;
  final bool hasZma;
  final int pointCount;
  final double? minFrequencyHz;
  final double? maxFrequencyHz;
  final double? minImpedanceOhm;
  final double? minImpedanceFrequencyHz;
  final double? maxPhaseAngleDeg;
  final double? maxPhaseFrequencyHz;
  final ImpedanceRiskLevel riskLevel;
  final List<ImpedanceIssue> issues;
  final String? notes;

  const DriverImpedanceSummary({
    required this.channelId,
    required this.driverName,
    required this.hasZma,
    required this.pointCount,
    this.minFrequencyHz,
    this.maxFrequencyHz,
    this.minImpedanceOhm,
    this.minImpedanceFrequencyHz,
    this.maxPhaseAngleDeg,
    this.maxPhaseFrequencyHz,
    required this.riskLevel,
    this.issues = const [],
    this.notes,
  });

  String get freqRangeLabel {
    if (minFrequencyHz == null || maxFrequencyHz == null) return 'N/A';
    return '${minFrequencyHz!.toStringAsFixed(0)} Hz – '
        '${maxFrequencyHz!.toStringAsFixed(0)} Hz';
  }

  String get minImpedanceLabel => minImpedanceOhm == null
      ? 'N/A'
      : '${minImpedanceOhm!.toStringAsFixed(1)} Ω';

  String get maxPhaseLabel => maxPhaseAngleDeg == null
      ? 'N/A'
      : '${maxPhaseAngleDeg!.toStringAsFixed(1)}°';

  Map<String, dynamic> toJson() => {
    'channelId': channelId,
    'driverName': driverName,
    'hasZma': hasZma,
    'pointCount': pointCount,
    if (minFrequencyHz != null) 'minFrequencyHz': minFrequencyHz,
    if (maxFrequencyHz != null) 'maxFrequencyHz': maxFrequencyHz,
    if (minImpedanceOhm != null) 'minImpedanceOhm': minImpedanceOhm,
    if (minImpedanceFrequencyHz != null)
      'minImpedanceFrequencyHz': minImpedanceFrequencyHz,
    if (maxPhaseAngleDeg != null) 'maxPhaseAngleDeg': maxPhaseAngleDeg,
    if (maxPhaseFrequencyHz != null)
      'maxPhaseFrequencyHz': maxPhaseFrequencyHz,
    'riskLevel': riskLevel.toJson(),
    'issues': issues.map((i) => i.toJson()).toList(),
    if (notes != null) 'notes': notes,
  };

  factory DriverImpedanceSummary.fromJson(Map<String, dynamic> j) =>
      DriverImpedanceSummary(
        channelId: j['channelId'] as String? ?? '',
        driverName: j['driverName'] as String? ?? '',
        hasZma: j['hasZma'] as bool? ?? false,
        pointCount: j['pointCount'] as int? ?? 0,
        minFrequencyHz: (j['minFrequencyHz'] as num?)?.toDouble(),
        maxFrequencyHz: (j['maxFrequencyHz'] as num?)?.toDouble(),
        minImpedanceOhm: (j['minImpedanceOhm'] as num?)?.toDouble(),
        minImpedanceFrequencyHz:
            (j['minImpedanceFrequencyHz'] as num?)?.toDouble(),
        maxPhaseAngleDeg: (j['maxPhaseAngleDeg'] as num?)?.toDouble(),
        maxPhaseFrequencyHz: (j['maxPhaseFrequencyHz'] as num?)?.toDouble(),
        riskLevel: ImpedanceRiskLevel.fromJson(
            j['riskLevel'] as String? ?? 'unknown'),
        issues: (j['issues'] as List? ?? [])
            .map((e) =>
                ImpedanceIssue.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        notes: j['notes'] as String?,
      );
}

class ImpedanceAnalysisResult {
  final String id;
  final DateTime createdAt;
  final List<DriverImpedanceSummary> summaries;
  final List<ImpedanceIssue> issues;
  final ImpedanceRiskLevel overallRisk;
  final String summary;
  final String readinessLabel;

  ImpedanceAnalysisResult({
    required this.id,
    DateTime? createdAt,
    required this.summaries,
    required this.issues,
    required this.overallRisk,
    required this.summary,
    required this.readinessLabel,
  }) : createdAt = createdAt ?? DateTime.now();

  int get warningCount => issues
      .where((i) =>
          i.riskLevel == ImpedanceRiskLevel.medium ||
          i.riskLevel == ImpedanceRiskLevel.high)
      .length;
  int get criticalCount =>
      issues.where((i) => i.riskLevel == ImpedanceRiskLevel.critical).length;
  bool get hasCritical => criticalCount > 0;
  bool get hasWarnings => warningCount > 0 || hasCritical;
  int get analyzedDriverCount => summaries.length;
  int get missingZmaCount =>
      summaries.where((s) => !s.hasZma).length;
  int get lowImpedanceCount => summaries
      .where((s) =>
          s.minImpedanceOhm != null && s.minImpedanceOhm! < 4.0)
      .length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'summaries': summaries.map((s) => s.toJson()).toList(),
    'issues': issues.map((i) => i.toJson()).toList(),
    'overallRisk': overallRisk.toJson(),
    'summary': summary,
    'readinessLabel': readinessLabel,
  };

  factory ImpedanceAnalysisResult.fromJson(Map<String, dynamic> j) =>
      ImpedanceAnalysisResult(
        id: j['id'] as String? ?? '',
        createdAt:
            DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        summaries: (j['summaries'] as List? ?? [])
            .map((e) => DriverImpedanceSummary.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
        issues: (j['issues'] as List? ?? [])
            .map((e) =>
                ImpedanceIssue.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        overallRisk: ImpedanceRiskLevel.fromJson(
            j['overallRisk'] as String? ?? 'unknown'),
        summary: j['summary'] as String? ?? '',
        readinessLabel: j['readinessLabel'] as String? ?? 'No ZMA data',
      );

  static ImpedanceAnalysisResult empty() => ImpedanceAnalysisResult(
        id: 'imp_empty',
        summaries: const [],
        issues: const [],
        overallRisk: ImpedanceRiskLevel.unknown,
        summary: 'No drivers analyzed.',
        readinessLabel: 'No ZMA data',
      );
}

// ── Analyzer ──────────────────────────────────────────────────────────────────

class ProImpedanceAnalyzer {
  static ImpedanceAnalysisResult analyze({
    required MeasurementProjectState acousticState,
  }) {
    int seq = 0;
    String nextId() =>
        'imp_${DateTime.now().millisecondsSinceEpoch}_${seq++}';

    final summaries = <DriverImpedanceSummary>[];
    final allIssues = <ImpedanceIssue>[];

    final enabledDrivers =
        acousticState.driverChannels.where((d) => d.enabled).toList();

    if (enabledDrivers.isEmpty) {
      return ImpedanceAnalysisResult(
        id: nextId(),
        summaries: const [],
        issues: const [],
        overallRisk: ImpedanceRiskLevel.unknown,
        summary: 'No enabled driver channels.',
        readinessLabel: 'No ZMA data',
      );
    }

    for (final driver in enabledDrivers) {
      final issues = <ImpedanceIssue>[];

      if (!driver.hasParsedZma || driver.zmaData == null) {
        // Missing ZMA
        final issue = ImpedanceIssue(
          id: nextId(),
          type: ImpedanceIssueType.missingZma,
          riskLevel: ImpedanceRiskLevel.medium,
          channelId: driver.id,
          title: 'Missing ZMA: ${driver.name}',
          description:
              'No impedance measurement data available for ${driver.name}.',
          recommendation: 'Import ZMA data for amplifier load-risk analysis.',
        );
        issues.add(issue);
        allIssues.add(issue);
        summaries.add(DriverImpedanceSummary(
          channelId: driver.id,
          driverName: driver.name,
          hasZma: false,
          pointCount: 0,
          riskLevel: ImpedanceRiskLevel.unknown,
          issues: issues,
          notes: 'No ZMA imported.',
        ));
        continue;
      }

      final zma = driver.zmaData!;
      final points = zma.points;

      // Filter valid impedance points
      final validPts = points
          .where((p) =>
              p.impedanceOhm != null &&
              p.impedanceOhm!.isFinite &&
              p.impedanceOhm! > 0 &&
              p.frequencyHz > 0)
          .toList();

      if (validPts.length < points.length) {
        final badCount = points.length - validPts.length;
        final issue = ImpedanceIssue(
          id: nextId(),
          type: ImpedanceIssueType.nonFiniteData,
          riskLevel: ImpedanceRiskLevel.low,
          channelId: driver.id,
          title: 'Non-finite ZMA values: ${driver.name}',
          description:
              '$badCount point(s) skipped due to non-finite or non-positive impedance values.',
          recommendation: 'Verify ZMA file integrity.',
        );
        issues.add(issue);
        allIssues.add(issue);
      }

      if (validPts.isEmpty) {
        final issue = ImpedanceIssue(
          id: nextId(),
          type: ImpedanceIssueType.nonFiniteData,
          riskLevel: ImpedanceRiskLevel.medium,
          channelId: driver.id,
          title: 'No valid ZMA points: ${driver.name}',
          description: 'All impedance values in ZMA are non-finite or zero.',
          recommendation: 'Re-export ZMA measurement and re-import.',
        );
        issues.add(issue);
        allIssues.add(issue);
        summaries.add(DriverImpedanceSummary(
          channelId: driver.id,
          driverName: driver.name,
          hasZma: true,
          pointCount: 0,
          riskLevel: ImpedanceRiskLevel.medium,
          issues: issues,
        ));
        continue;
      }

      // Sparse data
      if (validPts.length < 10) {
        final issue = ImpedanceIssue(
          id: nextId(),
          type: ImpedanceIssueType.sparseData,
          riskLevel: ImpedanceRiskLevel.low,
          channelId: driver.id,
          title: 'Sparse ZMA data: ${driver.name}',
          description:
              'Only ${validPts.length} valid impedance point(s) — '
              'analysis may be imprecise.',
          recommendation:
              'Re-measure with finer frequency resolution for better load analysis.',
        );
        issues.add(issue);
        allIssues.add(issue);
      }

      // Frequency range
      final freqMin = validPts.first.frequencyHz;
      final freqMax = validPts.last.frequencyHz;
      if (freqMin > 20 || freqMax < 20000) {
        final issue = ImpedanceIssue(
          id: nextId(),
          type: ImpedanceIssueType.outOfRangeData,
          riskLevel: ImpedanceRiskLevel.low,
          channelId: driver.id,
          title: 'ZMA out of full range: ${driver.name}',
          description:
              'ZMA measurement covers '
              '${freqMin.toStringAsFixed(0)} Hz – ${freqMax.toStringAsFixed(0)} Hz '
              '(expected 20 Hz – 20 kHz). '
              'Load analysis outside this range is extrapolated.',
          recommendation:
              'Extend ZMA measurement to cover 20 Hz – 20 kHz for complete load analysis.',
        );
        issues.add(issue);
        allIssues.add(issue);
      }

      // Find minimum impedance and its frequency
      var minZOhm = validPts.first.impedanceOhm!;
      var minZFreq = validPts.first.frequencyHz;
      for (final pt in validPts) {
        if (pt.impedanceOhm! < minZOhm) {
          minZOhm = pt.impedanceOhm!;
          minZFreq = pt.frequencyHz;
        }
      }

      // Find maximum absolute phase angle
      final phasePts = validPts
          .where((p) => p.impedancePhaseDeg != null && p.impedancePhaseDeg!.isFinite)
          .toList();
      double? maxAbsPhase;
      double? maxPhaseFreq;
      if (phasePts.isNotEmpty) {
        for (final pt in phasePts) {
          final abs = pt.impedancePhaseDeg!.abs();
          if (maxAbsPhase == null || abs > maxAbsPhase) {
            maxAbsPhase = abs;
            maxPhaseFreq = pt.frequencyHz;
          }
        }
      }

      // Risk rules — impedance magnitude
      ImpedanceRiskLevel zRisk;
      if (minZOhm < 2.0) {
        zRisk = ImpedanceRiskLevel.critical;
        final issue = ImpedanceIssue(
          id: nextId(),
          type: ImpedanceIssueType.lowMinimumImpedance,
          riskLevel: ImpedanceRiskLevel.critical,
          channelId: driver.id,
          frequencyHz: minZFreq,
          title: 'Critical load: ${driver.name}',
          description:
              'Minimum impedance is ${minZOhm.toStringAsFixed(2)} Ω '
              'at ${minZFreq.toStringAsFixed(0)} Hz — '
              'below 2 Ω is critical amplifier load stress.',
          recommendation:
              'Verify amplifier can drive < 2 Ω loads. Hardware load test required.',
        );
        issues.add(issue);
        allIssues.add(issue);
      } else if (minZOhm < 3.0) {
        zRisk = ImpedanceRiskLevel.high;
        final issue = ImpedanceIssue(
          id: nextId(),
          type: ImpedanceIssueType.lowMinimumImpedance,
          riskLevel: ImpedanceRiskLevel.high,
          channelId: driver.id,
          frequencyHz: minZFreq,
          title: 'High load risk: ${driver.name}',
          description:
              'Minimum impedance is ${minZOhm.toStringAsFixed(2)} Ω '
              'at ${minZFreq.toStringAsFixed(0)} Hz — '
              'amplifier current demand may be elevated.',
          recommendation:
              'Confirm amplifier is rated for loads below 3 Ω. Expert verification required.',
        );
        issues.add(issue);
        allIssues.add(issue);
      } else if (minZOhm < 4.0) {
        zRisk = ImpedanceRiskLevel.medium;
        final issue = ImpedanceIssue(
          id: nextId(),
          type: ImpedanceIssueType.lowMinimumImpedance,
          riskLevel: ImpedanceRiskLevel.medium,
          channelId: driver.id,
          frequencyHz: minZFreq,
          title: 'Medium load: ${driver.name}',
          description:
              'Minimum impedance is ${minZOhm.toStringAsFixed(2)} Ω '
              'at ${minZFreq.toStringAsFixed(0)} Hz — '
              'below nominal 4 Ω.',
          recommendation:
              'Verify amplifier specification covers 4 Ω loads.',
        );
        issues.add(issue);
        allIssues.add(issue);
      } else {
        zRisk = ImpedanceRiskLevel.low;
      }

      // Phase angle risk
      ImpedanceRiskLevel phaseRisk = ImpedanceRiskLevel.none;
      if (maxAbsPhase != null) {
        if (maxAbsPhase >= 60.0) {
          phaseRisk = ImpedanceRiskLevel.high;
          final issue = ImpedanceIssue(
            id: nextId(),
            type: ImpedanceIssueType.severePhaseAngle,
            riskLevel: ImpedanceRiskLevel.high,
            channelId: driver.id,
            frequencyHz: maxPhaseFreq,
            title: 'Severe phase angle: ${driver.name}',
            description:
                'Maximum impedance phase angle is '
                '${maxAbsPhase.toStringAsFixed(1)}° '
                'at ${maxPhaseFreq?.toStringAsFixed(0) ?? "?"} Hz — '
                'high reactive load on amplifier.',
            recommendation:
                'Confirm amplifier stability under reactive loads. Expert verification required.',
          );
          issues.add(issue);
          allIssues.add(issue);
        } else if (maxAbsPhase >= 45.0) {
          phaseRisk = ImpedanceRiskLevel.medium;
          final issue = ImpedanceIssue(
            id: nextId(),
            type: ImpedanceIssueType.severePhaseAngle,
            riskLevel: ImpedanceRiskLevel.medium,
            channelId: driver.id,
            frequencyHz: maxPhaseFreq,
            title: 'Elevated phase angle: ${driver.name}',
            description:
                'Maximum impedance phase angle is '
                '${maxAbsPhase.toStringAsFixed(1)}° '
                'at ${maxPhaseFreq?.toStringAsFixed(0) ?? "?"} Hz — '
                'moderate reactive load.',
            recommendation:
                'Review amplifier reactive load specification.',
          );
          issues.add(issue);
          allIssues.add(issue);
        }
      }

      // Combined risk: low impedance + high phase angle escalates
      ImpedanceRiskLevel combinedRisk = _maxRisk(zRisk, phaseRisk);
      if (zRisk.severity >= ImpedanceRiskLevel.medium.severity &&
          phaseRisk.severity >= ImpedanceRiskLevel.medium.severity) {
        combinedRisk = _maxRisk(combinedRisk, ImpedanceRiskLevel.high);
        if (zRisk.severity >= ImpedanceRiskLevel.high.severity &&
            phaseRisk.severity >= ImpedanceRiskLevel.high.severity) {
          combinedRisk = ImpedanceRiskLevel.critical;
        }
        // Add combined-risk issue only when it escalates beyond individual risks
        if (combinedRisk.severity > _maxRisk(zRisk, phaseRisk).severity ||
            (zRisk.severity >= ImpedanceRiskLevel.medium.severity &&
                phaseRisk.severity >= ImpedanceRiskLevel.medium.severity)) {
          final issue = ImpedanceIssue(
            id: nextId(),
            type: ImpedanceIssueType.lowImpedanceWithPhaseAngle,
            riskLevel: combinedRisk,
            channelId: driver.id,
            title: 'Combined Z+phase risk: ${driver.name}',
            description:
                'Low impedance (${minZOhm.toStringAsFixed(2)} Ω) combined with '
                'phase angle (${maxAbsPhase?.toStringAsFixed(1) ?? "?"}°) '
                'increases amplifier stress.',
            recommendation:
                'Verify amplifier is rated for this combined reactive/resistive load. '
                'Hardware stress test required.',
          );
          issues.add(issue);
          allIssues.add(issue);
        }
      }

      summaries.add(DriverImpedanceSummary(
        channelId: driver.id,
        driverName: driver.name,
        hasZma: true,
        pointCount: validPts.length,
        minFrequencyHz: freqMin,
        maxFrequencyHz: freqMax,
        minImpedanceOhm: minZOhm,
        minImpedanceFrequencyHz: minZFreq,
        maxPhaseAngleDeg: maxAbsPhase,
        maxPhaseFrequencyHz: maxPhaseFreq,
        riskLevel: combinedRisk,
        issues: issues,
        notes: 'ZMA: ${zma.sourceFileName}  ${zma.freqRangeLabel}  '
            '${validPts.length} pts',
      ));
    }

    // Overall risk = max across all summaries (exclude unknown from max comparison)
    ImpedanceRiskLevel overallRisk = ImpedanceRiskLevel.none;
    for (final s in summaries) {
      if (s.riskLevel != ImpedanceRiskLevel.unknown) {
        overallRisk = _maxRisk(overallRisk, s.riskLevel);
      }
    }
    // If no summaries analyzed, result is unknown
    if (summaries.isEmpty) {
      overallRisk = ImpedanceRiskLevel.unknown;
    }
    // Also consider missing ZMA as at least unknown
    final missingCount = summaries.where((s) => !s.hasZma).length;
    if (missingCount > 0 &&
        overallRisk.severity < ImpedanceRiskLevel.medium.severity) {
      overallRisk = ImpedanceRiskLevel.unknown;
    }

    final readinessLabel = _readinessLabel(overallRisk, missingCount, summaries.length);

    final criticalCount =
        allIssues.where((i) => i.riskLevel == ImpedanceRiskLevel.critical).length;
    final warnCount = allIssues
        .where((i) =>
            i.riskLevel == ImpedanceRiskLevel.high ||
            i.riskLevel == ImpedanceRiskLevel.medium)
        .length;

    return ImpedanceAnalysisResult(
      id: nextId(),
      summaries: summaries,
      issues: allIssues,
      overallRisk: overallRisk,
      summary: 'Analyzed ${summaries.length} driver(s)  '
          '$missingCount missing ZMA  '
          '${summaries.length - missingCount} with ZMA  '
          '$criticalCount critical  $warnCount warning(s)  '
          '${readinessLabel.toLowerCase()}  '
          'Advisory only — hardware verification required.',
      readinessLabel: readinessLabel,
    );
  }

  static ImpedanceRiskLevel _maxRisk(
          ImpedanceRiskLevel a, ImpedanceRiskLevel b) =>
      a.severity >= b.severity ? a : b;

  static String _readinessLabel(
    ImpedanceRiskLevel risk,
    int missingCount,
    int total,
  ) {
    if (total == 0) return 'No ZMA data';
    if (missingCount == total) return 'No ZMA data';
    if (risk == ImpedanceRiskLevel.critical) return 'Critical load risk';
    if (risk == ImpedanceRiskLevel.high) return 'Load risk warnings';
    if (risk == ImpedanceRiskLevel.medium) return 'Load risk warnings';
    if (missingCount > 0) return 'Impedance data partial';
    if (risk == ImpedanceRiskLevel.low || risk == ImpedanceRiskLevel.none) {
      return 'Load risk low';
    }
    return 'Impedance data partial';
  }
}
