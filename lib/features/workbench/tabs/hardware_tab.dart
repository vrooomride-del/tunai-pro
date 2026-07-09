// ── Hardware Guard Tab — Phase Q ──────────────────────────────────────────────
// Dry-run hardware planning. No USBi/BLE/SafeLoad/EEPROM write is enabled.
// AI suggests. Expert verifies. AOS protects. DSP executes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/pro_project.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_export_data.dart';
import '../../../core/pro_hardware_connection_data.dart';
import '../../../core/pro_hardware_write_plan_engine.dart';
import '../../../shared/pro_widgets.dart';

class HardwareTab extends ConsumerStatefulWidget {
  final String projectId;
  const HardwareTab({super.key, required this.projectId});

  @override
  ConsumerState<HardwareTab> createState() => _HardwareTabState();
}

class _HardwareTabState extends ConsumerState<HardwareTab> {
  bool _generating = false;

  ProProject? get _project => ref
      .read(proProjectStoreProvider)
      .projects
      .where((p) => p.id == widget.projectId)
      .firstOrNull;

  Future<void> _setTransport(HardwareTransportType t) async {
    final project = _project;
    if (project == null) return;
    final newConn = project.hardwareState.connectionState.copyWith(
      transportType: t,
      connectionStatus: t == HardwareTransportType.simulationOnly
          ? HardwareConnectionStatus.simulated
          : HardwareConnectionStatus.disconnected,
    );
    final newHw = project.hardwareState.copyWith(
      connectionState: newConn,
      updatedAt: DateTime.now(),
    );
    await ref.read(proProjectStoreProvider.notifier)
        .updateHardwareState(widget.projectId, newHw);
  }

  Future<void> _setTargetDevice(HardwareTargetDevice d) async {
    final project = _project;
    if (project == null) return;
    final newConn = project.hardwareState.connectionState.copyWith(targetDevice: d);
    final newHw = project.hardwareState.copyWith(
      connectionState: newConn,
      updatedAt: DateTime.now(),
    );
    await ref.read(proProjectStoreProvider.notifier)
        .updateHardwareState(widget.projectId, newHw);
  }

  Future<void> _checkConnection() async {
    final project = _project;
    if (project == null) return;
    final current = project.hardwareState.connectionState;
    // Phase Q: only simulated status update. No real hardware scan.
    final newStatus = current.transportType == HardwareTransportType.simulationOnly
        ? HardwareConnectionStatus.simulated
        : HardwareConnectionStatus.disconnected;
    final newConn = current.copyWith(
      connectionStatus: newStatus,
      lastCheckedAt: DateTime.now(),
    );
    final newHw = project.hardwareState.copyWith(
      connectionState: newConn,
      updatedAt: DateTime.now(),
    );
    await ref.read(proProjectStoreProvider.notifier)
        .updateHardwareState(widget.projectId, newHw);
  }

