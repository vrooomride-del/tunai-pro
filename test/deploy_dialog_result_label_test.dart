// Regression: result view must label each outcome with its actual parameter kind,
// not the hardcoded "Channel Gain" string; failure message must be visible.
// Also covers PEQ Q label/value formatting and restore completed state.

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
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/core/transport/adau1701_ch0_band0_read_service.dart';
import 'package:tunai_pro/core/transport/adau1701_deployment_preflight.dart';
import 'package:tunai_pro/core/transport/adau1701_deployment_report.dart';
import 'package:tunai_pro/core/transport/adau1701_tuning_transport.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';
import 'package:tunai_pro/core/transport/icp5_transports.dart';
import 'package:tunai_pro/features/workbench/widgets/deploy_dialog.dart';

// ── Fake port ─────────────────────────────────────────────────────────────────

typedef _Responder = Adau1701DeploymentReport Function(HardwareWriteOp op);

class _FakePort implements Icp5PeqWritePort {
  final _Responder responder;
  _FakePort(this.responder);

  @override
  Future<Adau1701DeploymentReport> preflightAndWrite(HardwareWriteOp op) async =>
      responder(op);
}

final _kAt = DateTime(2026, 7, 30);

Adau1701DeploymentReport _written() => Adau1701DeploymentReport(
      attemptedAt: _kAt,
      originalStateAvailable: true,
      preflightStatus: Adau1701PreflightStatus.passed,
      deploymentAllowed: true,
      deploymentResult: const Icp5PhaseCResult(
        success: true,
        wasActualWrite: true,
        writeMayHaveReachedDevice: true,
        message: 'ok',
      ),
    );

// Deploy report with capturedOriginalState — triggers _canRestorePeq in the dialog.
Adau1701DeploymentReport _writtenWithCapture() => Adau1701DeploymentReport(
      attemptedAt: _kAt,
      originalStateAvailable: true,
      preflightStatus: Adau1701PreflightStatus.passed,
      deploymentAllowed: true,
      capturedOriginalState: Adau1701Ch0Band0OriginalState(
        deviceId: 'DSP1701.100.00.01',
        capturedAt: _kAt,
        frequencyHz: 800,
        gainDb: -2.0,
        q: 1.0,
        property08State: 0,
      ),
      deploymentResult: const Icp5PhaseCResult(
        success: true,
        wasActualWrite: true,
        writeMayHaveReachedDevice: true,
        message: 'ok',
      ),
    );

Adau1701DeploymentReport _failed(String msg) => Adau1701DeploymentReport(
      attemptedAt: _kAt,
      originalStateAvailable: true,
      preflightStatus: Adau1701PreflightStatus.passed,
      deploymentAllowed: true,
      deploymentResult: Icp5PhaseCResult(
        success: false,
        wasActualWrite: true,
        writeMayHaveReachedDevice: true,
        message: msg,
      ),
    );

// ── Channels ──────────────────────────────────────────────────────────────────

const _kChannels = [
  DriverChannel(
    id: 'ch_tw_l',
    name: 'Tweeter L',
    role: DriverRole.tweeter,
    side: DriverSide.left,
  ),
];

// ── Fake connected transport (for restore success/fail tests) ─────────────────

List<int> _fakeStatePayload() {
  // Decodes to ch0/band0 = 1800 Hz, -1.0 dB — matches hardware_apply_flow_test.dart
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

class _FakeConnectedTransport implements Adau1701TuningTransport {
  final bool _connected;
  _FakeConnectedTransport({bool connected = true}) : _connected = connected;
  @override
  bool get isConnected => _connected;
  @override
  bool get handshakeComplete => _connected;
  @override
  String? get detectedProfile => _connected ? 'DSP1701.100.00.01' : null;
  @override
  Future<RawDspStateSnapshot> readRawDspState() async => RawDspStateSnapshot(
        deviceId: 'DSP1701.100.00.01',
        timestamp: DateTime.utc(2026, 7, 30),
        blockId: 0x2202,
        payload: _fakeStatePayload(),
      );
  @override
  Future<Adau1701WriteAck> writePeqGain(int c, double g, {int band = 0}) async =>
      const Adau1701WriteAck(success: true, message: 'ok');
  @override
  Future<Adau1701WriteAck> writeFilterFrequency(int c, int f,
          {int band = 0}) async =>
      const Adau1701WriteAck(success: true, message: 'ok');
  @override
  Future<Adau1701WriteAck> writePeqFrequency(int c, int f,
          {int band = 0}) async =>
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

// ── Host widget ───────────────────────────────────────────────────────────────

class _Host extends StatefulWidget {
  final Icp5PeqWritePort port;
  final TuningProjectState tuning;
  final Map<String, double> previousAppliedGains;
  const _Host({
    required this.port,
    required this.tuning,
    this.previousAppliedGains = const {},
  });

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDeployDialog(
        context: context,
        projectId: 'test',
        channels: _kChannels,
        tuning: widget.tuning,
        previousAppliedGains: widget.previousAppliedGains,
        overridePort: widget.port,
      );
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('host')));
}

