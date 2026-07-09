// ── Export Tab — Phase H/I/K/P ────────────────────────────────────────────────
// DSP Export Architecture Foundation.
// No hardware write. No USBi. No SafeLoad. No register addresses.
// AI suggests. Expert verifies. AOS protects. DSP executes.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/pro_project.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_protection_data.dart';
import '../../../core/pro_export_data.dart';
import '../../../core/pro_export_engine.dart';
import '../../../core/pro_dsp_target_data.dart';
import '../../../core/pro_dsp_address_registry.dart';
import '../../../core/pro_sigma_mapping_data.dart';
import '../../../shared/pro_widgets.dart';

class ExportTab extends ConsumerStatefulWidget {
  final String projectId;
  const ExportTab({super.key, required this.projectId});

  @override
  ConsumerState<ExportTab> createState() => _ExportTabState();
}

class _ExportTabState extends ConsumerState<ExportTab> {
  bool _generating = false;

  ProProject? get _project => ref
      .read(proProjectStoreProvider)
      .projects
      .where((p) => p.id == widget.projectId)
      .firstOrNull;

  Future<void> _generate() async {
    final project = _project;
    if (project == null) return;
    setState(() => _generating = true);
    await Future.delayed(const Duration(milliseconds: 80));

    final pkg = generateDspExportDraft(project: project);
    final exportState = project.exportState;
    final updated = exportState.copyWith(
      packages: [...exportState.packages, pkg],
      activePackageId: pkg.id,
      revision: exportState.revision + 1,
    );

    await ref
        .read(proProjectStoreProvider.notifier)
        .updateExportState(widget.projectId, updated);

    if (mounted) setState(() => _generating = false);
  }

  Future<void> _setTarget(DspTargetPlatform target) async {
    final project = _project;
    if (project == null) return;
    await ref.read(proProjectStoreProvider.notifier).updateExportState(
          widget.projectId,
          project.exportState.copyWith(selectedTarget: target),
        );
  }

