// ── Import Tab — File Picker + Drag-and-Drop ──────────────────────────────────
// Supports: (1) paste & parse (existing), (2) OS file picker (new),
// (3) drag-and-drop from file manager (new).
// Reuses ProMeasurementParser and existing _applyImport logic unchanged.
// No hardware write. No DSP addresses.

import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/pro_acoustic_data.dart';
import '../../../core/pro_measurement_parser.dart';
import '../../../core/pro_project.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/workbench_tab_provider.dart';
import '../../../shared/pro_widgets.dart';

// ── Filename heuristic helpers (pure — easily testable) ───────────────────────

/// Suggests a DriverChannel based on filename tokens. Returns null when the
/// result is ambiguous (the caller must not auto-confirm).
DriverChannel? suggestChannelForFile(
    String fileName, List<DriverChannel> channels) {
  if (channels.isEmpty) return null;
  final lower = fileName.toLowerCase();

  // Split on common separators: space, _, -, .
  final tokens =
      lower.split(RegExp(r'[\s\-_.]')).where((t) => t.isNotEmpty).toSet();

  bool hasToken(Iterable<String> candidates) =>
      candidates.any((c) => tokens.contains(c));

  final isLeft = hasToken(['l', 'left', 'lft']);
  final isRight = hasToken(['r', 'right', 'rgt']);
  final isWoofer = hasToken(['woofer', 'wf', 'bass', 'sub', 'lf', 'lo']);
  final isTweeter =
      hasToken(['tweeter', 'tw', 'treble', 'hf', 'hi', 'high', 'ht']);

  DriverChannel? pick(bool Function(DriverChannel) pred) {
    final matches = channels.where(pred).toList();
    return matches.length == 1 ? matches.first : null;
  }

  // Role + side combinations (most specific first).
  if (isWoofer && isLeft) {
    final c = pick((ch) =>
        ch.role == DriverRole.woofer && ch.side == DriverSide.left);
    if (c != null) return c;
  }
  if (isWoofer && isRight) {
    final c = pick((ch) =>
        ch.role == DriverRole.woofer && ch.side == DriverSide.right);
    if (c != null) return c;
  }
  if (isTweeter && isLeft) {
    final c = pick((ch) =>
        ch.role == DriverRole.tweeter && ch.side == DriverSide.left);
    if (c != null) return c;
  }
  if (isTweeter && isRight) {
    final c = pick((ch) =>
        ch.role == DriverRole.tweeter && ch.side == DriverSide.right);
    if (c != null) return c;
  }

  // Role only.
  if (isWoofer) {
    final c = pick((ch) => ch.role == DriverRole.woofer);
    if (c != null) return c;
  }
  if (isTweeter) {
    final c = pick((ch) => ch.role == DriverRole.tweeter);
    if (c != null) return c;
  }

  // Side only.
  if (isLeft) {
    final c = pick((ch) => ch.side == DriverSide.left);
    if (c != null) return c;
  }
  if (isRight) {
    final c = pick((ch) => ch.side == DriverSide.right);
    if (c != null) return c;
  }

  // Exactly one channel — unambiguous default.
  if (channels.length == 1) return channels.first;
  return null;
}

/// Derives the default AcousticFileType from a filename extension.
/// Returns [AcousticFileType.frd] for unknown extensions (safe default).
AcousticFileType typeFromFileName(String fileName) {
  final ext = fileName.split('.').lastOrNull?.toLowerCase() ?? '';
  return AcousticFileType.fromExtension(ext);
}

/// Returns true if the file extension is one the parser can handle.
bool isSupportedExtension(String fileName) {
  final ext = fileName.split('.').lastOrNull?.toLowerCase() ?? '';
  return const {'frd', 'zma', 'txt', 'csv'}.contains(ext);
}

// ── Pending file record (used by multi-file mapping) ──────────────────────────

class _PendingFile {
  final String fileName;
  final String content;
  AcousticFileType fileType;
  DriverChannel? targetChannel;

  _PendingFile({
    required this.fileName,
    required this.content,
    required this.fileType,
    required this.targetChannel,
  });
}

// ── ImportTab ─────────────────────────────────────────────────────────────────

class ImportTab extends ConsumerStatefulWidget {
  final String projectId;
  const ImportTab({super.key, required this.projectId});

  @override
  ConsumerState<ImportTab> createState() => _ImportTabState();
}

class _ImportTabState extends ConsumerState<ImportTab> {
  bool _isDraggingOver = false;

