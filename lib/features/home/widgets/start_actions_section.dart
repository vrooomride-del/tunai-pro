// TUNAI PRO UI v2 — Workspace Home start actions (Phase 4-A-1).
//
// UI extraction only: renders the same 7 ProHomeCards (5 preserved actions
// + the 2 previously-unlabelled "TOOLS" stubs, folded in rather than
// dropped) that lived inline in workspace_home.dart's build(), under
// ProSectionHeader labels instead of raw proLabel() text. All 7 callbacks
// are supplied by the caller — this widget only lays cards out, it never
// constructs navigation or reads any provider itself. The internal
// LayoutBuilder column heuristic replaces the deleted `_HomeGrid` (same
// `width > 600 ? 2 : 1` breakpoint), but uses Wrap instead of a single Row
// of Expanded so a 3-card and a 4-card group both tile cleanly into even
// rows (2-per-row) instead of squeezing every card in a section into one
// row regardless of count. Wrap never overflows horizontally, so this is
// at least as safe as the original at the overflow-smoke-test widths
// (1024/1280/1440).

import 'package:flutter/material.dart';

import '../../../shared/pro_widgets.dart';
import '../../../shared/components/section_header.dart';
import '../../../shared/design/pro_tokens.dart';

class StartActionsSection extends StatelessWidget {
  final VoidCallback onNewProject;
  final VoidCallback onOpenProject;
  final VoidCallback onOpenDemo;
  final VoidCallback onConnectHardware;
  final VoidCallback onImportData;
  final VoidCallback onDspProfileGenerator;
  final VoidCallback onDeviceManager;

  const StartActionsSection({
    super.key,
    required this.onNewProject,
    required this.onOpenProject,
    required this.onOpenDemo,
    required this.onConnectHardware,
    required this.onImportData,
    required this.onDspProfileGenerator,
    required this.onDeviceManager,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ProSpacing.xxl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const ProSectionHeader(title: 'Start'),
        const SizedBox(height: ProSpacing.md),
        _Grid(children: [
          ProHomeCard(
            title: 'New Project',
            subtitle: 'Create a new speaker or room tuning project.',
            icon: Icons.add_circle_outline,
            primary: true,
            onTap: onNewProject,
          ),
          ProHomeCard(
            title: 'Open Project',
            subtitle: 'Continue working on a saved tuning project.',
            icon: Icons.folder_open_outlined,
            onTap: onOpenProject,
          ),
          ProHomeCard(
            title: 'Open Demo Workstation',
            subtitle: 'TUNAI ONE Coax Demo — preloaded synthetic FRD/ZMA data, PEQ, XO, and deploy package.',
            icon: Icons.science_outlined,
            onTap: onOpenDemo,
          ),
        ]),
        const SizedBox(height: ProSpacing.xl),
        const ProSectionHeader(title: 'Hardware & Data', showDivider: true),
        const SizedBox(height: ProSpacing.md),
        _Grid(children: [
          ProHomeCard(
            title: 'Connect Hardware',
            subtitle: 'Connect TUNAI ONE, ACM, USB, network, or AOS-compatible hardware.',
            icon: Icons.usb_outlined,
            onTap: onConnectHardware,
          ),
          ProHomeCard(
            title: 'Import Data',
            subtitle: 'Load FRD, ZMA, impulse response, or measurement files.',
            icon: Icons.upload_file_outlined,
            onTap: onImportData,
          ),
          ProHomeCard(
            title: 'DSP Profile Generator',
            subtitle: 'Convert tuning decisions into deployable DSP profiles.',
            icon: Icons.settings_ethernet_outlined,
            onTap: onDspProfileGenerator,
          ),
          ProHomeCard(
            title: 'Device Manager',
            subtitle: 'Manage connected devices, firmware, and profile deployment.',
            icon: Icons.devices_outlined,
            onTap: onDeviceManager,
          ),
        ]),
      ]),
    );
  }
}

class _Grid extends StatelessWidget {
  final List<Widget> children;
  const _Grid({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final cols = constraints.maxWidth > 600 ? 2 : 1;
      if (cols == 1) {
        return Column(
          children: children
              .map((c) => Padding(padding: const EdgeInsets.only(bottom: 10), child: c))
              .toList(),
        );
      }
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: children
            .map((c) => SizedBox(width: (constraints.maxWidth - 10) / 2, child: c))
            .toList(),
      );
    });
  }
}
