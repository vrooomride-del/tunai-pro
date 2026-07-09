// ── TUNAI PRO Phase F — Verification Engine ───────────────────────────────────
// Transparent draft checks. No DSP write. No register access.
// AI suggests. Expert verifies. AOS protects. DSP executes.

import 'pro_acoustic_data.dart';
import 'pro_tuning_data.dart';
import 'pro_protection_data.dart';

ProtectionProjectState runProtectionVerification({
  required MeasurementProjectState acousticState,
  required TuningProjectState tuningState,
  required ProtectionProjectState protectionState,
}) {
  final issues = <VerificationIssue>[];
  int issueSeq = 0;

  String nextId() => 'issue_${issueSeq++}';

  // Helper: only run if rule is enabled
  ProtectionRule? findRule(ProtectionRuleType type) {
    try {
      return protectionState.rules.firstWhere(
          (r) => r.type == type && r.enabled);
    } catch (_) {
      return null;
    }
  }

  // 1. Measurement completeness
  final mcRule = findRule(ProtectionRuleType.measurementCompleteness);
  if (mcRule != null && acousticState.hasMissingMeasurements) {
    final missing = acousticState.totalDrivers - acousticState.importedFrdCount;
    issues.add(VerificationIssue(
      id: nextId(),
      ruleId: mcRule.id,
      severity: mcRule.severity,
      message: 'FRD data missing on $missing of ${acousticState.totalDrivers} channel(s). '
          'Optimization accuracy is reduced.',
      value: missing.toDouble(),
      threshold: 0,
    ));
  }

  // 2. Max PEQ boost
  final boostRule = findRule(ProtectionRuleType.maxBoost);
  if (boostRule != null) {
    for (final ch in tuningState.peqChannels) {
      for (final band in ch.bands) {
        if (!band.enabled || !band.type.hasGain) continue;
        if (band.gainDb > 10.0) {
          issues.add(VerificationIssue(
            id: nextId(),
            ruleId: boostRule.id,
            severity: ProtectionSeverity.critical,
            message: 'PEQ band boost of +${band.gainDb.toStringAsFixed(1)} dB exceeds critical threshold.',
            channelId: ch.channelId,
            value: band.gainDb,
            threshold: 10.0,
          ));
        } else if (band.gainDb > boostRule.threshold) {
          issues.add(VerificationIssue(
            id: nextId(),
            ruleId: boostRule.id,
            severity: boostRule.severity,
            message: 'PEQ band boost of +${band.gainDb.toStringAsFixed(1)} dB exceeds +${boostRule.threshold.toStringAsFixed(0)} dB warning threshold.',
            channelId: ch.channelId,
            value: band.gainDb,
            threshold: boostRule.threshold,
          ));
        }
      }
    }
  }

  // 3. Max PEQ cut
  final cutRule = findRule(ProtectionRuleType.maxCut);
  if (cutRule != null) {
    for (final ch in tuningState.peqChannels) {
      for (final band in ch.bands) {
        if (!band.enabled || !band.type.hasGain) continue;
        if (band.gainDb < cutRule.threshold) {
          issues.add(VerificationIssue(
            id: nextId(),
            ruleId: cutRule.id,
            severity: cutRule.severity,
            message: 'PEQ band cut of ${band.gainDb.toStringAsFixed(1)} dB is below ${cutRule.threshold.toStringAsFixed(0)} dB.',
            channelId: ch.channelId,
            value: band.gainDb,
            threshold: cutRule.threshold,
          ));
        }
      }
    }
  }

  // 4. Min high-pass (woofer channels without HPF)
  final hpfRule = findRule(ProtectionRuleType.minHighPass);
  if (hpfRule != null) {
    for (final driver in acousticState.driverChannels) {
      if (driver.role != DriverRole.coaxWoofer &&
          driver.role != DriverRole.woofer &&
          driver.role != DriverRole.subwoofer) { continue; }
      final xoCh = tuningState.getOrCreateCrossoverChannel(driver.id);
      if (!xoCh.hasHighPass) {
        issues.add(VerificationIssue(
          id: nextId(),
          ruleId: hpfRule.id,
          severity: hpfRule.severity,
          message: 'Woofer channel "${driver.name}" has no high-pass filter configured.',
          channelId: driver.id,
        ));
      }
    }
  }

  // 5. Max output gain
  final gainRule = findRule(ProtectionRuleType.maxOutputGain);
  if (gainRule != null) {
    for (final ctrl in tuningState.channelControls) {
      if (ctrl.gainDb > 10.0) {
        issues.add(VerificationIssue(
          id: nextId(),
          ruleId: gainRule.id,
          severity: ProtectionSeverity.critical,
          message: 'Output gain of +${ctrl.gainDb.toStringAsFixed(1)} dB exceeds critical threshold.',
          channelId: ctrl.channelId,
          value: ctrl.gainDb,
          threshold: 10.0,
        ));
      } else if (ctrl.gainDb > gainRule.threshold) {
        issues.add(VerificationIssue(
          id: nextId(),
          ruleId: gainRule.id,
          severity: gainRule.severity,
          message: 'Output gain of +${ctrl.gainDb.toStringAsFixed(1)} dB reduces headroom.',
          channelId: ctrl.channelId,
          value: ctrl.gainDb,
          threshold: gainRule.threshold,
        ));
      }
    }
  }

  // 6. Max delay
  final delayRule = findRule(ProtectionRuleType.maxDelay);
  if (delayRule != null) {
    for (final ctrl in tuningState.channelControls) {
      if (ctrl.delayMs > delayRule.threshold) {
        issues.add(VerificationIssue(
          id: nextId(),
          ruleId: delayRule.id,
          severity: delayRule.severity,
          message: 'Delay of ${ctrl.delayMs.toStringAsFixed(2)} ms exceeds ${delayRule.threshold.toStringAsFixed(0)} ms.',
          channelId: ctrl.channelId,
          value: ctrl.delayMs,
          threshold: delayRule.threshold,
        ));
      }
    }
  }

  // 7. Headroom reserve (max PEQ boost + max output gain combined)
  final headroomRule = findRule(ProtectionRuleType.headroomReserve);
  if (headroomRule != null) {
    double maxPeqBoost = 0.0;
    for (final ch in tuningState.peqChannels) {
      for (final band in ch.bands) {
        if (band.enabled && band.type.hasGain && band.gainDb > maxPeqBoost) {
          maxPeqBoost = band.gainDb;
        }
      }
    }
    final maxGain = tuningState.gainMaxDb;
    final combined = maxPeqBoost + maxGain;
    if (combined > headroomRule.threshold) {
      issues.add(VerificationIssue(
        id: nextId(),
        ruleId: headroomRule.id,
        severity: headroomRule.severity,
        message: 'Combined PEQ boost (${maxPeqBoost.toStringAsFixed(1)} dB) + '
            'output gain (${maxGain.toStringAsFixed(1)} dB) = '
            '${combined.toStringAsFixed(1)} dB. Headroom reserve may be limited.',
        value: combined,
        threshold: headroomRule.threshold,
      ));
    }
  }

  // 8. Polarity consistency
  final polarityRule = findRule(ProtectionRuleType.polarityConsistency);
  if (polarityRule != null && acousticState.totalDrivers > 0) {
    final inverted = tuningState.polarityInvertedCount;
    final ratio = inverted / acousticState.totalDrivers;
    if (ratio > polarityRule.threshold) {
      issues.add(VerificationIssue(
        id: nextId(),
        ruleId: polarityRule.id,
        severity: polarityRule.severity,
        message: '$inverted of ${acousticState.totalDrivers} channels have inverted polarity. '
            'Verify this is intentional.',
        value: ratio,
        threshold: polarityRule.threshold,
      ));
    }
  }

  // Determine verification status
  final hasCritical = issues.any((i) => i.severity == ProtectionSeverity.critical);
  final hasWarning = issues.any((i) => i.severity == ProtectionSeverity.warning);

  final status = hasCritical
      ? VerificationStatus.failed
      : hasWarning
          ? VerificationStatus.passedWithWarnings
          : VerificationStatus.passed;

  final exportLocked = hasCritical;

  return protectionState.copyWith(
    issues: issues,
    verificationStatus: status,
    exportLocked: exportLocked,
    revision: protectionState.revision + 1,
  );
}
