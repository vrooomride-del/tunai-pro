// ── TUNAI PRO Phase N — Acoustic Simulation Engine (Draft) ───────────────────
// Generates draft frequency response preview curves from project state.
// Uses imported FRD data when available; falls back to placeholder shapes.
// Phase N: complex (phase-aware) summation using FRD phase + delay + polarity.
// NOT final acoustic simulation. No hardware write. No DSP addresses.
// Phase-accurate baffle/enclosure diffraction NOT implemented.
// AI suggests. Expert verifies. AOS protects. DSP executes.

import 'dart:math' as math;
import 'pro_project.dart';
import 'pro_acoustic_data.dart';
import 'pro_simulation_data.dart';
import 'pro_tuning_data.dart';

// ── Public entry point ────────────────────────────────────────────────────────

SimulationRunResult generateSimulationDraft({
  required ProProject project,
  SimulationRunConfig? config,
}) {
  final cfg = config ?? const SimulationRunConfig();
  final acoustic = project.acousticState;
  final tuning = project.tuningState;

  int seq = 0;
  String nextId(String prefix) =>
      '${prefix}_${DateTime.now().millisecondsSinceEpoch}_${seq++}';

  // ── Validate frequency range ───────────────────────────────────────────────
  final warnings = <String>[];
  double minF = cfg.minFrequencyHz;
  double maxF = cfg.maxFrequencyHz;

  if (minF <= 0 || maxF <= minF) {
    warnings.add(
        'Invalid frequency range (${minF.toStringAsFixed(0)}–'
        '${maxF.toStringAsFixed(0)} Hz). Using defaults 20–20000 Hz.');
    minF = 20;
    maxF = 20000;
  }

  // ── Frequency grid: log-spaced ─────────────────────────────────────────────
  final freqs = _logGrid(minF, maxF, cfg.pointsPerOctave);

  // ── Curves ────────────────────────────────────────────────────────────────
  final curves = <SimulationCurve>[];

  // 1. Target curve
  if (cfg.includeTarget) {
    curves.add(_buildTargetCurve(nextId('curve'), acoustic.targetCurve, freqs));
  }

  // 2. Per-driver curves — use imported FRD when available
  final driverCurves = <SimulationCurve>[];
  bool hasImportedFrd = false;
  bool hasPlaceholderDriver = false;

  if (cfg.includeDrivers) {
    for (final driver in acoustic.driverChannels) {
      if (!driver.enabled) continue;
      final gainOffset = _channelGainDb(tuning, driver.id);
      if (driver.hasParsedFrd && driver.frdData != null) {
        hasImportedFrd = true;
        driverCurves.add(_buildImportedFrdCurve(
            nextId('curve'), driver, freqs, gainOffset));
      } else {
        hasPlaceholderDriver = true;
        driverCurves.add(
            _buildDriverCurve(nextId('curve'), driver, freqs, gainOffset));
      }
    }
    if (acoustic.driverChannels.isEmpty) {
      driverCurves.add(SimulationCurve(
        id: nextId('curve'),
        label: 'No Drivers',
        type: SimulationCurveType.driver,
        status: SimulationCurveStatus.empty,
        points: const [],
        warning: 'No driver channels configured.',
      ));
    }
    curves.addAll(driverCurves);

    if (hasImportedFrd && hasPlaceholderDriver) {
      warnings.add(
          'Mixed simulation: some drivers use imported FRD data, '
          'others use placeholder shapes. Import FRD for all channels for a '
          'consistent simulation.');
    }
  }

  // 3. Driver phase trace curves
  if (cfg.includeDriverPhaseCurves) {
    for (final driver in acoustic.driverChannels) {
      if (!driver.enabled) continue;
      final frd = driver.frdData;
      if (frd == null || !frd.hasPhase) continue;
      final pts = freqs.map((f) {
        final ph = _interpolatePhase(frd.points, f);
        return SimulationPoint(frequencyHz: f, value: ph, phaseDeg: ph);
      }).toList();
      curves.add(SimulationCurve(
        id: nextId('curve'),
        label: '${driver.name} Phase',
        type: SimulationCurveType.phaseTrace,
        status: SimulationCurveStatus.imported,
        scale: SimulationScale.phaseDeg,
        channelId: driver.id,
        points: pts,
        warning: 'Phase unwrap is simplified in Phase N.',
        notes: 'Source: ${frd.sourceFileName}',
      ));
    }
  }

  // 4. Phase-aware summed response and magnitude-only comparison
  final activeDriversWithPhase = acoustic.driverChannels
      .where((d) => d.enabled && d.hasParsedFrd && d.frdData!.hasPhase)
      .toList();
  final canPhaseAware =
      cfg.includePhaseAwareSummation && activeDriversWithPhase.length >= 2;

  if (cfg.includePhaseAwareSummation || cfg.includeMagnitudeOnlyComparison) {
    if (canPhaseAware) {
      // Build phase-aware complex summation
      final phaseAwareCurve = _buildPhaseAwareSummedCurve(
        id: nextId('curve'),
        drivers: activeDriversWithPhase,
        tuning: tuning,
        freqs: freqs,
        useAcousticOffsets: cfg.useAcousticOffsets,
      );
      curves.add(phaseAwareCurve);

      if (cfg.includeDriverPhaseCurves) {
        // Phase trace of summed response
        final phaseTracePts = freqs.asMap().entries.map((e) {
          final f = e.value;
          final pt = phaseAwareCurve.points[e.key];
          return SimulationPoint(
              frequencyHz: f, value: pt.phaseDeg ?? 0.0, phaseDeg: pt.phaseDeg);
        }).toList();
        curves.add(SimulationCurve(
          id: nextId('curve'),
          label: 'Summed Phase (Phase-aware Draft)',
          type: SimulationCurveType.phaseTrace,
          status: SimulationCurveStatus.phaseAwareDraft,
          scale: SimulationScale.phaseDeg,
          points: phaseTracePts,
          warning: 'Summed phase is draft only. Phase-accurate verification required.',
        ));
      }

      warnings.add(
          'Phase-aware summation draft uses imported FRD phase, delay, and polarity. '
          'Full acoustic verification is still required.');
      if (cfg.useAcousticOffsets) {
        warnings.add(
            'Acoustic offset delays applied. Distance measured to listening axis.');
      }
    } else if (cfg.includePhaseAwareSummation) {
      // Explain why we fell back
      final missingPhaseCount = acoustic.driverChannels
          .where((d) => d.enabled && d.hasParsedFrd && !d.frdData!.hasPhase)
          .length;
      final noFrdCount =
          acoustic.driverChannels.where((d) => d.enabled && !d.hasParsedFrd).length;
      warnings.add(
          'Phase-aware summation requires FRD phase for all active drivers. '
          'Magnitude-only fallback used.'
          '${missingPhaseCount > 0 ? " ($missingPhaseCount driver(s) have FRD without phase.)" : ""}'
          '${noFrdCount > 0 ? " ($noFrdCount driver(s) have no FRD.)" : ""}');
    }

    // Magnitude-only comparison (or sole summed if phase not available)
    if (cfg.includeMagnitudeOnlyComparison || !canPhaseAware) {
      final magOnlyCurve = _buildMagnitudeOnlySummedCurve(
          nextId('curve'), driverCurves, freqs,
          fallback: !canPhaseAware && cfg.includeSummed);
      curves.add(magOnlyCurve);
    }
  } else if (cfg.includeSummed) {
    // Legacy summed path (includeSummed flag, no phase config)
    curves.add(_buildMagnitudeOnlySummedCurve(
        nextId('curve'), driverCurves, freqs,
        fallback: true));
    if (!hasImportedFrd) {
      warnings.add(
          'Draft simulation. Placeholder response data — import FRD files to use measured data.');
    } else {
      warnings.add('Simulation uses imported FRD magnitude data. '
          'Summed response is magnitude-only draft — full phase-aware summation not implemented.');
    }
  }

  // 5. Phase placeholder (legacy)
  if (cfg.includePhasePlaceholder) {
    curves.add(SimulationCurve(
      id: nextId('curve'),
      label: 'Phase (Placeholder)',
      type: SimulationCurveType.phasePlaceholder,
      status: SimulationCurveStatus.placeholder,
      scale: SimulationScale.phaseDeg,
      points: freqs
          .map((f) => SimulationPoint(frequencyHz: f, value: 0.0))
          .toList(),
      warning: 'Phase placeholder — 0° across all frequencies. '
          'Use imported FRD with phase for Phase-aware draft.',
    ));
    warnings.add('Phase placeholder is flat 0° — not acoustically valid.');
  }

  // Standard trailing warnings
  warnings.add(
      'Simulation is draft-only and does not replace measured acoustic verification.');

  // ── Readiness ─────────────────────────────────────────────────────────────
  final hasPhaseAware =
      curves.any((c) => c.status == SimulationCurveStatus.phaseAwareDraft);
  final hasImported =
      curves.any((c) => c.status == SimulationCurveStatus.imported);

  final readiness = hasPhaseAware
      ? SimulationReadiness.calculatedDraft
      : hasImported
          ? SimulationReadiness.estimated
          : curves.isNotEmpty
              ? SimulationReadiness.placeholderOnly
              : SimulationReadiness.noData;

  final curveDescriptions = [
    if (cfg.includeTarget) 'target',
    if (cfg.includeDrivers)
      '${acoustic.driverChannels.where((d) => d.enabled).length} driver(s)',
    if (canPhaseAware) 'phase-aware summed',
    if (cfg.includeMagnitudeOnlyComparison) 'mag-only ref',
    if (cfg.includePhasePlaceholder) 'phase placeholder',
  ];

  return SimulationRunResult(
    id: nextId('run'),
    config: cfg,
    curves: curves,
    warnings: warnings,
    readiness: readiness,
    summary: 'Draft simulation: ${curveDescriptions.join(", ")}  '
        '${freqs.length} pts  '
        '${minF.toStringAsFixed(0)}–${maxF.toStringAsFixed(0)} Hz',
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Log-spaced frequency grid from [minF] to [maxF], [ppo] points per octave.
List<double> _logGrid(double minF, double maxF, int ppo) {
  if (minF <= 0 || maxF <= minF || ppo < 1) return [];
  final octaves = math.log(maxF / minF) / math.ln2;
  final count = (octaves * ppo).round() + 1;
  final result = <double>[];
  for (var i = 0; i < count; i++) {
    final f = minF * math.pow(2.0, i / ppo);
    if (f > maxF * 1.001) break;
    result.add(f.clamp(minF, maxF));
  }
  if (result.isEmpty || result.first > minF + 0.01) result.insert(0, minF);
  if (result.last < maxF - 0.01) result.add(maxF);
  return result;
}

/// Gain trim from channel control, or 0 dB.
double _channelGainDb(TuningProjectState tuning, String channelId) {
  try {
    final ctrl = tuning.channelControls
        .firstWhere((c) => c.channelId == channelId);
    return ctrl.hasGainTrim ? ctrl.gainDb : 0.0;
  } catch (_) {
    return 0.0;
  }
}

/// Delay in milliseconds from channel control, or 0.
double _channelDelayMs(TuningProjectState tuning, String channelId) {
  try {
    final ctrl = tuning.channelControls
        .firstWhere((c) => c.channelId == channelId);
    return ctrl.delayMs;
  } catch (_) {
    return 0.0;
  }
}

/// Polarity inversion from crossover channel state.
bool _channelPolarityInverted(TuningProjectState tuning, String channelId) {
  try {
    final xo = tuning.crossoverChannels
        .firstWhere((c) => c.channelId == channelId);
    return xo.polarityInverted;
  } catch (_) {
    return false;
  }
}

// ── Target curve builder ──────────────────────────────────────────────────────

SimulationCurve _buildTargetCurve(
    String id, TargetCurveState targetState, List<double> freqs) {
  final preset = targetState.selectedPreset;
  List<SimulationPoint> points;
  String label;
  const String warning = 'Target curve is a draft placeholder.';

  switch (preset) {
    case TargetCurvePreset.flat:
      label = 'Target: Flat';
      points = freqs.map((f) => SimulationPoint(frequencyHz: f, value: 0.0)).toList();

    case TargetCurvePreset.warm:
      label = 'Target: Warm';
      points = freqs.map((f) {
        double db = 0.0;
        if (f < 200) {
          db = 2.0 * (1.0 - f / 200.0);
        } else if (f > 8000) {
          db = -1.5 * math.log(f / 8000) / math.ln2;
        }
        return SimulationPoint(frequencyHz: f, value: db);
      }).toList();

    case TargetCurvePreset.studio:
      label = 'Target: Studio';
      points = freqs.map((f) {
        double db = 0.0;
        if (f > 10000) db = -1.0 * math.log(f / 10000) / math.ln2;
        return SimulationPoint(frequencyHz: f, value: db);
      }).toList();

    case TargetCurvePreset.nearfield:
      label = 'Target: Nearfield';
      points = freqs.map((f) {
        double db = 0.0;
        if (f >= 1500 && f <= 5000) {
          const center = 2800.0;
          final x = math.log(f / center) / math.ln2;
          db = 1.5 * math.exp(-x * x * 2.0);
        }
        if (f < 80) db -= 3.0 * (1.0 - f / 80.0);
        return SimulationPoint(frequencyHz: f, value: db);
      }).toList();

    case TargetCurvePreset.custom:
      label = 'Target: Custom';
      points = freqs.map((f) => SimulationPoint(frequencyHz: f, value: 0.0)).toList();
  }

  return SimulationCurve(
    id: id,
    label: label,
    type: SimulationCurveType.target,
    status: SimulationCurveStatus.placeholder,
    points: points,
    warning: warning,
  );
}

// ── Imported FRD curve builder ────────────────────────────────────────────────

SimulationCurve _buildImportedFrdCurve(
    String id, DriverChannel driver, List<double> freqs, double gainOffsetDb) {
  final frd = driver.frdData!;
  final srcPts = frd.points;
  final extraWarnings = <String>[];

  if (!frd.hasPhase) {
    extraWarnings.add('FRD has no phase data — magnitude only.');
  }
  if (frd.pointCount < 20) {
    extraWarnings.add(
        'Sparse FRD data (${frd.pointCount} pts) — interpolation may be imprecise.');
  }

  final frdMinF = frd.minFrequencyHz;
  final frdMaxF = frd.maxFrequencyHz;
  bool outOfRange = false;

  final points = freqs.map((f) {
    double db;
    if (f < frdMinF) {
      db = (srcPts.first.magnitudeDb ?? 0.0) + gainOffsetDb;
      outOfRange = true;
    } else if (f > frdMaxF) {
      db = (srcPts.last.magnitudeDb ?? 0.0) + gainOffsetDb;
      outOfRange = true;
    } else {
      db = _interpolateMagnitude(srcPts, f) + gainOffsetDb;
    }
    return SimulationPoint(frequencyHz: f, value: db);
  }).toList();

  if (outOfRange) {
    extraWarnings.add('Simulation range extends beyond FRD range '
        '(${frd.freqRangeLabel}) — clamped at boundaries.');
  }

  return SimulationCurve(
    id: id,
    label: '${driver.name} (${driver.role.short}) [FRD]',
    type: SimulationCurveType.driver,
    status: SimulationCurveStatus.imported,
    channelId: driver.id,
    points: points,
    warning: extraWarnings.isNotEmpty ? extraWarnings.join(' ') : null,
    notes: 'Source: ${frd.sourceFileName}  ${frd.freqRangeLabel}  '
        '${frd.pointCount} pts'
        '${frd.hasPhase ? " mag+phase" : " mag only"}',
  );
}

// ── Placeholder driver curve builder ─────────────────────────────────────────

SimulationCurve _buildDriverCurve(
    String id, DriverChannel driver, List<double> freqs, double gainOffsetDb) {
  final role = driver.role;
  final points = freqs.map((f) {
    final db = _driverPlaceholderDb(role, f) + gainOffsetDb;
    return SimulationPoint(frequencyHz: f, value: db);
  }).toList();

  return SimulationCurve(
    id: id,
    label: '${driver.name} (${role.short}) [placeholder]',
    type: SimulationCurveType.driver,
    status: SimulationCurveStatus.placeholder,
    channelId: driver.id,
    points: points,
    warning: 'Driver response uses placeholder shape until FRD import.',
    notes: 'Role: ${role.label}  Channel: ${driver.id}',
  );
}

/// Rough illustrative placeholder dB per driver role.
double _driverPlaceholderDb(DriverRole role, double f) {
  switch (role) {
    case DriverRole.woofer:
    case DriverRole.coaxWoofer:
      if (f <= 800) return 0.0;
      return -20.0 * math.log(f / 800) / math.log(10);
    case DriverRole.subwoofer:
      if (f <= 200) return 0.0;
      return -24.0 * math.log(f / 200) / math.log(10);
    case DriverRole.tweeter:
    case DriverRole.coaxTweeter:
      if (f >= 2000) return 0.0;
      return -18.0 * math.log(2000 / f) / math.log(10);
    case DriverRole.midrange:
      if (f < 200) return -18.0 * math.log(200 / f) / math.log(10);
      if (f > 3000) return -12.0 * math.log(f / 3000) / math.log(10);
      return 0.0;
    case DriverRole.fullrange:
    case DriverRole.passiveRadiator:
      if (f < 60) return -12.0 * math.log(60 / f) / math.log(10);
      if (f > 12000) return -6.0 * math.log(f / 12000) / math.log(10);
      return 0.0;
    case DriverRole.unknown:
      return 0.0;
  }
}

// ── Phase-aware complex summation ─────────────────────────────────────────────

SimulationCurve _buildPhaseAwareSummedCurve({
  required String id,
  required List<DriverChannel> drivers,
  required TuningProjectState tuning,
  required List<double> freqs,
  required bool useAcousticOffsets,
}) {
  final points = <SimulationPoint>[];

  for (final f in freqs) {
    double sumReal = 0.0;
    double sumImag = 0.0;

    for (final driver in drivers) {
      final frd = driver.frdData!;
      final gainDb = _channelGainDb(tuning, driver.id);
      final delayMs = _channelDelayMs(tuning, driver.id);
      final polarity = _channelPolarityInverted(tuning, driver.id);

      // Magnitude
      double magDb;
      final frdMinF = frd.minFrequencyHz;
      final frdMaxF = frd.maxFrequencyHz;
      if (f < frdMinF) {
        magDb = (frd.points.first.magnitudeDb ?? 0.0) + gainDb;
      } else if (f > frdMaxF) {
        magDb = (frd.points.last.magnitudeDb ?? 0.0) + gainDb;
      } else {
        magDb = _interpolateMagnitude(frd.points, f) + gainDb;
      }
      final magLinear = math.pow(10.0, magDb / 20.0).toDouble();

      // Phase from FRD
      double phaseDeg;
      if (f < frdMinF) {
        phaseDeg = frd.points.first.phaseDeg ?? 0.0;
      } else if (f > frdMaxF) {
        phaseDeg = frd.points.last.phaseDeg ?? 0.0;
      } else {
        phaseDeg = _interpolatePhase(frd.points, f);
      }

      // Polarity inversion = +180°
      if (polarity) phaseDeg += 180.0;

      // Delay phase shift: φ = -360° × f × delay_s
      final delayS = delayMs / 1000.0;
      phaseDeg += -360.0 * f * delayS;

      // Acoustic offset path delay
      if (useAcousticOffsets && driver.acousticOffset != null) {
        final pathDelay = driver.acousticOffset!.pathDelaySeconds;
        phaseDeg += -360.0 * f * pathDelay;
      }

      // Complex conversion
      final phaseRad = phaseDeg * math.pi / 180.0;
      sumReal += magLinear * math.cos(phaseRad);
      sumImag += magLinear * math.sin(phaseRad);
    }

    // Reconstruct magnitude and phase
    final magnitude = math.sqrt(sumReal * sumReal + sumImag * sumImag);
    final magDb = magnitude > 1e-12
        ? 20.0 * math.log(magnitude) / math.ln10
        : -120.0;
    final phaseDeg = math.atan2(sumImag, sumReal) * 180.0 / math.pi;

    points.add(SimulationPoint(
        frequencyHz: f, value: magDb, phaseDeg: phaseDeg));
  }

  return SimulationCurve(
    id: id,
    label: 'Summed phase-aware draft',
    type: SimulationCurveType.summedPhaseAware,
    status: SimulationCurveStatus.phaseAwareDraft,
    points: points,
    warning: 'Phase-aware summation draft — not final acoustic accuracy. '
        'Phase unwrap is simplified in Phase N.',
    notes: '${drivers.length} drivers  polarity+delay applied  '
        '${useAcousticOffsets ? "acoustic offset: on" : "acoustic offset: off"}',
  );
}

// ── Magnitude-only summed curve ───────────────────────────────────────────────

SimulationCurve _buildMagnitudeOnlySummedCurve(
    String id, List<SimulationCurve> driverCurves, List<double> freqs,
    {bool fallback = false}) {
  if (driverCurves.isEmpty || driverCurves.every((c) => c.points.isEmpty)) {
    return SimulationCurve(
      id: id,
      label: 'Summed magnitude-only reference',
      type: SimulationCurveType.summedMagnitudeOnly,
      status: SimulationCurveStatus.missingPhaseFallback,
      points: freqs.map((f) => SimulationPoint(frequencyHz: f, value: 0.0)).toList(),
      warning: 'No driver curves available for summation.',
    );
  }

  final points = <SimulationPoint>[];
  for (var i = 0; i < freqs.length; i++) {
    double powerSum = 0.0;
    for (final curve in driverCurves) {
      if (i < curve.points.length) {
        final db = curve.points[i].value;
        powerSum += math.pow(10.0, db / 10.0);
      }
    }
    final sumDb =
        powerSum > 0 ? 10.0 * math.log(powerSum) / math.ln10 : -60.0;
    points.add(SimulationPoint(frequencyHz: freqs[i], value: sumDb));
  }

  return SimulationCurve(
    id: id,
    label: fallback
        ? 'Summed response (Mag-only draft)'
        : 'Summed magnitude-only reference',
    type: SimulationCurveType.summedMagnitudeOnly,
    status: fallback
        ? SimulationCurveStatus.missingPhaseFallback
        : SimulationCurveStatus.placeholder,
    points: points,
    warning: 'Magnitude-only comparison ignores phase cancellation and reinforcement.',
    notes: 'Power-sum approximation — not phase-accurate.',
  );
}

// ── Interpolation ─────────────────────────────────────────────────────────────

/// Log-frequency linear interpolation of FRD magnitude at [f].
/// Assumes [pts] is sorted ascending by frequencyHz.
double _interpolateMagnitude(List<MeasurementDataPoint> pts, double f) {
  if (pts.isEmpty) return 0.0;
  if (pts.length == 1) return pts.first.magnitudeDb ?? 0.0;
  final bounds = _findBounds(pts, f);
  final lo = bounds.$1;
  final hi = bounds.$2;
  final f0 = pts[lo].frequencyHz;
  final f1 = pts[hi].frequencyHz;
  final m0 = pts[lo].magnitudeDb ?? 0.0;
  final m1 = pts[hi].magnitudeDb ?? 0.0;
  if (f1 <= f0) return m0;
  final t = f0 > 0 && f1 > 0
      ? (math.log(f / f0)) / (math.log(f1 / f0))
      : (f - f0) / (f1 - f0);
  return m0 + (m1 - m0) * t.clamp(0.0, 1.0);
}

/// Log-frequency linear interpolation of FRD phase at [f].
/// Simple continuous interpolation — no phase unwrap in Phase N.
double _interpolatePhase(List<MeasurementDataPoint> pts, double f) {
  if (pts.isEmpty) return 0.0;
  if (pts.length == 1) return pts.first.phaseDeg ?? 0.0;
  final bounds = _findBounds(pts, f);
  final lo = bounds.$1;
  final hi = bounds.$2;
  final f0 = pts[lo].frequencyHz;
  final f1 = pts[hi].frequencyHz;
  final p0 = pts[lo].phaseDeg ?? 0.0;
  final p1 = pts[hi].phaseDeg ?? 0.0;
  if (f1 <= f0) return p0;
  final t = f0 > 0 && f1 > 0
      ? (math.log(f / f0)) / (math.log(f1 / f0))
      : (f - f0) / (f1 - f0);
  return p0 + (p1 - p0) * t.clamp(0.0, 1.0);
}

/// Binary search: returns indices of the two surrounding points for [f].
(int, int) _findBounds(List<MeasurementDataPoint> pts, double f) {
  int lo = 0;
  int hi = pts.length - 1;
  while (lo < hi - 1) {
    final mid = (lo + hi) ~/ 2;
    if (pts[mid].frequencyHz <= f) { lo = mid; } else { hi = mid; }
  }
  return (lo, hi);
}