  Future<void> _setFormat(ExportFormat format) async {
    final project = _project;
    if (project == null) return;
    await ref.read(proProjectStoreProvider.notifier).updateExportState(
          widget.projectId,
          project.exportState.copyWith(selectedFormat: format),
        );
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(proProjectStoreProvider)
        .projects
        .where((p) => p.id == widget.projectId)
        .firstOrNull;
    final exportState = project?.exportState ?? ExportProjectState.createDefault();
    final protection = project?.protectionState ?? ProtectionProjectState.createDefault();
    final activePkg = exportState.activePackage;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Icon(Icons.upload_outlined,
              color: kProAccent.withValues(alpha: 0.6), size: 18),
          const SizedBox(width: 10),
          Text('DSP Export', style: proTitle(size: 16)),
          const Spacer(),
          if (exportState.packageCount > 0)
            Text('${exportState.packageCount} package(s)',
                style: proLabel(size: 9, color: Colors.white38, spacing: 0.5)),
        ]),
        const SizedBox(height: 4),
        Text('Draft export packages for DSP implementation. '
            'Hardware write is not enabled yet.',
            style: proSubtitle()),
        const SizedBox(height: 20),

        // Target selector
        _SelectorSection(
          label: 'DSP TARGET',
          children: DspTargetPlatform.values.map((t) => _Chip(
            label: t.label,
            selected: exportState.selectedTarget == t,
            onTap: () => _setTarget(t),
          )).toList(),
        ),
        const SizedBox(height: 12),

        // Format selector
        _SelectorSection(
          label: 'EXPORT FORMAT',
          children: ExportFormat.values.map((f) => _Chip(
            label: f.label,
            selected: exportState.selectedFormat == f,
            onTap: () => _setFormat(f),
          )).toList(),
        ),
        const SizedBox(height: 20),

        // Protection gate
        _ProtectionGateSummary(protection: protection),
        const SizedBox(height: 16),

        // Generate button
        GestureDetector(
          onTap: _generating ? null : _generate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: _generating
                  ? kProSurface
                  : kProAccent.withValues(alpha: 0.08),
              border: Border.all(
                  color: _generating
                      ? kProBorder
                      : kProAccent.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                _generating
                    ? Icons.hourglass_empty_outlined
                    : Icons.play_arrow_outlined,
                color: _generating ? Colors.white24 : kProAccent,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                _generating ? 'Generating...' : 'Generate Export Draft',
                style: TextStyle(
                    color: _generating ? Colors.white24 : kProAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 20),

        // DSP Target Profile (Phase I) — always shown based on selection
        _TargetProfilePanel(
          profile: DspTargetProfile.forPlatform(exportState.selectedTarget),
        ),
        const SizedBox(height: 16),

        // Active package
        if (activePkg != null) ...[
          _PackageSummary(pkg: activePkg),
          const SizedBox(height: 16),

          // Channel map
          if (activePkg.channelMaps.isNotEmpty) ...[
            Text('CHANNEL MAP', style: proLabel(size: 9, spacing: 2)),
            const SizedBox(height: 8),
            _ChannelMapCard(maps: activePkg.channelMaps),
            const SizedBox(height: 16),
          ],

          // Parameter blocks
          if (activePkg.parameterBlocks.isNotEmpty) ...[
            Text('PARAMETER BLOCKS (${activePkg.blockCount})',
                style: proLabel(size: 9, spacing: 2)),
            const SizedBox(height: 8),
            ...activePkg.parameterBlocks.map(
                (b) => _ParameterBlockCard(block: b)),
            const SizedBox(height: 16),
          ],

          // Implementation Draft (Phase I)
          if (activePkg.implementationDraftJson != null) ...[
            _ImplementationDraftPanel(
              draft: DspImplementationDraft.fromJson(
                  activePkg.implementationDraftJson!),
            ),
            const SizedBox(height: 16),
          ],

          // Phase P: Verified Address Registry
          _VerifiedAddressRegistryPanel(
            registryJson: activePkg.addressRegistrySnapshotJson,
          ),
          const SizedBox(height: 16),

          // Phase P: SigmaStudio Mapping Reference
          if (activePkg.sigmaMappingReferenceJson != null) ...[
            _SigmaMappingPanel(
              mappingRef: SigmaMappingReference.fromJson(
                  activePkg.sigmaMappingReferenceJson!),
            ),
            const SizedBox(height: 16),
          ],

          // Phase P: Fixed-Point Draft
          if (activePkg.fixedPointDraftJson != null) ...[
            _FixedPointDraftPanel(draftJson: activePkg.fixedPointDraftJson!),
            const SizedBox(height: 16),
          ],

          // JSON preview
          _JsonPreviewCard(pkg: activePkg),
        ] else
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: kProSurface,
              border: Border.all(color: kProBorder),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, color: Colors.white24, size: 13),
              const SizedBox(width: 10),
              Text('Generate an export draft to preview the DSP parameter structure.',
                  style: proSubtitle()),
            ]),
          ),
      ]),
    );
  }
}

// ── Selector Section ──────────────────────────────────────────────────────────

class _SelectorSection extends StatelessWidget {
  final String label;
  final List<Widget> children;
  const _SelectorSection({required this.label, required this.children});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: proLabel(size: 9, spacing: 2)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 6, children: children),
    ],
  );
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? kProAccent.withValues(alpha: 0.1) : Colors.transparent,
        border: Border.all(
            color: selected
                ? kProAccent.withValues(alpha: 0.5)
                : kProBorder),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(label,
          style: TextStyle(
              color: selected ? kProAccent : Colors.white38,
              fontSize: 10,
              fontWeight: selected ? FontWeight.w500 : FontWeight.normal)),
    ),
  );
}

// ── Protection Gate Summary ───────────────────────────────────────────────────

class _ProtectionGateSummary extends StatelessWidget {
  final ProtectionProjectState protection;
  const _ProtectionGateSummary({required this.protection});

