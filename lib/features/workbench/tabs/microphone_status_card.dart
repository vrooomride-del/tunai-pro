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
import '../../../core/pro_project.dart';
import '../../../shared/pro_widgets.dart';
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

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
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
        OutlinedButton(
          onPressed: () => showMicrophoneProfileManagerDialog(context,
              projectId: project.id),
          child: const Text('Manage Microphone'),
        ),
      ]),
    );
  }

  static String _rangeLabel(MeasurementMicrophoneProfile profile) {
    final curve = profile.calibrationCurve;
    if (curve == null) return '';
    return '${curve.angle.label} · '
        '${curve.validMinFrequencyHz.toStringAsFixed(0)}–'
        '${curve.validMaxFrequencyHz.toStringAsFixed(0)} Hz';
  }
}
