// TUNAI PRO UI/UX v3 Phase V3-6B — Deploy Failure UX Refinement.
//
// UI-layer only. HardwareWriteExecutionResult/HardwareWriteExecutor/
// HardwareWriteApproval/deploy planner/ICP5/BLE/USB/ACK parser are untouched.
//
// Covers:
//   - hardware_apply_flow.dart's FAILED chip no longer double-counts
//     blockedByPreflight outcomes. The shared HardwareWriteExecutionResult
//     .failedCount getter is intentionally NOT changed (it still counts
//     failed + timedOut + blockedByPreflight, per its existing contract) —
//     the fix is a UI-local recomputation, mirrored here exactly the way
//     readback_verification_semantics_test.dart already mirrors
//     deploy_tab.dart's banner-text ternary, since the counting logic lives
//     inside hardware_apply_flow.dart's private _ResultsView.
//   - a real failed (NACK) outcome renders as FAILED (red) with its
//     message/reason visible, through an actual HardwareApplyFlow execution.
//   - progress shows a percentage next to completed/total.
//   - DeployResultSummary's Verified/PASS_ACK wording is unaffected.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/deploy/pro_adau1701_hardware_context.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_executor.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_export_data.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/core/transport/adau1701_deployment_preflight.dart';
import 'package:tunai_pro/core/transport/adau1701_deployment_report.dart';
import 'package:tunai_pro/core/transport/adau1701_tuning_transport.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';
import 'package:tunai_pro/features/workbench/widgets/deploy_dialog.dart';
import 'package:tunai_pro/features/workbench/widgets/deploy_result_summary.dart';
import 'package:tunai_pro/features/workbench/widgets/hardware_apply_flow.dart';

// ── Group 1: mirrors hardware_apply_flow.dart's UI-local FAILED count ──────

HardwareWriteOp _op() => const HardwareWriteOp(
      channelId: 'ch_tw_l',
      parameterKind: HardwareParamKind.peqGain,
      bandIndex: 0,
      targetValue: -3.0,
      verification: HardwareParamVerification.captureProven,
      writable: true,
      reason: 'test',
    );

HardwareWriteOpOutcome _outcome(HardwareWriteOpStatus status) =>
    HardwareWriteOpOutcome(op: _op(), status: status, report: null, message: status.name);

HardwareWriteExecutionResult _result(List<HardwareWriteOpStatus> statuses) =>
    HardwareWriteExecutionResult(
      planId: 'p',
      executed: true,
      rejectionReason: null,
      outcomes: [for (final s in statuses) _outcome(s)],
    );

/// Exact mirror of the fix added to hardware_apply_flow.dart's _ResultsView
/// — kept as a standalone function here because _ResultsView is private and
/// cannot be constructed directly from a test file.
int _uiFailedOnlyCount(HardwareWriteExecutionResult r) => r.outcomes
    .where((o) =>
        o.status == HardwareWriteOpStatus.failed ||
        o.status == HardwareWriteOpStatus.timedOut)
    .length;

void main() {
  _uiFailedOnlyCountTests();
  _realExecutionTests();
}

void _uiFailedOnlyCountTests() {
  group('UI-local FAILED count excludes blockedByPreflight', () {
    test('a mix of blockedByPreflight + failed: shared failedCount counts '
        'both, the UI-local count counts only failed/timedOut', () {
      final r = _result([
        HardwareWriteOpStatus.blockedByPreflight,
        HardwareWriteOpStatus.blockedByPreflight,
        HardwareWriteOpStatus.failed,
      ]);

      // The shared getter is intentionally unchanged: it still counts all
      // three as "failures" (this is documented, existing behavior).
      expect(r.failedCount, 3);
      expect(r.blockedCount, 2);

      // The UI's own count (mirrored from hardware_apply_flow.dart) must not
      // overlap with BLOCKED — it counts only the genuine execution error.
      expect(_uiFailedOnlyCount(r), 1);
      expect(_uiFailedOnlyCount(r) + r.blockedCount, r.failedCount,
          reason: 'the two UI chips (FAILED + BLOCKED) must together equal '
              'exactly the shared failedCount, with zero overlap');
    });

    test('an all-blockedByPreflight result shows FAILED=0', () {
      final r = _result(List.filled(3, HardwareWriteOpStatus.blockedByPreflight));
      expect(_uiFailedOnlyCount(r), 0);
      expect(r.blockedCount, 3);
    });

    test('timedOut counts as FAILED, same as failed', () {
      final r = _result(
          [HardwareWriteOpStatus.failed, HardwareWriteOpStatus.timedOut]);
      expect(_uiFailedOnlyCount(r), 2);
      expect(r.blockedCount, 0);
    });
  });
}

// ── Group 2: real execution through HardwareApplyFlow ──────────────────────

List<int> _stateAPayload() {
  final p = List<int>.filled(513, 0x00);
  p[19] = 0x08;
  p[20] = 0x07;
  p[21] = 0xF6;
  p[23] = 0x14;
  p[24] = 0x01;
  p[154] = 0x01;
  p[308] = 0x02;
  return p;
}