  Color _statusColor() => switch (protection.verificationStatus) {
    VerificationStatus.passed             => kProGreen,
    VerificationStatus.passedWithWarnings => kProAmber,
    VerificationStatus.failed             => kProRed,
    VerificationStatus.notReady           => const Color(0xFF6B7280),
  };

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('PROTECTION GATE', style: proLabel(size: 9, spacing: 2)),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 8, children: [
        _StatChip(
          label: 'STATUS',
          value: protection.verificationStatus.label,
          color: _statusColor(),
        ),
        _StatChip(
          label: 'EXPORT',
          value: protection.exportLocked ? 'Locked' : 'Allowed',
          color: protection.exportLocked ? kProRed : kProGreen,
        ),
        _StatChip(
          label: 'WARNINGS',
          value: '${protection.warningCount}',
          color: protection.warningCount > 0 ? kProAmber : Colors.white38,
        ),
        _StatChip(
          label: 'CRITICAL',
          value: '${protection.criticalCount}',
          color: protection.criticalCount > 0 ? kProRed : Colors.white38,
        ),
      ]),
    ]),
  );
}

// ── Package Summary ───────────────────────────────────────────────────────────

class _PackageSummary extends StatelessWidget {
  final DspExportPackage pkg;
  const _PackageSummary({required this.pkg});

  Color _statusColor() => switch (pkg.status) {
    ExportStatus.draftReady => kProGreen,
    ExportStatus.blocked    => kProRed,
    ExportStatus.exported   => kProAccent,
    ExportStatus.notReady   => Colors.white38,
  };

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(
          color: pkg.isBlocked
              ? kProRed.withValues(alpha: 0.3)
              : pkg.isDraftReady
                  ? kProGreen.withValues(alpha: 0.2)
                  : kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('ACTIVE PACKAGE', style: proLabel(size: 9, spacing: 2)),
        const Spacer(),
        ProStatusPill(label: pkg.status.label, color: _statusColor()),
      ]),
      const SizedBox(height: 10),

      if (pkg.isBlocked && pkg.blockedReason != null) ...[
        Row(children: [
          const Icon(Icons.block_outlined, color: kProRed, size: 13),
          const SizedBox(width: 8),
          Expanded(
            child: Text(pkg.blockedReason!,
                style: proSubtitle(size: 10, color: kProRed.withValues(alpha: 0.8))),
          ),
        ]),
        const SizedBox(height: 10),
      ],

      Wrap(spacing: 10, runSpacing: 8, children: [
        _StatChip(label: 'TARGET', value: pkg.targetPlatform.label),
        _StatChip(label: 'FORMAT', value: pkg.format.label),
        _StatChip(label: 'BLOCKS', value: '${pkg.blockCount}'),
        _StatChip(label: 'CHANNELS', value: '${pkg.channelMaps.length}'),
        _StatChip(
          label: 'WARNINGS',
          value: '${pkg.warningCount}',
          color: pkg.warningCount > 0 ? kProAmber : null,
        ),
      ]),

      const SizedBox(height: 8),
      Text(
        'Created: ${_fmt(pkg.createdAt)}  ·  '
        'Tuning rev ${pkg.tuningRevision}  ·  '
        'Protection rev ${pkg.protectionRevision}',
        style: proLabel(size: 9, color: Colors.white24, spacing: 0.2),
      ),

      if (pkg.warnings.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text('WARNINGS', style: proLabel(size: 9, spacing: 1.5)),
        const SizedBox(height: 6),
        ...pkg.warnings.map((w) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.warning_amber_outlined,
                color: kProAmber, size: 12),
            const SizedBox(width: 6),
            Expanded(child: Text(w, style: proSubtitle(size: 10))),
          ]),
        )),
      ],
    ]),
  );

  String _fmt(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

// ── Channel Map Card ──────────────────────────────────────────────────────────

class _ChannelMapCard extends StatelessWidget {
  final List<ExportChannelMap> maps;
  const _ChannelMapCard({required this.maps});

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
      children: maps.map((m) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(
            width: 80,
            child: Text(m.channelId,
                style: proValue(size: 10, color: kProAccent)),
          ),
          SizedBox(
            width: 80,
            child: Text(m.logicalName, style: proSubtitle(size: 10)),
          ),
          SizedBox(
            width: 70,
            child: Text(m.role.toUpperCase(),
                style: proLabel(size: 8, color: Colors.white38, spacing: 0.5)),
          ),
          Text(m.side,
              style: proLabel(size: 8, color: Colors.white24, spacing: 0.3)),
          if (m.outputIndex != null) ...[
            const SizedBox(width: 12),
            Text('out ${m.outputIndex}',
                style: proLabel(size: 8, color: Colors.white24, spacing: 0.2)),
          ],
        ]),
      )).toList(),
    ),
  );
}