  // When a card-level DropTarget handles a drop first, this is set to prevent
  // the outer DropTarget from double-handling the same event.
  String? _dropHandledByCardId;

  ProProject? get _project => ref
      .read(proProjectStoreProvider)
      .projects
      .where((p) => p.id == widget.projectId)
      .firstOrNull;

  MeasurementProjectState get _acoustic =>
      _project?.acousticState ?? MeasurementProjectState.createDefault();

  // ── Core import (unchanged logic from previous version) ───────────────────

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
              importedFiles: updatedFiles,
              driverChannels: updatedChannels),
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

  Future<void> _addRepeatSweep(DriverChannel ch) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['frd', 'txt', 'csv'],
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final pf = result.files.first;
    final path = pf.path;
    if (path == null) return;

    String content;
    try {
      content = await File(path).readAsString();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('읽기 실패: ${pf.name} — ${_friendlyError(e)}'),
          backgroundColor: kProRed.withValues(alpha: 0.85),
        ));
      }
      return;
    }

    final parsed = ProMeasurementParser.parseFrd(
        fileName: pf.name, content: content);
    if (parsed.status == MeasurementParseStatus.failed ||
        parsed.data == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Parse failed: ${pf.name} — ${parsed.errors.firstOrNull ?? "unknown error"}'),
          backgroundColor: kProRed.withValues(alpha: 0.85),
        ));
      }
      return;
    }

    final entry = FrdSweepEntry.fromRawContent(pf.name, content);
    final acoustic = _acoustic;
    final updatedChannels = acoustic.driverChannels.map((c) {
      if (c.id != ch.id) return c;
      return c.copyWith(
          additionalFrdSweeps: [...c.additionalFrdSweeps, entry]);
    }).toList();

    await ref.read(proProjectStoreProvider.notifier).updateAcousticState(
          widget.projectId,
          acoustic.copyWith(driverChannels: updatedChannels),
        );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Repeat sweep added: ${pf.name}  (${parsed.data!.pointCount} pts)'),
        duration: const Duration(seconds: 3),
      ));
    }
  }

  Future<void> _removeRepeatSweep(DriverChannel ch, int index) async {
    final acoustic = _acoustic;
    final updatedChannels = acoustic.driverChannels.map((c) {
      if (c.id != ch.id) return c;
      final sweeps = [...c.additionalFrdSweeps]..removeAt(index);
      return c.copyWith(additionalFrdSweeps: sweeps);
    }).toList();

    await ref.read(proProjectStoreProvider.notifier).updateAcousticState(
          widget.projectId,
          acoustic.copyWith(driverChannels: updatedChannels),
        );
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
              importedFiles: updatedFiles,
              driverChannels: updatedChannels),
        );
  }

  // ── Paste & Parse dialog (unchanged) ──────────────────────────────────────

  Future<void> _openPasteDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ParseImportDialog(
        acoustic: _acoustic,
        onImport: _applyImport,
      ),
    );
  }

  // ── File picker ───────────────────────────────────────────────────────────

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['frd', 'zma', 'txt', 'csv'],
      allowMultiple: true,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;

    final pending = <_PendingFile>[];
    for (final pf in result.files) {
      final path = pf.path;
      if (path == null) continue;
      final name = pf.name;
      if (!isSupportedExtension(name)) continue;
      try {
        final content = await File(path).readAsString();
        pending.add(_PendingFile(
          fileName: name,
          content: content,
          fileType: typeFromFileName(name),
          targetChannel: suggestChannelForFile(name, _acoustic.driverChannels),
        ));
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('읽기 실패: $name — ${_friendlyError(e)}'),
            backgroundColor: kProRed.withValues(alpha: 0.85),
          ));
        }
      }
    }
    if (pending.isEmpty) return;
    await _showImportDialogForFiles(pending);
  }

  // ── Drag-and-drop handler ─────────────────────────────────────────────────

  Future<void> _handleDrop(DropDoneDetails detail,
      {DriverChannel? cardChannel}) async {
    if (cardChannel != null) {
      _dropHandledByCardId = cardChannel.id;
    }
    setState(() => _isDraggingOver = false);

    final supported = detail.files.where((f) => isSupportedExtension(f.name)).toList();
    final rejected = detail.files.where((f) => !isSupportedExtension(f.name)).toList();

    if (rejected.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('지원하지 않는 형식: ${rejected.map((f) => f.name).join(', ')}'),
        backgroundColor: kProAmber.withValues(alpha: 0.85),
      ));
    }
    if (supported.isEmpty) return;

    final pending = <_PendingFile>[];
    for (final xf in supported) {
      try {
        final content = await xf.readAsString();
        final suggestedChannel = cardChannel ??
            suggestChannelForFile(xf.name, _acoustic.driverChannels);
        pending.add(_PendingFile(
          fileName: xf.name,
          content: content,
          fileType: typeFromFileName(xf.name),
          targetChannel: suggestedChannel,
        ));
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('읽기 실패: ${xf.name} — ${_friendlyError(e)}'),
            backgroundColor: kProRed.withValues(alpha: 0.85),
          ));
        }
      }
    }
    if (pending.isEmpty) return;
    await _showImportDialogForFiles(pending);
  }

  // ── Route single/multi to the correct dialog ──────────────────────────────

  Future<void> _showImportDialogForFiles(List<_PendingFile> files) async {
    if (!mounted) return;
    if (files.length == 1) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _SingleFileImportDialog(
          pending: files.first,
          acoustic: _acoustic,
          onImport: _applyImport,
        ),
      );
    } else {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _FileMappingDialog(
          files: files,
          acoustic: _acoustic,
          onImportAll: (confirmed) async {
            for (final pf in confirmed) {
              if (!mounted) break;
              final r = _parseFile(pf);
              if (r.data != null && pf.targetChannel != null) {
                await _applyImport(pf.targetChannel!, r);
              }
            }
          },
        ),
      );
    }
  }

  // ── Parse helper (routes to parseFrd / parseZma) ──────────────────────────

  MeasurementParseResult _parseFile(_PendingFile pf) {
    if (pf.fileType == AcousticFileType.zma) {
      return ProMeasurementParser.parseZma(
          fileName: pf.fileName, content: pf.content);
    }
    return ProMeasurementParser.parseFrd(
        fileName: pf.fileName, content: pf.content);
  }

  static String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('FileSystemException') || msg.contains('No such file')) {
      return '파일을 찾을 수 없습니다';
    }
    if (msg.contains('Permission')) return '파일 접근 권한 없음';
    return msg.length > 60 ? '${msg.substring(0, 60)}…' : msg;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final acoustic = ref
            .watch(proProjectStoreProvider)
            .projects
            .where((p) => p.id == widget.projectId)
            .firstOrNull
            ?.acousticState ??
        MeasurementProjectState.createDefault();

    return DropTarget(
      onDragEntered: (_) => setState(() => _isDraggingOver = true),
      onDragExited: (_) => setState(() => _isDraggingOver = false),
      onDragDone: (detail) {
        if (_dropHandledByCardId != null) {
          _dropHandledByCardId = null;
          return;
        }
        _handleDrop(detail);
      },
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              // Header
              Row(children: [
                Icon(Icons.folder_open_outlined,
                    color: kProAccent.withValues(alpha: 0.6), size: 18),
                const SizedBox(width: 10),
                Text('Import', style: proTitle(size: 16)),
              ]),
              const SizedBox(height: 4),
              Text(
                'Import FRD / ZMA measurement files by selecting or dropping them.',
                style: proSubtitle(),
              ),
              const SizedBox(height: 20),

              // Supported formats card
              _FormatsCard(),
              const SizedBox(height: 16),

              // Import action card — file picker + paste
              _ImportActionCard(
                onPickFiles: _pickFiles,
                onPaste: _openPasteDialog,
              ),
              const SizedBox(height: 20),

              // Driver channel cards (each is also a drop target)
              Text('DRIVER CHANNELS', style: proLabel(size: 9, spacing: 2)),
              const SizedBox(height: 8),
              ...acoustic.driverChannels.map((ch) => _DroppableDriverCard(
                    channel: ch,
                    onRemoveFrd: () => _removeDriver(ch, true),
                    onRemoveZma: () => _removeDriver(ch, false),
                    onDropFiles: (detail) =>
                        _handleDrop(detail, cardChannel: ch),
                    onAddRepeatSweep: () => _addRepeatSweep(ch),
                    onRemoveRepeatSweep: (i) => _removeRepeatSweep(ch, i),
                  )),

              // "Analyze with AI" shortcut — only when FRD data is present.
              if (acoustic.parsedFrdCount > 0) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => ref
                        .read(workbenchTabProvider.notifier)
                        .go(kTabGuidedAi),
                    icon: const Icon(Icons.psychology_outlined, size: 15),
                    label: const Text('AI로 분석하기'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white60,
                      side: const BorderSide(color: Colors.white12),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],

              // Empty state
              if (acoustic.parsedFrdCount == 0 &&
                  acoustic.parsedZmaCount == 0) ...[
                const SizedBox(height: 8),
                _EmptyState(onPickFiles: _pickFiles),
              ],
            ]),
          ),

          // Drag-over overlay
          if (_isDraggingOver)
            IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: kProAccent.withValues(alpha: 0.06),
                  border: Border.all(
                    color: kProAccent.withValues(alpha: 0.5),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.upload_file_outlined,
                          color: kProAccent, size: 40),
                      const SizedBox(height: 12),
                      Text('FRD / ZMA 파일을 여기에 놓으세요',
                          style: proTitle(size: 15, color: kProAccent)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Droppable driver card wrapper ─────────────────────────────────────────────

class _DroppableDriverCard extends StatefulWidget {
  final DriverChannel channel;
  final VoidCallback onRemoveFrd;
  final VoidCallback onRemoveZma;
  final void Function(DropDoneDetails) onDropFiles;
  final VoidCallback onAddRepeatSweep;
  final void Function(int) onRemoveRepeatSweep;

  const _DroppableDriverCard({
    required this.channel,
    required this.onRemoveFrd,
    required this.onRemoveZma,
    required this.onDropFiles,
    required this.onAddRepeatSweep,
    required this.onRemoveRepeatSweep,
  });

  @override
  State<_DroppableDriverCard> createState() => _DroppableDriverCardState();
}

class _DroppableDriverCardState extends State<_DroppableDriverCard> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _isHovering = true),
      onDragExited: (_) => setState(() => _isHovering = false),
      onDragDone: (detail) {
        setState(() => _isHovering = false);
        widget.onDropFiles(detail);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: _isHovering
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: kProAccent.withValues(alpha: 0.7), width: 1.5),
              )
            : null,
        child: _DriverDataCard(
          channel: widget.channel,
          onRemoveFrd: widget.onRemoveFrd,
          onRemoveZma: widget.onRemoveZma,
          onAddRepeatSweep: widget.onAddRepeatSweep,
          onRemoveRepeatSweep: widget.onRemoveRepeatSweep,
        ),
      ),
    );
  }
}

