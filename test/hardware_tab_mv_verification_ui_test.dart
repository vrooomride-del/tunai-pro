import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/pro_adau1466_sigma_candidate.dart';
import 'package:tunai_pro/core/pro_adau1466_sigma_executor.dart';
import 'package:tunai_pro/core/pro_usbi_native_backend.dart';
import 'package:tunai_pro/features/workbench/tabs/hardware_tab.dart';

class _RealMuteBackend
    implements ProUsbiNativeBackend, ProUsbiTransactionDiagnosticsProvider {
  final List<List<int>> acknowledgements;
  UsbiNativeTransactionDiagnostics? _lastTransactionDiagnostics;
  @override
  UsbiNativeTransactionDiagnostics? get lastTransactionDiagnostics =>
      _lastTransactionDiagnostics;
  final List<List<int>> capturedBodyPackets = [];
  int callCount = 0;

  _RealMuteBackend(this.acknowledgements,
      {UsbiNativeTransactionDiagnostics? lastTransactionDiagnostics})
      : _lastTransactionDiagnostics = lastTransactionDiagnostics;

  @override
  bool get isAvailable => true;

  @override
  bool get isFake => false;

  @override
  Future<List<int>?> sendPacketsAndReadAck({
    required List<int> setupPacket,
    required List<int> bodyPacket,
    required List<int> ackReadRequest,
  }) async {
    capturedBodyPackets.add(List<int>.from(bodyPacket));
    final ack = acknowledgements[callCount++];
    _lastTransactionDiagnostics = UsbiNativeTransactionDiagnostics(
      setupPacket: List<int>.from(setupPacket),
      bodyPacket: List<int>.from(bodyPacket),
      ackRequestPacket: List<int>.from(ackReadRequest),
      setupTransferSuccess: true,
      bodyTransferSuccess: true,
      bytesTransferred: bodyPacket.length,
      ackReadSuccess: true,
      ackBytesTransferred: ack.length,
      rawAckBytes: List<int>.from(ack),
      setupElapsedMilliseconds: callCount,
      ackElapsedMilliseconds: callCount + 1,
    );
    return ack;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('real Hardware tab exposes the ADAU1466 MV verification UI',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backend = ProUsbiNativeBackendFake();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: HardwareTab(
              projectId: 'widget-test-project',
              usbiBackend: backend,
              isWindowsPlatform: () => true,
              initialUsbiDeviceOpen: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('USBi — Windows Temporary Engineering'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('adau1466-mv-verification-ui')), findsOneWidget);
    expect(find.byKey(const Key('adau1466-mute1-3-validation-ui')), findsOneWidget);
    expect(find.byKey(const Key('adau1466-gain-diagnostics-ui')),
        findsOneWidget);
    expect(find.byKey(const Key('operational-master-volume-control')), findsOneWidget);
    expect(find.text('Linked Stereo Master Volume'), findsOneWidget);
    expect(find.text('MV WRITE ACTIVE'), findsWidgets);
    expect(find.text('MV WRITE ACTIVE · XO/PEQ BLOCKED'), findsOneWidget);
    expect(find.text('Backend available: yes'), findsOneWidget);
    expect(find.text('Platform: Windows'), findsWidgets);
    expect(find.text('Executor: real'), findsOneWidget);
    expect(find.text('MV L 0x0067'), findsOneWidget);
    expect(find.text('MV R 0x0064'), findsOneWidget);
    expect(find.text('MV L 0x0067 candidate row'), findsOneWidget);
    expect(find.text('MV R 0x0064 candidate row'), findsOneWidget);
    expect(find.text('0x0067: PASS_ACK · audible verification pending'), findsOneWidget);
    expect(find.text('0x0064: PASS_ACK · audible verification pending'), findsOneWidget);
    expect(find.text('Smoke Test'), findsNWidgets(2));
    expect(find.text('Mute1_3'), findsWidgets);
    expect(find.text('Address 0x060E'), findsOneWidget);
    expect(find.text('Captured states: unchecked=0, checked=1'), findsOneWidget);
    expect(find.text('Current assumed baseline: 1'), findsOneWidget);
    expect(find.text('Run One-Shot Mute Diagnostic'),
        findsOneWidget);
    expect(find.text('ADAU1466 Mapped Gain One-Shot Diagnostics'), findsOneWidget);
    for (final row in const [
      ('WFL — Single 1', 'Target 0x03B8', 'Slew 0x03B9', 'Test 0x00000840', 'Restore 0x0000068E'),
      ('MID_L — Single 1_4', 'Target 0x03C4', 'Slew 0x03C5', 'Test 0x000014B9', 'Restore 0x00001076'),
      ('TWL — Single 1_5', 'Target 0x03C7', 'Slew 0x03C8', 'Test 0x000020D8', 'Restore 0x00001A17'),
      ('WFR — Single 1_6', 'Target 0x03BB', 'Slew 0x03BC', 'Test 0x00000840', 'Restore 0x0000068E'),
      ('MID_R — Single 1_7', 'Target 0x03CA', 'Slew 0x03CB', 'Test 0x00005281', 'Restore 0x00004189'),
      ('TWR — Single 1_8', 'Target 0x03CD', 'Slew 0x03CE', 'Test 0x00001A17', 'Restore 0x000014B9'),
    ]) {
      expect(find.text(row.$1), findsOneWidget);
      expect(find.text(row.$2), findsOneWidget);
      expect(find.text(row.$3), findsOneWidget);
      expect(find.text(row.$4), findsWidgets);
      expect(find.text(row.$5), findsWidgets);
    }
    expect(find.text('Run One-Shot Gain Diagnostic'), findsNWidgets(6));
    expect(find.text('audible verification pending'), findsNWidgets(2));
    expect(find.text('physical mapping pending for all six channels'), findsOneWidget);
    expect(find.textContaining('Physical WFL / OUT3 mapping remains pending'),
        findsOneWidget);

    for (final blocked in ['XO', 'PEQ', 'SafeLoad', 'Gain', 'Mute', 'Delay']) {
      expect(find.text('$blocked blocked'), findsOneWidget);
    }

    expect(find.text('WRITE DISABLED'), findsNothing);
    expect(find.text('Placeholder: Yes'), findsNothing);
    expect(find.text('Dry-Run Only'), findsNothing);
    expect(find.text('Detection Only: Yes'), findsNothing);
    expect(find.text('Generate Dry-Run Write Plan'), findsNothing);
  });

  testWidgets('Smoke Test calls the real executor and reports actual write',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backend = ProUsbiNativeBackendFake();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: HardwareTab(
              projectId: 'widget-test-project',
              usbiBackend: backend,
              isWindowsPlatform: () => true,
              initialUsbiDeviceOpen: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('USBi — Windows Temporary Engineering'));
    await tester.pumpAndSettle();

    expect(find.text('wasActualWrite status: false'), findsNWidgets(4));
    expect(backend.callCount, 0);

    await tester.tap(find.byKey(const Key('smoke-test-0067')));
    await tester.pumpAndSettle();

    expect(backend.callCount, 2,
        reason: 'Smoke Test must send 0.5 and then restore 1.0');
    expect(backend.capturedBodyPackets[0],
        [0x00, 0x67, 0x00, 0x80, 0x00, 0x00]);
    expect(backend.capturedBodyPackets[1],
        [0x00, 0x67, 0x01, 0x00, 0x00, 0x00]);
    expect(find.text('ACK status: PASS_ACK'), findsOneWidget);
    expect(find.text('restore status: PASS_ACK'), findsOneWidget);
    expect(find.text('wasActualWrite status: true'), findsOneWidget);
    expect(find.text('0x0067: PASS_ACK · audible verification pending'), findsOneWidget);
    expect(find.textContaining('0x0067: VERIFIED'), findsNothing);
  });

  test('actual-write allowlist remains limited to 0x0067 and 0x0064', () {
    expect(ProUsbiSigmaVerificationExecutor.writeEnabledAddresses,
        equals({0x0067, 0x0064}));
  });

  testWidgets('Mute diagnostic requires confirmation and runs only once',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backend = _RealMuteBackend(const [[0x01], [0x01]]);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: HardwareTab(
              projectId: 'mute-widget-test',
              usbiBackend: backend,
              isWindowsPlatform: () => true,
              initialUsbiDeviceOpen: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('USBi — Windows Temporary Engineering'));
    await tester.pumpAndSettle();

    final button = find.byKey(const Key('controlled-mute-smoke-test'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Confirm one-shot Mute1_3 diagnostic'), findsOneWidget);
    expect(backend.callCount, 0);

    await tester.tap(find.byKey(const Key('cancel-mute-diagnostic')));
    await tester.pumpAndSettle();
    expect(backend.callCount, 0);

    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-mute-diagnostic')));
    await tester.pumpAndSettle();

    expect(backend.callCount, 2);
    expect(backend.capturedBodyPackets, const [
      [0x06, 0x0E, 0x00, 0x00, 0x00, 0x00],
      [0x06, 0x0E, 0x00, 0x00, 0x00, 0x01],
    ]);
    expect(find.text('TEST TRANSACTION DIAGNOSTICS'), findsOneWidget);
    expect(find.text('RESTORE TRANSACTION DIAGNOSTICS'), findsOneWidget);
    expect(find.text('body packet: 06 0E 00 00 00 00'), findsOneWidget);
    expect(find.text('body packet: 06 0E 00 00 00 01'), findsOneWidget);
    expect(find.text('raw ACK bytes: 01'), findsNWidgets(2));
    expect(find.text('one-shot session status: used'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    expect(find.textContaining('VERIFIED'), findsWidgets);
    expect(find.text('Mute1_3 VERIFIED'), findsNothing);
  });

  testWidgets('restore without raw ACK 01 stops all session DSP writes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backend = _RealMuteBackend(const [[0x01], [0x00]]);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: HardwareTab(
              projectId: 'mute-restore-widget-test',
              usbiBackend: backend,
              isWindowsPlatform: () => true,
              initialUsbiDeviceOpen: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('USBi — Windows Temporary Engineering'));
    await tester.pumpAndSettle();

    final button = find.byKey(const Key('controlled-mute-smoke-test'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-mute-diagnostic')));
    await tester.pumpAndSettle();

    expect(backend.callCount, 2);
    expect(find.byKey(const Key('mute-diagnostic-stop-warning')), findsOneWidget);
    expect(find.byKey(const Key('session-dsp-write-stop-warning')), findsOneWidget);
    expect(find.text('raw ACK bytes: 00'), findsOneWidget);
    expect(find.text('session DSP write status: STOPPED'), findsOneWidget);
    expect(tester.widget<Slider>(
        find.byKey(const Key('operational-master-volume-slider'))).onChanged,
        isNull);
    expect(tester.widget<OutlinedButton>(
        find.byKey(const Key('smoke-test-0067'))).onPressed, isNull);
  });

  testWidgets('Gain diagnostic confirms, runs six stages once, and stays PASS_ACK',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backend = _RealMuteBackend(List<List<int>>.generate(6, (_) => [0x01]));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: HardwareTab(
              projectId: 'gain-widget-test',
              usbiBackend: backend,
              isWindowsPlatform: () => true,
              initialUsbiDeviceOpen: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('USBi — Windows Temporary Engineering'));
    await tester.pumpAndSettle();

    final midLButton =
        find.byKey(const Key('run-one-shot-gain-diagnostic-MID_L'));
    await tester.ensureVisible(midLButton);
    await tester.tap(midLButton);
    await tester.pumpAndSettle();
    expect(find.text('Confirm one-shot Gain MID_L diagnostic'), findsOneWidget);
    expect(find.textContaining('Channel: MID_L / Single 1_4'), findsOneWidget);
    expect(find.textContaining('Target: 0x03C4'), findsOneWidget);
    expect(find.textContaining('Slew: 0x03C5'), findsOneWidget);
    expect(find.textContaining('Test value: 0x000014B9'), findsOneWidget);
    expect(find.textContaining('Restore value: 0x00001076'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancel-gain-diagnostic')));
    await tester.pumpAndSettle();
    expect(backend.callCount, 0);

    final button = find.byKey(const Key('run-one-shot-gain-diagnostic-WFL'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Confirm one-shot Gain WFL diagnostic'), findsOneWidget);
    expect(backend.callCount, 0);

    await tester.tap(find.byKey(const Key('confirm-gain-diagnostic')));
    await tester.pumpAndSettle();

    expect(backend.callCount, 6);
    expect(backend.capturedBodyPackets, const [
      [0x03, 0xB9, 0x00, 0x00, 0x20, 0x8A],
      [0x60, 0x00, 0x00, 0x00, 0x08, 0x40],
      [0x60, 0x05, 0x00, 0x00, 0x03, 0xB8, 0x00, 0x00,
        0x00, 0x01, 0x00, 0x00, 0x00, 0x00],
      [0x03, 0xB9, 0x00, 0x00, 0x20, 0x8A],
      [0x60, 0x00, 0x00, 0x00, 0x06, 0x8E],
      [0x60, 0x05, 0x00, 0x00, 0x03, 0xB8, 0x00, 0x00,
        0x00, 0x01, 0x00, 0x00, 0x00, 0x00],
    ]);
    for (var stage = 1; stage <= 3; stage++) {
      expect(find.text('TEST stage $stage ACK: PASS_ACK'), findsOneWidget);
      expect(find.text('RESTORE stage $stage ACK: PASS_ACK'), findsOneWidget);
    }
    expect(find.text('one-shot session status: used'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    for (final channel in ['MID_L', 'TWL', 'WFR', 'MID_R', 'TWR']) {
      expect(tester.widget<OutlinedButton>(find.byKey(
          Key('run-one-shot-gain-diagnostic-$channel'))).onPressed, isNull);
    }
    expect(find.text('Gain Single 1 VERIFIED'), findsNothing);
  });

  testWidgets('Gain restore failure stops all further session writes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backend = _RealMuteBackend(const [
      [0x01], [0x01], [0x01], [0x01], [0x00], [0x01],
    ]);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: HardwareTab(
              projectId: 'gain-restore-widget-test',
              usbiBackend: backend,
              isWindowsPlatform: () => true,
              initialUsbiDeviceOpen: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('USBi — Windows Temporary Engineering'));
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('run-one-shot-gain-diagnostic-WFL'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-gain-diagnostic')));
    await tester.pumpAndSettle();

    expect(backend.callCount, 6);
    expect(find.byKey(const Key('gain-diagnostic-stop-warning')), findsOneWidget);
    expect(find.byKey(const Key('session-dsp-write-stop-warning')), findsOneWidget);
    expect(tester.widget<Slider>(
        find.byKey(const Key('operational-master-volume-slider'))).onChanged,
        isNull);
    expect(tester.widget<OutlinedButton>(
        find.byKey(const Key('controlled-mute-smoke-test'))).onPressed, isNull);
  });

  test('executor blocks every non-MV category before backend I/O', () async {
    final backend = ProUsbiNativeBackendFake();
    final executor = ProUsbiSigmaVerificationExecutor(
      backend: backend,
      isWindowsPlatform: () => true,
    );

    final blockedTargets = <String, int>{
      'XO': 0x0100,
      'PEQ': 0x0200,
      'SafeLoad': 0x6000,
      'Gain': 0x0300,
      'Mute': 0x0400,
      'Delay': 0x0500,
      'unknown': 0x0600,
      'unverified output mapping': 0x0700,
    };

    for (final entry in blockedTargets.entries) {
      final result = await executor.writeWithRestore(
        SigmaVerificationWriteRequest(
          id: entry.key,
          addressInt: entry.value,
          addressHex: '0x${entry.value.toRadixString(16).padLeft(4, '0')}',
          label: entry.key,
          testValue32: 0x00800000,
          restoreValue32: 0x01000000,
          userConfirmed: true,
          restoreValueConfirmed: true,
        ),
      );
      expect(result.resultStatus, CandidateValidationStatus.blocked,
          reason: entry.key);
      expect(result.testWasActualWrite, isFalse, reason: entry.key);
    }
    expect(backend.callCount, 0);
  });
}