// ── Parameter Block Card ──────────────────────────────────────────────────────

class _ParameterBlockCard extends StatelessWidget {
  final ExportParameterBlock block;
  const _ParameterBlockCard({required this.block});

  Color _typeColor() => switch (block.type) {
    ExportBlockType.peq        => kProAccent,
    ExportBlockType.crossover  => const Color(0xFFB47FFF),
    ExportBlockType.gain       => kProGreen,
    ExportBlockType.delay      => kProAmber,
    ExportBlockType.phase      => const Color(0xFF4DD9E8),
    ExportBlockType.protection => kProRed,
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
        width: 3,
        height: 32,
        decoration: BoxDecoration(
          color: _typeColor().withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(block.title, style: proTitle(size: 11)),
            const SizedBox(width: 8),
            ProStatusPill(label: block.type.label, color: _typeColor()),
            if (block.channelId.isNotEmpty && block.channelId != 'system') ...[
              const SizedBox(width: 6),
              Text('ch: ${block.channelId}',
                  style: proLabel(size: 8, color: Colors.white24, spacing: 0.3)),
            ],
          ]),
          const SizedBox(height: 3),
          Text(block.summary, style: proSubtitle(size: 10)),
          if (block.warning != null) ...[
            const SizedBox(height: 4),
            Text('⚠ ${block.warning}',
                style: proSubtitle(size: 9, color: kProAmber)),
          ],
        ]),
      ),
    ]),
  );
}

// ── JSON Preview Card ─────────────────────────────────────────────────────────

class _JsonPreviewCard extends StatefulWidget {
  final DspExportPackage pkg;
  const _JsonPreviewCard({required this.pkg});

  @override
  State<_JsonPreviewCard> createState() => _JsonPreviewCardState();
}

class _JsonPreviewCardState extends State<_JsonPreviewCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    const encoder = JsonEncoder.withIndent('  ');
    // Compact preview: top-level keys only + first 40 chars of values
    final full = widget.pkg.toJson();
    final preview = {
      'id': full['id'],
      'status': full['status'],
      'targetPlatform': full['targetPlatform'],
      'format': full['format'],
      'projectName': full['projectName'],
      'tuningRevision': full['tuningRevision'],
      'protectionRevision': full['protectionRevision'],
      'channelMaps': '[ ${widget.pkg.channelMaps.length} channels ]',
      'parameterBlocks': '[ ${widget.pkg.blockCount} blocks ]',
      'warnings': widget.pkg.warnings,
      if (full['blockedReason'] != null) 'blockedReason': full['blockedReason'],
    };
    final previewJson = encoder.convert(preview);
    final fullJson = encoder.convert(full);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('JSON PREVIEW', style: proLabel(size: 9, spacing: 2)),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Text(
              _expanded ? 'Collapse' : 'Show full',
              style: TextStyle(
                  color: kProAccent.withValues(alpha: 0.7),
                  fontSize: 10),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: kProBg,
            border: Border.all(color: kProBorder),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            _expanded ? fullJson : previewJson,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 9,
              color: Color(0xFF9CA3AF),
              height: 1.5,
            ),
            maxLines: _expanded ? null : 30,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.fade,
          ),
        ),
      ]),
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _StatChip({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: kProBg,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: proLabel(size: 9)),
      const SizedBox(height: 4),
      Text(value,
          style: proValue(size: 12, color: color ?? Colors.white70)),
    ]),
  );
}

// ── Phase I: DSP Target Profile Panel ────────────────────────────────────────

class _TargetProfilePanel extends StatelessWidget {
  final DspTargetProfile profile;
  const _TargetProfilePanel({required this.profile});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('DSP TARGET PROFILE', style: proLabel(size: 9, spacing: 2)),
      const SizedBox(height: 10),

