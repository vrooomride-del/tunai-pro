// ── Deploy Tab — Phase R ───────────────────────────────────────────────────────
// Versioned deploy package / preset management. No hardware write.
// AI suggests. Expert verifies. AOS protects. DSP executes.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/factory_profile_builder.dart';
import '../../../core/factory_profile_exporter.dart';
import '../../../core/factory_sound_profile.dart';
import '../../../core/pro_project.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_deploy_package_data.dart';
import '../../../core/pro_deploy_package_engine.dart';
import '../../../core/pro_export_data.dart';
import '../../../core/deploy/pro_hardware_capability.dart';
import '../../../core/deploy/pro_hardware_context_provider.dart';
import '../widgets/deploy_result_summary.dart';
import '../widgets/hardware_apply_flow.dart';
import '../../../core/deploy/pro_hardware_write_executor.dart';
import '../../../core/workbench_tab_provider.dart';
import 'room_auto_peq_controller.dart';
import '../../../shared/pro_widgets.dart';
import '../../../shared/components/section_header.dart';
import '../../../shared/components/info_row.dart';

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
  final _scrollCtrl = ScrollController();

  // ── Factory Sound Profile state ──────────────────────────────────────────────
  bool _fpCreating = false;
  bool _fpShowExport = false;
  final _fpNameController = TextEditingController();
  final _fspKey = GlobalKey();

  // ── Hardware Apply result (for PASS_ACK display) ─────────────────────────────
  HardwareWriteExecutionResult? _lastHardwareResult;

  ProProject? get _project => ref
      .read(proProjectStoreProvider)
      .projects
      .where((p) => p.id == widget.projectId)
      .firstOrNull;

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    _fpNameController.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _createFactoryProfile() async {
    final project = _project;
    if (project == null) return;
    setState(() => _fpCreating = true);
    try {
      final name = _fpNameController.text.trim().isEmpty
          ? null
          : _fpNameController.text.trim();
      final profile = FactoryProfileBuilder.build(project, profileName: name);
      if (profile == null) return;
      await ref
          .read(proProjectStoreProvider.notifier)
          .addFactoryProfile(widget.projectId, profile);
      _fpNameController.clear();
    } finally {
      if (mounted) setState(() => _fpCreating = false);
    }
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
    final project = ref
        .watch(proProjectStoreProvider)
        .projects
        .where((p) => p.id == widget.projectId)
        .firstOrNull;
    final deployState =
        project?.deployState ?? DeployProjectState.createDefault();
    final activePkg = deployState.activePackage;

    // Watched (not just read inside HardwareApplyFlow's contextFactory
    // closure) so this build re-runs whenever the live BLE/USB context
    // changes — see the HardwareApplyFlow construction below for why that
    // matters: without this watch, DeployTab never rebuilds on a BLE
    // connect/disconnect, so HardwareApplyFlow (a plain StatefulWidget)
    // would never even get the chance to notice.
    final activeContext = ref.watch(activeAdau1701ContextProvider);

    ref.listen<DeployScrollTarget?>(deployScrollTargetProvider, (_, target) {
      if (target == DeployScrollTarget.factoryProfile) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _fspKey.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(ctx,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOut);
          }
        });
        ref.read(deployScrollTargetProvider.notifier).state = null;
      }
    });

    return SingleChildScrollView(
      controller: _scrollCtrl,
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
            child: const Text('DEPLOY',
                style: TextStyle(
                    fontSize: 9,
                    color: kProAmber,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          'Versioned packages for preset deployment and hardware apply.',
          style: proSubtitle(),
        ),
        const SizedBox(height: 24),

        // ── A: Readiness overview ────────────────────────────────────────────
        const ProSectionHeader(
            title: 'DEPLOY READINESS', icon: Icons.checklist_outlined),
        const SizedBox(height: 8),
        _ReadinessPanel(project: project),
        const SizedBox(height: 20),

        // ── B: Generate package panel ────────────────────────────────────────
        const ProSectionHeader(
            title: 'GENERATE PACKAGE', icon: Icons.add_circle_outline),
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
          const ProSectionHeader(
              title: 'ACTIVE PACKAGE', icon: Icons.inventory_outlined),
          const SizedBox(height: 8),
          _ActivePackagePanel(pkg: activePkg),
          const SizedBox(height: 20),
        ],

        // ── C2: Hardware apply (gated approve → apply workflow) ──────────────
        if (project != null && project.exportState.activePackage != null) ...[
          const ProSectionHeader(
              title: 'HARDWARE APPLY', icon: Icons.memory_outlined),
          const SizedBox(height: 8),
          HardwareApplyFlow(
            // HardwareApplyFlow is a plain StatefulWidget: it resolves
            // contextFactory() exactly once, in initState, and caches the
            // result for its whole lifetime. Because the IndexedStack in
            // WorkbenchShell keeps every tab mounted, that snapshot would
            // otherwise never refresh — a user who opens Deploy before
            // connecting BLE (or who reconnects with a new BLE session)
            // would see a permanently-stale "Hardware disconnected" even
            // after a real handshake succeeds elsewhere in the app. Keying
            // on the identity of the live transport (falling back to a
            // constant for "no active context yet, using the USB provider")
            // forces a remount — and therefore a fresh initState — exactly
            // when the active transport actually changes, and only then.
            key: ValueKey(activeContext?.transport ?? 'usb-fallback'),
            exportPackage: project.exportState.activePackage!,
            profile: _hardwareProfileFor(
                project.exportState.activePackage!.targetPlatform),
            // Same active-context preference as the Gain deploy dialog
            // (deploy_dialog.dart): BLE when connected, USB otherwise. This
            // was previously hardcoded to the USB-only provider, so a
            // BLE-connected device always failed preflight here even though
            // the same transport worked for Gain deploy.
            contextFactory: () =>
                activeContext ?? ref.read(adau1701Icp5UsbContextProvider),
            onResult: (result) {
              if (!mounted) return;
              setState(() => _lastHardwareResult = result);
              // Shared so other tabs (Measure's live After-measurement mode)
              // can gate on the same real write result instead of a weaker,
              // local-only "apply succeeded" signal.
              ref.read(lastHardwareWriteResultProvider.notifier).state = result;
              // Phase 3-F3 §3 — persist a restart-safe VerifiedDeploymentReceipt
              // when this result is a genuine, fully-verified success for
              // Room's currently-approved correction or rollback plan. No-op
              // for Factory packages, ack-only/partial results, or a
              // mismatched plan — never fabricated. See
              // RoomAutoPeqController.recordVerifiedDeployment.
              ref
                  .read(roomAutoPeqControllerProvider(project.id).notifier)
                  .recordVerifiedDeployment(result);
            },
          ),
          if (_lastHardwareResult != null) ...[
            const SizedBox(height: 12),
            if (_lastHardwareResult!.allWritten)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1A0D),
                  border:
                      Border.all(color: const Color(0xFF4CAF50).withAlpha(80)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle_outline,
                            color: Color(0xFF4CAF50), size: 14),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            // V3-5B: allWritten (the branch gate above, kept
                            // unchanged) is true for both fully readback-
                            // verified and ack-only-only results — this text
                            // must not claim "verified" for an ack-only
                            // write. V3-6A: the English clause now comes from
                            // DeployResultSummary.labelFor, the same shared
                            // wording deploy_dialog.dart/hardware_apply_flow
                            // .dart use — byte-identical resulting text.
                            '${DeployResultSummary.labelFor(_lastHardwareResult!)}'
                            ' — ${_lastHardwareResult!.allReadbackVerified ? "DSP write complete." : "Write accepted."}',
                            style: const TextStyle(
                                color: Color(0xFF4CAF50),
                                fontSize: 11,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.mic_outlined, size: 13),
                      label: const Text('Load After-Measurement FRD'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF4CAF50),
                        side: const BorderSide(
                            color: Color(0xFF4CAF50), width: 0.7),
                        textStyle: const TextStyle(fontSize: 12),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                      ),
                      onPressed: () => ref
                          .read(workbenchTabProvider.notifier)
                          .go(kTabGuidedAi),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: kProAmber.withValues(alpha: 0.06),
                  border: Border.all(color: kProAmber.withValues(alpha: 0.4)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.block_outlined,
                        color: kProAmber, size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'After-measurement unavailable: ${_lastHardwareResult!.executed ? '${_lastHardwareResult!.failedCount} operation(s) failed' : _lastHardwareResult!.rejectionReason ?? 'Not executed'}',
                        style: const TextStyle(
                            color: kProAmber, fontSize: 11, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 20),
        ] else ...[
          const ProSectionHeader(
              title: 'HARDWARE APPLY', icon: Icons.memory_outlined),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kProSurface,
              border: Border.all(color: kProBorder),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Export a package from the Export tab to enable Hardware Apply.',
              style: proSubtitle(size: 11),
            ),
          ),
          const SizedBox(height: 20),
        ],

        // ── D: Package history ───────────────────────────────────────────────
        if (deployState.packages.isNotEmpty) ...[
          const ProSectionHeader(
              title: 'PACKAGE HISTORY', icon: Icons.history_outlined),
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
        const ProSectionHeader(
            title: 'PRESET MANAGEMENT', icon: Icons.bookmarks_outlined),
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
          const ProSectionHeader(
              title: 'JSON PREVIEW', icon: Icons.data_object_outlined),
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
                Icon(_showJson ? Icons.expand_less : Icons.expand_more,
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
                const JsonEncoder.withIndent('  ').convert(activePkg.toJson()),
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

        // ── G: Factory Sound Profile ─────────────────────────────────────────
        ProSectionHeader(
            key: _fspKey,
            title: 'FACTORY SOUND PROFILE',
            icon: Icons.verified_outlined),
        const SizedBox(height: 8),
        if (project != null)
          _FactoryProfileSection(
            project: project,
            nameController: _fpNameController,
            creating: _fpCreating,
            showExport: _fpShowExport,
            onToggleExport: () =>
                setState(() => _fpShowExport = !_fpShowExport),
            onCreate: _createFactoryProfile,
          ),
        const SizedBox(height: 20),

        // ── H: Safety banner ─────────────────────────────────────────────────
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
                _SafetyRow('No hardware write has been performed.',
                    Icons.block_outlined),
                SizedBox(height: 4),
                _SafetyRow('EEPROM/Selfboot write is disabled.',
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

// Maps an export target platform to a hardware capability profile for the
// review-only apply preview. Defaults to the ADAU1701 ICP5 profile; the
// ADAU1466 developer profile assumes nothing writable.
HardwareDeviceProfile _hardwareProfileFor(DspTargetPlatform target) =>
    target == DspTargetPlatform.adau1466
        ? HardwareDeviceProfiles.adau1466Developer
        : HardwareDeviceProfiles.adau1701Icp5;

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

    final tuning = project!.tuningState;
    final eligibility = FactoryProfileBuilder.checkEligibility(project!);
    final connState = hardware.connectionState;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ProInfoRow(
            label: 'Project',
            value: '${project!.name} · ${project!.dspTarget}'),
        ProInfoRow(label: 'Status', value: project!.profileStatus.label),
        ProInfoRow(label: 'Measurement', value: acoustic.readinessLabel),
        ProInfoRow(
            label: 'PEQ bands',
            value: '${tuning.totalPeqBands} (${tuning.activePeqBands} active)'),
        ProInfoRow(label: 'Simulation', value: simulation.readinessLabel),
        ProInfoRow(label: 'Protection', value: protection.readinessLabel),
        ProInfoRow(label: 'Export', value: export.readinessLabel),
        ProInfoRow(label: 'Connection', value: connState.transportType.label),
        ProInfoRow(label: 'Hardware', value: hardware.readinessLabel),
        ProInfoRow(label: 'Deploy packages', value: '${deploy.packageCount}'),
        ProInfoRow(label: 'Presets', value: '${deploy.presetCount}'),
        ProInfoRow(label: 'Readiness', value: deploy.readinessLabel),
        ProInfoRow(
          label: 'Factory Profile',
          value: eligibility.isApproved
              ? 'Eligible'
              : 'Not eligible: ${eligibility.reasons.firstOrNull ?? '—'}',
          valueColor: eligibility.isApproved ? null : kProAmber,
        ),
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
        Text('Name (optional)',
            style: proLabel(size: 9, color: Colors.white38)),
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
        Text('Notes (optional)',
            style: proLabel(size: 9, color: Colors.white38)),
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
              borderSide: BorderSide(color: kProAccent.withValues(alpha: 0.5)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: generating ? null : onGenerate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color:
                  generating ? kProSurface : kProAccent.withValues(alpha: 0.08),
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
        if (pkg.status == DeployPackageStatus.stale) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: kProAmber.withValues(alpha: 0.08),
              border: Border.all(color: kProAmber.withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber_outlined,
                  size: 13, color: kProAmber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Stale package — tuning changed after this package was '
                  'created. Build or select a current package before '
                  'deploying.',
                  style: proSubtitle(size: 10, color: kProAmber),
                ),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 8),
        ProInfoRow(label: 'Name', value: pkg.name),
        ProInfoRow(label: 'Kind', value: pkg.kind.label),
        ProInfoRow(
            label: 'Created',
            value: pkg.createdAt.toLocal().toString().substring(0, 16)),
        if (pkg.exportPackageId != null)
          ProInfoRow(label: 'Export Package ID', value: pkg.exportPackageId!),
        if (pkg.hardwarePlanId != null)
          ProInfoRow(label: 'Hardware Plan ID', value: pkg.hardwarePlanId!),
        ProInfoRow(label: 'Warnings', value: '${pkg.snapshot.warnings.length}'),
        if (pkg.snapshot.blockedReason != null) ...[
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.block_outlined, size: 12, color: kProAmber),
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
          ProInfoRow(label: 'Notes', value: pkg.notes!),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
              color:
                  canCreate ? kProAccent.withValues(alpha: 0.08) : kProSurface,
              border: Border.all(
                  color: canCreate
                      ? kProAccent.withValues(alpha: 0.4)
                      : kProBorder),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.bookmark_add_outlined,
                  size: 13, color: canCreate ? kProAccent : Colors.white24),
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
                      color: preset.locked ? kProAmber : Colors.white38),
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
                                style:
                                    proLabel(size: 8, color: Colors.white24)),
                            const SizedBox(width: 6),
                            Text(preset.slotType.label,
                                style:
                                    proLabel(size: 8, color: Colors.white24)),
                            if (preset.targetPlatform != null) ...[
                              const SizedBox(width: 6),
                              Text(preset.targetPlatform!.label,
                                  style:
                                      proLabel(size: 8, color: Colors.white24)),
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
          Text('No presets saved yet.', style: proSubtitle(size: 10)),
        ],
      ]),
    );
  }
}

