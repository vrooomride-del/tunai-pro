// ── Deploy Tab — Phase R ───────────────────────────────────────────────────────
// Versioned deploy package / preset management. No hardware write.
// AI suggests. Expert verifies. AOS protects. DSP executes.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/pro_project.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_deploy_package_data.dart';
import '../../../core/pro_deploy_package_engine.dart';
import '../../../shared/pro_widgets.dart';

class DeployTab extends ConsumerStatefulWidget {
  final String projectId;
  const DeployTab({super.key, required this.projectId});

  @override
  ConsumerState<DeployTab> createState() => _DeployTabState();
}

class _DeployTabState extends ConsumerState<DeployTab> {
  bool _generating = false;
  bool _showJson = false;
  DeployPackageKind _selectedKind = DeployPackageKind.fullProjectSnapshot;
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();

  ProProject? get _project => ref
      .read(proProjectStoreProvider)
      .projects
      .where((p) => p.id == widget.projectId)
      .firstOrNull;

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _generatePackage() async {
    final project = _project;
    if (project == null) return;
    setState(() => _generating = true);
    try {
      final pkg = generateDeployPackage(
        project: project,
        kind: _selectedKind,
        name: _nameController.text.trim().isEmpty
            ? null
            : _nameController.text.trim(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );
      final existing = project.deployState.packages;
      final updated = [...existing.take(9), pkg];
      final newDeploy = project.deployState.copyWith(
        packages: updated,
        activePackageId: pkg.id,
        updatedAt: DateTime.now(),
        revision: project.deployState.revision + 1,
      );
      await ref
          .read(proProjectStoreProvider.notifier)
          .updateDeployState(widget.projectId, newDeploy);
      _nameController.clear();
      _notesController.clear();
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _setActivePackage(String id) async {
    final project = _project;
    if (project == null) return;
    final newDeploy = project.deployState.copyWith(
      activePackageId: id,
      updatedAt: DateTime.now(),
    );
    await ref
        .read(proProjectStoreProvider.notifier)
        .updateDeployState(widget.projectId, newDeploy);
  }

  Future<void> _archivePackage(String id) async {
    final project = _project;
    if (project == null) return;
    final updated = project.deployState.packages.map((p) {
      if (p.id != id) return p;
      return p.copyWith(status: DeployPackageStatus.archived);
    }).toList();
    final newDeploy = project.deployState.copyWith(
      packages: updated,
      updatedAt: DateTime.now(),
    );
    await ref
        .read(proProjectStoreProvider.notifier)
        .updateDeployState(widget.projectId, newDeploy);
  }

  Future<void> _createPreset() async {
    final project = _project;
    final activePkg = project?.deployState.activePackage;
    if (project == null || activePkg == null) return;
    final now = DateTime.now();
    final preset = PresetRecord(
      id: 'preset_${now.millisecondsSinceEpoch}',
      name: activePkg.name,
      version: activePkg.version,
      slotType: PresetSlotType.project,
      createdAt: now,
      updatedAt: now,
      deployPackageId: activePkg.id,
      targetPlatform: project.exportState.selectedTarget,
    );
    final updated = [...project.deployState.presets, preset];
    final newDeploy = project.deployState.copyWith(
      presets: updated,
      activePresetId: preset.id,
      updatedAt: DateTime.now(),
    );
    await ref
        .read(proProjectStoreProvider.notifier)
        .updateDeployState(widget.projectId, newDeploy);
  }

  Future<void> _togglePresetLock(String id) async {
    final project = _project;
    if (project == null) return;
    final updated = project.deployState.presets.map((p) {
      if (p.id != id) return p;
      return p.copyWith(locked: !p.locked, updatedAt: DateTime.now());
    }).toList();
    final newDeploy = project.deployState.copyWith(
      presets: updated,
      updatedAt: DateTime.now(),
    );
    await ref
        .read(proProjectStoreProvider.notifier)
        .updateDeployState(widget.projectId, newDeploy);
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(proProjectStoreProvider)
        .projects
        .where((p) => p.id == widget.projectId)
        .firstOrNull;
    final deployState = project?.deployState ?? DeployProjectState.createDefault();
    final activePkg = deployState.activePackage;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ──────────────────────────────────────────────────────────
        Row(children: [
          Icon(Icons.inventory_2_outlined,
              color: kProAccent.withValues(alpha: 0.6), size: 18),
          const SizedBox(width: 10),
          Text('Deploy Packages', style: proTitle(size: 16)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: kProAmber.withValues(alpha: 0.12),
              border: Border.all(color: kProAmber.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text('PHASE R',
                style: TextStyle(
                    fontSize: 9,
                    color: kProAmber,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          'Versioned review packages for preset deployment. Hardware write remains disabled.',
          style: proSubtitle(),
        ),
        const SizedBox(height: 24),

        // ── A: Readiness overview ────────────────────────────────────────────
        const _SectionHeader('DEPLOY READINESS', Icons.checklist_outlined),
        const SizedBox(height: 8),
        _ReadinessPanel(project: project),
        const SizedBox(height: 20),

        // ── B: Generate package panel ────────────────────────────────────────
        const _SectionHeader('GENERATE PACKAGE', Icons.add_circle_outline),
        const SizedBox(height: 8),
        _GeneratePanel(
          selectedKind: _selectedKind,
          nameController: _nameController,
          notesController: _notesController,
          generating: _generating,
          onKindChanged: (k) => setState(() => _selectedKind = k),
          onGenerate: _generatePackage,
        ),
        const SizedBox(height: 20),

        // ── C: Active package summary ────────────────────────────────────────
        if (activePkg != null) ...[
          const _SectionHeader('ACTIVE PACKAGE', Icons.inventory_outlined),
          const SizedBox(height: 8),
          _ActivePackagePanel(pkg: activePkg),
          const SizedBox(height: 20),
        ],

        // ── D: Package history ───────────────────────────────────────────────
        if (deployState.packages.isNotEmpty) ...[
          const _SectionHeader('PACKAGE HISTORY', Icons.history_outlined),
          const SizedBox(height: 8),
          _PackageHistoryPanel(
            packages: deployState.packages.reversed.toList(),
            activeId: deployState.activePackageId,
            onSetActive: _setActivePackage,
            onArchive: _archivePackage,
          ),
          const SizedBox(height: 20),
        ],

        // ── E: Preset management ─────────────────────────────────────────────
        const _SectionHeader('PRESET MANAGEMENT', Icons.bookmarks_outlined),
        const SizedBox(height: 8),
        _PresetPanel(
          deployState: deployState,
          canCreate: activePkg != null,
          onCreatePreset: _createPreset,
          onToggleLock: _togglePresetLock,
        ),
        const SizedBox(height: 20),

        // ── F: JSON preview ──────────────────────────────────────────────────
        if (activePkg != null) ...[
          const _SectionHeader('JSON PREVIEW', Icons.data_object_outlined),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => setState(() => _showJson = !_showJson),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                color: kProSurface,
                border: Border.all(color: kProBorder),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(children: [
                Icon(_showJson
                    ? Icons.expand_less
                    : Icons.expand_more,
                    color: Colors.white38, size: 14),
                const SizedBox(width: 8),
                Text(
                  _showJson ? 'Collapse JSON' : 'Expand active package JSON',
                  style: proSubtitle(size: 10),
                ),
              ]),
            ),
          ),
          if (_showJson) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0A),
                border: Border.all(color: kProBorder),
                borderRadius: BorderRadius.circular(4),
              ),
              child: SelectableText(
                const JsonEncoder.withIndent('  ')
                    .convert(activePkg.toJson()),
                style: const TextStyle(
                    fontSize: 9,
                    fontFamily: 'monospace',
                    color: Colors.white54,
                    height: 1.5),
              ),
            ),
          ],
          const SizedBox(height: 20),
        ],

        // ── G: Safety banner ─────────────────────────────────────────────────
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: kProAmber.withValues(alpha: 0.06),
            border: Border.all(color: kProAmber.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            _SafetyRow(
                'No hardware write has been performed.',
                Icons.block_outlined),
            SizedBox(height: 4),
            _SafetyRow(
                'EEPROM/Selfboot write is disabled.',
                Icons.memory_outlined),
            SizedBox(height: 4),
            _SafetyRow(
                'Hardware deployment requires a future controlled write phase.',
                Icons.warning_amber_outlined),
          ]),
        ),
      ]),
    );
  }
}

