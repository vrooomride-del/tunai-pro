import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/pro_usbi_native_backend.dart';
import 'gain_tab.dart' show OperationalAdau1466MuteControls;

class MuteTab extends StatelessWidget {
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
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: OperationalAdau1466MuteControls(
          backend: usbiBackend ?? const ProUsbiNativeBackendDisabled(),
          isWindowsPlatform: isWindowsPlatform ?? () => Platform.isWindows,
          deviceOpen: deviceOpen,
          dspWritesDisabled: dspWritesDisabled,
          onDspWriteStop: onDspWriteStop,
        ),
      );
}
