// ── Import Tab — Phase M ──────────────────────────────────────────────────────
// Real FRD/ZMA paste-import with ProMeasurementParser.
// File picker integration is a future phase item (desktop file_picker package).
// No hardware write. No DSP addresses.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/pro_project.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_acoustic_data.dart';
import '../../../core/pro_measurement_parser.dart';
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

  // ── Parse & import dialog ─────────────────────────────────────────────────

  Future<void> _openImportDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ParseImportDialog(
        acoustic: _acoustic,
        onImport: (channel, result) async {
          await _applyImport(channel, result);
        },
      ),
    );
  }

  Future<void> _applyImport(
      DriverChannel channel, MeasurementParseResult result) async {
    final data = result.data;
    if (data == null) return;
    final acoustic = _acoustic;
    final now = DateTime.now();
    final isFrd = data.fileType == AcousticFileType.frd ||
        data.fileType == AcousticFileType.txt ||
        data.fileType == AcousticFileType.csv;

    final fileRef = AcousticFileRef(
      id: 'ref_${now.millisecondsSinceEpoch}',
      fileName: data.sourceFileName,
      type: data.fileType,
      importedAt: now,
      pointCount: data.pointCount,
      minFrequency: data.minFrequencyHz,
      maxFrequency: data.maxFrequencyHz,
      parseStatus: result.status,
      parsedDataId: data.id,
    );

    final updatedFiles = [...acoustic.importedFiles, fileRef];
    final updatedChannels = acoustic.driverChannels.map((ch) {
      if (ch.id != channel.id) return ch;
      if (isFrd) {
        return ch.copyWith(
          frdFile: fileRef,
          frdData: data,
          measurementStatus:
              ch.hasZma ? MeasurementStatus.validated : MeasurementStatus.imported,
        );
      } else {
        return ch.copyWith(
          zmaFile: fileRef,
          zmaData: data,
          measurementStatus:
              ch.hasFrd ? MeasurementStatus.validated : MeasurementStatus.imported,
        );
      }
    }).toList();

    await ref.read(proProjectStoreProvider.notifier).updateAcousticState(
      widget.projectId,
      acoustic.copyWith(
          importedFiles: updatedFiles, driverChannels: updatedChannels),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${data.fileType.label.toUpperCase()} imported → '
            '${channel.name}  ${data.freqRangeLabel}  '
            '${data.pointCount} pts'),
        duration: const Duration(seconds: 3),
      ));
    }
  }

  Future<void> _removeDriver(DriverChannel ch, bool removeFrd) async {
    final acoustic = _acoustic;
    AcousticFileRef? fileToRemove;
    List<AcousticFileRef> updatedFiles = acoustic.importedFiles;

    final updatedChannels = acoustic.driverChannels.map((c) {
      if (c.id != ch.id) return c;
      if (removeFrd) {
        fileToRemove = c.frdFile;
        return c.copyWith(
          clearFrd: true,
          clearFrdData: true,
          measurementStatus:
              c.hasZma ? MeasurementStatus.imported : MeasurementStatus.empty,
        );
      } else {
        fileToRemove = c.zmaFile;
        return c.copyWith(
          clearZma: true,
          clearZmaData: true,
          measurementStatus:
              c.hasFrd ? MeasurementStatus.imported : MeasurementStatus.empty,
        );
      }
    }).toList();

    if (fileToRemove != null) {
      updatedFiles =
          acoustic.importedFiles.where((f) => f.id != fileToRemove!.id).toList();
    }

    await ref.read(proProjectStoreProvider.notifier).updateAcousticState(
      widget.projectId,
      acoustic.copyWith(
          importedFiles: updatedFiles, driverChannels: updatedChannels),
    );
  }

  @override
  Widget build(BuildContext context) {
    final acoustic = ref.watch(proProjectStoreProvider)
            .projects
            .where((p) => p.id == widget.projectId)
            .firstOrNull
            ?.acousticState ??
        MeasurementProjectState.createDefault();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Icon(Icons.folder_open_outlined,
              color: kProAccent.withValues(alpha: 0.6), size: 18),
          const SizedBox(width: 10),
          Text('Import', style: proTitle(size: 16)),
        ]),
        const SizedBox(height: 4),
        Text(
          'Parse FRD / ZMA measurement files and assign to driver channels.',
          style: proSubtitle(),
        ),
        const SizedBox(height: 20),

        // Supported formats card
        _FormatsCard(),
        const SizedBox(height: 16),

        // Import action
        _ImportActionCard(onImport: _openImportDialog),
        const SizedBox(height: 20),

        // Driver channel cards
        Text('DRIVER CHANNELS', style: proLabel(size: 9, spacing: 2)),
        const SizedBox(height: 8),
        ...acoustic.driverChannels.map((ch) => _DriverDataCard(
              channel: ch,
              onRemoveFrd: () => _removeDriver(ch, true),
              onRemoveZma: () => _removeDriver(ch, false),
            )),

        // Empty state
        if (acoustic.parsedFrdCount == 0 && acoustic.parsedZmaCount == 0) ...[
          const SizedBox(height: 8),
          _EmptyState(),
        ],
      ]),
    );
  }
}