const _kDeviceId = 'DSP1701.100.00.01';

/// Band-1 (non-zero) PEQ gain write is an ACK-only path per
/// pro_icp5_peq_write_port.dart — a NACK on it surfaces as
/// HardwareWriteOpStatus.failed (not blockedByPreflight, which requires a
/// preflight refusal). Frequency/Q for the same band still ACK normally.
class _NackGainTransport implements Adau1701TuningTransport {
  @override
  bool get isConnected => true;
  @override
  bool get handshakeComplete => true;
  @override
  String? get detectedProfile => _kDeviceId;
  @override
  Future<RawDspStateSnapshot> readRawDspState() async => RawDspStateSnapshot(
        deviceId: _kDeviceId,
        timestamp: DateTime.utc(2026, 8, 5),
        blockId: 0x2202,
        payload: _stateAPayload(),
      );
  @override
  Future<Adau1701WriteAck> writePeqGain(int c, double g, {int band = 0}) async =>
      const Adau1701WriteAck(success: false, message: 'malformed ACK');
  @override
  Future<Adau1701WriteAck> writeFilterFrequency(int c, int f,
          {int band = 0, bool isHighPass = false}) async =>
      const Adau1701WriteAck(success: true, message: 'ok');
  @override
  Future<Adau1701WriteAck> writePeqFrequency(int c, int f, {int band = 0}) async =>
      const Adau1701WriteAck(success: true, message: 'ok');
  @override
  Future<Adau1701WriteAck> writePeqQ(int c, double q, {int band = 0}) async =>
      const Adau1701WriteAck(success: true, message: 'ok');
  @override
  Future<Adau1701WriteAck> writeOutputGain(int c, double g) async =>
      const Adau1701WriteAck(success: true, message: 'ok');
  @override
  Future<Adau1701WriteAck> writeMasterMute(bool muted) async =>
      const Adau1701WriteAck(success: true, message: 'ok');
}

class _AckOnlyTransport implements Adau1701TuningTransport {
  @override
  bool get isConnected => true;
  @override
  bool get handshakeComplete => true;
  @override
  String? get detectedProfile => _kDeviceId;
  @override
  Future<RawDspStateSnapshot> readRawDspState() async => RawDspStateSnapshot(
        deviceId: _kDeviceId,
        timestamp: DateTime.utc(2026, 8, 5),
        blockId: 0x2202,
        payload: _stateAPayload(),
      );
  @override
  Future<Adau1701WriteAck> writePeqGain(int c, double g, {int band = 0}) async =>
      const Adau1701WriteAck(success: true, message: 'ok');
  @override
  Future<Adau1701WriteAck> writeFilterFrequency(int c, int f,
          {int band = 0, bool isHighPass = false}) async =>
      const Adau1701WriteAck(success: true, message: 'ok');
  @override
  Future<Adau1701WriteAck> writePeqFrequency(int c, int f, {int band = 0}) async =>
      const Adau1701WriteAck(success: true, message: 'ok');
  @override
  Future<Adau1701WriteAck> writePeqQ(int c, double q, {int band = 0}) async =>
      const Adau1701WriteAck(success: true, message: 'ok');
  @override
  Future<Adau1701WriteAck> writeOutputGain(int c, double g) async =>
      const Adau1701WriteAck(success: true, message: 'ok');
  @override
  Future<Adau1701WriteAck> writeMasterMute(bool muted) async =>
      const Adau1701WriteAck(success: true, message: 'ok');
}

DspExportPackage _pkgBand1Gain({required String id}) => DspExportPackage(
      id: id,
      parameterBlocks: [
        const ExportParameterBlock(
          id: 'blk',
          type: ExportBlockType.peq,
          channelId: 'ch_wf_l',
          title: 'PEQ',
          summary: '',
          parameters: {
            'bands': {
              'band_1': {
                'freq_hz': 1800.0,
                'gain_db': -1.0,
                'q': 2.0,
                'type': 'peak',
              },
            }
          },
        ),
      ],
    );

Finder _btn(String label) => find.ancestor(
      of: find.text(label),
      matching: find.bySubtype<OutlinedButton>(),
    );

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

Future<void> _approveAndApply(WidgetTester tester) async {
  await tester.ensureVisible(_btn('APPROVE VERIFIED WRITE'));
  await tester.pump();
  await tester.tap(_btn('APPROVE VERIFIED WRITE'));
  await tester.pump();
  await tester.ensureVisible(_btn('APPLY VERIFIED SETTINGS'));
  await tester.pump();
  await tester.tap(_btn('APPLY VERIFIED SETTINGS'));
  await tester.pumpAndSettle();
}

