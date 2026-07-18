// Widget tests for Adau1701Icp5TuningPanel.
// Uses a fake transport (no physical hardware or serial port).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/transport/adau1701_tuning_transport.dart';
import 'package:tunai_pro/core/transport/icp5_frame_codec.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';
import 'package:tunai_pro/features/workbench/tabs/adau1701_icp5_tuning_panel.dart';

// ── Fixture helpers ───────────────────────────────────────────────────────────

const _kProfile = Icp5FrameCodec.expectedProfile;

List<int> _payload({int freqLo = 0xD0, int freqHi = 0x07, int gainByte = 0xF6}) {
  // freq 0x07D0 = 2000, gain 0xF6 = -10 tenths = -1.0 dB, Q 20 tenths = 2.0
  final p = List<int>.filled(513, 0x00);
  p[19] = freqLo;
  p[20] = freqHi;
  p[21] = gainByte;
  p[23] = 0x14;
  p[24] = 0x01;
  return p;
}

RawDspStateSnapshot _snapshot({int freqLo = 0xD0, int freqHi = 0x07, int gainByte = 0xF6}) =>
    RawDspStateSnapshot(
      deviceId: _kProfile,
      timestamp: DateTime.utc(2025, 1, 1),
      blockId: 0x2202,
      payload: _payload(freqLo: freqLo, freqHi: freqHi, gainByte: gainByte),
    );

// ── Fake transport ────────────────────────────────────────────────────────────

class _FakeTuningTransport implements Adau1701TuningTransport {
  @override
  final bool isConnected;
  @override
  final bool handshakeComplete;
  @override
  final String? detectedProfile;

  final Object? _readError;
  final RawDspStateSnapshot? _readSnapshot;
  final bool _gainWriteSuccess;
  final bool _freqWriteSuccess;

  /// Second read (readback) can return different data if [_readbackSnapshot] is set.
  final RawDspStateSnapshot? _readbackSnapshot;
  int _readCount = 0;

  _FakeTuningTransport({
    this.isConnected = true,
    this.handshakeComplete = true,
    this.detectedProfile = _kProfile,
    RawDspStateSnapshot? readSnapshot,
    Object? readError,
    bool gainWriteSuccess = true,
    bool freqWriteSuccess = true,
    RawDspStateSnapshot? readbackSnapshot,
  })  : _readSnapshot = readSnapshot,
        _readError = readError,
        _gainWriteSuccess = gainWriteSuccess,
        _freqWriteSuccess = freqWriteSuccess,
        _readbackSnapshot = readbackSnapshot;

  @override
  Future<RawDspStateSnapshot> readRawDspState() async {
    if (_readError != null) throw _readError!;
    _readCount++;
    if (_readCount > 1 && _readbackSnapshot != null) {
      return _readbackSnapshot!;
    }
    return _readSnapshot!;
  }

  @override
  Future<Adau1701WriteAck> writePeqGain(int channel, double gainDb) async =>
      Adau1701WriteAck(
        success: _gainWriteSuccess,
        message: _gainWriteSuccess ? 'PASS_ACK' : 'No ACK.',
      );

  @override
  Future<Adau1701WriteAck> writeFilterFrequency(
          int channel, int frequencyHz) async =>
      Adau1701WriteAck(
        success: _freqWriteSuccess,
        message: _freqWriteSuccess ? 'PASS_ACK' : 'No ACK.',
      );
}

// ── Test helpers ──────────────────────────────────────────────────────────────