  Future<void> _generateWritePlan() async {
    final project = _project;
    if (project == null) return;
    final pkg = project.exportState.activePackage;
    if (pkg == null) return;

    setState(() => _generating = true);
    try {
      final plan = generateHardwareWritePlan(project: project, package: pkg);
      final existing = project.hardwareState.writePlans;
      // Keep last 5 plans
      final updated = [...existing.take(4), plan];
      final newHw = project.hardwareState.copyWith(
        writePlans: updated,
        activePlanId: plan.id,
        updatedAt: DateTime.now(),
        revision: project.hardwareState.revision + 1,
      );
      await ref.read(proProjectStoreProvider.notifier)
          .updateHardwareState(widget.projectId, newHw);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(proProjectStoreProvider)
        .projects
        .where((p) => p.id == widget.projectId)
        .firstOrNull;
    final hwState = project?.hardwareState ?? HardwareProjectState.createDefault();
    final conn = hwState.connectionState;
    final activePlan = hwState.activePlan;
    final activePkg = project?.exportState.activePackage;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Icon(Icons.security_outlined,
              color: kProAccent.withValues(alpha: 0.6), size: 18),
          const SizedBox(width: 10),
          Text('Hardware Guard', style: proTitle(size: 16)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: kProAmber.withValues(alpha: 0.12),
              border: Border.all(color: kProAmber.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text('DRY RUN ONLY',
                style: TextStyle(fontSize: 9, color: kProAmber,
                    fontWeight: FontWeight.w600, letterSpacing: 0.8)),
          ),
        ]),
        const SizedBox(height: 4),
        Text('Dry-run hardware planning. No USBi/BLE write is enabled.',
            style: proSubtitle()),
        const SizedBox(height: 24),

        // A: Connection State Panel
        const _SectionHeader('CONNECTION STATE', Icons.usb_outlined),
        const SizedBox(height: 8),
        _ConnectionPanel(
          conn: conn,
          onTransport: _setTransport,
          onTarget: _setTargetDevice,
          onCheck: _checkConnection,
        ),
        const SizedBox(height: 20),

        // B: Active Export Package
        const _SectionHeader('ACTIVE EXPORT PACKAGE', Icons.upload_outlined),
        const SizedBox(height: 8),
        _ExportPackagePanel(pkg: activePkg, protection: project?.protectionState),
        const SizedBox(height: 20),

        // C: Generate button
        GestureDetector(
          onTap: (_generating || activePkg == null) ? null : _generateWritePlan,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: (_generating || activePkg == null)
                  ? kProSurface
                  : kProAccent.withValues(alpha: 0.08),
              border: Border.all(
                  color: (_generating || activePkg == null)
                      ? kProBorder
                      : kProAccent.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                _generating
                    ? Icons.hourglass_empty_outlined
                    : Icons.play_arrow_outlined,
                color: (_generating || activePkg == null)
                    ? Colors.white24
                    : kProAccent,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                activePkg == null
                    ? 'No Export Package — Generate Export First'
                    : _generating
                        ? 'Generating...'
                        : 'Generate Dry-Run Write Plan',
                style: TextStyle(
                    color: (_generating || activePkg == null)
                        ? Colors.white24
                        : kProAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 20),

        // D: Guard checklist
        if (activePlan != null) ...[
          const _SectionHeader('GUARD CHECKLIST', Icons.checklist_outlined),
          const SizedBox(height: 8),
          _GuardChecklistPanel(plan: activePlan),
          const SizedBox(height: 20),

          // E: Write plan preview
          const _SectionHeader('WRITE PLAN PREVIEW', Icons.list_alt_outlined),
          const SizedBox(height: 8),
          _WritePlanPanel(plan: activePlan),
          const SizedBox(height: 20),

          // F: Warnings
          if (activePlan.warnings.isNotEmpty || activePlan.blockedReason != null) ...[
            const _SectionHeader('WARNINGS', Icons.warning_amber_outlined),
            const SizedBox(height: 8),
            _WarningsPanel(plan: activePlan),
            const SizedBox(height: 20),
          ],
        ] else ...[
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
              Expanded(
                child: Text(
                  'Generate an export draft first, then click '
                  '"Generate Dry-Run Write Plan" to preview the hardware guard checklist.',
                  style: proSubtitle(),
                ),
              ),
            ]),
          ),
        ],

        // Hardware write disabled notice (always shown)
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: kProAmber.withValues(alpha: 0.06),
            border: Border.all(color: kProAmber.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.block_outlined, color: kProAmber, size: 13),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Hardware write remains disabled. '
                'No USBi/BLE packets are sent. No SafeLoad is executed. '
                'No EEPROM/Selfboot write is performed.',
                style: proSubtitle(size: 9),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── Section Header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SectionHeader(this.label, this.icon);

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: Colors.white38, size: 13),
    const SizedBox(width: 6),
    Text(label, style: proLabel(size: 9, spacing: 2)),
  ]);
}

// ── Connection Panel ──────────────────────────────────────────────────────────

class _ConnectionPanel extends StatelessWidget {
  final HardwareConnectionState conn;
  final ValueChanged<HardwareTransportType> onTransport;
  final ValueChanged<HardwareTargetDevice> onTarget;
  final VoidCallback onCheck;

  const _ConnectionPanel({
    required this.conn,
    required this.onTransport,
    required this.onTarget,
    required this.onCheck,
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
        // Transport selector
        Text('TRANSPORT', style: proLabel(size: 9, color: Colors.white38, spacing: 1.5)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final t in [
            HardwareTransportType.simulationOnly,
            HardwareTransportType.usbi,
            HardwareTransportType.ble,
            HardwareTransportType.usbAudio,
          ])
            _SelectChip(
              label: t.label,
              selected: conn.transportType == t,
              onTap: () => onTransport(t),
            ),
        ]),
        const SizedBox(height: 12),

        // Device target
        Text('DEVICE TARGET', style: proLabel(size: 9, color: Colors.white38, spacing: 1.5)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final d in [
            HardwareTargetDevice.simulation,
            HardwareTargetDevice.adau1466,
            HardwareTargetDevice.adau1701,
            HardwareTargetDevice.aosBox,
          ])
            _SelectChip(
              label: d.label,
              selected: conn.targetDevice == d,
              onTap: () => onTarget(d),
            ),
        ]),
        const SizedBox(height: 12),

        // Status row
        Row(children: [
          _StatusDot(status: conn.connectionStatus),
          const SizedBox(width: 8),
          Text(conn.connectionStatus.label,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const Spacer(),
          if (conn.lastCheckedAt != null)
            Text(
              'Last checked: ${_timeLabel(conn.lastCheckedAt!)}',
              style: proSubtitle(size: 9),
            ),
        ]),
        const SizedBox(height: 10),

        // Check connection button
        GestureDetector(
          onTap: onCheck,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: kProSurface,
              border: Border.all(color: kProBorder),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.refresh_outlined, size: 13, color: Colors.white38),
              const SizedBox(width: 6),
              Text('Check Connection Placeholder',
                  style: proLabel(size: 10, color: Colors.white38, spacing: 0)),
            ]),
          ),
        ),
        const SizedBox(height: 4),
        Text('Simulated status only. No real hardware scan.',
            style: proSubtitle(size: 9)),
      ]),
    );
  }

  String _timeLabel(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    return '${diff.inMinutes}m ago';
  }
}

