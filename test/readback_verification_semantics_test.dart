// TUNAI PRO UI/UX v3 Phase V3-5B — Readback Verification Semantics Fix.
//
// Bug: HardwareWriteExecutionResult.allWritten's doc comment claimed
// "readback verification", but its implementation (outcomes.every((o) =>
// o.succeeded)) is true for BOTH `written` AND `ackOnly` outcomes.
// deploy_tab.dart used allWritten to gate a green "PASS_ACK 수신 — DSP 쓰기
// 완료." ("write complete") banner — so an all-ack-only result (which is the
// common case: even a real, production band-0/channel-0 PEQ write always
// includes an ack-only Q op, see pro_icp5_peq_write_port.dart) rendered as
// if it were fully DSP-verified.
//
// Fix (presentation/aggregate only — no write execution, retry, transport,
// protocol, or ACK-parser change):
//   - allWritten is kept exactly as-is (not removed/renamed) for existing
//     callers/tests.
//   - New HardwareWriteExecutionResult.allReadbackVerified: true only when
//     every outcome is HardwareWriteOpStatus.written (no ack-only).
//   - deploy_tab.dart's banner text (not its branch gate, which is still
//     allWritten, unchanged) now reads allReadbackVerified to choose between
//     "Verified — DSP 쓰기 완료." and "PASS_ACK (not DSP-verified) — 쓰기
//     승인됨."

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/deploy/pro_adau1701_hardware_context.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_context_provider.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_executor.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_write_plan.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_export_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/transport/adau1701_tuning_transport.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';
import 'package:tunai_pro/features/workbench/tabs/deploy_tab.dart';

const _kProjectsKey = 'tunai_pro_projects';

// ── Group 1/2 helpers: unit-level result fixtures ──────────────────────────

HardwareWriteOp _op({int? bandIndex}) => HardwareWriteOp(
      channelId: 'ch_tw_l',
      parameterKind: HardwareParamKind.peqGain,
      bandIndex: bandIndex,
      targetValue: -3.0,
      verification: HardwareParamVerification.captureProven,
      writable: true,
      reason: 'test',
    );

HardwareWriteOpOutcome _outcome(HardwareWriteOpStatus status) =>
    HardwareWriteOpOutcome(
      op: _op(bandIndex: 0),
      status: status,
      report: null,
      message: status.name,
    );

HardwareWriteExecutionResult _result(List<HardwareWriteOpStatus> statuses) =>
    HardwareWriteExecutionResult(
      planId: 'p',
      executed: true,
      rejectionReason: null,
      outcomes: [for (final s in statuses) _outcome(s)],
    );

/// Mirrors deploy_tab.dart's banner text ternary exactly — the same pattern
/// deploy_button_enablement_test.dart already uses to test an extracted
/// predicate rather than duplicating a full widget mount for pure logic.
String _bannerText(HardwareWriteExecutionResult result) =>
    result.allReadbackVerified
        ? 'Verified — DSP write complete.'
        : 'PASS_ACK (not DSP-verified) — Write accepted.';

// ── Group 3 helpers: real production write path (widget-level) ────────────

