// ── TUNAI PRO — Tuning Report Snapshot (typed, read-only) ─────────────────────
// A frozen, serializable snapshot composing project state + the separate
// measurement store + two DERIVED results (phase alignment, optimizer scores).
//
// This is a reporting model only. It does NOT modify the project, the optimizer
// engine, DspExportPackage, DeployPackageSnapshot, or any DSP/transport path.
// Build it with buildTuningReport(...) — a pure function. No file/PDF emission.

import 'pro_measurement.dart';
import 'pro_measurement_store.dart';
import 'pro_optimizer_data.dart';
import 'pro_phase_alignment.dart';
import 'pro_project.dart';
import 'pro_simulation_optimizer.dart';
import 'pro_tuning_data.dart';

/// Report schema version — bump when the serialized shape changes.
const int kTuningReportSchemaVersion = 1;

// ── Section models ────────────────────────────────────────────────────────────

class TuningReportProjectMeta {
  final String projectId;
  final String projectName;
  final String speakerModel;
  final String roomName;
  final String channelConfig;
  final String dspTarget;
  final int sampleRate;
  final String profileStatus;
  final String safetyStatus;
  final DateTime updatedAt;

  const TuningReportProjectMeta({
    required this.projectId,
    required this.projectName,
    required this.speakerModel,
    required this.roomName,
    required this.channelConfig,
    required this.dspTarget,
    required this.sampleRate,
    required this.profileStatus,
    required this.safetyStatus,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        'projectName': projectName,
        'speakerModel': speakerModel,
        'roomName': roomName,
        'channelConfig': channelConfig,
        'dspTarget': dspTarget,
        'sampleRate': sampleRate,
        'profileStatus': profileStatus,
        'safetyStatus': safetyStatus,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory TuningReportProjectMeta.fromJson(Map<String, dynamic> j) =>
      TuningReportProjectMeta(
        projectId: j['projectId'] as String? ?? '',
        projectName: j['projectName'] as String? ?? '',
        speakerModel: j['speakerModel'] as String? ?? '',
        roomName: j['roomName'] as String? ?? '',
        channelConfig: j['channelConfig'] as String? ?? '',
        dspTarget: j['dspTarget'] as String? ?? '',
        sampleRate: j['sampleRate'] as int? ?? 0,
        profileStatus: j['profileStatus'] as String? ?? '',
        safetyStatus: j['safetyStatus'] as String? ?? '',
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class TuningReportMeasurementSummary {
  final int totalDrivers;
  final int frdImportedCount;
  final bool hasMissingMeasurements;

  /// From the separate measurement store (not part of ProProject).
  final int sessionCount;
  final int completedSessionCount;
  final int totalPoints;
  final int acceptedPoints;
  final DateTime? lastSessionAt;

  const TuningReportMeasurementSummary({
    required this.totalDrivers,
    required this.frdImportedCount,
    required this.hasMissingMeasurements,
    required this.sessionCount,
    required this.completedSessionCount,
    required this.totalPoints,
    required this.acceptedPoints,
    required this.lastSessionAt,
  });

  Map<String, dynamic> toJson() => {
        'totalDrivers': totalDrivers,
        'frdImportedCount': frdImportedCount,
        'hasMissingMeasurements': hasMissingMeasurements,
        'sessionCount': sessionCount,
        'completedSessionCount': completedSessionCount,
        'totalPoints': totalPoints,
        'acceptedPoints': acceptedPoints,
        if (lastSessionAt != null)
          'lastSessionAt': lastSessionAt!.toIso8601String(),
      };

  factory TuningReportMeasurementSummary.fromJson(Map<String, dynamic> j) =>
      TuningReportMeasurementSummary(
        totalDrivers: j['totalDrivers'] as int? ?? 0,
        frdImportedCount: j['frdImportedCount'] as int? ?? 0,
        hasMissingMeasurements: j['hasMissingMeasurements'] as bool? ?? false,
        sessionCount: j['sessionCount'] as int? ?? 0,
        completedSessionCount: j['completedSessionCount'] as int? ?? 0,
        totalPoints: j['totalPoints'] as int? ?? 0,
        acceptedPoints: j['acceptedPoints'] as int? ?? 0,
        lastSessionAt: DateTime.tryParse(j['lastSessionAt'] as String? ?? ''),
      );
}

class TuningReportTargetCurveSummary {
  final String presetName;
  final String presetLabel;

  const TuningReportTargetCurveSummary({
    required this.presetName,
    required this.presetLabel,
  });

  Map<String, dynamic> toJson() =>
      {'presetName': presetName, 'presetLabel': presetLabel};

  factory TuningReportTargetCurveSummary.fromJson(Map<String, dynamic> j) =>
      TuningReportTargetCurveSummary(
        presetName: j['presetName'] as String? ?? '',
        presetLabel: j['presetLabel'] as String? ?? '',
      );
}

class TuningReportCrossoverSummary {
  final int configuredChannels;
  final int hpfCount;
  final int lpfCount;
  final int polarityInvertedCount;

  const TuningReportCrossoverSummary({
    required this.configuredChannels,
    required this.hpfCount,
    required this.lpfCount,
    required this.polarityInvertedCount,
  });

  Map<String, dynamic> toJson() => {
        'configuredChannels': configuredChannels,
        'hpfCount': hpfCount,
        'lpfCount': lpfCount,
        'polarityInvertedCount': polarityInvertedCount,
      };

  factory TuningReportCrossoverSummary.fromJson(Map<String, dynamic> j) =>
      TuningReportCrossoverSummary(
        configuredChannels: j['configuredChannels'] as int? ?? 0,
        hpfCount: j['hpfCount'] as int? ?? 0,
        lpfCount: j['lpfCount'] as int? ?? 0,
        polarityInvertedCount: j['polarityInvertedCount'] as int? ?? 0,
      );
}

class TuningReportPeqSummary {
  final int channelCount;
  final int totalBands;
  final int activeBands;

  const TuningReportPeqSummary({
    required this.channelCount,
    required this.totalBands,
    required this.activeBands,
  });

  Map<String, dynamic> toJson() => {
        'channelCount': channelCount,
        'totalBands': totalBands,
        'activeBands': activeBands,
      };

  factory TuningReportPeqSummary.fromJson(Map<String, dynamic> j) =>
      TuningReportPeqSummary(
        channelCount: j['channelCount'] as int? ?? 0,
        totalBands: j['totalBands'] as int? ?? 0,
        activeBands: j['activeBands'] as int? ?? 0,
      );
}

/// One frozen phase-alignment verdict (derived from XoPhaseAlignment).
class TuningReportPhasePair {
  final String lowLabel;
  final String highLabel;
  final double crossoverHz;
  final double phaseDiffDeg;
  final String status; // good | check | misalign

  const TuningReportPhasePair({
    required this.lowLabel,
    required this.highLabel,
    required this.crossoverHz,
    required this.phaseDiffDeg,
    required this.status,
  });

  Map<String, dynamic> toJson() => {
        'lowLabel': lowLabel,
        'highLabel': highLabel,
        'crossoverHz': crossoverHz,
        'phaseDiffDeg': phaseDiffDeg,
        'status': status,
      };

  factory TuningReportPhasePair.fromJson(Map<String, dynamic> j) =>
      TuningReportPhasePair(
        lowLabel: j['lowLabel'] as String? ?? '',
        highLabel: j['highLabel'] as String? ?? '',
        crossoverHz: (j['crossoverHz'] as num?)?.toDouble() ?? 0.0,
        phaseDiffDeg: (j['phaseDiffDeg'] as num?)?.toDouble() ?? 0.0,
        status: j['status'] as String? ?? '',
      );
}

class TuningReportPhaseAlignmentSummary {
  /// Electrical phase simulation only — measured acoustic phase is not included.
  final bool electricalOnly;
  final List<TuningReportPhasePair> pairs;

  const TuningReportPhaseAlignmentSummary({
    this.electricalOnly = true,
    required this.pairs,
  });

  int get goodCount => pairs.where((p) => p.status == 'good').length;
  int get checkCount => pairs.where((p) => p.status == 'check').length;
  int get misalignCount => pairs.where((p) => p.status == 'misalign').length;

  Map<String, dynamic> toJson() => {
        'electricalOnly': electricalOnly,
        'pairs': pairs.map((p) => p.toJson()).toList(),
      };

  factory TuningReportPhaseAlignmentSummary.fromJson(Map<String, dynamic> j) =>
      TuningReportPhaseAlignmentSummary(
        electricalOnly: j['electricalOnly'] as bool? ?? true,
        pairs: (j['pairs'] as List? ?? [])
            .map((e) =>
                TuningReportPhasePair.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class TuningReportOptimizerSummary {
  final int runCount;
  final int acceptedCount;
  final int pendingCount;
  final int rejectedCount;
  final int lockedCount;

  /// Frozen simulated target-match scores (0–100). Null when no drivers.
  final double? beforeScore;
  final double? afterScore;
  final String? confidence; // low | medium | high

  /// Electrical + measured magnitude projection — not a measured verification.
  final bool simulatedProjection;

  const TuningReportOptimizerSummary({
    required this.runCount,
    required this.acceptedCount,
    required this.pendingCount,
    required this.rejectedCount,
    required this.lockedCount,
    required this.beforeScore,
    required this.afterScore,
    required this.confidence,
    this.simulatedProjection = true,
  });

  double? get improvement =>
      (beforeScore == null || afterScore == null) ? null : afterScore! - beforeScore!;

  Map<String, dynamic> toJson() => {
        'runCount': runCount,
        'acceptedCount': acceptedCount,
        'pendingCount': pendingCount,
        'rejectedCount': rejectedCount,
        'lockedCount': lockedCount,
        if (beforeScore != null) 'beforeScore': beforeScore,
        if (afterScore != null) 'afterScore': afterScore,
        if (confidence != null) 'confidence': confidence,
        'simulatedProjection': simulatedProjection,
      };

  factory TuningReportOptimizerSummary.fromJson(Map<String, dynamic> j) =>
      TuningReportOptimizerSummary(
        runCount: j['runCount'] as int? ?? 0,
        acceptedCount: j['acceptedCount'] as int? ?? 0,
        pendingCount: j['pendingCount'] as int? ?? 0,
        rejectedCount: j['rejectedCount'] as int? ?? 0,
        lockedCount: j['lockedCount'] as int? ?? 0,
        beforeScore: (j['beforeScore'] as num?)?.toDouble(),
        afterScore: (j['afterScore'] as num?)?.toDouble(),
        confidence: j['confidence'] as String?,
        simulatedProjection: j['simulatedProjection'] as bool? ?? true,
      );
}

class TuningReportDeploymentSummary {
  final int packageCount;
  final int presetCount;
  final int readyPackageCount;
  final int blockedPackageCount;
  final String readinessLabel;
  final String? activePackageVersion;
  final String? activePackageStatus;

  const TuningReportDeploymentSummary({
    required this.packageCount,
    required this.presetCount,
    required this.readyPackageCount,
    required this.blockedPackageCount,
    required this.readinessLabel,
    required this.activePackageVersion,
    required this.activePackageStatus,
  });

  Map<String, dynamic> toJson() => {
        'packageCount': packageCount,
        'presetCount': presetCount,
        'readyPackageCount': readyPackageCount,
        'blockedPackageCount': blockedPackageCount,
        'readinessLabel': readinessLabel,
        if (activePackageVersion != null)
          'activePackageVersion': activePackageVersion,
        if (activePackageStatus != null)
          'activePackageStatus': activePackageStatus,
      };

  factory TuningReportDeploymentSummary.fromJson(Map<String, dynamic> j) =>
      TuningReportDeploymentSummary(
        packageCount: j['packageCount'] as int? ?? 0,
        presetCount: j['presetCount'] as int? ?? 0,
        readyPackageCount: j['readyPackageCount'] as int? ?? 0,
        blockedPackageCount: j['blockedPackageCount'] as int? ?? 0,
        readinessLabel: j['readinessLabel'] as String? ?? '',
        activePackageVersion: j['activePackageVersion'] as String?,
        activePackageStatus: j['activePackageStatus'] as String?,
      );
}

class TuningReportRevisions {
  final int tuning;
  final int protection;
  final int optimizer;

  const TuningReportRevisions({
    required this.tuning,
    required this.protection,
    required this.optimizer,
  });

  Map<String, dynamic> toJson() =>
      {'tuning': tuning, 'protection': protection, 'optimizer': optimizer};

  factory TuningReportRevisions.fromJson(Map<String, dynamic> j) =>
      TuningReportRevisions(
        tuning: j['tuning'] as int? ?? 0,
        protection: j['protection'] as int? ?? 0,
        optimizer: j['optimizer'] as int? ?? 0,
      );
}

// ── Top-level report snapshot ─────────────────────────────────────────────────

class TuningReportData {
  final int schemaVersion;
  final DateTime generatedAt;
  final TuningReportProjectMeta project;
  final TuningReportMeasurementSummary measurement;
  final TuningReportTargetCurveSummary targetCurve;
  final TuningReportCrossoverSummary crossover;
  final TuningReportPeqSummary peq;
  final TuningReportPhaseAlignmentSummary phaseAlignment;
  final TuningReportOptimizerSummary optimizer;
  final TuningReportDeploymentSummary deployment;
  final List<String> warnings;
  final TuningReportRevisions revisions;

  const TuningReportData({
    this.schemaVersion = kTuningReportSchemaVersion,
    required this.generatedAt,
    required this.project,
    required this.measurement,
    required this.targetCurve,
    required this.crossover,
    required this.peq,
    required this.phaseAlignment,
    required this.optimizer,
    required this.deployment,
    required this.warnings,
    required this.revisions,
  });

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'generatedAt': generatedAt.toIso8601String(),
        'project': project.toJson(),
        'measurement': measurement.toJson(),
        'targetCurve': targetCurve.toJson(),
        'crossover': crossover.toJson(),
        'peq': peq.toJson(),
        'phaseAlignment': phaseAlignment.toJson(),
        'optimizer': optimizer.toJson(),
        'deployment': deployment.toJson(),
        'warnings': warnings,
        'revisions': revisions.toJson(),
      };

  factory TuningReportData.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic> sub(String key) =>
        Map<String, dynamic>.from((j[key] as Map?) ?? const {});
    return TuningReportData(
      schemaVersion: j['schemaVersion'] as int? ?? kTuningReportSchemaVersion,
      generatedAt: DateTime.tryParse(j['generatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      project: TuningReportProjectMeta.fromJson(sub('project')),
      measurement: TuningReportMeasurementSummary.fromJson(sub('measurement')),
      targetCurve: TuningReportTargetCurveSummary.fromJson(sub('targetCurve')),
      crossover: TuningReportCrossoverSummary.fromJson(sub('crossover')),
      peq: TuningReportPeqSummary.fromJson(sub('peq')),
      phaseAlignment:
          TuningReportPhaseAlignmentSummary.fromJson(sub('phaseAlignment')),
      optimizer: TuningReportOptimizerSummary.fromJson(sub('optimizer')),
      deployment: TuningReportDeploymentSummary.fromJson(sub('deployment')),
      warnings: (j['warnings'] as List? ?? []).map((e) => e.toString()).toList(),
      revisions: TuningReportRevisions.fromJson(sub('revisions')),
    );
  }
}

// ── Pure builder ──────────────────────────────────────────────────────────────

/// Builds a frozen [TuningReportData] snapshot from live project state and the
/// (separate) measurement store. Read-only: it computes phase alignment via
/// [XoPhaseAlignment] and optimizer target-match scores via
/// [ProSimulationOptimizer], then freezes the derived results into the report.
///
/// Does not mutate anything, emit files, or touch the optimizer engine,
/// export/deploy models, or any DSP/transport path.
TuningReportData buildTuningReport(
  ProProject project,
  ProMeasurementStore measurementStore, {
  DateTime? generatedAt,
}) {
  final acoustic = project.acousticState;
  final tuning = project.tuningState;
  final now = generatedAt ?? DateTime.now();
  final warnings = <String>[];

  // ── Project meta ────────────────────────────────────────────────────────────
  final meta = TuningReportProjectMeta(
    projectId: project.id,
    projectName: project.name,
    speakerModel: project.speakerModel,
    roomName: project.roomName,
    channelConfig: project.channelConfig,
    dspTarget: project.dspTarget,
    sampleRate: project.sampleRate,
    profileStatus: project.profileStatus.label,
    safetyStatus: project.safetyStatus.label,
    updatedAt: project.updatedAt,
  );

  // ── Measurement (project acoustic + separate measurement store) ─────────────
  final completedSessions = measurementStore.sessions
      .where((s) =>
          s.status == MeasurementSessionStatus.completed ||
          s.status == MeasurementSessionStatus.reviewed)
      .toList();
  final allPoints = measurementStore.sessions.expand((s) => s.points).toList();
  final acceptedPoints = allPoints
      .where((p) => p.status == MeasurementPointStatus.accepted)
      .length;
  final lastSession = measurementStore.sessions.isEmpty
      ? null
      : measurementStore.sessions
          .reduce((a, b) => a.updatedAt.isAfter(b.updatedAt) ? a : b);

  final measurement = TuningReportMeasurementSummary(
    totalDrivers: acoustic.totalDrivers,
    frdImportedCount: acoustic.importedFrdCount,
    hasMissingMeasurements: acoustic.hasMissingMeasurements,
    sessionCount: measurementStore.sessions.length,
    completedSessionCount: completedSessions.length,
    totalPoints: allPoints.length,
    acceptedPoints: acceptedPoints,
    lastSessionAt: lastSession?.updatedAt,
  );
  if (acoustic.hasMissingMeasurements) {
    warnings.add(
        'FRD data missing on ${acoustic.totalDrivers - acoustic.importedFrdCount} '
        'channel(s); simulation is draft-only.');
  }

  // ── Target curve ────────────────────────────────────────────────────────────
  final preset = acoustic.targetCurve.selectedPreset;
  final targetCurve = TuningReportTargetCurveSummary(
    presetName: preset.name,
    presetLabel: preset.label,
  );

  // ── Crossover ───────────────────────────────────────────────────────────────
  final crossover = TuningReportCrossoverSummary(
    configuredChannels: tuning.configuredXoChannels,
    hpfCount: tuning.hpfCount,
    lpfCount: tuning.lpfCount,
    polarityInvertedCount: tuning.polarityInvertedCount,
  );

  // ── PEQ ─────────────────────────────────────────────────────────────────────
  final peq = TuningReportPeqSummary(
    channelCount: tuning.peqChannels.length,
    totalBands: tuning.totalPeqBands,
    activeBands: tuning.activePeqBands,
  );

  // ── Phase alignment (derived, frozen) ───────────────────────────────────────
  final phaseAlignment = _buildPhaseAlignment(project);

  // ── Optimizer (derived scores, frozen) ──────────────────────────────────────
  final optimizer = _buildOptimizerSummary(project);

  // ── Deployment ──────────────────────────────────────────────────────────────
  final deploy = project.deployState;
  final activePkg = deploy.activePackage;
  final deployment = TuningReportDeploymentSummary(
    packageCount: deploy.packageCount,
    presetCount: deploy.presetCount,
    readyPackageCount: deploy.readyPackageCount,
    blockedPackageCount: deploy.blockedPackageCount,
    readinessLabel: deploy.readinessLabel,
    activePackageVersion: activePkg?.version,
    activePackageStatus: activePkg?.status.label,
  );
  if (deploy.blockedPackageCount > 0) {
    warnings.add('${deploy.blockedPackageCount} deployment package(s) blocked.');
  }
  if (phaseAlignment.misalignCount > 0) {
    warnings.add(
        '${phaseAlignment.misalignCount} crossover(s) show phase misalignment '
        '(electrical simulation).');
  }

  return TuningReportData(
    generatedAt: now,
    project: meta,
    measurement: measurement,
    targetCurve: targetCurve,
    crossover: crossover,
    peq: peq,
    phaseAlignment: phaseAlignment,
    optimizer: optimizer,
    deployment: deployment,
    warnings: warnings,
    revisions: TuningReportRevisions(
      tuning: tuning.tuningRevision,
      protection: project.protectionState.revision,
      optimizer: project.optimizerState.revision,
    ),
  );
}

TuningReportPhaseAlignmentSummary _buildPhaseAlignment(ProProject project) {
  final tuning = project.tuningState;
  final controlById = {
    for (final c in tuning.channelControls) c.channelId: c,
  };
  final nameById = {
    for (final d in project.acousticState.driverChannels) d.id: d.name,
  };
  final inputs = <XoAlignmentInput>[
    for (final ch in tuning.crossoverChannels)
      XoAlignmentInput(
        label: nameById[ch.channelId] ?? ch.channelId,
        channel: ch,
        delayMs: controlById[ch.channelId]?.delayMs ?? 0.0,
        phaseOffsetDeg: controlById[ch.channelId]?.phaseOffsetDeg ?? 0.0,
      ),
  ];
  final pairs = [
    for (final p in XoPhaseAlignment.analyze(inputs))
      TuningReportPhasePair(
        lowLabel: p.lowLabel,
        highLabel: p.highLabel,
        crossoverHz: p.crossoverHz,
        phaseDiffDeg: p.phaseDiffDeg,
        status: p.status.name,
      ),
  ];
  return TuningReportPhaseAlignmentSummary(pairs: pairs);
}

TuningReportOptimizerSummary _buildOptimizerSummary(ProProject project) {
  final opt = project.optimizerState;
  final acoustic = project.acousticState;
  final drivers = acoustic.driverChannels;

  double? before;
  double? after;
  String? confidence;

  if (drivers.isNotEmpty) {
    final config = opt.activeRun?.config ?? const OptimizerRunConfig();
    final preset = acoustic.targetCurve.selectedPreset;
    var sumBefore = 0.0;
    var sumAfter = 0.0;
    var n = 0;
    OptimizerConfidence? worst;
    for (final driver in drivers) {
      final currentPeq = project.tuningState.peqChannels.firstWhere(
          (c) => c.channelId == driver.id,
          orElse: () => PeqChannelState.empty(driver.id));
      final result = ProSimulationOptimizer.optimizeDriver(
        driver: driver,
        currentPeq: currentPeq,
        target: preset,
        config: config,
        nextId: () => 'report',
      );
      sumBefore += result.before.score;
      sumAfter += result.after.score;
      n++;
      for (final s in result.suggestions) {
        if (s.type != OptimizerSuggestionType.addPeqBand) continue;
        if (worst == null || s.confidence.index < worst.index) {
          worst = s.confidence;
        }
      }
    }
    before = sumBefore / n;
    after = sumAfter / n;
    worst ??= drivers.every((d) => d.hasParsedFrd)
        ? OptimizerConfidence.medium
        : OptimizerConfidence.low;
    confidence = worst.name;
  }

  return TuningReportOptimizerSummary(
    runCount: opt.runs.length,
    acceptedCount: opt.acceptedSuggestionCount,
    pendingCount: opt.pendingSuggestionCount,
    rejectedCount: opt.rejectedSuggestionCount,
    lockedCount: opt.lockedSuggestionCount,
    beforeScore: before,
    afterScore: after,
    confidence: confidence,
  );
}
