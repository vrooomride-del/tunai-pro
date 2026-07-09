// ── TUNAI PRO Phase M — Acoustic Simulation Engine (Draft) ───────────────────
// Generates draft frequency response preview curves from project state.
// Uses imported FRD data when available; falls back to placeholder shapes.
// Not final acoustic simulation. No hardware write. No DSP addresses.
// Phase-aware summation is NOT implemented. Placeholder summation only.
// AI suggests. Expert verifies. AOS protects. DSP executes.

import 'dart:math' as math;
import 'pro_project.dart';
import 'pro_acoustic_data.dart';
import 'pro_simulation_data.dart';
import 'pro_tuning_data.dart';

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
    final target = _buildTargetCurve(
        nextId('curve'), acoustic.targetCurve, freqs);
    curves.add(target);
  }

  // 2. Per-driver curves — use imported FRD when available
  final driverCurves = <SimulationCurve>[];
  bool hasImportedFrd = false;
  bool hasPlaceholderDriver = false;
  if (cfg.includeDrivers) {
    for (final driver in acoustic.driverChannels) {
      final gainOffset = _channelGainDb(tuning, driver.id);
      if (driver.hasParsedFrd && driver.frdData != null) {
        hasImportedFrd = true;
        driverCurves.add(_buildImportedFrdCurve(
            nextId('curve'), driver, freqs, gainOffset));
      } else {
        hasPlaceholderDriver = true;
        driverCurves.add(_buildDriverCurve(
            nextId('curve'), driver, freqs, gainOffset));
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

  // 3. Summed response
  if (cfg.includeSummed) {
    final summed = _buildSummedCurve(nextId('curve'), driverCurves, freqs);
    curves.add(summed);
    warnings.add(
        'Summed response is a visual draft only. '
        'Full acoustic phase-aware summation is not implemented.');
  }

  // 4. Phase placeholder
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
          'Phase-aware summation not implemented.',
    ));
    warnings.add('Phase data is a flat placeholder — not acoustically valid.');
  }

  // Standard warnings
  if (!hasImportedFrd) {
    warnings.add(
        'Draft simulation. Placeholder response data — import FRD files to use measured data.');
  } else {
    warnings.add('Simulation uses imported FRD magnitude data. '
        'Summed response is magnitude-only draft — full phase-aware summation not implemented.');
  }
  warnings.add(
      'Simulation is draft-only and does not replace measured verification.');

  // ── Readiness ─────────────────────────────────────────────────────────────

  final readiness = curves.any(
              (c) => c.status == SimulationCurveStatus.imported)
      ? SimulationReadiness.estimated   // imported FRD = better than placeholder
      : curves.any(
              (c) => c.status == SimulationCurveStatus.calculatedDraft)
          ? SimulationReadiness.calculatedDraft
          : curves.any((c) =>
                  c.status == SimulationCurveStatus.estimated)
              ? SimulationReadiness.estimated
              : curves.isNotEmpty
                  ? SimulationReadiness.placeholderOnly
                  : SimulationReadiness.noData;

  final curveDescriptions = [
    if (cfg.includeTarget) 'target',
    if (cfg.includeDrivers)
      '${acoustic.driverChannels.length} driver(s)',
    if (cfg.includeSummed) 'summed',
    if (cfg.includePhasePlaceholder) 'phase placeholder',
  ];

  return SimulationRunResult(
    id: nextId('run'),
    config: cfg,
    curves: curves,
    warnings: warnings,
    readiness: readiness,
    summary: 'Draft simulation: ${curveDescriptions.join(', ')}  '
        '${freqs.length} frequency points  '
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
  // Always include exact endpoints
  if (result.isEmpty || result.first > minF + 0.01) result.insert(0, minF);
  if (result.last < maxF - 0.01) result.add(maxF);
  return result;
}

/// Simple gain trim from channel control, or 0 dB.
double _channelGainDb(TuningProjectState tuning, String channelId) {
  try {
    final ctrl = tuning.channelControls
        .firstWhere((c) => c.channelId == channelId);
    return ctrl.hasGainTrim ? ctrl.gainDb : 0.0;
  } catch (_) {
    return 0.0;
  }
}

// ── Target curve builder ──────────────────────────────────────────────────────