class _StatusDot extends StatelessWidget {
  final HardwareConnectionStatus status;
  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      HardwareConnectionStatus.connected  => kProGreen,
      HardwareConnectionStatus.simulated  => const Color(0xFF4A9EFF),
      HardwareConnectionStatus.detected   => const Color(0xFF4A9EFF),
      HardwareConnectionStatus.error      => const Color(0xFFEF4444),
      HardwareConnectionStatus.unauthorized => kProAmber,
      HardwareConnectionStatus.driverMissing => kProAmber,
      _                                   => Colors.white24,
    };
    return Container(
      width: 8, height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _SelectChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SelectChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? kProAccent.withValues(alpha: 0.12) : kProSurface,
        border: Border.all(
            color: selected
                ? kProAccent.withValues(alpha: 0.5)
                : kProBorder),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              color: selected ? kProAccent : Colors.white38)),
    ),
  );
}

// ── Export Package Panel ──────────────────────────────────────────────────────

class _ExportPackagePanel extends StatelessWidget {
  final DspExportPackage? pkg;
  final dynamic protection; // ProtectionProjectState
  const _ExportPackagePanel({this.pkg, this.protection});

  @override
  Widget build(BuildContext context) {
    if (pkg == null) {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: kProSurface,
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline, color: Colors.white24, size: 13),
          const SizedBox(width: 8),
          Text('No export package. Generate an export draft first.',
              style: proSubtitle()),
        ]),
      );
    }

    final hasMapping = pkg!.sigmaMappingReferenceJson != null;
    final hasFP = pkg!.fixedPointDraftJson != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _InfoRow('Target', pkg!.targetPlatform.label),
        const SizedBox(height: 4),
        _InfoRow('Format', pkg!.format.label),
        const SizedBox(height: 4),
        _InfoRow('Status', pkg!.status.label),
        const SizedBox(height: 4),
        _InfoRow('Sigma Mapping', hasMapping ? 'Present' : 'Not generated'),
        const SizedBox(height: 4),
        _InfoRow('Fixed-point Draft', hasFP ? 'Present' : 'Not generated'),
        const SizedBox(height: 4),
        _InfoRow('Warnings', '${pkg!.warningCount}'),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Row(children: [
    Text('$label:', style: proLabel(size: 9, color: Colors.white38, spacing: 0)),
    const SizedBox(width: 8),
    Text(value, style: const TextStyle(color: Colors.white70, fontSize: 10)),
  ]);
}

// ── Guard Checklist Panel ─────────────────────────────────────────────────────

class _GuardChecklistPanel extends StatelessWidget {
  final HardwareWritePlan plan;
  const _GuardChecklistPanel({required this.plan});

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
          const _GuardPill(HardwareGuardStatus.pass),
          const SizedBox(width: 6),
          Text('${plan.guardChecks.where((c) => c.status == HardwareGuardStatus.pass).length}',
              style: const TextStyle(fontSize: 10, color: Colors.white54)),
          const SizedBox(width: 12),
          const _GuardPill(HardwareGuardStatus.warning),
          const SizedBox(width: 6),
          Text('${plan.warningCheckCount}',
              style: const TextStyle(fontSize: 10, color: Colors.white54)),
          const SizedBox(width: 12),
          const _GuardPill(HardwareGuardStatus.blocked),
          const SizedBox(width: 6),
          Text('${plan.blockedCheckCount}',
              style: const TextStyle(fontSize: 10, color: Colors.white54)),
        ]),
        const SizedBox(height: 10),
        ...plan.guardChecks.map((c) => _GuardCheckRow(check: c)),
      ]),
    );
  }
}

class _GuardCheckRow extends StatelessWidget {
  final HardwareGuardCheck check;
  const _GuardCheckRow({required this.check});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _GuardPill(check.status),
        const SizedBox(width: 8),
        Expanded(
          child: Text(check.title,
              style: const TextStyle(color: Colors.white70, fontSize: 10,
                  fontWeight: FontWeight.w500)),
        ),
      ]),
      Padding(
        padding: const EdgeInsets.only(left: 52, top: 2),
        child: Text(check.description, style: proSubtitle(size: 9)),
      ),
      if (check.recommendation != null)
        Padding(
          padding: const EdgeInsets.only(left: 52, top: 1),
          child: Text('→ ${check.recommendation}',
              style: proSubtitle(size: 9, color: kProAmber.withValues(alpha: 0.7))),
        ),
    ]),
  );
}