// ── Single-file import dialog (file picker / single drop) ─────────────────────

class _SingleFileImportDialog extends StatefulWidget {
  final _PendingFile pending;
  final MeasurementProjectState acoustic;
  final Future<void> Function(DriverChannel, MeasurementParseResult) onImport;

  const _SingleFileImportDialog({
    required this.pending,
    required this.acoustic,
    required this.onImport,
  });

  @override
  State<_SingleFileImportDialog> createState() =>
      _SingleFileImportDialogState();
}

class _SingleFileImportDialogState extends State<_SingleFileImportDialog> {
  late AcousticFileType _fileType;
  DriverChannel? _targetChannel;
  MeasurementParseResult? _result;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _fileType = widget.pending.fileType;
    _targetChannel = widget.pending.targetChannel ??
        (widget.acoustic.driverChannels.isNotEmpty
            ? widget.acoustic.driverChannels.first
            : null);
    // Auto-parse on open.
    _parse();
  }

  void _parse() {
    MeasurementParseResult r;
    if (_fileType == AcousticFileType.zma) {
      r = ProMeasurementParser.parseZma(
          fileName: widget.pending.fileName, content: widget.pending.content);
    } else {
      r = ProMeasurementParser.parseFrd(
          fileName: widget.pending.fileName, content: widget.pending.content);
    }
    setState(() => _result = r);
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
    final canImport = result != null && result.data != null &&
        _targetChannel != null && !_importing;

    return Dialog(
      backgroundColor: kProPanel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Row(children: [
              const Icon(Icons.insert_drive_file_outlined,
                  color: kProAccent, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.pending.fileName,
                  style: proTitle(size: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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
              ...[
                AcousticFileType.frd,
                AcousticFileType.zma,
                AcousticFileType.txt,
              ].map((t) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _fileType = t);
                        _parse();
                      },
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
            const SizedBox(height: 14),

            // Parse result preview (auto-parsed on open)
            if (result != null) _ParseResultPanel(result: result),
            const SizedBox(height: 14),

            // Target channel selector
            if (widget.acoustic.driverChannels.isNotEmpty) ...[
              Row(children: [
                Text('Assign to channel:', style: proLabel(size: 10)),
                const SizedBox(width: 10),
                DropdownButton<DriverChannel>(
                  value: _targetChannel,
                  dropdownColor: kProPanel,
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 11),
                  underline: Container(height: 0.5, color: kProBorder),
                  items: widget.acoustic.driverChannels
                      .map((ch) => DropdownMenuItem(
                            value: ch,
                            child: Text(ch.name),
                          ))
                      .toList(),
                  onChanged: (ch) => setState(() => _targetChannel = ch),
                ),
              ]),
              const SizedBox(height: 14),
            ],

            // Action row
            Row(children: [
              _Btn(
                label: _importing ? 'Importing…' : 'Import & Assign',
                onTap: canImport ? _import : null,
                color: kProAccent,
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ── Multi-file mapping dialog ─────────────────────────────────────────────────

class _FileMappingDialog extends StatefulWidget {
  final List<_PendingFile> files;
  final MeasurementProjectState acoustic;
  final Future<void> Function(List<_PendingFile>) onImportAll;

  const _FileMappingDialog({
    required this.files,
    required this.acoustic,
    required this.onImportAll,
  });

  @override
  State<_FileMappingDialog> createState() => _FileMappingDialogState();
}

class _FileMappingDialogState extends State<_FileMappingDialog> {
  late final List<_PendingFile> _rows;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _rows = List.of(widget.files);
  }

  bool get _hasDuplicateChannels {
    final used = <String?>[];
    for (final r in _rows) {
      if (r.targetChannel != null) {
        if (used.contains(r.targetChannel!.id)) return true;
        used.add(r.targetChannel!.id);
      }
    }
    return false;
  }

  Future<void> _importAll() async {
    setState(() => _importing = true);
    final confirmed = _rows
        .where((r) => r.targetChannel != null)
        .toList();
    await widget.onImportAll(confirmed);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final hasDup = _hasDuplicateChannels;
    final canImport =
        !_importing && _rows.any((r) => r.targetChannel != null);

    return Dialog(
      backgroundColor: kProPanel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: Container(
        width: 680,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Row(children: [
              const Icon(Icons.folder_open_outlined,
                  color: kProAccent, size: 16),
              const SizedBox(width: 8),
              Text('Import ${_rows.length} Files',
                  style: proTitle(size: 14)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child:
                    const Icon(Icons.close, color: Colors.white38, size: 16),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              '각 파일의 형식과 채널을 확인한 뒤 Import All을 누르세요.',
              style: proSubtitle(size: 10),
            ),
            const SizedBox(height: 16),

            // File rows
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var i = 0; i < _rows.length; i++)
                      _FileMappingRow(
                        pending: _rows[i],
                        channels: widget.acoustic.driverChannels,
                        onTypeChanged: (t) =>
                            setState(() => _rows[i].fileType = t),
                        onChannelChanged: (ch) =>
                            setState(() => _rows[i].targetChannel = ch),
                      ),
                  ],
                ),
              ),
            ),

            if (hasDup) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.warning_amber_rounded,
                    color: kProAmber, size: 12),
                const SizedBox(width: 6),
                Text('같은 채널에 여러 파일이 할당됩니다.',
                    style: proSubtitle(
                        size: 10, color: kProAmber)),
              ]),
            ],

            const SizedBox(height: 16),
            Row(children: [
              _Btn(
                label: _importing ? 'Importing…' : 'Import All',
                onTap: (canImport && !hasDup) ? _importAll : null,
                color: kProAccent,
              ),
              const SizedBox(width: 10),
              Text(
                '${_rows.where((r) => r.targetChannel != null).length}/${_rows.length} 파일 매핑됨',
                style: proSubtitle(size: 10),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel',
                    style:
                        TextStyle(color: Colors.white38, fontSize: 11)),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ── Single row in the multi-file mapping dialog ───────────────────────────────

class _FileMappingRow extends StatelessWidget {
  final _PendingFile pending;
  final List<DriverChannel> channels;
  final ValueChanged<AcousticFileType> onTypeChanged;
  final ValueChanged<DriverChannel?> onChannelChanged;

  const _FileMappingRow({
    required this.pending,
    required this.channels,
    required this.onTypeChanged,
    required this.onChannelChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Parse preview (sync — no mutation).
    final result = pending.fileType == AcousticFileType.zma
        ? ProMeasurementParser.parseZma(
            fileName: pending.fileName, content: pending.content)
        : ProMeasurementParser.parseFrd(
            fileName: pending.fileName, content: pending.content);
    final ok = result.data != null;
    final statusColor = ok ? kProGreen : kProRed;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(children: [
        // Status dot
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
              color: statusColor, shape: BoxShape.circle),
        ),

        // Filename
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(pending.fileName,
                  style: proValue(size: 10, color: Colors.white70),
                  overflow: TextOverflow.ellipsis),
              if (ok)
                Text(
                  '${result.data!.pointCount} pts  '
                  '${result.data!.freqRangeLabel}',
                  style: proSubtitle(size: 9),
                )
              else
                Text(
                  result.errors.firstOrNull ?? '파싱 실패',
                  style: const TextStyle(color: kProRed, fontSize: 9),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),

        // Format selector
        SizedBox(
          width: 100,
          child: DropdownButton<AcousticFileType>(
            value: pending.fileType,
            dropdownColor: kProPanel,
            isExpanded: true,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
            underline: Container(height: 0.5, color: kProBorder),
            items: [
              AcousticFileType.frd,
              AcousticFileType.zma,
              AcousticFileType.txt,
            ]
                .map((t) => DropdownMenuItem(
                    value: t, child: Text(t.label)))
                .toList(),
            onChanged: (t) {
              if (t != null) onTypeChanged(t);
            },
          ),
        ),
        const SizedBox(width: 10),

        // Channel selector
        SizedBox(
          width: 150,
          child: DropdownButton<DriverChannel?>(
            value: pending.targetChannel,
            dropdownColor: kProPanel,
            isExpanded: true,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
            underline: Container(height: 0.5, color: kProBorder),
            hint: Text('채널 선택',
                style: proSubtitle(size: 10)),
            items: [
              const DropdownMenuItem<DriverChannel?>(
                  value: null, child: Text('— skip —')),
              ...channels.map((ch) => DropdownMenuItem(
                  value: ch, child: Text(ch.name))),
            ],
            onChanged: onChannelChanged,
          ),
        ),
      ]),
    );
  }
}

// ── Parse & Paste dialog (original, unchanged logic) ─────────────────────────

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
            Row(children: [
              const Icon(Icons.upload_file_outlined,
                  color: kProAccent, size: 16),
              const SizedBox(width: 8),
              Text('Paste & Parse Measurement Data',
                  style: proTitle(size: 14)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Icon(Icons.close,
                    color: Colors.white38, size: 16),
              ),
            ]),
            const SizedBox(height: 16),

            // File type selector
            Row(children: [
              Text('File type:', style: proLabel(size: 10)),
              const SizedBox(width: 10),
              ...[
                AcousticFileType.frd,
                AcousticFileType.zma,
                AcousticFileType.txt
              ].map((t) => Padding(
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

            _Field(
              label: 'File name (optional)',
              child: TextField(
                controller: _fileNameCtrl,
                style:
                    const TextStyle(color: Colors.white70, fontSize: 11),
                decoration: _inputDec('e.g. woofer_left.frd'),
              ),
            ),
            const SizedBox(height: 10),

            _Field(
              label: 'Paste file content',
              child: TextField(
                controller: _contentCtrl,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontFamily: 'monospace'),
                decoration: _inputDec(
                    '# Example FRD\n20    -3.2   180.0\n50     0.1    90.5\n...'),
                maxLines: 10,
              ),
            ),
            const SizedBox(height: 12),

            if (widget.acoustic.driverChannels.isNotEmpty) ...[
              Row(children: [
                Text('Assign to channel:', style: proLabel(size: 10)),
                const SizedBox(width: 10),
                DropdownButton<DriverChannel>(
                  value: _targetChannel,
                  dropdownColor: kProPanel,
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 11),
                  underline: Container(height: 0.5, color: kProBorder),
                  items: widget.acoustic.driverChannels
                      .map((ch) => DropdownMenuItem(
                            value: ch,
                            child: Text(ch.name),
                          ))
                      .toList(),
                  onChanged: (ch) => setState(() => _targetChannel = ch),
                ),
              ]),
              const SizedBox(height: 12),
            ],

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
                    style:
                        TextStyle(color: Colors.white38, fontSize: 11)),
              ),
            ]),

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
            borderSide:
                const BorderSide(color: kProBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(3),
            borderSide:
                const BorderSide(color: kProBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(3),
            borderSide:
                BorderSide(color: kProAccent.withValues(alpha: 0.5))),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      );
}

