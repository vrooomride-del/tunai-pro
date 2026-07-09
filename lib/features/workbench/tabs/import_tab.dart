// ── Import Tab — Phase C ──────────────────────────────────────────────────────
// REW / VituixCAD style acoustic file management.
// Supports .frd, .zma, .txt, .csv references.
// No real file picker yet — mock import builds the data model.
// Actual file picker integration is a future phase item.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/pro_project.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_acoustic_data.dart';
import '../../../shared/pro_widgets.dart';

class ImportTab extends ConsumerStatefulWidget {
  final String projectId;
  const ImportTab({super.key, required this.projectId});

  @override
  ConsumerState<ImportTab> createState() => _ImportTabState();
}

class _ImportTabState extends ConsumerState<ImportTab> {
  ProProject? get _project => ref.read(proProjectStoreProvider)
      .projects.where((p) => p.id == widget.projectId).firstOrNull;

  MeasurementProjectState get _acoustic =>
      _project?.acousticState ?? MeasurementProjectState.createDefault();

  Future<void> _mockImportFrd() async {
    final project = _project;
    if (project == null) return;
    final acoustic = _acoustic;
    final now = DateTime.now();
    final fileRef = AcousticFileRef(
      id: 'frd_${now.millisecondsSinceEpoch}',
      fileName: 'woofer_left_nearfield.frd',
      type: AcousticFileType.frd,
      importedAt: now,
      pointCount: 512,
      minFrequency: 20.0,
      maxFrequency: 20000.0,
      notes: 'Mock import — nearfield measurement',
    );
    final updatedFiles = [...acoustic.importedFiles, fileRef];
    // Auto-assign to first woofer L channel that has no FRD
    final updatedChannels = acoustic.driverChannels.map((ch) {
      if (ch.id == 'ch_wf_l' && !ch.hasFrd) {
        return ch.copyWith(frdFile: fileRef, measurementStatus: MeasurementStatus.imported);
      }
      return ch;
    }).toList();
    await ref.read(proProjectStoreProvider.notifier).updateAcousticState(
      widget.projectId,
      acoustic.copyWith(importedFiles: updatedFiles, driverChannels: updatedChannels),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('FRD imported → Woofer L · 20 Hz – 20 kHz · 512 points'),
        duration: Duration(seconds: 3),
      ));
    }
  }

  Future<void> _mockImportZma() async {
    final project = _project;
    if (project == null) return;
    final acoustic = _acoustic;
    final now = DateTime.now();
    final fileRef = AcousticFileRef(
      id: 'zma_${now.millisecondsSinceEpoch}',
      fileName: 'woofer_left_impedance.zma',
      type: AcousticFileType.zma,
      importedAt: now,
      pointCount: 256,
      minFrequency: 20.0,
      maxFrequency: 5000.0,
      notes: 'Mock import — impedance sweep',
    );
    final updatedFiles = [...acoustic.importedFiles, fileRef];
    final updatedChannels = acoustic.driverChannels.map((ch) {
      if (ch.id == 'ch_wf_l' && !ch.hasZma) {
        return ch.copyWith(zmaFile: fileRef,
            measurementStatus: ch.hasFrd ? MeasurementStatus.validated : MeasurementStatus.imported);
      }
      return ch;
    }).toList();
    await ref.read(proProjectStoreProvider.notifier).updateAcousticState(
      widget.projectId,
      acoustic.copyWith(importedFiles: updatedFiles, driverChannels: updatedChannels),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('ZMA imported → Woofer L · impedance sweep · 256 points'),
        duration: Duration(seconds: 3),
      ));
    }
  }

  Future<void> _assignFile(AcousticFileRef file, DriverChannel channel, bool isFrd) async {
    final acoustic = _acoustic;
    final updatedChannels = acoustic.driverChannels.map((ch) {
      if (ch.id == channel.id) {
        final updated = isFrd
            ? ch.copyWith(frdFile: file, measurementStatus: MeasurementStatus.imported)
            : ch.copyWith(zmaFile: file, measurementStatus: MeasurementStatus.imported);
        return updated;
      }
      return ch;
    }).toList();
    await ref.read(proProjectStoreProvider.notifier).updateAcousticState(
      widget.projectId,
      acoustic.copyWith(driverChannels: updatedChannels),
    );
  }

  Future<void> _removeFile(String fileId) async {
    final acoustic = _acoustic;
    final updatedFiles = acoustic.importedFiles.where((f) => f.id != fileId).toList();
    final updatedChannels = acoustic.driverChannels.map((ch) {
      DriverChannel updated = ch;
      if (ch.frdFile?.id == fileId) {
        updated = updated.copyWith(clearFrd: true,
            measurementStatus: updated.hasZma ? MeasurementStatus.imported : MeasurementStatus.empty);
      }
      if (ch.zmaFile?.id == fileId) {
        updated = updated.copyWith(clearZma: true,
            measurementStatus: updated.hasFrd ? MeasurementStatus.imported : MeasurementStatus.empty);
      }
      return updated;
    }).toList();
    await ref.read(proProjectStoreProvider.notifier).updateAcousticState(
      widget.projectId,
      acoustic.copyWith(importedFiles: updatedFiles, driverChannels: updatedChannels),
    );
  }

  @override
  Widget build(BuildContext context) {
    final acoustic = ref.watch(proProjectStoreProvider)
        .projects.where((p) => p.id == widget.projectId).firstOrNull
        ?.acousticState ?? MeasurementProjectState.createDefault();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.folder_open_outlined, color: kProAccent.withValues(alpha: 0.6), size: 18),
          const SizedBox(width: 10),
          Text('Import', style: proTitle(size: 16)),
        ]),
        const SizedBox(height: 4),
        Text('Manage FRD / ZMA acoustic measurement files. Assign to driver channels.',
            style: proSubtitle()),
        const SizedBox(height: 20),

        // Supported formats banner
        _FormatsCard(),
        const SizedBox(height: 16),

        // Import action buttons
        _ImportActionsCard(onFrd: _mockImportFrd, onZma: _mockImportZma),
        const SizedBox(height: 16),

        // Driver mapping
        Text('DRIVER CHANNEL MAPPING', style: proLabel(size: 9, spacing: 2)),
        const SizedBox(height: 8),
        ...acoustic.driverChannels.map((ch) => _DriverMappingCard(
          channel: ch,
          importedFiles: acoustic.importedFiles,
          onAssignFrd: (file) => _assignFile(file, ch, true),
          onAssignZma: (file) => _assignFile(file, ch, false),
        )),

        const SizedBox(height: 16),

        // Imported files list
        if (acoustic.importedFiles.isNotEmpty) ...[
          Text('IMPORTED FILES', style: proLabel(size: 9, spacing: 2)),
          const SizedBox(height: 8),
          ...acoustic.importedFiles.map((f) => _FileRefCard(
            file: f,
            onRemove: () => _removeFile(f.id),
          )),
        ],

        // Empty state
        if (acoustic.importedFiles.isEmpty) ...[
          const SizedBox(height: 16),
          _EmptyImportState(),
        ],
      ]),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _FormatsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('SUPPORTED FORMATS', style: proLabel(size: 9, spacing: 1.8)),
      const SizedBox(height: 10),
      const Wrap(spacing: 8, runSpacing: 6, children: [
        _FormatChip(ext: '.frd', desc: 'Frequency Response Data'),
        _FormatChip(ext: '.zma', desc: 'Impedance Data'),
        _FormatChip(ext: '.txt', desc: 'Plain text (REW export)'),
        _FormatChip(ext: '.csv', desc: 'Comma-separated values'),
      ]),
      const SizedBox(height: 10),
      Text(
        'Compatible with REW, VituixCAD, ARTA, LspCAD, and generic SPL/impedance exports.',
        style: proSubtitle(size: 10),
      ),
    ]),
  );
}