class _FakeConnectedTransport implements Adau1701TuningTransport {
  @override
  bool get isConnected => true;
  @override
  bool get handshakeComplete => true;
  @override
  String? get detectedProfile => 'DSP1701.100.00.01';
  @override
  Future<RawDspStateSnapshot> readRawDspState() async => RawDspStateSnapshot(
        deviceId: 'DSP1701.100.00.01',
        timestamp: DateTime.utc(2026, 8, 5),
        blockId: 0x2202,
        payload: List<int>.filled(513, 0x00),
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

const _kTweeterL = DriverChannel(
  id: 'ch_tw_l',
  name: 'Tweeter L',
  role: DriverRole.tweeter,
  side: DriverSide.left,
  dspOutputIndex: 1,
);

ProProject _projectWithBand0Peq() {
  final now = DateTime.utc(2026, 8, 5);
  final pkg = DspExportPackage(
    id: 'pkg_peq',
    targetPlatform: DspTargetPlatform.adau1701,
    status: ExportStatus.draftReady,
    projectName: 'Readback verification semantics test',
    parameterBlocks: [
      ExportParameterBlock(
        id: 'peq_ch_tw_l',
        type: ExportBlockType.peq,
        channelId: 'ch_tw_l',
        title: 'Tweeter L PEQ',
        summary: 'Band 1',
        parameters: {
          'bands': {
            // band_1 (any band > 0) is unconditionally ACK-only for
            // gain/frequency/Q — no PRO readback service exists for
            // non-band-0 PEQ slots (pro_icp5_peq_write_port.dart) — this is
            // exactly the common real production write that used to render
            // the misleading "write complete" banner via the buggy
            // allWritten-only gate.
            'band_1': {'freq_hz': 1000.0, 'gain_db': -3.0, 'q': 1.0},
          },
        },
      ),
    ],
  );
  return ProProject(
    id: 'p_readback',
    name: 'Readback verification semantics test',
    createdAt: now,
    updatedAt: now,
    dspTarget: 'ADAU1701',
    connection: HardwareConnection.connected,
    acousticState: MeasurementProjectState.createDefault()
        .copyWith(driverChannels: const [_kTweeterL]),
    exportState: ExportProjectState(
      selectedTarget: DspTargetPlatform.adau1701,
      packages: [pkg],
      activePackageId: pkg.id,
    ),
  );
}

void _seed(ProProject project) {
  SharedPreferences.setMockInitialValues({
    _kProjectsKey: ProProject.encodeList([project]),
  });
}

void main() {
  group('HardwareWriteExecutionResult.allReadbackVerified', () {
    test('true when every outcome is written', () {
      final result = _result(
          [HardwareWriteOpStatus.written, HardwareWriteOpStatus.written]);
      expect(result.allReadbackVerified, isTrue);
      expect(result.allWritten, isTrue, reason: 'unchanged field');
    });

    test('false when any outcome is ack-only, even with no failures', () {
      final result = _result(
          [HardwareWriteOpStatus.written, HardwareWriteOpStatus.ackOnly]);
      expect(result.allReadbackVerified, isFalse);
      // allWritten must remain true here — this is the exact case the bug
      // was about: allWritten alone cannot distinguish this from a fully
      // readback-verified result.
      expect(result.allWritten, isTrue);
    });

    test('false for an all-ack-only result', () {
      final result = _result(List.filled(3, HardwareWriteOpStatus.ackOnly));
      expect(result.allReadbackVerified, isFalse);
      expect(result.allWritten, isTrue);
      expect(result.allPassed, isTrue);
    });

    test('false when execution failed, regardless of other outcomes', () {
      final result = _result(
          [HardwareWriteOpStatus.written, HardwareWriteOpStatus.failed]);
      expect(result.allReadbackVerified, isFalse);
      expect(result.allWritten, isFalse);
    });

    test('false for an empty/unexecuted result', () {
      const result = HardwareWriteExecutionResult(
        planId: 'p',
        executed: false,
        rejectionReason: 'no approved operations',
        outcomes: [],
      );
      expect(result.allReadbackVerified, isFalse);
    });
  });

  group('deploy_tab.dart banner text selection (mirrors production ternary)', () {
    test('ack-only outcomes never produce the "Verified" banner text', () {
      final result = _result(List.filled(3, HardwareWriteOpStatus.ackOnly));
      expect(_bannerText(result), 'PASS_ACK (not DSP-verified) — Write accepted.');
      expect(_bannerText(result), isNot(contains('Verified —')));
    });

    test('a mixed written+ackOnly result also stays in the ack-only wording',
        () {
      final result = _result(
          [HardwareWriteOpStatus.written, HardwareWriteOpStatus.ackOnly]);
      expect(_bannerText(result), 'PASS_ACK (not DSP-verified) — Write accepted.');
    });

    test('a fully readback-verified result produces the "Verified" banner',
        () {
      final result = _result(
          [HardwareWriteOpStatus.written, HardwareWriteOpStatus.written]);
      expect(_bannerText(result), 'Verified — DSP write complete.');
    });
  });

  group('DeployTab — real production write path, widget level', () {
    testWidgets(
        'a real band-1 PEQ apply (all ops ack-only, no readback service) '
        'shows the ack-only banner text, never "Verified"', (tester) async {
      _seed(_projectWithBand0Peq());
      final fakeCtx =
          Adau1701HardwareContext.fromTransport(_FakeConnectedTransport());

      await tester.pumpWidget(ProviderScope(
        overrides: [
          activeAdau1701ContextProvider.overrideWith((ref) => fakeCtx),
        ],
        child: const MaterialApp(
          home: Scaffold(body: DeployTab(projectId: 'p_readback')),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('APPROVE VERIFIED WRITE'));
      await tester.tap(find.text('APPROVE VERIFIED WRITE'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('APPLY VERIFIED SETTINGS'));
      await tester.tap(find.text('APPLY VERIFIED SETTINGS'));
      await tester.pumpAndSettle();

      expect(find.text('PASS_ACK (not DSP-verified) — Write accepted.'),
          findsOneWidget,
          reason: 'band-1 gain/frequency/Q are all ack-only for this real '
              'write path — the summary banner must not claim full '
              'verification');
      expect(find.text('Verified — DSP 쓰기 완료.'), findsNothing);
      expect(find.textContaining('PASS_ACK 수신 — DSP 쓰기 완료.'), findsNothing,
          reason: 'the old, unqualified "write complete" wording must be '
              'gone');
    });
  });
}