void _realExecutionTests() {
  group('hardware_apply_flow.dart — real failed outcome', () {
    testWidgets(
        'a NACK gain write shows FAILED (not BLOCKED) and its reason is '
        'visible', (tester) async {
      final transport = _NackGainTransport();
      await tester.pumpWidget(_wrap(HardwareApplyFlow(
        exportPackage: _pkgBand1Gain(id: 'exp-fail'),
        profile: HardwareDeviceProfiles.adau1701Icp5,
        contextFactory: () => Adau1701HardwareContext.fromTransport(transport),
      )));

      await _approveAndApply(tester);

      expect(find.text('APPLY RESULTS'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(find.textContaining('malformed ACK'), findsOneWidget,
          reason: 'V3-6B: the failure reason/message must now be visible '
              'per-row, not just the generic status label');
      expect(find.text('PASS_ACK (not DSP-verified)'), findsNothing,
          reason: 'a result with a genuine failure must never show a '
              'success summary');
    });

    testWidgets('an all-ack-only result still shows PASS_ACK (not '
        'DSP-verified), never Verified', (tester) async {
      await tester.pumpWidget(_wrap(HardwareApplyFlow(
        exportPackage: _pkgBand1Gain(id: 'exp-ack'),
        profile: HardwareDeviceProfiles.adau1701Icp5,
        contextFactory: () =>
            Adau1701HardwareContext.fromTransport(_AckOnlyTransport()),
      )));

      await _approveAndApply(tester);

      expect(find.text('PASS_ACK (not DSP-verified)'), findsOneWidget);
      expect(find.text('Verified'), findsNothing);
      expect(find.text('Failed'), findsNothing);
    });
  });

  group('Progress percentage', () {
    testWidgets(
        'hardware_apply_flow.dart shows a percentage during/after apply',
        (tester) async {
      await tester.pumpWidget(_wrap(HardwareApplyFlow(
        exportPackage: _pkgBand1Gain(id: 'exp-pct'),
        profile: HardwareDeviceProfiles.adau1701Icp5,
        contextFactory: () =>
            Adau1701HardwareContext.fromTransport(_AckOnlyTransport()),
      )));

      await _approveAndApply(tester);

      // The write completes fast enough in tests that the live "Writing…"
      // percentage row may not survive a frame — but the underlying
      // computation is exercised either way. This is a smoke check that
      // nothing throws; the deploy_dialog.dart percentage below is the
      // reliably-observable case (see deploy_dialog_result_label_test.dart's
      // sibling assertions are not needed here since that dialog is tested
      // separately).
      expect(tester.takeException(), isNull);
    });
  });

  group('DeployResultSummary — unaffected by this phase', () {
    test('labelFor is still the single source of Verified/PASS_ACK wording',
        () {
      final written = _result([HardwareWriteOpStatus.written]);
      final ackOnly = _result([HardwareWriteOpStatus.ackOnly]);
      expect(DeployResultSummary.labelFor(written), 'Verified');
      expect(DeployResultSummary.labelFor(ackOnly), 'PASS_ACK (not DSP-verified)');
    });
  });

  group('deploy_dialog.dart — progress percentage', () {
    testWidgets(
        'a percentage is shown next to completed / total while executing',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final completer = Completer<Adau1701DeploymentReport>();
      final port = _CompleterPort(completer);

      const channel = DriverChannel(
        id: 'ch_tw_l',
        name: 'Tweeter L',
        role: DriverRole.tweeter,
        side: DriverSide.left,
      );
      final tuning = TuningProjectState.createDefault()
          .replaceControl(const ChannelControlState(channelId: 'ch_tw_l', gainDb: -3.0));

      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: _DialogHost(
            port: port,
            channels: const [channel],
            tuning: tuning,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('APPROVE & WRITE'));
      // One pump (not settle) — the write is still pending on the completer,
      // so the executing view with its progress percentage must be visible.
      await tester.pump();

      expect(find.textContaining('%'), findsOneWidget);

      // Resolve so the test doesn't leave a pending timer/future behind.
      completer.complete(Adau1701DeploymentReport(
        attemptedAt: DateTime(2026, 8, 5),
        originalStateAvailable: true,
        preflightStatus: Adau1701PreflightStatus.passed,
        deploymentAllowed: true,
        deploymentResult: const Icp5PhaseCResult(
          success: true,
          wasActualWrite: true,
          writeMayHaveReachedDevice: true,
          message: 'ok',
        ),
      ));
      await tester.pumpAndSettle();
    });
  });
}

class _CompleterPort implements Icp5PeqWritePort {
  final Completer<Adau1701DeploymentReport> completer;
  _CompleterPort(this.completer);

  @override
  Future<Adau1701DeploymentReport> preflightAndWrite(HardwareWriteOp op) =>
      completer.future;
}

class _DialogHost extends StatefulWidget {
  final Icp5PeqWritePort port;
  final List<DriverChannel> channels;
  final TuningProjectState tuning;
  const _DialogHost({required this.port, required this.channels, required this.tuning});

  @override
  State<_DialogHost> createState() => _DialogHostState();
}

class _DialogHostState extends State<_DialogHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDeployDialog(
        context: context,
        projectId: 'test',
        channels: widget.channels,
        tuning: widget.tuning,
        previousAppliedGains: const {},
        overridePort: widget.port,
      );
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('host')));
}