// ── Parse / Import Dialog ─────────────────────────────────────────────────────

class _ParseImportDialog extends StatefulWidget {
  final MeasurementProjectState acoustic;
  final Future<void> Function(DriverChannel, MeasurementParseResult) onImport;

  const _ParseImportDialog({required this.acoustic, required this.onImport});

  @override
  State<_ParseImportDialog> createState() => _ParseImportDialogState();
}

class _ParseImportDialogState extends State<_ParseImportDialog> {
  final _fileNameCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  AcousticFileType _fileType = AcousticFileType.frd;
  DriverChannel? _targetChannel;
  MeasurementParseResult? _result;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    if (widget.acoustic.driverChannels.isNotEmpty) {
      _targetChannel = widget.acoustic.driverChannels.first;
    }
  }

  @override
  void dispose() {
    _fileNameCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  void _parse() {
    final content = _contentCtrl.text;
    final fileName = _fileNameCtrl.text.trim().isEmpty
        ? 'paste_${DateTime.now().millisecondsSinceEpoch}.${_fileType.name}'
        : _fileNameCtrl.text.trim();

    MeasurementParseResult result;
    if (_fileType == AcousticFileType.zma) {
      result = ProMeasurementParser.parseZma(
          fileName: fileName, content: content);
    } else {
      result = ProMeasurementParser.parseFrd(
          fileName: fileName, content: content);
    }
    setState(() => _result = result);
  }

  Future<void> _import() async {
    final r = _result;
    final ch = _targetChannel;
    if (r == null || r.data == null || ch == null) return;
    setState(() => _importing = true);
    await widget.onImport(ch, r);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final canImport =
        result != null && result.data != null && _targetChannel != null;

    return Dialog(
      backgroundColor: kProPanel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: Container(
        width: 620,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Row(children: [
              const Icon(Icons.upload_file_outlined,
                  color: kProAccent, size: 16),
              const SizedBox(width: 8),
              Text('Paste & Parse Measurement Data', style: proTitle(size: 14)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Icon(Icons.close, color: Colors.white38, size: 16),
              ),
            ]),
            const SizedBox(height: 16),

            // File type selector
            Row(children: [
              Text('File type:', style: proLabel(size: 10)),
              const SizedBox(width: 10),
              ...[AcousticFileType.frd, AcousticFileType.zma,
                  AcousticFileType.txt].map((t) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () => setState(() => _fileType = t),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _fileType == t
                          ? kProAccent.withValues(alpha: 0.15)
                          : Colors.transparent,
                      border: Border.all(
                          color: _fileType == t
                              ? kProAccent.withValues(alpha: 0.6)
                              : kProBorder),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(t.label,
                        style: TextStyle(
                            color: _fileType == t
                                ? kProAccent
                                : Colors.white38,
                            fontSize: 10)),
                  ),
                ),
              )),
            ]),
            const SizedBox(height: 12),

            // File name
            _Field(
              label: 'File name (optional)',
              child: TextField(
                controller: _fileNameCtrl,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
                decoration: _inputDec('e.g. woofer_left.frd'),
              ),
            ),
            const SizedBox(height: 10),

            // Content
            _Field(
              label: 'Paste file content',
              child: TextField(
                controller: _contentCtrl,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 10,
                    fontFamily: 'monospace'),
                decoration: _inputDec(
                    '# Example FRD\n20    -3.2   180.0\n50     0.1    90.5\n...'),
                maxLines: 10,
              ),
            ),
            const SizedBox(height: 12),

            // Target channel
            if (widget.acoustic.driverChannels.isNotEmpty) ...[
              Row(children: [
                Text('Assign to channel:', style: proLabel(size: 10)),
                const SizedBox(width: 10),
                DropdownButton<DriverChannel>(
                  value: _targetChannel,
                  dropdownColor: kProPanel,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                  underline: Container(height: 0.5, color: kProBorder),
                  items: widget.acoustic.driverChannels.map((ch) =>
                    DropdownMenuItem(
                      value: ch,
                      child: Text(ch.name),
                    ),
                  ).toList(),
                  onChanged: (ch) => setState(() => _targetChannel = ch),
                ),
              ]),
              const SizedBox(height: 12),
            ],

            // Action row
            Row(children: [
              _Btn(label: 'Parse', onTap: _parse, color: kProAmber),
              const SizedBox(width: 10),
              _Btn(
                label: _importing ? 'Importing…' : 'Import & Assign',
                onTap: canImport && !_importing ? _import : null,
                color: kProAccent,
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
              ),
            ]),

            // Parse result preview
            if (result != null) ...[
              const SizedBox(height: 16),
              _ParseResultPanel(result: result),
            ],
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: Colors.white12, fontSize: 10),
        filled: true,
        fillColor: kProSurface,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(3),
            borderSide: const BorderSide(color: kProBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(3),
            borderSide: const BorderSide(color: kProBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(3),
            borderSide:
                BorderSide(color: kProAccent.withValues(alpha: 0.5))),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      );
}