// ── Small helper widgets ──────────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  final DeployPackageStatus status;
  const _StatusPill(this.status);

  @override
  Widget build(BuildContext context) {
    final (color, bg) = switch (status) {
      DeployPackageStatus.ready => (
          kProGreen,
          kProGreen.withValues(alpha: 0.12)
        ),
      DeployPackageStatus.blocked => (
          const Color(0xFFEF4444),
          const Color(0xFFEF4444).withValues(alpha: 0.12)
        ),
      DeployPackageStatus.archived => (
          Colors.white24,
          Colors.white.withValues(alpha: 0.04)
        ),
      DeployPackageStatus.exported => (
          kProAccent,
          kProAccent.withValues(alpha: 0.12)
        ),
      DeployPackageStatus.draft => (
          Colors.white38,
          Colors.white.withValues(alpha: 0.06)
        ),
      DeployPackageStatus.stale => (
          Colors.amber,
          Colors.amber.withValues(alpha: 0.12)
        ),
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
      DeployReadinessLevel.readyForDryRun => kProGreen,
      DeployReadinessLevel.readyForReview => kProAccent,
      DeployReadinessLevel.warnings => kProAmber,
      DeployReadinessLevel.blocked => const Color(0xFFEF4444),
      DeployReadinessLevel.incomplete => Colors.white38,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(3)),
      child: Text(level.label,
          style: TextStyle(
              fontSize: 8, color: color, fontWeight: FontWeight.w500)),
    );
  }
}