      Wrap(spacing: 10, runSpacing: 8, children: [
        _StatChip(label: 'TARGET', value: profile.displayName),
        _StatChip(label: 'PRECISION', value: profile.precision.label),
        _StatChip(label: 'MAX CHANNELS', value: '${profile.maxChannels}'),
        _StatChip(label: 'MAX PEQ/CH', value: '${profile.maxPeqBandsPerChannel}'),
        _StatChip(label: 'SAMPLE RATES', value: profile.sampleRateLabel),
      ]),
      const SizedBox(height: 12),

      Text('CAPABILITIES', style: proLabel(size: 9, spacing: 1.5)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6,
        children: profile.capabilities.map((c) => ProStatusPill(
          label: c.type.label,
          color: c.supported ? kProGreen : Colors.white24,
        )).toList(),
      ),

      if (profile.warning != null) ...[
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.warning_amber_outlined, color: kProAmber, size: 12),
          const SizedBox(width: 6),
          Expanded(
            child: Text(profile.warning!,
                style: proSubtitle(size: 9, color: kProAmber)),
          ),
        ]),
      ],

      if (profile.notes != null) ...[
        const SizedBox(height: 6),
        Text(profile.notes!,
            style: proLabel(size: 9, color: Colors.white24, spacing: 0.2)),
      ],
    ]),
  );
}

// ── Phase I: Implementation Draft Panel ──────────────────────────────────────

class _ImplementationDraftPanel extends StatefulWidget {
  final DspImplementationDraft draft;
  const _ImplementationDraftPanel({required this.draft});

  @override
  State<_ImplementationDraftPanel> createState() =>
      _ImplementationDraftPanelState();
}

class _ImplementationDraftPanelState extends State<_ImplementationDraftPanel> {
  bool _showAllStages = false;

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    const previewCount = 6;
    final stages = _showAllStages
        ? draft.biquadStages
        : draft.biquadStages.take(previewCount).toList();

    final calcCount = draft.calculatedCount;
    final phCount = draft.placeholderCount;
    final verCount = draft.requiresVerificationCount;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('IMPLEMENTATION DRAFT', style: proLabel(size: 9, spacing: 2)),
          const Spacer(),
          Text(draft.readinessLabel,
              style: proLabel(size: 9, color: Colors.white38, spacing: 0.3)),
        ]),
        const SizedBox(height: 10),

        Wrap(spacing: 10, runSpacing: 8, children: [
          _StatChip(label: 'PARAM SLOTS', value: '${draft.slotCount}'),
          _StatChip(label: 'BIQUAD STAGES', value: '${draft.stageCount}'),
          if (calcCount > 0)
            _StatChip(label: 'CALCULATED', value: '$calcCount',
                color: kProGreen),
          if (phCount > 0)
            _StatChip(label: 'PLACEHOLDER', value: '$phCount',
                color: kProAmber),
          if (verCount > 0)
            _StatChip(label: 'NEEDS VERIFY', value: '$verCount',
                color: kProRed),
        ]),

        // XO cascade summary (Phase K)
        if (_hasXoCascadeStages(draft)) ...[
          const SizedBox(height: 10),
          _XoCascadeSummary(draft: draft),
        ],

        const SizedBox(height: 8),
        const Row(children: [
          Icon(Icons.warning_amber_outlined, color: kProAmber, size: 11),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'Floating-point draft only. Not hardware-ready. '
              'Not ADAU fixed-point. No hardware address.',
              style: TextStyle(
                  fontSize: 9, color: kProAmber,
                  fontFamily: 'monospace'),
            ),
          ),
        ]),

        if (draft.warnings.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...draft.warnings.map((w) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline, color: Colors.white24, size: 11),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(w, style: proSubtitle(size: 9,
                      color: Colors.white38))),
            ]),
          )),
        ],

        if (draft.biquadStages.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('BIQUAD STAGES', style: proLabel(size: 9, spacing: 1.5)),
          const SizedBox(height: 6),
          ...stages.map((s) => _BiquadStageRow(stage: s)),
          if (draft.biquadStages.length > previewCount) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => setState(() => _showAllStages = !_showAllStages),
              child: Text(
                _showAllStages
                    ? 'Show fewer'
                    : 'Show all ${draft.biquadStages.length} stages',
                style: TextStyle(
                    color: kProAccent.withValues(alpha: 0.7), fontSize: 10),
              ),
            ),
          ],
        ],
      ]),
    );
  }

  bool _hasXoCascadeStages(DspImplementationDraft draft) =>
      draft.biquadStages.any((s) =>
          s.title.contains('HPF') || s.title.contains('LPF'));
}

