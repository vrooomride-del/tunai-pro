// ── TUNAI PRO Phase 3-C — Measure tab Microphone status card ───────────────
//
// Shown identically above BOTH Factory (LiveMeasurementSection) and Room
// (RoomMeasurementSection) content, since both read the exact same
// ProProject.selectedMicrophoneProfile at capture time (see
// live_measurement_controller.dart / room_measurement_controller.dart
// capture()). This card never blocks capture — it only ever informs.

import 'package:flutter/material.dart';

import '../../../core/calibration/calibration_types.dart';
import '../../../core/calibration/microphone_profile_edit_rules.dart';
import '../../../core/measurement/measurement_setup_readiness_project_identity.dart';
import '../../../core/pro_project.dart';
import '../../../shared/pro_widgets.dart';
import '../../mic/guided_measurement_setup_dialog.dart';
import '../../mic/microphone_profile_manager_dialog.dart';

class MicrophoneStatusCard extends StatelessWidget {
  final ProProject project;
  const MicrophoneStatusCard({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    final profile = project.selectedMicrophoneProfile;
    final displayState = deriveMicrophoneDisplayState(profile);
    final (label, color, detail) = switch (displayState) {
      MicrophoneDisplayState.notSelected => (
          'Measurement microphone not selected',
          Colors.white38,
          '측정 정확도를 위해 마이크를 등록하고 선택하세요.',
        ),
      MicrophoneDisplayState.calibrationReady => (
          'Calibrated — ${profile!.manufacturer} ${profile.model}',
          kProGreen,
          _rangeLabel(profile),
        ),
      MicrophoneDisplayState.explicitlyUncalibrated => (
          'Explicitly uncalibrated',
          kProAmber,
          '보정 없이 측정 중입니다 — 정확도가 낮아질 수 있습니다.',
        ),
      MicrophoneDisplayState.invalid => (
          'Calibration invalid',
          kProRed,
          '선택된 프로필의 보정 데이터가 유효하지 않습니다.',
        ),
    };

    final (setupLabel, setupColor) = _setupStatusLabel();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.mic_none, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: proValue(size: 12, color: color)),
                Text(detail, style: proSubtitle(size: 10)),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.fact_check_outlined, size: 14, color: setupColor),
              const SizedBox(width: 6),
              Text('Setup Check: $setupLabel',
                  style: proSubtitle(size: 11, color: setupColor)),
            ]),
            OutlinedButton(
              onPressed: () => showMicrophoneProfileManagerDialog(context,
                  projectId: project.id),
              child: const Text('Manage Microphone'),
            ),
            OutlinedButton(
              onPressed: () => showGuidedMeasurementSetupDialog(context,
                  projectId: project.id),
              child: const Text('Check Measurement Setup'),
            ),
          ],
        ),
      ]),
    );
  }

  (String, Color) _setupStatusLabel() {
    final readiness = project.currentSetupReadiness;
    if (readiness == null) return ('Not checked', Colors.white38);
    final currentIdentity =
        MeasurementSetupReadinessProjectIdentity.forProject(project);
    if (readiness.isStaleFor(currentIdentity)) return ('Stale', kProAmber);
    if (readiness.isExpired()) return ('Expired', kProAmber);
    if (readiness.isReady) return ('Ready', kProGreen);
    if (readiness.warnings.isNotEmpty && readiness.blockers.isEmpty) {
      return ('Warning', kProAmber);
    }
    return ('Blocked', kProRed);
  }

  static String _rangeLabel(MeasurementMicrophoneProfile profile) {
    final curve = profile.calibrationCurve;
    if (curve == null) return '';
    return '${curve.angle.label} · '
        '${curve.validMinFrequencyHz.toStringAsFixed(0)}–'
        '${curve.validMaxFrequencyHz.toStringAsFixed(0)} Hz';
  }
}