// ── Shared small widgets ──────────────────────────────────────────────────────

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
  const _Btn(
      {required this.label, required this.onTap, required this.color});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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

// ── Parse result preview panel ────────────────────────────────────────────────

class _ParseResultPanel extends StatelessWidget {
  final MeasurementParseResult result;
  const _ParseResultPanel({required this.result});

  Color get _statusColor => switch (result.status) {
        MeasurementParseStatus.parsed => kProGreen,
        MeasurementParseStatus.parsedWithWarnings => kProAmber,
        MeasurementParseStatus.failed => kProRed,
        MeasurementParseStatus.unsupported => kProRed,
        MeasurementParseStatus.notParsed => Colors.white24,
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
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Row(children: [
          ProStatusPill(
              label: result.status.label, color: _statusColor),
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
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                  const Icon(Icons.error_outline,
                      size: 10, color: kProRed),
                  const SizedBox(width: 5),
                  Expanded(
                      child: Text(e,
                          style: const TextStyle(
                              color: kProRed, fontSize: 9))),
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
        padding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                color: warn ? kProAmber : kProAccent, fontSize: 9)),
      );
}

// ── Driver data card (unchanged display logic) ────────────────────────────────

class _DriverDataCard extends StatelessWidget {
  final DriverChannel channel;
  final VoidCallback onRemoveFrd;
  final VoidCallback onRemoveZma;
  final VoidCallback onAddRepeatSweep;
  final void Function(int) onRemoveRepeatSweep;