class _GuardPill extends StatelessWidget {
  final HardwareGuardStatus status;
  const _GuardPill(this.status);

  @override
  Widget build(BuildContext context) {
    final (color, bg) = switch (status) {
      HardwareGuardStatus.pass  => (kProGreen, kProGreen.withValues(alpha: 0.12)),
      HardwareGuardStatus.warning => (kProAmber, kProAmber.withValues(alpha: 0.12)),
      HardwareGuardStatus.blocked => (const Color(0xFFEF4444), const Color(0xFFEF4444).withValues(alpha: 0.12)),
      HardwareGuardStatus.notApplicable => (Colors.white24, Colors.white.withValues(alpha: 0.04)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(status.label, style: TextStyle(fontSize: 8, color: color)),
    );
  }
}

// ── Write Plan Panel ──────────────────────────────────────────────────────────

class _WritePlanPanel extends StatelessWidget {
  final HardwareWritePlan plan;
  const _WritePlanPanel({required this.plan});

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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: kProAmber.withValues(alpha: 0.12),
              border: Border.all(color: kProAmber.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text('DRY RUN ONLY',
                style: TextStyle(fontSize: 8, color: kProAmber,
                    fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          ),
          const SizedBox(width: 10),
          Text(plan.summary, style: proSubtitle(size: 9)),
        ]),
        const SizedBox(height: 10),
        if (plan.steps.isEmpty)
          Text('No write steps generated.', style: proSubtitle())
        else ...[
          // Column headers
          Row(children: [
            SizedBox(width: 24, child: Text('#', style: proLabel(size: 8, spacing: 0, color: Colors.white24))),
            Expanded(flex: 3, child: Text('LOGICAL NAME', style: proLabel(size: 8, spacing: 0, color: Colors.white24))),
            SizedBox(width: 60, child: Text('ADDRESS', style: proLabel(size: 8, spacing: 0, color: Colors.white24))),
            SizedBox(width: 50, child: Text('VERIFIED', style: proLabel(size: 8, spacing: 0, color: Colors.white24))),
            SizedBox(width: 55, child: Text('STATUS', style: proLabel(size: 8, spacing: 0, color: Colors.white24))),
          ]),
          const SizedBox(height: 6),
          const Divider(color: kProBorder, height: 1),
          const SizedBox(height: 4),
          ...plan.steps.map((s) => _StepRow(step: s)),
        ],
      ]),
    );
  }
}

class _StepRow extends StatelessWidget {
  final HardwareWritePlanStep step;
  const _StepRow({required this.step});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        SizedBox(
          width: 24,
          child: Text('${step.order + 1}',
              style: proSubtitle(size: 9)),
        ),
        Expanded(
          flex: 3,
          child: Text(step.logicalName,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
              overflow: TextOverflow.ellipsis),
        ),
        SizedBox(
          width: 60,
          child: Text(step.addressHex ?? '—',
              style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: step.addressHex != null
                      ? const Color(0xFF4A9EFF)
                      : Colors.white24)),
        ),
        SizedBox(
          width: 50,
          child: Text(step.addressVerified ? 'Yes' : 'No',
              style: TextStyle(
                  fontSize: 9,
                  color: step.addressVerified ? kProGreen : Colors.white38)),
        ),
        SizedBox(width: 55, child: _GuardPill(step.status)),
      ]),
      if (step.warning != null)
        Padding(
          padding: const EdgeInsets.only(left: 24, top: 1),
          child: Text(step.warning!,
              style: proSubtitle(size: 9, color: kProAmber.withValues(alpha: 0.7))),
        ),
    ]),
  );
}

// ── Warnings Panel ────────────────────────────────────────────────────────────

class _WarningsPanel extends StatelessWidget {
  final HardwareWritePlan plan;
  const _WarningsPanel({required this.plan});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kProAmber.withValues(alpha: 0.04),
        border: Border.all(color: kProAmber.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (plan.blockedReason != null) ...[
          Row(children: [
            const Icon(Icons.block_outlined, size: 12, color: kProAmber),
            const SizedBox(width: 6),
            Expanded(
              child: Text(plan.blockedReason!,
                  style: const TextStyle(fontSize: 10, color: kProAmber,
                      fontWeight: FontWeight.w500)),
            ),
          ]),
          const SizedBox(height: 6),
        ],
        ...plan.warnings.map((w) => Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('• ', style: TextStyle(fontSize: 9, color: Colors.white38)),
            Expanded(child: Text(w, style: proSubtitle(size: 9))),
          ]),
        )),
      ]),
    );
  }
}