class _Field extends StatelessWidget {
  final String label;
  final Widget child;
  const _Field({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: proLabel(size: 9, spacing: 1)),
      const SizedBox(height: 5),
      child,
    ],
  );
}

class _Btn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color color;
  const _Btn({required this.label, required this.onTap, required this.color});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(
            color: onTap != null
                ? color.withValues(alpha: 0.6)
                : Colors.white12),
        borderRadius: BorderRadius.circular(4),
        color: onTap != null
            ? color.withValues(alpha: 0.08)
            : Colors.transparent,
      ),
      child: Text(label,
          style: TextStyle(
              color: onTap != null ? color : Colors.white24,
              fontSize: 11)),
    ),
  );
}

// ── Parse result preview ──────────────────────────────────────────────────────

class _ParseResultPanel extends StatelessWidget {
  final MeasurementParseResult result;
  const _ParseResultPanel({required this.result});

  Color get _statusColor => switch (result.status) {
    MeasurementParseStatus.parsed             => kProGreen,
    MeasurementParseStatus.parsedWithWarnings => kProAmber,
    MeasurementParseStatus.failed             => kProRed,
    MeasurementParseStatus.unsupported        => kProRed,
    MeasurementParseStatus.notParsed          => Colors.white24,
  };

  @override
  Widget build(BuildContext context) {
    final data = result.data;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: _statusColor.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ProStatusPill(label: result.status.label, color: _statusColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(result.summary,
                style: proSubtitle(size: 10),
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        if (data != null) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            _InfoChip('${data.pointCount} pts'),
            _InfoChip(data.freqRangeLabel),
            if (data.hasMagnitude) const _InfoChip('Magnitude ✓'),
            if (data.hasPhase) const _InfoChip('Phase ✓'),
            if (data.hasImpedance) const _InfoChip('Impedance ✓'),
            if (!data.hasPhase && !data.hasImpedance)
              const _InfoChip('No phase', warn: true),
          ]),
        ],
        if (result.warnings.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...result.warnings.take(3).map((w) => Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 10, color: kProAmber),
              const SizedBox(width: 5),
              Expanded(child: Text(w, style: proSubtitle(size: 9))),
            ]),
          )),
          if (result.warnings.length > 3)
            Text('+ ${result.warnings.length - 3} more warnings…',
                style: proSubtitle(size: 9)),
        ],
        if (result.errors.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...result.errors.take(2).map((e) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline, size: 10, color: kProRed),
              const SizedBox(width: 5),
              Expanded(
                  child: Text(e,
                      style: const TextStyle(
                          color: kProRed,
                          fontSize: 9))),
            ],
          )),
        ],
      ]),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final bool warn;
  const _InfoChip(this.label, {this.warn = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: warn
          ? kProAmber.withValues(alpha: 0.1)
          : kProAccent.withValues(alpha: 0.07),
      border: Border.all(
          color: warn
              ? kProAmber.withValues(alpha: 0.3)
              : kProAccent.withValues(alpha: 0.2)),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(label,
        style: TextStyle(
            color: warn ? kProAmber : kProAccent,
            fontSize: 9)),
  );
}