// ── _ReadinessPanel ───────────────────────────────────────────────────────────

class _ReadinessPanel extends StatelessWidget {
  final ProProject? project;
  const _ReadinessPanel({required this.project});

  @override
  Widget build(BuildContext context) {
    if (project == null) {
      return _emptyBox('No project loaded.');
    }
    final acoustic = project!.acousticState;
    final simulation = project!.simulationState;
    final protection = project!.protectionState;
    final export = project!.exportState;
    final hardware = project!.hardwareState;
    final deploy = project!.deployState;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _InfoRow('Project', project!.name),
        _InfoRow('Status', project!.profileStatus.label),
        _InfoRow('Measurement', acoustic.readinessLabel),
        _InfoRow('Simulation', simulation.readinessLabel),
        _InfoRow('Protection', protection.readinessLabel),
        _InfoRow('Export', export.readinessLabel),
        _InfoRow('Hardware', hardware.readinessLabel),
        _InfoRow('Deploy packages', '${deploy.packageCount}'),
        _InfoRow('Presets', '${deploy.presetCount}'),
        _InfoRow('Readiness', deploy.readinessLabel),
      ]),
    );
  }
}

// ── _GeneratePanel ────────────────────────────────────────────────────────────

class _GeneratePanel extends StatelessWidget {
  final DeployPackageKind selectedKind;
  final TextEditingController nameController;
  final TextEditingController notesController;
  final bool generating;
  final ValueChanged<DeployPackageKind> onKindChanged;
  final VoidCallback onGenerate;

