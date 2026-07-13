import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/pro_adau1466_sigma_candidate.dart';
import 'package:tunai_pro/core/pro_adau1466_sigma_executor.dart';
import 'package:tunai_pro/core/pro_usbi_native_backend.dart';
import 'package:tunai_pro/features/workbench/tabs/hardware_tab.dart';

class _RealMuteBackend implements ProUsbiNativeBackend {
  final List<List<int>> acknowledgements;
  final List<List<int>> capturedBodyPackets = [];
  int callCount = 0;

  _RealMuteBackend(this.acknowledgements);

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
    return acknowledgements[callCount++];
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
    expect(find.text('Controlled Mute Smoke Test'), findsOneWidget);
    expect(find.text('audible verification pending'), findsOneWidget);
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

    expect(find.text('wasActualWrite status: false'), findsNWidgets(3));
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

  testWidgets('Controlled Mute Smoke Test writes 0 then restores 1',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backend = _RealMuteBackend([
      [0x01],
      [0x01],
    ]);
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

    expect(backend.capturedBodyPackets, [
      [0x06, 0x0E, 0x00, 0x00, 0x00, 0x00],
      [0x06, 0x0E, 0x00, 0x00, 0x00, 0x01],
    ]);
    expect(find.text('test ACK status: PASS_ACK'), findsOneWidget);
    expect(find.text('restore ACK status: PASS_ACK'), findsOneWidget);
    expect(find.text('wasActualWrite status: true'), findsOneWidget);
    expect(find.textContaining('VERIFIED'), findsWidgets);
    expect(find.text('Mute1_3 VERIFIED'), findsNothing);
  });

  testWidgets('Mute restore ACK failure shows prominent warning',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backend = _RealMuteBackend([
      [0x01],
      [0x00],
    ]);
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

    expect(backend.callCount, 2);
    expect(find.byKey(const Key('mute-restore-failure-warning')), findsOneWidget);
    expect(find.text('restore ACK status: FAIL'), findsOneWidget);
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