SimulationCurve _buildTargetCurve(
    String id, TargetCurveState targetState, List<double> freqs) {
  final preset = targetState.selectedPreset;

  List<SimulationPoint> points;
  String label;
  String warning;

  switch (preset) {
    case TargetCurvePreset.flat:
      label = 'Target: Flat';
      warning = 'Target curve is a draft placeholder.';
      points = freqs
          .map((f) => SimulationPoint(frequencyHz: f, value: 0.0))
          .toList();

    case TargetCurvePreset.warm:
      label = 'Target: Warm';
      warning = 'Target curve is a draft placeholder.';
      // Gentle bass lift below 200 Hz, mild treble rolloff above 8 kHz
      points = freqs.map((f) {
        double db = 0.0;
        if (f < 200) {
          db = 2.0 * (1.0 - f / 200.0); // up to +2 dB at 20 Hz
        } else if (f > 8000) {
          db = -1.5 * math.log(f / 8000) / math.ln2; // gentle rolloff
        }
        return SimulationPoint(frequencyHz: f, value: db);
      }).toList();

    case TargetCurvePreset.studio:
      label = 'Target: Studio';
      warning = 'Target curve is a draft placeholder.';
      // Near-flat with slight HF rolloff above 10 kHz
      points = freqs.map((f) {
        double db = 0.0;
        if (f > 10000) {
          db = -1.0 * math.log(f / 10000) / math.ln2;
        }
        return SimulationPoint(frequencyHz: f, value: db);
      }).toList();

    case TargetCurvePreset.nearfield:
      label = 'Target: Nearfield';
      warning = 'Target curve is a draft placeholder.';
      // Elevated presence region around 2–4 kHz
      points = freqs.map((f) {
        double db = 0.0;
        if (f >= 1500 && f <= 5000) {
          const center = 2800.0;
          final x = (math.log(f / center) / math.ln2);
          db = 1.5 * math.exp(-x * x * 2.0);
        }
        if (f < 80) {
          db -= 3.0 * (1.0 - f / 80.0);
        }
        return SimulationPoint(frequencyHz: f, value: db);
      }).toList();

    case TargetCurvePreset.custom:
      label = 'Target: Custom';
      warning =
          'Custom target — using 0 dB placeholder. Import or define target curve.';
      points = freqs
          .map((f) => SimulationPoint(frequencyHz: f, value: 0.0))
          .toList();
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

// ── Driver curve builder ──────────────────────────────────────────────────────

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
    warning: 'Driver response uses placeholder data until FRD import is implemented.',
    notes: 'Role: ${role.label}  Channel: ${driver.id}',
  );
}

/// Rough placeholder dB shape per driver role.
/// All values are illustrative — not acoustically accurate.
double _driverPlaceholderDb(DriverRole role, double f) {
  switch (role) {
    case DriverRole.woofer:
    case DriverRole.coaxWoofer:
      // Broad LPF shape — flat below 800 Hz, rolls off above
      if (f <= 800) return 0.0;
      return -20.0 * math.log(f / 800) / math.log(10);

    case DriverRole.subwoofer:
      // Very low pass — flat below 200 Hz
      if (f <= 200) return 0.0;
      return -24.0 * math.log(f / 200) / math.log(10);

    case DriverRole.tweeter:
    case DriverRole.coaxTweeter:
      // HPF shape — flat above 2000 Hz, rolls off below
      if (f >= 2000) return 0.0;
      return -18.0 * math.log(2000 / f) / math.log(10);

    case DriverRole.midrange:
      // Bandpass-ish — peaks 500–3000 Hz
      if (f < 200) return -18.0 * math.log(200 / f) / math.log(10);
      if (f > 3000) return -12.0 * math.log(f / 3000) / math.log(10);
      return 0.0;

    case DriverRole.fullrange:
    case DriverRole.passiveRadiator:
      // Broad response with gentle roll-offs at extremes
      if (f < 60) return -12.0 * math.log(60 / f) / math.log(10);
      if (f > 12000) return -6.0 * math.log(f / 12000) / math.log(10);
      return 0.0;

    case DriverRole.unknown:
      return 0.0;
  }
}

// ── Imported FRD curve builder ────────────────────────────────────────────────