class _XoCascadeSummary extends StatelessWidget {
  final DspImplementationDraft draft;
  const _XoCascadeSummary({required this.draft});

  @override
  Widget build(BuildContext context) {
    final xoStages = draft.biquadStages
        .where((s) => s.title.contains('HPF') || s.title.contains('LPF'))
        .toList();
    final calcXo =
        xoStages.where((s) =>
            s.coefficients.status == BiquadDraftStatus.calculatedDraft).length;
    final verifyXo =
        xoStages.where((s) =>
            s.coefficients.status == BiquadDraftStatus.requiresVerification ||
            s.coefficients.status == BiquadDraftStatus.placeholder).length;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: kProBg,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.filter_alt_outlined,
              size: 11, color: Color(0xFF4A9EFF)),
          const SizedBox(width: 6),
          Text('XO CASCADE', style: proLabel(size: 9, spacing: 1.5)),
          const Spacer(),
          Text('${xoStages.length} stage(s)',
              style: proLabel(size: 9, color: Colors.white38, spacing: 0.3)),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: [
          if (calcXo > 0)
            ProStatusPill(label: '$calcXo Calculated Draft', color: kProGreen),
          if (verifyXo > 0)
            ProStatusPill(label: '$verifyXo Requires Verify', color: kProAmber),
        ]),
        const SizedBox(height: 6),
        const Text(
          'Requires acoustic verification. '
          'Draft cascade does not imply final acoustic summation correctness.',
          style: TextStyle(
              fontSize: 9, color: Colors.white38, fontFamily: 'monospace'),
        ),
      ]),
    );
  }
}

class _BiquadStageRow extends StatefulWidget {
  final BiquadDraftStage stage;
  const _BiquadStageRow({required this.stage});

  @override
  State<_BiquadStageRow> createState() => _BiquadStageRowState();
}

class _BiquadStageRowState extends State<_BiquadStageRow> {
  bool _expanded = false;

  Color _statusColor(BiquadDraftStatus s) => switch (s) {
    BiquadDraftStatus.calculatedDraft      => kProGreen,
    BiquadDraftStatus.placeholder          => kProAmber,
    BiquadDraftStatus.requiresVerification => kProRed,
    BiquadDraftStatus.notRequired          => Colors.white24,
  };

  @override
  Widget build(BuildContext context) {
    final c = widget.stage.coefficients;
    final isCalculated = c.status == BiquadDraftStatus.calculatedDraft;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: kProBg,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: isCalculated
              ? () => setState(() => _expanded = !_expanded)
              : null,
          borderRadius: BorderRadius.circular(3),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(widget.stage.title, style: proTitle(size: 10)),
                  const SizedBox(height: 2),
                  Text(widget.stage.filterSummary,
                      style: proLabel(size: 9,
                          color: Colors.white38, spacing: 0.2)),
                ]),
              ),
              const SizedBox(width: 8),
              ProStatusPill(
                label: c.status.label,
                color: _statusColor(c.status),
              ),
              if (isCalculated) ...[
                const SizedBox(width: 6),
                Icon(
                  _expanded
                      ? Icons.expand_less
                      : Icons.expand_more,
                  color: Colors.white24,
                  size: 14,
                ),
              ],
            ]),
          ),
        ),

        if (_expanded && isCalculated) ...[
          const Divider(height: 1, thickness: 1, color: Color(0xFF2A2A2A)),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              _CoeffRow('b0', c.b0),
              _CoeffRow('b1', c.b1),
              _CoeffRow('b2', c.b2),
              _CoeffRow('a1', c.a1),
              _CoeffRow('a2', c.a2),
              const SizedBox(height: 4),
              Text(
                'Floating-point  ·  a0 normalized to 1.0  ·  '
                'Not ADAU fixed-point',
                style: proLabel(size: 8, color: Colors.white24, spacing: 0.2),
              ),
              if (c.warning != null) ...[
                const SizedBox(height: 4),
                Text(c.warning!,
                    style: proSubtitle(size: 9, color: Colors.white38)),
              ],
            ]),
          ),
        ],
      ]),
    );
  }
}

