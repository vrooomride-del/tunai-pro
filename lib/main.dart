import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/home/workspace_home.dart';
import 'core/dsp_safety_notice.dart';
import 'shared/design/pro_theme.dart';

void main() {
  runApp(const ProviderScope(child: TunaiProApp()));
}

class TunaiProApp extends StatelessWidget {
  const TunaiProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TUNAI PRO',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: DspSafetyNotice.scaffoldMessengerKey,
      theme: buildProThemeV2(),
      home: const WorkspaceHome(),
    );
  }
}