class _KindChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _KindChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? kProAccent.withValues(alpha: 0.1) : kProSurface,
            border: Border.all(
                color:
                    selected ? kProAccent.withValues(alpha: 0.5) : kProBorder),
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
          child: Text(text,
              style: const TextStyle(fontSize: 10, color: kProAmber)),
        ),
      ]);
}

// ── _FactoryProfileSection ────────────────────────────────────────────────────

class _FactoryProfileSection extends StatelessWidget {
  final ProProject project;
  final TextEditingController nameController;
  final bool creating;
  final bool showExport;
  final VoidCallback onToggleExport;
  final VoidCallback onCreate;

  const _FactoryProfileSection({
    required this.project,
    required this.nameController,
    required this.creating,
    required this.showExport,
    required this.onToggleExport,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    final eligibility = FactoryProfileBuilder.checkEligibility(project);
    final latestProfile = project.factoryProfiles.isNotEmpty
        ? project.factoryProfiles.last
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Eligibility result
        _EligibilityCard(eligibility: eligibility),
        const SizedBox(height: 10),

        if (eligibility.isApproved) ...[
          // Profile name input
          TextField(
            controller: nameController,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: InputDecoration(
              hintText: project.name,
              hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
              labelText: 'Profile Name',
              labelStyle: const TextStyle(color: Colors.white38, fontSize: 11),
              filled: true,
              fillColor: kProSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: kProBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: kProBorder),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: creating ? null : onCreate,
              icon: creating
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: Colors.white))
                  : const Icon(Icons.verified_outlined, size: 14),
              label: const Text('Create Factory Sound Profile',
                  style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                backgroundColor: kProAccent.withValues(alpha: 0.15),
                foregroundColor: kProAccent,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                  side: BorderSide(color: kProAccent.withValues(alpha: 0.4)),
                ),
              ),
            ),
          ),
        ],

        // Latest profile summary
        if (latestProfile != null) ...[
          const SizedBox(height: 12),
          _ProfileSummaryCard(
            profile: latestProfile,
            showExport: showExport,
            onToggleExport: onToggleExport,
          ),
        ],
      ],
    );
  }
}

