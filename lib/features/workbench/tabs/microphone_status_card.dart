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
    // §8 — one language per status. These used to mix an English status
    // ("Explicitly uncalibrated") with a Korean explanation in one card.
    final (name, status, color, detail) = switch (displayState) {
      MicrophoneDisplayState.notSelected => (
          '마이크가 선택되지 않았습니다',
          '선택 필요',
          Colors.white38,
          '측정 정확도를 위해 마이크를 등록하고 선택하세요.',
        ),
      MicrophoneDisplayState.calibrationReady => (
          '${profile!.manufacturer} ${profile.model}',
          '보정 완료',
          kProGreen,
          _rangeLabel(profile),
        ),
      MicrophoneDisplayState.explicitlyUncalibrated => (
          profile == null
              ? '보정 없이 사용'
              : '${profile.manufacturer} ${profile.model}',
          '보정 없이 사용',
          kProAmber,
          '보정 없이 측정 중입니다 — 정확도가 낮아질 수 있습니다.',
        ),
      MicrophoneDisplayState.invalid => (
          '${profile!.manufacturer} ${profile.model}',
          '보정 파일 확인 필요',
          kProRed,
          '선택된 프로필의 보정 데이터를 사용할 수 없습니다.',
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
        // §6 — this card is the start of every measurement, so it reads as a
        // titled section rather than one more status strip among the
        // professional panels.
        Row(children: [
          Icon(Icons.mic_none, size: 17, color: color),
          const SizedBox(width: 10),
          Text('측정 마이크', style: proTitle(size: 13)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color.withValues(alpha: 0.45)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(status, style: TextStyle(color: color, fontSize: 10)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(name, style: proValue(size: 13)),
        if (detail.isNotEmpty) Text(detail, style: proSubtitle(size: 10)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: () => showMicrophoneProfileManagerDialog(context,
                  projectId: project.id),
              icon: const Icon(Icons.settings_outlined, size: 14),
              label: const Text('마이크 설정'),
            ),
            OutlinedButton.icon(
              onPressed: () => showGuidedMeasurementSetupDialog(context,
                  projectId: project.id),
              icon:
                  Icon(Icons.fact_check_outlined, size: 14, color: setupColor),
              label: Text('측정 준비 확인 · $setupLabel'),
            ),
          ],
        ),
      ]),
    );
  }

  (String, Color) _setupStatusLabel() {
    final readiness = project.currentSetupReadiness;
    if (readiness == null) return ('확인 필요', Colors.white38);
    final currentIdentity =
        MeasurementSetupReadinessProjectIdentity.forProject(project);
    if (readiness.isStaleFor(currentIdentity)) return ('설정 변경됨', kProAmber);
    if (readiness.isExpired()) return ('유효 기간 지남', kProAmber);
    if (readiness.isReady) return ('준비 완료', kProGreen);
    if (readiness.warnings.isNotEmpty && readiness.blockers.isEmpty) {
      return ('주의 사항 있음', kProAmber);
    }
    return ('다시 확인 필요', kProRed);
  }

  static String _rangeLabel(MeasurementMicrophoneProfile profile) {
    final curve = profile.calibrationCurve;
    if (curve == null) return '';
    return '${curve.angle.label} · '
        '${curve.validMinFrequencyHz.toStringAsFixed(0)}–'
        '${curve.validMaxFrequencyHz.toStringAsFixed(0)} Hz';
  }
}