  const _DriverDataCard({
    required this.channel,
    required this.onRemoveFrd,
    required this.onRemoveZma,
    required this.onAddRepeatSweep,
    required this.onRemoveRepeatSweep,
  });

  Color _statusColor(MeasurementStatus s) => switch (s) {
        MeasurementStatus.validated => kProGreen,
        MeasurementStatus.imported => kProAccent,
        MeasurementStatus.needsReview => kProAmber,
        MeasurementStatus.missingFile => kProRed,
        MeasurementStatus.empty => const Color(0xFF6B7280),
      };

  @override
  Widget build(BuildContext context) {
    final frd = channel.frdData;
    final zma = channel.zmaData;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Row(children: [
          if (channel.dspOutputIndex != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text('OUT ${channel.dspOutputIndex}',
                  style: proLabel(
                      size: 9,
                      color: Colors.white24,
                      spacing: 1)),
            ),
          Text(channel.name, style: proTitle(size: 12)),
          const SizedBox(width: 8),
          Text(channel.shortLabel,
              style: proLabel(
                  size: 9, color: Colors.white38, spacing: 0.5)),
          const Spacer(),
          ProStatusPill(
            label: channel.measurementStatus.label,
            color: _statusColor(channel.measurementStatus),
          ),
        ]),
        const SizedBox(height: 10),
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
        if (channel.hasParsedFrd) ...[
          const SizedBox(height: 10),
          _RepeatSweepsSection(
            sweeps: channel.additionalFrdSweeps,
            onAdd: onAddRepeatSweep,
            onRemove: onRemoveRepeatSweep,
          ),
        ],
      ]),
    );
  }
}