class _FormatChip extends StatelessWidget {
  final String ext;
  final String desc;
  const _FormatChip({required this.ext, required this.desc});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: kProAccent.withValues(alpha: 0.08),
      border: Border.all(color: kProAccent.withValues(alpha: 0.25)),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(ext, style: const TextStyle(color: kProAccent, fontSize: 10, fontWeight: FontWeight.w500)),
      const SizedBox(width: 6),
      Text(desc, style: proSubtitle(size: 9)),
    ]),
  );
}

class _ImportActionsCard extends StatelessWidget {
  final VoidCallback onFrd;
  final VoidCallback onZma;
  const _ImportActionsCard({required this.onFrd, required this.onZma});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('IMPORT ACTIONS', style: proLabel(size: 9, spacing: 1.8)),
      const SizedBox(height: 12),
      Row(children: [
        _ActionBtn(
          label: 'Mock Import FRD',
          icon: Icons.show_chart,
          color: kProAccent,
          onTap: onFrd,
        ),
        const SizedBox(width: 10),
        _ActionBtn(
          label: 'Mock Import ZMA',
          icon: Icons.electric_bolt_outlined,
          color: kProAmber,
          onTap: onZma,
        ),
      ]),
      const SizedBox(height: 10),
      Text(
        'Real file picker integration (file_picker package) is planned for Phase D. '
        'Mock import populates the acoustic data model to validate state flow.',
        style: proSubtitle(size: 10),
      ),
    ]),
  );
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 7),
        Text(label, style: TextStyle(color: color, fontSize: 11, letterSpacing: 0.3)),
      ]),
    ),
  );
}