class _CoeffRow extends StatelessWidget {
  final String name;
  final double value;
  const _CoeffRow(this.name, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1.5),
    child: Row(children: [
      SizedBox(
        width: 24,
        child: Text(name,
            style: proLabel(size: 9,
                color: Colors.white38, spacing: 0.5)),
      ),
      Text(
        value.toStringAsFixed(8),
        style: const TextStyle(
            fontSize: 10,
            color: Colors.white70,
            fontFamily: 'monospace'),
      ),
    ]),
  );
}

// ── Phase P: Verified Address Registry Panel ──────────────────────────────────

class _VerifiedAddressRegistryPanel extends StatelessWidget {
  final Map<String, dynamic>? registryJson;
  const _VerifiedAddressRegistryPanel({required this.registryJson});

  @override
  Widget build(BuildContext context) {
    final registry = registryJson != null
        ? DspAddressRegistry.fromJson(registryJson!)
        : DspAddressRegistry.createDefault();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.verified_outlined, color: Color(0xFF4A9EFF), size: 13),
          const SizedBox(width: 8),
          Text('VERIFIED ADDRESS REGISTRY', style: proLabel(size: 9, spacing: 2)),
          const Spacer(),
          _InfoChip('${registry.verifiedCount} verified',
              const Color(0xFF4A9EFF)),
        ]),
        const SizedBox(height: 10),
        ...registry.addresses.map((addr) => _AddressRow(addr: addr)),
        const SizedBox(height: 8),
        Text(
          'Verified addresses are references only. '
          'Hardware write remains disabled.',
          style: proSubtitle(size: 9),
        ),
      ]),
    );
  }
}

class _AddressRow extends StatelessWidget {
  final VerifiedDspAddress addr;
  const _AddressRow({required this.addr});

  @override
  Widget build(BuildContext context) {
    final isVerified =
        addr.verificationStatus == DspAddressVerificationStatus.verified;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Container(
          width: 6, height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isVerified ? const Color(0xFF4A9EFF) : Colors.white24,
          ),
        ),
        const SizedBox(width: 8),
        Text(addr.platform.label,
            style: proLabel(size: 9, color: Colors.white38, spacing: 0)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(addr.logicalName,
              style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ),
        Text(addr.addressHex,
            style: const TextStyle(
                color: Color(0xFF4A9EFF),
                fontSize: 10,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Text(addr.source.label,
            style: proSubtitle(size: 9)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: isVerified
                ? const Color(0xFF4A9EFF).withValues(alpha: 0.12)
                : kProSurface,
            border: Border.all(
                color: isVerified
                    ? const Color(0xFF4A9EFF).withValues(alpha: 0.4)
                    : kProBorder),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(addr.verificationStatus.label,
              style: TextStyle(
                  fontSize: 9,
                  color: isVerified ? const Color(0xFF4A9EFF) : Colors.white38)),
        ),
      ]),
    );
  }
}

// ── Phase P: SigmaStudio Mapping Reference Panel ──────────────────────────────