SimulationCurve _buildImportedFrdCurve(
    String id, DriverChannel driver, List<double> freqs, double gainOffsetDb) {
  final frd = driver.frdData!;
  final srcPts = frd.points;

  final warnings = <String>[];
  if (!frd.hasPhase) {
    warnings.add('FRD has no phase data — magnitude only.');
  }
  if (frd.pointCount < 20) {
    warnings.add('Sparse FRD data (${frd.pointCount} points) — interpolation may be imprecise.');
  }

  // Clamp note for out-of-range points
  final frdMinF = frd.minFrequencyHz;
  final frdMaxF = frd.maxFrequencyHz;

  final points = freqs.map((f) {
    double db;
    if (f < frdMinF) {
      // Clamp to first point value
      db = (srcPts.first.magnitudeDb ?? 0.0) + gainOffsetDb;
    } else if (f > frdMaxF) {
      // Clamp to last point value
      db = (srcPts.last.magnitudeDb ?? 0.0) + gainOffsetDb;
    } else {
      db = _interpolateMagnitude(srcPts, f) + gainOffsetDb;
    }
    return SimulationPoint(frequencyHz: f, value: db);
  }).toList();

  final hasOutOfRange = freqs.first < frdMinF || freqs.last > frdMaxF;
  if (hasOutOfRange) {
    warnings.add('Simulation range extends beyond FRD range '
        '(${frd.freqRangeLabel}) — clamped at boundaries.');
  }

  return SimulationCurve(
    id: id,
    label: '${driver.name} (${driver.role.short}) [FRD]',
    type: SimulationCurveType.driver,
    status: SimulationCurveStatus.imported,
    channelId: driver.id,
    points: points,
    warning: warnings.isNotEmpty ? warnings.join(' ') : null,
    notes: 'Source: ${frd.sourceFileName}  ${frd.freqRangeLabel}  '
        '${frd.pointCount} pts'
        '${frd.hasPhase ? " mag+phase" : " mag only"}',
  );
}

/// Linear interpolation of FRD magnitude at frequency [f].
/// Assumes [pts] is sorted ascending by frequencyHz.
double _interpolateMagnitude(List<MeasurementDataPoint> pts, double f) {
  if (pts.isEmpty) return 0.0;
  if (pts.length == 1) return pts.first.magnitudeDb ?? 0.0;

  // Find surrounding points
  int lo = 0;
  int hi = pts.length - 1;
  while (lo < hi - 1) {
    final mid = (lo + hi) ~/ 2;
    if (pts[mid].frequencyHz <= f) {
      lo = mid;
    } else {
      hi = mid;
    }
  }

  final f0 = pts[lo].frequencyHz;
  final f1 = pts[hi].frequencyHz;
  final m0 = pts[lo].magnitudeDb ?? 0.0;
  final m1 = pts[hi].magnitudeDb ?? 0.0;

  if (f1 <= f0) return m0;

  // Linear interpolation on log-frequency axis
  final t = (math.log(f / f0)) / (math.log(f1 / f0));
  return m0 + (m1 - m0) * t.clamp(0.0, 1.0);
}

// ── Summed curve builder ──────────────────────────────────────────────────────

SimulationCurve _buildSummedCurve(
    String id, List<SimulationCurve> driverCurves, List<double> freqs) {
  if (driverCurves.isEmpty || driverCurves.every((c) => c.points.isEmpty)) {
    return SimulationCurve(
      id: id,
      label: 'Summed Response (Placeholder)',
      type: SimulationCurveType.summed,
      status: SimulationCurveStatus.placeholder,
      points: freqs
          .map((f) => SimulationPoint(frequencyHz: f, value: 0.0))
          .toList(),
      warning:
          'Summed response is a visual draft only. '
          'Full acoustic phase-aware summation is not implemented.',
    );
  }

  // Power-sum approximation: 10 * log10(sum of linear power per curve)
  // This is a rough conservative placeholder — NOT phase-accurate.
  final points = <SimulationPoint>[];
  for (var i = 0; i < freqs.length; i++) {
    double powerSum = 0.0;
    for (final curve in driverCurves) {
      if (i < curve.points.length) {
        final db = curve.points[i].value;
        powerSum += math.pow(10.0, db / 10.0);
      }
    }
    final sumDb = powerSum > 0
        ? 10.0 * math.log(powerSum) / math.ln10
        : -60.0;
    points.add(SimulationPoint(frequencyHz: freqs[i], value: sumDb));
  }

  return SimulationCurve(
    id: id,
    label: 'Summed Response (Draft)',
    type: SimulationCurveType.summed,
    status: SimulationCurveStatus.placeholder,
    points: points,
    warning:
        'Summed response is a visual draft only. '
        'Full acoustic phase-aware summation is not implemented.',
    notes: 'Power-sum approximation — not phase-accurate.',
  );
}