// ── Driver data card ──────────────────────────────────────────────────────────

class _DriverDataCard extends StatelessWidget {
  final DriverChannel channel;
  final VoidCallback onRemoveFrd;
  final VoidCallback onRemoveZma;

  const _DriverDataCard({
    required this.channel,
    required this.onRemoveFrd,
    required this.onRemoveZma,
  });

  Color _statusColor(MeasurementStatus s) => switch (s) {
    MeasurementStatus.validated   => kProGreen,
    MeasurementStatus.imported    => kProAccent,
    MeasurementStatus.needsReview => kProAmber,
    MeasurementStatus.missingFile => kProRed,
    MeasurementStatus.empty       => const Color(0xFF6B7280),
  };

  @override
  Widget build(BuildContext context) {
    final frd = channel.frdData;
    final zma = channel.zmaData;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header row
        Row(children: [
          if (channel.dspOutputIndex != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text('OUT ${channel.dspOutputIndex}',
                  style: proLabel(size: 9, color: Colors.white24, spacing: 1)),
            ),
          Text(channel.name, style: proTitle(size: 12)),
          const SizedBox(width: 8),
          Text(channel.shortLabel,
              style: proLabel(size: 9, color: Colors.white38, spacing: 0.5)),
          const Spacer(),
          ProStatusPill(
            label: channel.measurementStatus.label,
            color: _statusColor(channel.measurementStatus),
          ),
        ]),
        const SizedBox(height: 10),

        // FRD + ZMA slots
        Row(children: [
          Expanded(
            child: _DataSlot(
              label: 'FRD',
              data: frd,
              fileRef: channel.frdFile,
              color: kProAccent,
              onRemove: channel.hasParsedFrd ? onRemoveFrd : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _DataSlot(
              label: 'ZMA',
              data: zma,
              fileRef: channel.zmaFile,
              color: kProAmber,
              onRemove: channel.hasParsedZma ? onRemoveZma : null,
            ),
          ),
        ]),
      ]),
    );
  }
}

class _DataSlot extends StatelessWidget {
  final String label;
  final ParsedMeasurementData? data;
  final AcousticFileRef? fileRef;
  final Color color;
  final VoidCallback? onRemove;