class _SigmaMappingPanel extends StatelessWidget {
  final SigmaMappingReference mappingRef;
  const _SigmaMappingPanel({required this.mappingRef});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.map_outlined, color: Color(0xFFFBBF24), size: 13),
          const SizedBox(width: 8),
          Text('SIGMASTUDIO MAPPING REFERENCE',
              style: proLabel(size: 9, spacing: 2)),
          const Spacer(),
          _InfoChip(mappingRef.status.label, const Color(0xFFFBBF24)),
        ]),
        const SizedBox(height: 4),
        Text(mappingRef.summary, style: proSubtitle(size: 9)),
        const SizedBox(height: 10),
        Row(children: [
          _InfoChip('${mappingRef.mappedCount} mapped', Colors.white38),
          const SizedBox(width: 6),
          _InfoChip('${mappingRef.verifiedMappedCount} verified',
              const Color(0xFF4A9EFF)),
          const SizedBox(width: 6),
          _InfoChip('${mappingRef.requiresCaptureCount} need capture',
              const Color(0xFFFBBF24)),
        ]),
        const SizedBox(height: 10),
        ...mappingRef.mappings.map((m) => _MappingRow(mapping: m)),
        if (mappingRef.warnings.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...mappingRef.warnings.map((w) => Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('⚠ ', style: TextStyle(fontSize: 9, color: Color(0xFFFBBF24))),
              Expanded(child: Text(w, style: proSubtitle(size: 9))),
            ]),
          )),
        ],
      ]),
    );
  }
}

class _MappingRow extends StatelessWidget {
  final SigmaParameterMapping mapping;
  const _MappingRow({required this.mapping});

  @override
  Widget build(BuildContext context) {
    final isVerified = mapping.mappingStatus == SigmaMappingStatus.mappedVerified;
    final needsCapture = mapping.mappingStatus == SigmaMappingStatus.requiresCapture;
    final statusColor = isVerified
        ? const Color(0xFF4A9EFF)
        : needsCapture
            ? const Color(0xFFFBBF24)
            : Colors.white38;

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(children: [
        Text(mapping.blockKind.label,
            style: proLabel(size: 9, color: Colors.white38, spacing: 0)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(mapping.logicalName,
              style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ),
        if (mapping.addressHex != null) ...[
          Text(mapping.addressHex!,
              style: const TextStyle(
                  color: Color(0xFF4A9EFF),
                  fontSize: 10,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            border: Border.all(color: statusColor.withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            isVerified ? 'Verified' : needsCapture ? 'Capture needed' : 'Unverified',
            style: TextStyle(fontSize: 9, color: statusColor),
          ),
        ),
      ]),
    );
  }
}

// ── Phase P: Fixed-Point Draft Panel ─────────────────────────────────────────

class _FixedPointDraftPanel extends StatelessWidget {
  final Map<String, dynamic> draftJson;
  const _FixedPointDraftPanel({required this.draftJson});

  @override
  Widget build(BuildContext context) {
    final stageCount = draftJson['stageCount'] as int? ?? 0;
    final warning = draftJson['warning'] as String? ?? '';
    final stages = draftJson['stages'] as List? ?? [];

    int draftCount = 0;
    int verifyCount = 0;
    for (final stage in stages) {
      final coeffs = (stage as Map)['coefficients'] as List? ?? [];
      for (final c in coeffs) {
        final status = (c as Map)['status'] as String? ?? '';
        if (status == 'convertedDraft') draftCount++;
        if (status == 'requiresVerification') verifyCount++;
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.memory_outlined, color: Color(0xFFA78BFA), size: 13),
          const SizedBox(width: 8),
          Text('ADAU FIXED-POINT DRAFT', style: proLabel(size: 9, spacing: 2)),
          const Spacer(),
          const _InfoChip('8.24 format', Color(0xFFA78BFA)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _InfoChip('$stageCount stage(s)', Colors.white38),
          const SizedBox(width: 6),
          _InfoChip('$draftCount converted (draft)', const Color(0xFFA78BFA)),
          if (verifyCount > 0) ...[
            const SizedBox(width: 6),
            _InfoChip('$verifyCount need verification', const Color(0xFFFBBF24)),
          ],
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFFBBF24).withValues(alpha: 0.06),
            border: Border.all(
                color: const Color(0xFFFBBF24).withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('⚠ ',
                style: TextStyle(fontSize: 9, color: Color(0xFFFBBF24))),
            Expanded(
              child: Text(
                warning.isNotEmpty
                    ? warning
                    : 'Draft fixed-point values are not hardware-ready.',
                style: proSubtitle(size: 9),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final Color color;
  const _InfoChip(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      border: Border.all(color: color.withValues(alpha: 0.3)),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(label,
        style: TextStyle(fontSize: 9, color: color)),
  );
}
