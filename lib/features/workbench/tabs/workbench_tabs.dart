import 'package:flutter/material.dart';
import '../../../shared/pro_widgets.dart';

class MeasureTab extends StatelessWidget {
  const MeasureTab({super.key});
  @override
  Widget build(BuildContext context) => const WorkbenchPlaceholder(
    title: 'Measurement Workspace',
    subtitle: 'Capture frequency response, phase, impulse response, and stereo balance.',
    icon: Icons.mic_none_outlined,
    stats: [
      ProQuickStat('FR RANGE', '20 Hz – 20 kHz'),
      ProQuickStat('RESOLUTION', '1/24 oct'),
      ProQuickStat('CHANNELS', 'L / R / Sum'),
      ProQuickStat('SMOOTHING', '1/6 oct'),
    ],
  );
}

class AnalyzeTab extends StatelessWidget {
  const AnalyzeTab({super.key});
  @override
  Widget build(BuildContext context) => const WorkbenchPlaceholder(
    title: 'Acoustic Analysis',
    subtitle: 'Review detected acoustic issues before tuning.',
    icon: Icons.bar_chart_outlined,
    stats: [
      ProQuickStat('PEAKS', '—'),
      ProQuickStat('DIPS', '—'),
      ProQuickStat('RESONANCES', '—'),
      ProQuickStat('SCORE', '—'),
    ],
  );
}

class CrossoverTab extends StatelessWidget {
  const CrossoverTab({super.key});
  @override
  Widget build(BuildContext context) => const WorkbenchPlaceholder(
    title: 'Crossover Designer',
    subtitle: 'Configure crossover frequency, slope, polarity, and routing.',
    icon: Icons.device_hub_outlined,
    stats: [
      ProQuickStat('HP FREQ', '—'),
      ProQuickStat('LP FREQ', '—'),
      ProQuickStat('SLOPE', '—'),
      ProQuickStat('POLARITY', '—'),
    ],
  );
}

class PeqTab extends StatelessWidget {
  const PeqTab({super.key});
  @override
  Widget build(BuildContext context) => const WorkbenchPlaceholder(
    title: 'Parametric EQ',
    subtitle: 'Review and edit correction filters.',
    icon: Icons.tune_outlined,
    stats: [
      ProQuickStat('BANDS', '0 / 8'),
      ProQuickStat('MAX GAIN', '—'),
      ProQuickStat('ALGORITHM', 'Biquad IIR'),
      ProQuickStat('FORMAT', 'Direct Form II'),
    ],
  );
}

class DelayPhaseTab extends StatelessWidget {
  const DelayPhaseTab({super.key});
  @override
  Widget build(BuildContext context) => const WorkbenchPlaceholder(
    title: 'Time Alignment',
    subtitle: 'Adjust delay and phase for driver integration and imaging.',
    icon: Icons.access_time_outlined,
    stats: [
      ProQuickStat('L DELAY', '0.00 ms'),
      ProQuickStat('R DELAY', '0.00 ms'),
      ProQuickStat('PHASE', '0°'),
      ProQuickStat('RESOLUTION', '0.02 ms'),
    ],
  );
}

class LimiterTab extends StatelessWidget {
  const LimiterTab({super.key});
  @override
  Widget build(BuildContext context) => const WorkbenchPlaceholder(
    title: 'Limiter',
    subtitle: 'Set safe output boundaries for the speaker system.',
    icon: Icons.shield_outlined,
    stats: [
      ProQuickStat('THRESHOLD', '—'),
      ProQuickStat('ATTACK', '—'),
      ProQuickStat('RELEASE', '—'),
      ProQuickStat('MODE', 'RMS / Peak'),
    ],
  );
}

class ProtectionTab extends StatelessWidget {
  const ProtectionTab({super.key});
  @override
  Widget build(BuildContext context) => const WorkbenchPlaceholder(
    title: 'Protection Validation',
    subtitle: 'Verify the profile against speaker, amplifier, and thermal limits.',
    icon: Icons.verified_user_outlined,
    stats: [
      ProQuickStat('SPEAKER', 'Not checked'),
      ProQuickStat('AMPLIFIER', 'Not checked'),
      ProQuickStat('THERMAL', 'Not checked'),
      ProQuickStat('AOS STATUS', 'Inactive'),
    ],
  );
}

class CompareTab extends StatelessWidget {
  const CompareTab({super.key});
  @override
  Widget build(BuildContext context) => const WorkbenchPlaceholder(
    title: 'Compare Profiles',
    subtitle: 'Compare original, generated, and manually edited profiles.',
    icon: Icons.compare_arrows_outlined,
    stats: [
      ProQuickStat('PROFILE A', 'Original'),
      ProQuickStat('PROFILE B', 'Generated'),
      ProQuickStat('DELTA RMS', '—'),
      ProQuickStat('DELTA PEAK', '—'),
    ],
  );
}

class DeployTab extends StatelessWidget {
  const DeployTab({super.key});
  @override
  Widget build(BuildContext context) => const WorkbenchPlaceholder(
    title: 'Deploy DSP Profile',
    subtitle: 'Write verified profiles to connected hardware.',
    icon: Icons.upload_outlined,
    stats: [
      ProQuickStat('TARGET', 'Not selected'),
      ProQuickStat('STATUS', 'Not verified'),
      ProQuickStat('CHECKSUM', '—'),
      ProQuickStat('LAST DEPLOY', 'Never'),
    ],
  );
}

class ReportTab extends StatelessWidget {
  const ReportTab({super.key});
  @override
  Widget build(BuildContext context) => const WorkbenchPlaceholder(
    title: 'Tuning Report',
    subtitle: 'Export measurements, tuning decisions, and validation results.',
    icon: Icons.summarize_outlined,
    stats: [
      ProQuickStat('FORMAT', 'PDF / JSON'),
      ProQuickStat('PAGES', '—'),
      ProQuickStat('GENERATED', 'Never'),
      ProQuickStat('SIGNED BY', '—'),
    ],
  );
}
