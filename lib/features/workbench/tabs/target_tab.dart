// ── Target Tab — Phase C ──────────────────────────────────────────────────────
// Target curve preset selection and placeholder graph area.
// No real target matching or optimization yet — Phase D / E item.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_acoustic_data.dart';
import '../../../shared/pro_widgets.dart';

class TargetTab extends ConsumerWidget {
  final String projectId;
  const TargetTab({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acoustic = ref.watch(proProjectStoreProvider)
        .projects.where((p) => p.id == projectId).firstOrNull
        ?.acousticState ?? MeasurementProjectState.createDefault();
    final target = acoustic.targetCurve;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.track_changes_outlined, color: kProAccent.withValues(alpha: 0.6), size: 18),
          const SizedBox(width: 10),
          Text('Target', style: proTitle(size: 16)),
        ]),
        const SizedBox(height: 4),
        Text('Select the target frequency response curve for optimization.',
            style: proSubtitle()),
        const SizedBox(height: 20),

        // Current selection summary
        _CurrentTargetCard(target: target),
        const SizedBox(height: 16),

        // Preset selection
        Text('TARGET PRESETS', style: proLabel(size: 9, spacing: 2)),
        const SizedBox(height: 8),
        ...TargetCurvePreset.values.map((preset) => _PresetCard(
          preset: preset,
          selected: target.selectedPreset == preset,
          onSelect: () async {
            final project = ref.read(proProjectStoreProvider)
                .projects.where((p) => p.id == projectId).firstOrNull;
            if (project == null) return;
            await ref.read(proProjectStoreProvider.notifier).updateAcousticState(
              projectId,
              project.acousticState.copyWith(
                targetCurve: target.copyWith(selectedPreset: preset),
              ),
            );
          },
        )),

        const SizedBox(height: 20),

        // Graph placeholder
        Text('FREQUENCY RESPONSE PREVIEW', style: proLabel(size: 9, spacing: 2)),
        const SizedBox(height: 8),
        _GraphPlaceholder(preset: target.selectedPreset),

        const SizedBox(height: 20),

        // Phase D notice
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: kProSurface,
            border: Border.all(color: kProBorder),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(children: [
            const Icon(Icons.hourglass_empty_outlined, color: Colors.white24, size: 13),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Target curve matching and PEQ optimization will be available in Phase D. '
                'Import FRD data and select a target preset to prepare for optimization.',
                style: proSubtitle(size: 11),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _CurrentTargetCard extends StatelessWidget {
  final TargetCurveState target;
  const _CurrentTargetCard({required this.target});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('CURRENT TARGET', style: proLabel(size: 9, spacing: 1.8)),
          const SizedBox(height: 6),
          Text(target.selectedPreset.label, style: proTitle(size: 14, color: kProAccent)),
          const SizedBox(height: 4),
          Text(target.selectedPreset.description, style: proSubtitle(size: 10)),
        ]),
      ),
      const ProStatusPill(label: 'SELECTED', color: kProAccent),
    ]),
  );
}

class _PresetCard extends StatelessWidget {
  final TargetCurvePreset preset;
  final bool selected;
  final VoidCallback onSelect;
  const _PresetCard({required this.preset, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onSelect,
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: selected ? kProAccent.withValues(alpha: 0.06) : kProSurface,
        border: Border.all(color: selected ? kProAccent.withValues(alpha: 0.5) : kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(preset.label,
                style: proTitle(size: 12, color: selected ? kProAccent : Colors.white70)),
            const SizedBox(height: 3),
            Text(preset.description, style: proSubtitle(size: 10)),
          ]),
        ),
        if (selected)
          const Icon(Icons.check_circle_outline, color: kProAccent, size: 14)
        else
          const Icon(Icons.radio_button_unchecked, color: Colors.white12, size: 14),
      ]),
    ),
  );
}

class _GraphPlaceholder extends StatelessWidget {
  final TargetCurvePreset preset;
  const _GraphPlaceholder({required this.preset});

  @override
  Widget build(BuildContext context) => Container(
    height: 160,
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Stack(children: [
      // Grid lines
      CustomPaint(size: const Size.fromHeight(160), painter: _GridPainter()),
      // Label overlay
      Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.show_chart, color: Colors.white12, size: 24),
          const SizedBox(height: 8),
          Text('${preset.label} target curve', style: proLabel(size: 10, color: Colors.white24)),
          Text('Graph renders in Phase D', style: proSubtitle(size: 9)),
        ]),
      ),
      // Freq axis labels
      Positioned(
        bottom: 8,
        left: 0,
        right: 0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: ['20 Hz', '100', '1k', '10k', '20k']
              .map((l) => Text(l, style: proSubtitle(size: 8)))
              .toList(),
        ),
      ),
    ]),
  );
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1E2832)
      ..strokeWidth = 0.5;
    const cols = 10;
    const rows = 6;
    for (int i = 1; i < cols; i++) {
      final x = size.width * i / cols;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (int i = 1; i < rows; i++) {
      final y = size.height * i / rows;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
