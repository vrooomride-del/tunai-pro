// Widget-level regression: DeployDialog with 4 known channels must NOT
// render "No driver channels configured." — it must render "No pending writes."
// when no gain/PEQ/XO writes are needed.
//
// This test pins the _planView branch: with non-empty channels and a plan that
// produces 0 writable operations, the condition must be 'No pending writes.',
// not 'No driver channels configured.'.
//
// If this test fails, the runtime binary is using the pre-Task-B condition
// (_plan.operations.isEmpty instead of widget.channels.isEmpty).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/features/workbench/widgets/deploy_dialog.dart';

const _kChannels = [
  DriverChannel(id: 'ch_tw_l', name: 'Tweeter L', role: DriverRole.tweeter, side: DriverSide.left),
  DriverChannel(id: 'ch_wf_l', name: 'Woofer L',  role: DriverRole.woofer,  side: DriverSide.left),
  DriverChannel(id: 'ch_tw_r', name: 'Tweeter R', role: DriverRole.tweeter, side: DriverSide.right),
  DriverChannel(id: 'ch_wf_r', name: 'Woofer R',  role: DriverRole.woofer,  side: DriverSide.right),
];

/// Pumps a minimal scaffold that opens DeployDialog with [channels] when built.
/// The dialog is opened immediately via addPostFrameCallback so tests can
/// find it after the first pump+settle.
Widget _host({
  List<DriverChannel> channels = _kChannels,
  TuningProjectState? tuning,
  Map<String, double> previousAppliedGains = const {},
}) {
  return ProviderScope(
    child: MaterialApp(
      home: _DialogOpener(
        channels: channels,
        tuning: tuning ?? TuningProjectState.createDefault(),
        previousAppliedGains: previousAppliedGains,
      ),
    ),
  );
}

class _DialogOpener extends StatefulWidget {
  final List<DriverChannel> channels;
  final TuningProjectState tuning;
  final Map<String, double> previousAppliedGains;

  const _DialogOpener({
    required this.channels,
    required this.tuning,
    required this.previousAppliedGains,
  });

  @override
  State<_DialogOpener> createState() => _DialogOpenerState();
}

class _DialogOpenerState extends State<_DialogOpener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDeployDialog(
        context: context,
        projectId: 'test-proj',
        channels: widget.channels,
        tuning: widget.tuning,
        previousAppliedGains: widget.previousAppliedGains,
      );
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('host')));
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DeployDialog channel rendering', () {
    testWidgets(
        '4 channels + no pending writes → shows "No pending writes." not '
        '"No driver channels configured."', (tester) async {
      // Default tuning: all gains 0 dB, no PEQ bands enabled, no XO.
      // buildAdau1701GainExportPackage → 0 blocks (0 dB = hardware default).
      // buildAdau1701PeqXoExportBlocks → 0 blocks.
      // _hasWritableOps = false → planView renders the no-ops message.
      // Expected: 'No pending writes.' (not 'No driver channels configured.')
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(
        find.text('No driver channels configured.'),
        findsNothing,
        reason: 'widget.channels has 4 entries → must not show channels-empty message',
      );
      expect(
        find.text('No pending writes.'),
        findsOneWidget,
        reason: 'widget.channels non-empty, no writes needed → pending-writes message',
      );
      // Never-tuned project (peqChannels empty): the empty state must name the
      // next action, not just say "nothing to do".
      expect(
        find.textContaining('Run Guided AI or manual tuning first'),
        findsOneWidget,
        reason: 'empty state must tell the user what to do next',
      );
    });

    testWidgets(
        'empty channels list → shows "No driver channels configured."',
        (tester) async {
      // Confirms the message IS shown when channels are genuinely empty.
      // This should only happen if canDeploy allows it (it normally doesn't).
      await tester.pumpWidget(_host(channels: const []));
      await tester.pumpAndSettle();

      expect(
        find.text('No driver channels configured.'),
        findsOneWidget,
        reason: 'empty channels → channels-empty message',
      );
      expect(
        find.text('No pending writes.'),
        findsNothing,
      );
    });

    testWidgets(
        'channels passed to showDeployDialog are not lost in modal route',
        (tester) async {
      // Regression: channels must survive the showDialog builder closure.
      // If channels were replaced with [] during route construction, the first
      // test above would also show 'No driver channels configured.'.
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      // 4 channels × 0-dB default → 0 gain blocks → 0 writable ops.
      // The message is driven by widget.channels.isEmpty, not plan state.
      expect(find.text('No driver channels configured.'), findsNothing);
    });

    testWidgets(
        'non-zero gain on one channel → plan shows PENDING WRITES header',
        (tester) async {
      // Confirms the plan path works: when a gain is set, the plan is non-empty
      // and the dialog shows the ops list, not the no-ops message.
      final tuning = TuningProjectState.createDefault();
      final ctrl = tuning.getOrCreateControl('ch_tw_l').copyWith(gainDb: -6.0);
      final tuningWithGain = tuning.replaceControl(ctrl);

      await tester.pumpWidget(_host(tuning: tuningWithGain));
      await tester.pumpAndSettle();

      expect(find.text('No driver channels configured.'), findsNothing);
      expect(find.text('No pending writes.'), findsNothing);
      // The plan view header for writable ops.
      expect(find.text('PENDING WRITES'), findsOneWidget);
    });
  });
}