  const _GeneratePanel({
    required this.selectedKind,
    required this.nameController,
    required this.notesController,
    required this.generating,
    required this.onKindChanged,
    required this.onGenerate,
  });

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
        // Kind selector
        Text('Package kind', style: proLabel(size: 9, color: Colors.white38)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final kind in DeployPackageKind.values)
            _KindChip(
              label: kind.label,
              selected: kind == selectedKind,
              onTap: () => onKindChanged(kind),
            ),
        ]),
        const SizedBox(height: 10),
        // Name field
        Text('Name (optional)', style: proLabel(size: 9, color: Colors.white38)),
        const SizedBox(height: 4),
        TextField(
          controller: nameController,
          style: const TextStyle(fontSize: 11, color: Colors.white70),
          decoration: InputDecoration(
            hintText: 'Auto-generated if empty',
            hintStyle: const TextStyle(fontSize: 11, color: Colors.white24),
            filled: true,
            fillColor: kProBg,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(3),
              borderSide: const BorderSide(color: kProBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(3),
              borderSide: const BorderSide(color: kProBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(3),
              borderSide: BorderSide(color: kProAccent.withValues(alpha: 0.5)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('Notes (optional)', style: proLabel(size: 9, color: Colors.white38)),
        const SizedBox(height: 4),
        TextField(
          controller: notesController,
          style: const TextStyle(fontSize: 11, color: Colors.white70),
          maxLines: 2,
          decoration: InputDecoration(
            hintText: 'Optional review notes',
            hintStyle: const TextStyle(fontSize: 11, color: Colors.white24),
            filled: true,
            fillColor: kProBg,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(3),
              borderSide: const BorderSide(color: kProBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(3),
              borderSide: const BorderSide(color: kProBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(3),
              borderSide:
                  BorderSide(color: kProAccent.withValues(alpha: 0.5)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: generating ? null : onGenerate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: generating
                  ? kProSurface
                  : kProAccent.withValues(alpha: 0.08),
              border: Border.all(
                  color: generating
                      ? kProBorder
                      : kProAccent.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                generating
                    ? Icons.hourglass_empty_outlined
                    : Icons.add_circle_outline,
                color: generating ? Colors.white24 : kProAccent,
                size: 14,
              ),
              const SizedBox(width: 8),
              Text(
                generating ? 'Generating...' : 'Generate Deploy Package',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: generating ? Colors.white24 : kProAccent),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ── _ActivePackagePanel ───────────────────────────────────────────────────────

class _ActivePackagePanel extends StatelessWidget {
  final DeployPackage pkg;
  const _ActivePackagePanel({required this.pkg});

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
          _StatusPill(pkg.status),
          const SizedBox(width: 8),
          _ReadinessPill(pkg.readinessLevel),
          const Spacer(),
          Text(pkg.version,
              style: proLabel(size: 9, color: Colors.white38, spacing: 0.5)),
        ]),
        const SizedBox(height: 8),
        _InfoRow('Name', pkg.name),
        _InfoRow('Kind', pkg.kind.label),
        _InfoRow('Created',
            pkg.createdAt.toLocal().toString().substring(0, 16)),
        if (pkg.exportPackageId != null)
          _InfoRow('Export Package ID', pkg.exportPackageId!),
        if (pkg.hardwarePlanId != null)
          _InfoRow('Hardware Plan ID', pkg.hardwarePlanId!),
        _InfoRow('Warnings', '${pkg.snapshot.warnings.length}'),
        if (pkg.snapshot.blockedReason != null) ...[
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.block_outlined,
                size: 12, color: kProAmber),
            const SizedBox(width: 6),
            Expanded(
              child: Text(pkg.snapshot.blockedReason!,
                  style: const TextStyle(
                      fontSize: 10,
                      color: kProAmber,
                      fontWeight: FontWeight.w500)),
            ),
          ]),
        ],
        if (pkg.notes != null) ...[
          const SizedBox(height: 4),
          _InfoRow('Notes', pkg.notes!),
        ],
      ]),
    );
  }
}

// ── _PackageHistoryPanel ──────────────────────────────────────────────────────

class _PackageHistoryPanel extends StatelessWidget {
  final List<DeployPackage> packages;
  final String? activeId;
  final ValueChanged<String> onSetActive;
  final ValueChanged<String> onArchive;

  const _PackageHistoryPanel({
    required this.packages,
    required this.activeId,
    required this.onSetActive,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: packages.map((pkg) {
          final isActive = pkg.id == activeId;
          return Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            decoration: BoxDecoration(
              color: isActive
                  ? kProAccent.withValues(alpha: 0.06)
                  : Colors.transparent,
              border: Border(
                top: packages.first == pkg
                    ? BorderSide.none
                    : const BorderSide(color: kProBorder, width: 0.5),
                left: BorderSide(
                  color: isActive ? kProAccent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(children: [
              _StatusPill(pkg.status),
              const SizedBox(width: 6),
              _ReadinessPill(pkg.readinessLevel),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(pkg.name,
                      style: proTitle(
                          size: 10,
                          color: isActive ? Colors.white : Colors.white60),
                      overflow: TextOverflow.ellipsis),
                  Text(pkg.version,
                      style: proLabel(size: 8, color: Colors.white24)),
                ]),
              ),
              if (!isActive && pkg.status != DeployPackageStatus.archived)
                GestureDetector(
                  onTap: () => onSetActive(pkg.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: kProBorder),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text('Set Active',
                        style: proLabel(size: 8, color: Colors.white38)),
                  ),
                ),
              if (pkg.status != DeployPackageStatus.archived) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => onArchive(pkg.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: kProBorder),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text('Archive',
                        style: proLabel(size: 8, color: Colors.white38)),
                  ),
                ),
              ],
            ]),
          );
        }).toList(),
      ),
    );
  }
}