Widget _host(
  Icp5PeqWritePort port,
  TuningProjectState tuning, {
  Map<String, double> previousAppliedGains = const {},
  List<Override> overrides = const [],
}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: _Host(
          port: port,
          tuning: tuning,
          previousAppliedGains: previousAppliedGains,
        ),
      ),
    );

// Tuning with Band 1 enabled (freq=1000, gain=-3.0).
TuningProjectState _tuningWithPeq() {
  final base = PeqChannelState.fixed('ch_tw_l');
  final bands = List<PeqBand>.from(base.bands);
  bands[0] = bands[0].copyWith(enabled: true, frequencyHz: 1000.0, gainDb: -3.0, q: 1.0);
  return TuningProjectState(
    peqChannels: [base.copyWith(bands: bands)],
    crossoverChannels: const [],
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Deploy result view labels', () {
    testWidgets(
        'gain written → label is "PEQ B1 Gain", not "Channel Gain"',
        (tester) async {
      // Both peqGain and peqFrequency are captureProven and reach the port.
      // Verify the gain label is correct (not the hardcoded "Channel Gain").
      final port = _FakePort((_) => _written());

      await tester.pumpWidget(_host(port, _tuningWithPeq()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('APPROVE & WRITE'));
      await tester.pumpAndSettle();

      // Must NOT show hardcoded Channel Gain label
      expect(find.textContaining('Channel Gain'), findsNothing,
          reason: 'hardcoded "Channel Gain" must be replaced with _opKindLabel');

      // Correct label for the only writable op (peqGain)
      expect(find.textContaining('PEQ B1 Gain'), findsOneWidget);
    });

    testWidgets(
        'gain failed → failure message is shown, not just "Failed"',
        (tester) async {
      // Both peqGain and peqFrequency are deployed; both fail with the same message.
      // Verify that when ops fail, o.message is shown in the result view.
      const failMsg = 'Write ACKed but readback value did not match target.';
      final port = _FakePort((_) => _failed(failMsg));

      await tester.pumpWidget(_host(port, _tuningWithPeq()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('APPROVE & WRITE'));
      await tester.pumpAndSettle();

      expect(find.textContaining(failMsg), findsAtLeastNWidgets(1),
          reason: 'failure message must be visible in result view');
    });

    testWidgets(
        'gain+Q written → status label "Written" shown for both (frequency fails readback)',
        (tester) async {
      final port = _FakePort((op) {
        if (op.parameterKind == HardwareParamKind.peqFrequency) {
          return _failed('readback mismatch');
        }
        return _written();
      });

      await tester.pumpWidget(_host(port, _tuningWithPeq()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('APPROVE & WRITE'));
      await tester.pumpAndSettle();

      // band_0: gain (written) + frequency (failed) + Q (written) = 2 "Written" for band_0.
      // bands 1–9: 9 bypass gain ops (each written) = 9 more "Written" labels.
      expect(find.text('Written'), findsNWidgets(11));
    });
  });

  group('PEQ Q labels and values', () {
    // Tuning with Q=0.7 so the value '0.7' is distinct from gain/freq values.
    TuningProjectState _tuningWithQ() {
      final base = PeqChannelState.fixed('ch_tw_l');
      final bands = List<PeqBand>.from(base.bands);
      bands[0] = bands[0].copyWith(
        enabled: true,
        frequencyHz: 800.0,
        gainDb: -3.0,
        q: 0.7,
      );
      return TuningProjectState(
        peqChannels: [base.copyWith(bands: bands)],
        crossoverChannels: const [],
      );
    }

    TuningProjectState _tuningWithBand10Q() {
      final base = PeqChannelState.fixed('ch_tw_l');
      final bands = List<PeqBand>.from(base.bands);
      // band index 9 = UI Band 10
      bands[9] = bands[9].copyWith(
        enabled: true,
        frequencyHz: 5000.0,
        gainDb: 1.0,
        q: 1.4,
      );
      return TuningProjectState(
        peqChannels: [base.copyWith(bands: bands)],
        crossoverChannels: const [],
      );
    }

    testWidgets('Q op kind label is "PEQ B1 Q", not "peqQ" in result view',
        (tester) async {
      final port = _FakePort((_) => _written());

      await tester.pumpWidget(_host(port, _tuningWithQ()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('APPROVE & WRITE'));
      await tester.pumpAndSettle();

      expect(find.textContaining('PEQ B1 Q'), findsAtLeastNWidgets(1));
      expect(find.textContaining('peqQ'), findsNothing,
          reason: 'raw enum name must not appear');
    });

    testWidgets('Band 10 Q label is "PEQ B10 Q" in result view', (tester) async {
      final port = _FakePort((_) => _written());

      await tester.pumpWidget(_host(port, _tuningWithBand10Q()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('APPROVE & WRITE'));
      await tester.pumpAndSettle();

      expect(find.textContaining('PEQ B10 Q'), findsAtLeastNWidgets(1));
    });

    testWidgets('Q value in pending list is bare numeric, no unit, no sign',
        (tester) async {
      final port = _FakePort((_) => _written());

      await tester.pumpWidget(_host(port, _tuningWithQ()));
      await tester.pumpAndSettle();

      // Plan view is visible before writing — check value column for Q op.
      // Q=0.7 → '0.7'; must NOT show '+0.7 dB'.
      expect(find.text('0.7'), findsOneWidget,
          reason: 'Q value must be bare numeric');
      expect(find.textContaining('+0.7'), findsNothing,
          reason: 'Q value must not have + sign');
      expect(find.textContaining('0.7 dB'), findsNothing,
          reason: 'Q value must not have dB unit');
    });

    testWidgets('Gain value in pending list keeps dB format', (tester) async {
      final port = _FakePort((_) => _written());

      await tester.pumpWidget(_host(port, _tuningWithQ()));
      await tester.pumpAndSettle();

      // gain=-3.0 → '-3.0 dB'
      expect(find.textContaining('-3.0 dB'), findsAtLeastNWidgets(1));
    });

    testWidgets('Frequency value in pending list keeps Hz format', (tester) async {
      final port = _FakePort((_) => _written());

      await tester.pumpWidget(_host(port, _tuningWithQ()));
      await tester.pumpAndSettle();

      // freq=800 → '800 Hz' (sub-1000 stays in Hz)
      expect(find.textContaining('800 Hz'), findsAtLeastNWidgets(1));
    });
  });

  group('Restore completed state', () {
    // All deploy ops fail → no project-store persist.
    // previousAppliedGains non-empty → _canRestoreGain always true → RESTORE (GAIN) shows.
    // Restore gain write via connected fake transport → result.allPassed → RESTORED shown.

    testWidgets(
        'RESTORED chip shown and RESTORE button absent after successful restore',
        (tester) async {
      // All deploy ops fail: no channelGain is written → no store persist.
      final port = _FakePort((_) => _failed('test: all deploy ops fail'));
      final fakeCtx =
          Adau1701HardwareContext.fromTransport(_FakeConnectedTransport());

      await tester.pumpWidget(_host(
        port,
        _tuningWithPeq(),
        previousAppliedGains: {'ch_tw_l': -3.0},
        overrides: [
          adau1701Icp5UsbContextProvider.overrideWithValue(fakeCtx),
        ],
      ));
      await tester.pumpAndSettle();

      // Deploy (all ops fail → result not all passed, but RESTORE still available)
      await tester.tap(find.text('APPROVE & WRITE'));
      await tester.pumpAndSettle();

      // RESTORE button visible after deploy (previousAppliedGains non-empty)
      expect(
        find.ancestor(
          of: find.textContaining('RESTORE'),
          matching: find.bySubtype<OutlinedButton>(),
        ),
        findsOneWidget,
        reason: 'RESTORE button must appear after deploy when previous gains exist',
      );

      // Tap restore — connected fake transport acks gain write → allPassed
      await tester.tap(find.ancestor(
        of: find.textContaining('RESTORE'),
        matching: find.bySubtype<OutlinedButton>(),
      ));
      await tester.pumpAndSettle();

      // RESTORED chip is visible; RESTORE button is gone
      expect(find.text('RESTORED'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.textContaining('RESTORE ('),
          matching: find.bySubtype<OutlinedButton>(),
        ),
        findsNothing,
        reason: 'RESTORE button must be gone after successful restore',
      );
    });

    testWidgets('RESTORE button shown again after failed restore (retry)',
        (tester) async {
      // channelGain op fails → no project-store persist → no error.
      // previousAppliedGains non-empty → _canRestoreGain always true.
      // After failed restore, _canRestoreGain remains true → RESTORE button stays.
      final port = _FakePort((op) {
        if (op.parameterKind == HardwareParamKind.channelGain) {
          return _failed('write failed');
        }
        return _written();
      });
      final disconnectedCtx = Adau1701HardwareContext.fromTransport(
        _FakeConnectedTransport(connected: false),
      );

      await tester.pumpWidget(_host(
        port,
        _tuningWithPeq(),
        previousAppliedGains: {'ch_tw_l': -3.0},
        overrides: [
          adau1701Icp5UsbContextProvider.overrideWithValue(disconnectedCtx),
        ],
      ));
      await tester.pumpAndSettle();

      // Deploy (channelGain fails, PEQ succeeds, no store persist)
      await tester.tap(find.text('APPROVE & WRITE'));
      await tester.pumpAndSettle();

      // Tap restore (will fail — restore transport disconnected)
      await tester.tap(find.ancestor(
        of: find.textContaining('RESTORE'),
        matching: find.bySubtype<OutlinedButton>(),
      ));
      await tester.pumpAndSettle();

      // RESTORE button must still appear for retry; RESTORED must NOT appear
      expect(find.text('RESTORED'), findsNothing);
      expect(
        find.ancestor(
          of: find.textContaining('RESTORE'),
          matching: find.bySubtype<OutlinedButton>(),
        ),
        findsOneWidget,
        reason: 'RESTORE button must remain for retry after failed restore',
      );
    });
  });
}
