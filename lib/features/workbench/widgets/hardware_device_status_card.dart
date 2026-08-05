// TUNAI PRO UI/UX v3 Phase V3-5A — Hardware Device Status Card.
//
// A single, read-only "DEVICE STATUS" summary separating four verification
// layers the rest of the UI currently conflates (see the V3-5 audit):
//   - Transport:            activeAdau1701ContextProvider live state — the
//                            fresh, in-memory transport handle that is null
//                            on every app restart until a real BLE/USB
//                            connect flow repopulates it this session.
//   - DSP Identity:         existing HardwareConnection.connected semantics
//                            (project_status_bar.dart's isConnected), which
//                            is already gated on a real PASS_HANDSHAKE
//                            identity confirmation — combined with the live
//                            transport check so a stale, restart-surviving
//                            persisted flag never reads as "Verified" with
//                            nothing actually connected.
//   - Parameter Readback:   no connection-level aggregate exists yet in this
//                            codebase — only per-operation
//                            HardwareWriteOpStatus results, shown per-row in
//                            the Deploy dialog. This card states that
//                            limitation instead of inventing an aggregate.
//   - Physical Output:      always "Not Tested" — no automated path exists
//                            anywhere in the app for this, by design; this
//                            row exists so the gap is visible, not hidden.
//
// Presentation only. No BLE/USB transport, ICP5 protocol, ACK parser, DSP
// executor, or deploy write-flow code is read, written, or duplicated here
// beyond the two booleans already computed elsewhere in the app.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/deploy/pro_hardware_context_provider.dart';
import '../../../core/pro_project.dart';
import '../../../core/pro_project_store.dart';
import '../../../shared/components/info_row.dart';
import '../../../shared/components/section_header.dart';
import '../../../shared/pro_widgets.dart';

class HardwareDeviceStatusCard extends ConsumerWidget {
  final String projectId;
  const HardwareDeviceStatusCard({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref
        .watch(proProjectStoreProvider)
        .projects
        .where((p) => p.id == projectId)
        .firstOrNull;

    final hasLiveContext = ref.watch(activeAdau1701ContextProvider) != null;
    final isConnectedPersisted =
        project?.connection == HardwareConnection.connected;
    final dspIdentityVerified = isConnectedPersisted && hasLiveContext;

    const dimColor = Color(0xFF6B7280);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const ProSectionHeader(
            title: 'DEVICE STATUS', icon: Icons.verified_outlined),
        const SizedBox(height: 10),
        ProInfoRow(
          label: 'Transport',
          value: hasLiveContext ? 'Connected' : 'Disconnected',
          valueColor: hasLiveContext ? kProGreen : dimColor,
        ),
        ProInfoRow(
          label: 'DSP Identity',
          value: dspIdentityVerified ? 'Verified' : 'Not Verified',
          valueColor: dspIdentityVerified ? kProGreen : dimColor,
        ),
        const SizedBox(height: 2),
        const Row(children: [
          Expanded(
            flex: 2,
            child: Text('Parameter Readback',
                style: TextStyle(color: dimColor, fontSize: 12)),
          ),
          SizedBox(width: 8),
          ProStatusPill(label: 'NOT AVAILABLE', color: kProAmber),
        ]),
        const SizedBox(height: 6),
        const ProInfoRow(
          label: 'Physical Output',
          value: 'Not Tested',
          valueColor: dimColor,
        ),
      ]),
    );
  }
}