  const _DataSlot({
    required this.label,
    required this.data,
    required this.fileRef,
    required this.color,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final hasData = data != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: hasData ? color.withValues(alpha: 0.06) : Colors.transparent,
        border: Border.all(
            color: hasData ? color.withValues(alpha: 0.3) : kProBorder),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(label,
              style: TextStyle(
                  color: color.withValues(alpha: 0.8),
                  fontSize: 9,
                  letterSpacing: 1.5)),
          const Spacer(),
          if (onRemove != null)
            GestureDetector(
              onTap: onRemove,
              child: const Icon(Icons.close,
                  color: Colors.white24, size: 12),
            ),
        ]),
        const SizedBox(height: 4),
        if (hasData) ...[
          Text(data!.sourceFileName,
              style: proValue(size: 10, color: Colors.white70),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text('${data!.freqRangeLabel}  ·  ${data!.pointCount} pts',
              style: proSubtitle(size: 9)),
          const SizedBox(height: 2),
          Wrap(spacing: 4, children: [
            if (data!.hasMagnitude)
              _MiniChip('Mag', color),
            if (data!.hasPhase)
              _MiniChip('Phase', color),
            if (data!.hasImpedance)
              const _MiniChip('Z', kProAmber),
            if (!data!.hasPhase && !data!.hasImpedance)
              const _MiniChip('No phase', kProAmber),
          ]),
          if (fileRef?.parseStatus == MeasurementParseStatus.parsedWithWarnings)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded,
                    size: 9, color: kProAmber),
                SizedBox(width: 4),
                Text('Parsed with warnings',
                    style: TextStyle(color: kProAmber, fontSize: 9)),
              ]),
            ),
        ] else ...[
          Text('— not imported —', style: proSubtitle(size: 10)),
        ],
      ]),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final Color color;
  const _MiniChip(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(2),
    ),
    child: Text(label,
        style: TextStyle(color: color, fontSize: 8, letterSpacing: 0.3)),
  );
}

// ── Supporting static widgets ─────────────────────────────────────────────────

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
        _FormatChip(ext: '.frd', desc: 'SPL freq magnitude [phase]'),
        _FormatChip(ext: '.zma', desc: 'Impedance freq Ω [phase]'),
        _FormatChip(ext: '.txt', desc: 'REW / ARTA plain text export'),
        _FormatChip(ext: '.csv', desc: 'Comma-separated (parsed as FRD)'),
      ]),
      const SizedBox(height: 10),
      Text(
        'Whitespace or comma delimited. Lines starting with #  *  ;  // are treated as comments.',
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
      Text(ext,
          style: const TextStyle(
              color: kProAccent,
              fontSize: 10,
              fontWeight: FontWeight.w500)),
      const SizedBox(width: 6),
      Text(desc, style: proSubtitle(size: 9)),
    ]),
  );
}

class _ImportActionCard extends StatelessWidget {
  final VoidCallback onImport;
  const _ImportActionCard({required this.onImport});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('IMPORT', style: proLabel(size: 9, spacing: 1.8)),
      const SizedBox(height: 12),
      GestureDetector(
        onTap: onImport,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: kProAccent.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(4),
            color: kProAccent.withValues(alpha: 0.06),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.upload_file_outlined, color: kProAccent, size: 14),
            SizedBox(width: 8),
            Text('Paste & Parse FRD / ZMA…',
                style: TextStyle(
                    color: kProAccent, fontSize: 11, letterSpacing: 0.3)),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        'Paste file content, select format (FRD / ZMA) and target driver channel. '
        'Desktop file picker integration planned for a future phase.',
        style: proSubtitle(size: 10),
      ),
    ]),
  );
}

class _EmptyState extends StatelessWidget {
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
      Text('No FRD / ZMA data imported',
          style: proTitle(size: 12, color: Colors.white38)),
      const SizedBox(height: 6),
      Text(
        'Use "Paste & Parse FRD / ZMA" above to import real measurement data.\n'
        'Simulation will use placeholder driver curves until FRD is imported.',
        style: proSubtitle(size: 10),
        textAlign: TextAlign.center,
      ),
    ]),
  );
}