// ── Repeat sweeps section (inside DriverDataCard) ─────────────────────────────

class _RepeatSweepsSection extends StatelessWidget {
  final List<FrdSweepEntry> sweeps;
  final VoidCallback onAdd;
  final void Function(int) onRemove;

  const _RepeatSweepsSection({
    required this.sweeps,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(
            sweeps.isEmpty
                ? 'REPEAT SWEEPS'
                : 'REPEAT SWEEPS (${sweeps.length})',
            style: proLabel(size: 8, spacing: 1.2),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onAdd,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.add, color: kProAccent, size: 11),
              const SizedBox(width: 3),
              Text('Add Repeat Sweep',
                  style: TextStyle(
                      color: kProAccent.withValues(alpha: 0.8), fontSize: 9)),
            ]),
          ),
        ]),
        if (sweeps.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (var i = 0; i < sweeps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(children: [
                const Icon(Icons.fiber_manual_record,
                    color: kProAccent, size: 6),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    sweeps[i].fileName,
                    style: proValue(size: 9, color: Colors.white60),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () => onRemove(i),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.close,
                        color: Colors.white24, size: 11),
                  ),
                ),
              ]),
            ),
        ] else ...[
          const SizedBox(height: 4),
          Text(
            'Add a second measurement of the same driver to enable repeatability scoring.',
            style: proSubtitle(size: 9),
          ),
        ],
      ],
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
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: hasData
            ? color.withValues(alpha: 0.06)
            : Colors.transparent,
        border: Border.all(
            color:
                hasData ? color.withValues(alpha: 0.3) : kProBorder),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
          Text(
              '${data!.freqRangeLabel}  ·  ${data!.pointCount} pts',
              style: proSubtitle(size: 9)),
          const SizedBox(height: 2),
          Wrap(spacing: 4, children: [
            if (data!.hasMagnitude) _MiniChip('Mag', color),
            if (data!.hasPhase) _MiniChip('Phase', color),
            if (data!.hasImpedance)
              const _MiniChip('Z', kProAmber),
            if (!data!.hasPhase && !data!.hasImpedance)
              const _MiniChip('No phase', kProAmber),
          ]),
          if (fileRef?.parseStatus ==
              MeasurementParseStatus.parsedWithWarnings)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded,
                    size: 9, color: kProAmber),
                SizedBox(width: 4),
                Text('Parsed with warnings',
                    style: TextStyle(
                        color: kProAmber, fontSize: 9)),
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
        padding:
            const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontSize: 8,
                letterSpacing: 0.3)),
      );
}