// ── _PresetPanel ──────────────────────────────────────────────────────────────

class _PresetPanel extends StatelessWidget {
  final DeployProjectState deployState;
  final bool canCreate;
  final VoidCallback onCreatePreset;
  final ValueChanged<String> onToggleLock;

  const _PresetPanel({
    required this.deployState,
    required this.canCreate,
    required this.onCreatePreset,
    required this.onToggleLock,
  });

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
        GestureDetector(
          onTap: canCreate ? onCreatePreset : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: canCreate
                  ? kProAccent.withValues(alpha: 0.08)
                  : kProSurface,
              border: Border.all(
                  color: canCreate
                      ? kProAccent.withValues(alpha: 0.4)
                      : kProBorder),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.bookmark_add_outlined,
                  size: 13,
                  color: canCreate ? kProAccent : Colors.white24),
              const SizedBox(width: 7),
              Text(
                canCreate
                    ? 'Save Active Package as Preset'
                    : 'Generate a package first',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: canCreate ? kProAccent : Colors.white24),
              ),
            ]),
          ),
        ),
        if (deployState.presets.isNotEmpty) ...[
          const SizedBox(height: 10),
          ...deployState.presets.map((preset) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Icon(Icons.bookmark_outlined,
                  size: 12,
                  color: preset.locked
                      ? kProAmber
                      : Colors.white38),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(preset.name,
                      style: proTitle(size: 10),
                      overflow: TextOverflow.ellipsis),
                  Row(children: [
                    Text(preset.version,
                        style: proLabel(size: 8, color: Colors.white24)),
                    const SizedBox(width: 6),
                    Text(preset.slotType.label,
                        style: proLabel(size: 8, color: Colors.white24)),
                    if (preset.targetPlatform != null) ...[
                      const SizedBox(width: 6),
                      Text(preset.targetPlatform!.label,
                          style: proLabel(size: 8, color: Colors.white24)),
                    ],
                    if (preset.locked) ...[
                      const SizedBox(width: 6),
                      const Text('LOCKED',
                          style: TextStyle(
                              fontSize: 8,
                              color: kProAmber,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5)),
                    ],
                  ]),
                ]),
              ),
              GestureDetector(
                onTap: () => onToggleLock(preset.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    border: Border.all(color: kProBorder),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(preset.locked ? 'Unlock' : 'Lock',
                      style: proLabel(size: 8, color: Colors.white38)),
                ),
              ),
            ]),
          )),
        ] else ...[
          const SizedBox(height: 8),
          Text('No presets saved yet.',
              style: proSubtitle(size: 10)),
        ],
      ]),
    );
  }
}