class _DriverMappingCard extends StatelessWidget {
  final DriverChannel channel;
  final List<AcousticFileRef> importedFiles;
  final ValueChanged<AcousticFileRef> onAssignFrd;
  final ValueChanged<AcousticFileRef> onAssignZma;

  const _DriverMappingCard({
    required this.channel,
    required this.importedFiles,
    required this.onAssignFrd,
    required this.onAssignZma,
  });

  Color _statusColor(MeasurementStatus s) => switch (s) {
    MeasurementStatus.validated   => kProGreen,
    MeasurementStatus.imported    => kProAccent,
    MeasurementStatus.needsReview => kProAmber,
    MeasurementStatus.missingFile => kProRed,
    MeasurementStatus.empty       => const Color(0xFF6B7280),
  };

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('OUT ${channel.dspOutputIndex ?? '—'}',
            style: proLabel(size: 9, color: Colors.white24, spacing: 1)),
        const SizedBox(width: 10),
        Text(channel.name, style: proTitle(size: 12)),
        const SizedBox(width: 8),
        Text(channel.shortLabel, style: proLabel(size: 9, color: Colors.white38, spacing: 0.5)),
        const Spacer(),
        ProStatusPill(
          label: channel.measurementStatus.label,
          color: _statusColor(channel.measurementStatus),
        ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _FileSlot(label: 'FRD', file: channel.frdFile, color: kProAccent),
        const SizedBox(width: 10),
        _FileSlot(label: 'ZMA', file: channel.zmaFile, color: kProAmber),
      ]),
    ]),
  );
}

class _FileSlot extends StatelessWidget {
  final String label;
  final AcousticFileRef? file;
  final Color color;
  const _FileSlot({required this.label, required this.file, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 160,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: file != null ? color.withValues(alpha: 0.06) : Colors.transparent,
      border: Border.all(color: file != null ? color.withValues(alpha: 0.3) : kProBorder),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 9, letterSpacing: 1.5)),
      const SizedBox(height: 3),
      if (file != null) ...[
        Text(file!.fileName,
            style: proValue(size: 10, color: Colors.white60),
            overflow: TextOverflow.ellipsis),
        Text(file!.freqRangeLabel, style: proSubtitle(size: 9)),
        if (file!.pointCount != null)
          Text('${file!.pointCount} pts', style: proSubtitle(size: 9)),
      ] else
        Text('— not assigned —', style: proSubtitle(size: 10)),
    ]),
  );
}

class _FileRefCard extends StatelessWidget {
  final AcousticFileRef file;
  final VoidCallback onRemove;
  const _FileRefCard({required this.file, required this.onRemove});

  Color get _typeColor => switch (file.type) {
    AcousticFileType.frd => kProAccent,
    AcousticFileType.zma => kProAmber,
    _ => Colors.white38,
  };

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: _typeColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(3),
        ),
        alignment: Alignment.center,
        child: Text(file.type.label, style: TextStyle(color: _typeColor, fontSize: 8, letterSpacing: 0.5)),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(file.fileName, style: proTitle(size: 11)),
          Text(
            '${file.freqRangeLabel}${file.pointCount != null ? ' · ${file.pointCount} pts' : ''}',
            style: proSubtitle(size: 10),
          ),
          if (file.notes != null)
            Text(file.notes!, style: proSubtitle(size: 9)),
        ]),
      ),
      GestureDetector(
        onTap: onRemove,
        child: const Icon(Icons.close, color: Colors.white24, size: 14),
      ),
    ]),
  );
}

class _EmptyImportState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      border: Border.all(color: kProBorder, style: BorderStyle.solid),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(children: [
      const Icon(Icons.upload_file_outlined, color: Colors.white12, size: 28),
      const SizedBox(height: 12),
      Text('No files imported', style: proTitle(size: 12, color: Colors.white38)),
      const SizedBox(height: 6),
      Text(
        'Use "Mock Import FRD" or "Mock Import ZMA" above to populate driver channel data.\n'
        'Real file picker will be available in Phase D.',
        style: proSubtitle(size: 10),
        textAlign: TextAlign.center,
      ),
    ]),
  );
}