Widget _wrap(Adau1701TuningTransport transport) => MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Adau1701Icp5TuningPanel(transport: transport),
          ),
        ),
      ),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // Fake async delays: make pump not need fake timers for the Timer.periodic
  // by using pumpAndSettle with timeout.

  group('disconnected state', () {
    testWidgets('shows not-connected prompt and no READ button', (tester) async {
      final transport = _FakeTuningTransport(isConnected: false);
      await tester.pumpWidget(_wrap(transport));
      await tester.pump();

      expect(find.textContaining('Not connected'), findsOneWidget);
      expect(find.text('READ DSP STATE'), findsNothing);
    });

    testWidgets('shows handshake pending when connected but not handshaked',
        (tester) async {
      final transport = _FakeTuningTransport(
        isConnected: true,
        handshakeComplete: false,
      );
      await tester.pumpWidget(_wrap(transport));
      await tester.pump();

      expect(find.textContaining('Handshake pending'), findsOneWidget);
    });

    testWidgets('shows profile mismatch when handshaked but wrong profile',
        (tester) async {
      final transport = _FakeTuningTransport(
        isConnected: true,
        handshakeComplete: true,
        detectedProfile: 'WRONG.PROFILE',
      );
      await tester.pumpWidget(_wrap(transport));
      await tester.pump();

      expect(find.textContaining('Profile mismatch'), findsOneWidget);
    });
  });

  group('connected — before READ', () {
    testWidgets('shows ADAU1701 ready status and READ button', (tester) async {
      final transport =
          _FakeTuningTransport(readSnapshot: _snapshot());
      await tester.pumpWidget(_wrap(transport));
      await tester.pump();

      expect(find.textContaining('ADAU1701 ready'), findsOneWidget);
      expect(find.text('READ DSP STATE'), findsOneWidget);
      expect(find.text('RUN PREFLIGHT + APPLY'), findsNothing);
    });
  });

  group('after successful READ', () {
    testWidgets('shows current state card and edit fields', (tester) async {
      final transport =
          _FakeTuningTransport(readSnapshot: _snapshot());
      await tester.pumpWidget(_wrap(transport));
      await tester.pump();

      await tester.tap(find.text('READ DSP STATE'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.textContaining('CURRENT STATE'), findsOneWidget);
      expect(find.textContaining('2000 Hz'), findsOneWidget);
      expect(find.textContaining('-1.0 dB'), findsOneWidget);
      expect(find.text('RUN PREFLIGHT + APPLY'), findsOneWidget);
    });

    testWidgets('pre-populates gain and frequency fields from hardware',
        (tester) async {
      final transport =
          _FakeTuningTransport(readSnapshot: _snapshot());
      await tester.pumpWidget(_wrap(transport));
      await tester.pump();

      await tester.tap(find.text('READ DSP STATE'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Verify the TextField controllers have the hardware values.
      // find.byType(TextField) returns [gain, freq] in order.
      final textFields = tester.widgetList<TextField>(find.byType(TextField));
      expect(textFields.first.controller?.text, '-1.0');
      expect(textFields.last.controller?.text, '2000');
    });
  });

  group('after successful APPLY + READBACK', () {
    testWidgets('shows PASS verification card', (tester) async {
      // Readback returns same frequency/gain as written → PASS
      final readbackSnap = _snapshot(); // 2000 Hz, -1.0 dB
      final transport = _FakeTuningTransport(
        readSnapshot: _snapshot(),
        readbackSnapshot: readbackSnap,
      );
      await tester.pumpWidget(_wrap(transport));
      await tester.pump();

      await tester.tap(find.text('READ DSP STATE'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Values pre-filled; tap apply
      await tester.tap(find.text('RUN PREFLIGHT + APPLY'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.textContaining('VERIFICATION PASS'), findsOneWidget);
      expect(find.textContaining('GAIN WRITE ACK'), findsOneWidget);
      expect(find.textContaining('FREQ WRITE ACK'), findsOneWidget);
    });
  });

  group('after APPLY — gain write fails', () {
    testWidgets('shows GAIN WRITE ACK fail, no FREQ ACK row, no verification',
        (tester) async {
      final transport = _FakeTuningTransport(
        readSnapshot: _snapshot(),
        gainWriteSuccess: false,
      );
      await tester.pumpWidget(_wrap(transport));
      await tester.pump();

      await tester.tap(find.text('READ DSP STATE'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await tester.tap(find.text('RUN PREFLIGHT + APPLY'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.textContaining('GAIN WRITE ACK'), findsOneWidget);
      expect(find.textContaining('FREQ WRITE ACK'), findsNothing);
      expect(find.textContaining('VERIFICATION'), findsNothing);
      expect(find.textContaining('Gain write failed'), findsOneWidget);
    });
  });

  group('after APPLY — freq write fails', () {
    testWidgets('shows both ACK rows (gain pass, freq fail), no verification',
        (tester) async {
      final transport = _FakeTuningTransport(
        readSnapshot: _snapshot(),
        gainWriteSuccess: true,
        freqWriteSuccess: false,
      );
      await tester.pumpWidget(_wrap(transport));
      await tester.pump();

      await tester.tap(find.text('READ DSP STATE'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await tester.tap(find.text('RUN PREFLIGHT + APPLY'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.textContaining('GAIN WRITE ACK'), findsOneWidget);
      expect(find.textContaining('FREQ WRITE ACK'), findsOneWidget);
      expect(find.textContaining('VERIFICATION'), findsNothing);
      expect(find.textContaining('Frequency write failed'), findsOneWidget);
    });
  });

  group('read failure', () {
    testWidgets('shows error row, no state card', (tester) async {
      final transport = _FakeTuningTransport(
        readError: StateError('ICP5 timeout'),
      );
      await tester.pumpWidget(_wrap(transport));
      await tester.pump();

      await tester.tap(find.text('READ DSP STATE'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.textContaining('ICP5 timeout'), findsOneWidget);
      expect(find.textContaining('CURRENT STATE'), findsNothing);
    });
  });

  group('input validation', () {
    testWidgets('shows error for empty gain field', (tester) async {
      final transport =
          _FakeTuningTransport(readSnapshot: _snapshot());
      await tester.pumpWidget(_wrap(transport));
      await tester.pump();

      await tester.tap(find.text('READ DSP STATE'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Clear gain field
      final gainTextField =
          find.byType(TextField).first;
      await tester.enterText(gainTextField, '');

      await tester.tap(find.text('RUN PREFLIGHT + APPLY'));
      await tester.pump();

      expect(find.textContaining('Enter valid gain'), findsOneWidget);
    });

    testWidgets('shows error for out-of-range gain', (tester) async {
      final transport =
          _FakeTuningTransport(readSnapshot: _snapshot());
      await tester.pumpWidget(_wrap(transport));
      await tester.pump();

      await tester.tap(find.text('READ DSP STATE'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final gainTextField = find.byType(TextField).first;
      await tester.enterText(gainTextField, '99.0');

      await tester.tap(find.text('RUN PREFLIGHT + APPLY'));
      await tester.pump();

      expect(find.textContaining('Gain must be'), findsOneWidget);
    });
  });
}
