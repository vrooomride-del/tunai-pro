// Widget tests for Adau1701Icp5TuningPanel.
// Uses a fake transport (no physical hardware or serial port).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/transport/adau1701_tuning_transport.dart';
import 'package:tunai_pro/core/transport/icp5_frame_codec.dart';
import 'package:tunai_pro/core/transport/icp5_raw_state_read.dart';
import 'package:tunai_pro/features/workbench/tabs/adau1701_icp5_tuning_panel.dart';
import 'package:tunai_pro/features/workbench/widgets/adau1701_peq_response_graph.dart';

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
  final bool _qWriteSuccess;

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
    bool qWriteSuccess = true,
    RawDspStateSnapshot? readbackSnapshot,
  })  : _readSnapshot = readSnapshot,
        _readError = readError,
        _gainWriteSuccess = gainWriteSuccess,
        _freqWriteSuccess = freqWriteSuccess,
        _qWriteSuccess = qWriteSuccess,
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

  // Records the output (channel) and band index of the most recent write of
  // each type so tests can assert selection is threaded through.
  int? lastGainBand;
  int? lastFreqBand;
  int? lastQBand;
  int? lastGainChannel;
  int? lastFreqChannel;

  @override
  Future<Adau1701WriteAck> writePeqGain(int channel, double gainDb,
      {int band = 0}) async {
    lastGainBand = band;
    lastGainChannel = channel;
    return Adau1701WriteAck(
      success: _gainWriteSuccess,
      message: _gainWriteSuccess ? 'PASS_ACK' : 'No ACK.',
    );
  }

  @override
  Future<Adau1701WriteAck> writeFilterFrequency(int channel, int frequencyHz,
      {int band = 0}) async {
    lastFreqBand = band;
    lastFreqChannel = channel;
    return Adau1701WriteAck(
      success: _freqWriteSuccess,
      message: _freqWriteSuccess ? 'PASS_ACK' : 'No ACK.',
    );
  }

  @override
  Future<Adau1701WriteAck> writePeqQ(int channel, double q,
      {int band = 0}) async {
    lastQBand = band;
    return Adau1701WriteAck(
      success: _qWriteSuccess,
      message: _qWriteSuccess ? 'PASS_ACK' : 'No ACK.',
    );
  }
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
  group('disconnected state', () {
    testWidgets('shows not-connected prompt and no READ button', (tester) async {
      final transport = _FakeTuningTransport(isConnected: false);
      await tester.binding.setSurfaceSize(const Size(1200, 3200));
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
      await tester.binding.setSurfaceSize(const Size(1200, 3200));
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
      await tester.binding.setSurfaceSize(const Size(1200, 3200));
      await tester.pumpWidget(_wrap(transport));
      await tester.pump();

      expect(find.textContaining('Profile mismatch'), findsOneWidget);
    });
  });

  group('connected — before READ', () {
    testWidgets('shows ADAU1701 ready status and READ button', (tester) async {
      final transport =
          _FakeTuningTransport(readSnapshot: _snapshot());
      await tester.binding.setSurfaceSize(const Size(1200, 3200));
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
      await tester.binding.setSurfaceSize(const Size(1200, 3200));
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
      await tester.binding.setSurfaceSize(const Size(1200, 3200));
      await tester.pumpWidget(_wrap(transport));
      await tester.pump();

      await tester.tap(find.text('READ DSP STATE'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Verify the TextField controllers have the hardware values.
      // find.byType(TextField) returns [gain, freq, q] in order.
      final textFields =
          tester.widgetList<TextField>(find.byType(TextField)).toList();
      expect(textFields[0].controller?.text, '-1.0'); // gain
      expect(textFields[1].controller?.text, '2000'); // frequency
      expect(textFields[2].controller?.text, '2.0'); // Q (prefilled from read)
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
      await tester.binding.setSurfaceSize(const Size(1200, 3200));
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

  group('after Q APPLY (adopted-from-Consumer, unverified)', () {
    testWidgets('shows Q WRITE ACK + Q READBACK and the unverified banner',
        (tester) async {
      final transport = _FakeTuningTransport(
        readSnapshot: _snapshot(),
        readbackSnapshot: _snapshot(),
      );
      await tester.binding.setSurfaceSize(const Size(1200, 3200));
      await tester.pumpWidget(_wrap(transport));
      await tester.pump();

      await tester.tap(find.text('READ DSP STATE'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final applyQ = find.text('APPLY Q (UNVERIFIED)');
      await tester.ensureVisible(applyQ);
      await tester.tap(applyQ);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.textContaining('Q WRITE ACK'), findsOneWidget);
      expect(find.textContaining('Q READBACK'), findsOneWidget);
      // Banner makes the unverified status explicit.
      expect(find.textContaining('do not treat a PASS here as confirmed'),
          findsOneWidget);
    });

    testWidgets('Q write failure shows error and no readback row',
        (tester) async {
      final transport = _FakeTuningTransport(
        readSnapshot: _snapshot(),
        qWriteSuccess: false,
      );
      await tester.binding.setSurfaceSize(const Size(1200, 3200));
      await tester.pumpWidget(_wrap(transport));
      await tester.pump();

      await tester.tap(find.text('READ DSP STATE'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final applyQ = find.text('APPLY Q (UNVERIFIED)');
      await tester.ensureVisible(applyQ);
      await tester.tap(applyQ);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.textContaining('Q WRITE ACK'), findsOneWidget);
      expect(find.textContaining('Q write failed'), findsOneWidget);
      expect(find.textContaining('Q READBACK'), findsNothing);
    });
  });

  group('multi-band selection', () {
    testWidgets('selecting Band 3 threads band index 2 into gain/freq writes',
        (tester) async {
      final transport = _FakeTuningTransport(readSnapshot: _snapshot());
      await tester.binding.setSurfaceSize(const Size(1200, 3200));
      await tester.pumpWidget(_wrap(transport));
      await tester.pump();

      await tester.tap(find.text('READ DSP STATE'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Select Band 3 (index 2).
      final band3 = find.byKey(const ValueKey('peq_band_2'));
      await tester.ensureVisible(band3);
      await tester.tap(band3);
      await tester.pump();

      await tester.tap(find.text('RUN PREFLIGHT + APPLY'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(transport.lastGainBand, 2);
      expect(transport.lastFreqBand, 2);
      // No readback/verification for non-Band-1 (decoder is Band 1 only).
      expect(find.textContaining('VERIFICATION'), findsNothing);
      // Unverified-band banner is shown.
      expect(find.textContaining('is NOT capture-proven and has no readback'),
          findsOneWidget);
    });

    testWidgets('Band 1 (default) still writes band index 0 with verification',
        (tester) async {
      final transport = _FakeTuningTransport(
        readSnapshot: _snapshot(),
        readbackSnapshot: _snapshot(),
      );
      await tester.binding.setSurfaceSize(const Size(1200, 3200));
      await tester.pumpWidget(_wrap(transport));
      await tester.pump();

      await tester.tap(find.text('READ DSP STATE'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await tester.tap(find.text('RUN PREFLIGHT + APPLY'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(transport.lastGainBand, 0);
      expect(transport.lastFreqBand, 0);
      expect(find.textContaining('VERIFICATION PASS'), findsOneWidget);
    });
  });

  group('PEQ response graph + output switching', () {
    testWidgets('graph appears after READ and shows Output 1', (tester) async {
      final transport = _FakeTuningTransport(readSnapshot: _snapshot());
      await tester.binding.setSurfaceSize(const Size(1200, 3200));
      await tester.pumpWidget(_wrap(transport));
      await tester.pump();

      await tester.tap(find.text('READ DSP STATE'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byType(Adau1701PeqResponseGraph), findsOneWidget);
      expect(find.textContaining('PEQ RESPONSE — OUTPUT 1'), findsOneWidget);
      // Output selector chips 1..4 exist.
      expect(find.byKey(const ValueKey('peq_output_0')), findsOneWidget);
      expect(find.byKey(const ValueKey('peq_output_3')), findsOneWidget);
    });

    testWidgets('selecting Output 3 threads channel index 2 into writes',
        (tester) async {
      final transport = _FakeTuningTransport(readSnapshot: _snapshot());
      await tester.binding.setSurfaceSize(const Size(1200, 3200));
      await tester.pumpWidget(_wrap(transport));
      await tester.pump();

      await tester.tap(find.text('READ DSP STATE'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final out3 = find.byKey(const ValueKey('peq_output_2'));
      await tester.ensureVisible(out3);
      await tester.tap(out3);
      await tester.pump();

      await tester.tap(find.text('RUN PREFLIGHT + APPLY'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(transport.lastGainChannel, 2);
      expect(transport.lastFreqChannel, 2);
      // Non-Output-1 → no readback verification card.
      expect(find.textContaining('VERIFICATION'), findsNothing);
      expect(find.textContaining('PEQ RESPONSE — OUTPUT 3'), findsOneWidget);
    });

    testWidgets('Output 1 (default) writes channel 0 with verification',
        (tester) async {
      final transport = _FakeTuningTransport(
        readSnapshot: _snapshot(),
        readbackSnapshot: _snapshot(),
      );
      await tester.binding.setSurfaceSize(const Size(1200, 3200));
      await tester.pumpWidget(_wrap(transport));
      await tester.pump();

      await tester.tap(find.text('READ DSP STATE'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await tester.tap(find.text('RUN PREFLIGHT + APPLY'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(transport.lastGainChannel, 0);
      expect(find.textContaining('VERIFICATION PASS'), findsOneWidget);
    });

    testWidgets('disabling the selected band drops it from the enabled count',
        (tester) async {
      final transport = _FakeTuningTransport(readSnapshot: _snapshot());
      await tester.binding.setSurfaceSize(const Size(1200, 3200));
      await tester.pumpWidget(_wrap(transport));
      await tester.pump();

      await tester.tap(find.text('READ DSP STATE'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // After READ, Band 1 is enabled → "1 / 10 bands".
      expect(find.textContaining('1 / 10 bands'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('peq_band_enable_toggle')));
      await tester.pump();

      // Now zero enabled bands contribute to the curve.
      expect(find.textContaining('0 / 10 bands'), findsOneWidget);
    });

    testWidgets('editing frequency immediately updates the graph bands',
        (tester) async {
      final transport = _FakeTuningTransport(readSnapshot: _snapshot());
      await tester.binding.setSurfaceSize(const Size(1200, 3200));
      await tester.pumpWidget(_wrap(transport));
      await tester.pump();

      await tester.tap(find.text('READ DSP STATE'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      Adau1701PeqResponseGraph graph() =>
          tester.widget<Adau1701PeqResponseGraph>(
              find.byType(Adau1701PeqResponseGraph));

      // After READ, selected band (Band 1) holds the read frequency (2000 Hz).
      expect(graph().bands[0].frequencyHz, 2000);
      expect(graph().bands[0].enabled, isTrue);

      // Edit the FREQUENCY field (2nd text field: gain, freq, q).
      await tester.enterText(find.byType(TextField).at(1), '8000');
      await tester.pump();

      // The graph immediately reflects the edited value — no Simulation needed.
      expect(graph().bands[0].frequencyHz, 8000);
      expect(graph().bands[0].enabled, isTrue);
    });
  });

  group('after APPLY — gain write fails', () {
    testWidgets('shows GAIN WRITE ACK fail, no FREQ ACK row, no verification',
        (tester) async {
      final transport = _FakeTuningTransport(
        readSnapshot: _snapshot(),
        gainWriteSuccess: false,
      );
      await tester.binding.setSurfaceSize(const Size(1200, 3200));
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
      await tester.binding.setSurfaceSize(const Size(1200, 3200));
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
      await tester.binding.setSurfaceSize(const Size(1200, 3200));
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
      await tester.binding.setSurfaceSize(const Size(1200, 3200));
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
      await tester.binding.setSurfaceSize(const Size(1200, 3200));
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