// ── Static cards ──────────────────────────────────────────────────────────────

class _FormatsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: kProSurface,
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text('SUPPORTED FORMATS',
              style: proLabel(size: 9, spacing: 1.8)),
          const SizedBox(height: 10),
          const Wrap(spacing: 8, runSpacing: 6, children: [
            _FormatChip(ext: '.frd', desc: 'SPL freq magnitude [phase]'),
            _FormatChip(ext: '.zma', desc: 'Impedance freq Ω [phase]'),
            _FormatChip(ext: '.txt', desc: 'REW / ARTA plain text export'),
            _FormatChip(ext: '.csv', desc: 'Comma-separated (parsed as FRD)'),
          ]),
          const SizedBox(height: 10),
          Text(
            'Whitespace or comma delimited. '
            'Lines starting with #  *  ;  // are treated as comments.',
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
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: kProAccent.withValues(alpha: 0.08),
          border:
              Border.all(color: kProAccent.withValues(alpha: 0.25)),
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
  final VoidCallback onPickFiles;
  final VoidCallback onPaste;
  const _ImportActionCard({required this.onPickFiles, required this.onPaste});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: kProSurface,
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text('IMPORT', style: proLabel(size: 9, spacing: 1.8)),
          const SizedBox(height: 12),
          Row(children: [
            // Primary: file picker
            GestureDetector(
              onTap: onPickFiles,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: kProAccent.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(4),
                  color: kProAccent.withValues(alpha: 0.06),
                ),
                child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  Icon(Icons.folder_open_outlined,
                      color: kProAccent, size: 14),
                  SizedBox(width: 8),
                  Text('Open FRD / ZMA Files…',
                      style: TextStyle(
                          color: kProAccent,
                          fontSize: 11,
                          letterSpacing: 0.3)),
                ]),
              ),
            ),
            const SizedBox(width: 10),
            // Secondary: paste
            GestureDetector(
              onTap: onPaste,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: kProBorder),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  Icon(Icons.content_paste_outlined,
                      color: Colors.white38, size: 13),
                  SizedBox(width: 7),
                  Text('Paste & Parse…',
                      style: TextStyle(
                          color: Colors.white38, fontSize: 11)),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Text(
            'Select .frd / .zma / .txt / .csv files, or drag and drop them '
            'anywhere on this screen.',
            style: proSubtitle(size: 10),
          ),
        ]),
      );
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onPickFiles;
  const _EmptyState({required this.onPickFiles});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onPickFiles,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            border: Border.all(
                color: kProBorder, style: BorderStyle.solid),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(children: [
            const Icon(Icons.upload_file_outlined,
                color: Colors.white12, size: 28),
            const SizedBox(height: 12),
            Text('No FRD / ZMA data imported',
                style:
                    proTitle(size: 12, color: Colors.white38)),
            const SizedBox(height: 6),
            Text(
              'Click here or drag files to import measurement data.\n'
              'Simulation will use placeholder driver curves until FRD is imported.',
              style: proSubtitle(size: 10),
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      );
}
