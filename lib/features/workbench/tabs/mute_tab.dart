import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/pro_project_store.dart';
import '../../../core/pro_usbi_native_backend.dart';
import '../../../shared/pro_widgets.dart';
import 'gain_tab.dart' show OperationalAdau1466MuteControls;

/// P0-4 — target-aware Mute tab. ADAU1466's operational Mute controls (USBi
/// writes against ADAU1466-specific Sigma-block addresses) must never render
/// for an ADAU1701 project — those addresses mean nothing on that hardware.
/// ADAU1701 has no hardware-verified Mute write path wired to this tab
/// today (see [_Adau1701MuteUnavailable]'s doc comment), so it shows an
/// honest unavailable state rather than either the wrong hardware's
/// controls or a fabricated ADAU1701 write.
class MuteTab extends ConsumerWidget {
  final String projectId;
  final ProUsbiNativeBackend? usbiBackend;
  final bool Function()? isWindowsPlatform;
  final bool deviceOpen;
  final bool dspWritesDisabled;
  final void Function(String warning)? onDspWriteStop;

  const MuteTab(
      {super.key,
      required this.projectId,
      this.usbiBackend,
      this.isWindowsPlatform,
      this.deviceOpen = false,
      this.dspWritesDisabled = false,
      this.onDspWriteStop});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(proProjectStoreProvider);
    final project = store.projects.where((p) => p.id == projectId).firstOrNull;
    final isAdau1466 = project?.dspTarget == 'ADAU1466';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: isAdau1466
          ? OperationalAdau1466MuteControls(
              backend: usbiBackend ?? const ProUsbiNativeBackendDisabled(),
              isWindowsPlatform: isWindowsPlatform ?? () => Platform.isWindows,
              deviceOpen: deviceOpen,
              dspWritesDisabled: dspWritesDisabled,
              onDspWriteStop: onDspWriteStop,
            )
          : const _Adau1701MuteUnavailable(),
    );
  }
}

/// ADAU1701 has no hardware-verified Mute write path wired to this tab.
/// `writeMasterMute`/`writeCapturedMasterMuteState` exist on the ICP5
/// transport (lib/core/transport/icp5_transports.dart) and are reachable
/// from the Hardware diagnostics panel, but carry no readback verification
/// and are not connected to this UI — showing them here would imply a
/// build-verified control that does not exist. Do not implement a new
/// ADAU1701 Mute write from a candidate address/polarity to close this gap;
/// only wire this tab up once a real, hardware-verified path exists.
class _Adau1701MuteUnavailable extends StatelessWidget {
  const _Adau1701MuteUnavailable();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: kProSurface,
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 16, color: Colors.white38),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'ADAU1701 Mute control is not hardware-verified in this '
                'build.',
                style: proSubtitle(size: 12),
              ),
            ),
          ],
        ),
      );
}