class _EligibilityCard extends StatelessWidget {
  final FactoryProfileEligibility eligibility;
  const _EligibilityCard({required this.eligibility});

  @override
  Widget build(BuildContext context) {
    if (eligibility.isApproved) {
      return Row(children: [
        const Icon(Icons.check_circle_outline,
            color: Color(0xFF4CAF50), size: 14),
        const SizedBox(width: 8),
        Text('Eligible for factory profile creation',
            style: proSubtitle(size: 11, color: const Color(0xFF4CAF50))),
      ]);
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.07),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.block_outlined, color: Colors.redAccent, size: 13),
            const SizedBox(width: 6),
            Text('Not eligible',
                style: proSubtitle(size: 11, color: Colors.redAccent)),
          ]),
          const SizedBox(height: 6),
          for (final r in eligibility.reasons)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ',
                      style: TextStyle(color: Colors.redAccent, fontSize: 10)),
                  Expanded(
                    child: Text(r,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 10, height: 1.4)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileSummaryCard extends StatelessWidget {
  final FactorySoundProfile profile;
  final bool showExport;
  final VoidCallback onToggleExport;
  const _ProfileSummaryCard({
    required this.profile,
    required this.showExport,
    required this.onToggleExport,
  });

  @override
  Widget build(BuildContext context) {
    String? exportJson;
    String? exportError;
    try {
      exportJson = const JsonEncoder.withIndent('  ')
          .convert(FactoryProfileExporter.toJson(profile));
    } on UnsupportedHardwareExportError catch (e) {
      exportError = e.toString();
    } catch (e) {
      exportError = 'Export error: $e';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.verified, color: Color(0xFF4CAF50), size: 14),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                profile.profileName,
                style: proTitle(size: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: kProAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: kProAccent.withValues(alpha: 0.4)),
              ),
              child: Text('v${profile.version}',
                  style: const TextStyle(
                      fontSize: 9,
                      color: kProAccent,
                      fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 8),
          _profileRow('Hardware', profile.hardwareTarget),
          _profileRow('Channels', profile.channelConfig),
          _profileRow('Validation', profile.validationStatus),
          _profileRow(
              'Cycles', '${profile.completedCycleNumbers.length} completed'),
          _profileRow('Fingerprint', profile.projectFingerprint),
          _profileRow(
              'Created', profile.createdAt.toIso8601String().substring(0, 19)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: onToggleExport,
            child: Row(children: [
              Icon(showExport ? Icons.expand_less : Icons.expand_more,
                  color: Colors.white38, size: 13),
              const SizedBox(width: 6),
              Text(
                showExport ? 'Collapse JSON export' : 'Export JSON',
                style: proSubtitle(size: 10),
              ),
            ]),
          ),
          if (showExport) ...[
            const SizedBox(height: 6),
            if (exportError != null)
              Text(exportError,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 10))
            else
              SelectableText(
                exportJson!,
                style: const TextStyle(
                    fontSize: 8,
                    fontFamily: 'monospace',
                    color: Colors.white54,
                    height: 1.5),
              ),
          ],
        ],
      ),
    );
  }

  Widget _profileRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white38, fontSize: 10)),
            Text(value,
                style: const TextStyle(color: Colors.white54, fontSize: 10)),
          ],
        ),
      );
}

Widget _emptyBox(String msg) => Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(msg,
          style: const TextStyle(fontSize: 10, color: Colors.white38)),
    );