// ── Small helper widgets ──────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SectionHeader(this.label, this.icon);

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 11, color: Colors.white24),
    const SizedBox(width: 6),
    Text(label, style: proLabel(size: 9, color: Colors.white38, spacing: 1.5)),
  ]);
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(children: [
      SizedBox(
        width: 130,
        child: Text(label, style: proLabel(size: 9, color: Colors.white38)),
      ),
      Expanded(
        child: Text(value, style: proSubtitle(size: 10)),
      ),
    ]),
  );
}

class _StatusPill extends StatelessWidget {
  final DeployPackageStatus status;
  const _StatusPill(this.status);

  @override
  Widget build(BuildContext context) {
    final (color, bg) = switch (status) {
      DeployPackageStatus.ready    => (kProGreen, kProGreen.withValues(alpha: 0.12)),
      DeployPackageStatus.blocked  => (const Color(0xFFEF4444), const Color(0xFFEF4444).withValues(alpha: 0.12)),
      DeployPackageStatus.archived => (Colors.white24, Colors.white.withValues(alpha: 0.04)),
      DeployPackageStatus.exported => (kProAccent, kProAccent.withValues(alpha: 0.12)),
      DeployPackageStatus.draft    => (Colors.white38, Colors.white.withValues(alpha: 0.06)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(3)),
      child: Text(status.label,
          style: TextStyle(
              fontSize: 8,
              color: color,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4)),
    );
  }
}

class _ReadinessPill extends StatelessWidget {
  final DeployReadinessLevel level;
  const _ReadinessPill(this.level);

  @override
  Widget build(BuildContext context) {
    final color = switch (level) {
      DeployReadinessLevel.readyForDryRun  => kProGreen,
      DeployReadinessLevel.readyForReview  => kProAccent,
      DeployReadinessLevel.warnings        => kProAmber,
      DeployReadinessLevel.blocked         => const Color(0xFFEF4444),
      DeployReadinessLevel.incomplete      => Colors.white38,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(3)),
      child: Text(level.label,
          style: TextStyle(
              fontSize: 8,
              color: color,
              fontWeight: FontWeight.w500)),
    );
  }
}

class _KindChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _KindChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: selected
            ? kProAccent.withValues(alpha: 0.1)
            : kProSurface,
        border: Border.all(
            color: selected
                ? kProAccent.withValues(alpha: 0.5)
                : kProBorder),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              color: selected ? kProAccent : Colors.white38,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
    ),
  );
}

class _SafetyRow extends StatelessWidget {
  final String text;
  final IconData icon;
  const _SafetyRow(this.text, this.icon);

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: kProAmber, size: 12),
    const SizedBox(width: 8),
    Expanded(
      child: Text(text, style: const TextStyle(fontSize: 10, color: kProAmber)),
    ),
  ]);
}

Widget _emptyBox(String msg) => Container(
  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
  decoration: BoxDecoration(
    color: kProSurface,
    border: Border.all(color: kProBorder),
    borderRadius: BorderRadius.circular(4),
  ),
  child: Text(msg, style: const TextStyle(fontSize: 10, color: Colors.white38)),
);
