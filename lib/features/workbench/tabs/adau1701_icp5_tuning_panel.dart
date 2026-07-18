// ADAU1701 ICP5 Tuning Panel
//
// Provides the minimum usable tuning workflow for ADAU1701 via ICP5:
//   Connect → Detect → Read → Edit → Preflight → Write → Verify → PASS/FAIL
//
// Only confirmed fields are editable: PEQ gain and PEQ frequency.
// Q is displayed read-only (no confirmed write path).
// property08 is displayed read-only (semantic meaning unconfirmed).

import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/transport/adau1701_ch0_band0_read_service.dart';
import '../../../core/transport/adau1701_peq_deployment_gate.dart';
import '../../../core/transport/adau1701_tuning_transport.dart';
import '../../../core/transport/icp5_frame_codec.dart';
import '../../../shared/pro_widgets.dart';

class Adau1701Icp5TuningPanel extends StatefulWidget {
  final Adau1701TuningTransport transport;

  const Adau1701Icp5TuningPanel({super.key, required this.transport});

  @override
  State<Adau1701Icp5TuningPanel> createState() =>
      _Adau1701Icp5TuningPanelState();
}

class _Adau1701Icp5TuningPanelState extends State<Adau1701Icp5TuningPanel> {
  late final Adau1701PeqDeploymentGate _gate;
  late final TextEditingController _gainCtrl;
  late final TextEditingController _freqCtrl;
  Timer? _statusTimer;

  bool _busy = false;

  // After READ
  Adau1701Ch0Band0OriginalState? _readState;
  String? _readError;

  // After PREFLIGHT
  String? _preflightMessage;
  bool? _preflightPassed;

  // After APPLY — snapshotted at apply time, not re-read from controllers
  double? _appliedGain;
  int? _appliedFreq;
  bool? _gainWriteOk;
  bool? _freqWriteOk;
  Adau1701Ch0Band0OriginalState? _verifyState;
  String? _applyError;

  @override
  void initState() {
    super.initState();
    _gate = Adau1701PeqDeploymentGate(transport: widget.transport);
    _gainCtrl = TextEditingController();
    _freqCtrl = TextEditingController();
    // Poll transport status so the status bar reflects live ICP5 connection
    // changes without requiring the parent widget to rebuild.
    _statusTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _gainCtrl.dispose();
    _freqCtrl.dispose();
    super.dispose();
  }

  bool get _transportReady =>
      widget.transport.isConnected &&
      widget.transport.handshakeComplete &&
      widget.transport.detectedProfile == Icp5FrameCodec.expectedProfile;

  Future<void> _read() async {
    setState(() {
      _busy = true;
      _readState = null;
      _readError = null;
      _preflightMessage = null;
      _preflightPassed = null;
      _appliedGain = null;
      _appliedFreq = null;
      _gainWriteOk = null;
      _freqWriteOk = null;
      _verifyState = null;
      _applyError = null;
    });
    try {
      final svc = Adau1701Ch0Band0ReadService(transport: widget.transport);
      final result = await svc.readOriginalState();
      if (!mounted) return;
      if (result.succeeded) {
        final s = result.originalState!;
        setState(() {
          _readState = s;
          _gainCtrl.text = s.gainDb.toStringAsFixed(1);
          _freqCtrl.text = '${s.frequencyHz}';
        });
      } else {
        setState(() => _readError = result.message);
      }
    } catch (e) {
      if (mounted) setState(() => _readError = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    final newGain = double.tryParse(_gainCtrl.text);
    final newFreq = int.tryParse(_freqCtrl.text);
    if (newGain == null || newFreq == null) {
      setState(() => _applyError = 'Enter valid gain (dB) and frequency (Hz).');
      return;
    }
    if (newGain < -6.0 || newGain > 3.0) {
      setState(() => _applyError = 'Gain must be −6.0 .. +3.0 dB.');
      return;
    }
    if (newFreq < 20 || newFreq > 20000) {
      setState(() => _applyError = 'Frequency must be 20 .. 20 000 Hz.');
      return;
    }

    setState(() {
      _busy = true;
      _preflightMessage = null;
      _preflightPassed = null;
      // Snapshot intended values at apply time so _VerificationCard has stable data.
      _appliedGain = newGain;
      _appliedFreq = newFreq;
      _gainWriteOk = null;
      _freqWriteOk = null;
      _verifyState = null;
      _applyError = null;
    });

    try {
      // ── 1. Preflight ────────────────────────────────────────────────────
      const writePlan = Adau1701PeqWriteFields(gain: true, frequency: true);
      final preflight = await _gate.runPreflight(writePlan);
      if (!mounted) return;
      setState(() {
        _preflightPassed = preflight.passed;
        _preflightMessage = preflight.message;
      });
      if (!preflight.passed) return;

      // ── 2. Write gain ───────────────────────────────────────────────────
      final gainResult = await widget.transport.writePeqGain(0, newGain);
      if (!mounted) return;
      setState(() => _gainWriteOk = gainResult.success);
      if (!gainResult.success) {
        setState(() => _applyError = 'Gain write failed: ${gainResult.message}');
        return;
      }

      // ── 3. Write frequency ──────────────────────────────────────────────
      final freqResult =
          await widget.transport.writeFilterFrequency(0, newFreq);
      if (!mounted) return;
      setState(() => _freqWriteOk = freqResult.success);
      if (!freqResult.success) {
        setState(
            () => _applyError = 'Frequency write failed: ${freqResult.message}');
        return;
      }

      // ── 4. Read-back verification ───────────────────────────────────────
      final svc = Adau1701Ch0Band0ReadService(transport: widget.transport);
      final verify = await svc.readOriginalState();
      if (!mounted) return;
      if (verify.succeeded) {
        setState(() => _verifyState = verify.originalState);
      } else {
        setState(() => _applyError = 'Readback failed: ${verify.message}');
      }
    } catch (e) {
      if (mounted) setState(() => _applyError = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Status bar ───────────────────────────────────────────────────────
      _StatusBar(transport: widget.transport),
      const SizedBox(height: 16),

      if (!_transportReady) ...[
        _infoRow('Connect ICP5 and complete the handshake above to enable '
            'ADAU1701 PEQ tuning.'),
      ] else ...[
        // ── Read section ───────────────────────────────────────────────────
        _ActionButton(
          label: 'READ DSP STATE',
          icon: Icons.download_outlined,
          busy: _busy,
          onPressed: _read,
        ),
        if (_readError != null) ...[
          const SizedBox(height: 8),
          _errorRow(_readError!),
        ],
        if (_readState != null) ...[
          const SizedBox(height: 12),
          _OriginalStateCard(state: _readState!),
          const SizedBox(height: 16),

          // ── Edit section ─────────────────────────────────────────────────
          Text('NEW VALUES', style: proSubtitle(size: 9)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: _FieldEditor(
                label: 'GAIN (dB)  −6.0 .. +3.0',
                controller: _gainCtrl,
                hint: '-1.0',
                keyboardType: const TextInputType.numberWithOptions(
                    signed: true, decimal: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _FieldEditor(
                label: 'FREQUENCY (Hz)  20 .. 20 000',
                controller: _freqCtrl,
                hint: '2000',
                keyboardType: TextInputType.number,
              ),
            ),
          ]),
          const SizedBox(height: 16),

          // ── Apply section ────────────────────────────────────────────────
          _ActionButton(
            label: 'RUN PREFLIGHT + APPLY',
            icon: Icons.send_outlined,
            busy: _busy,
            color: kProAccent,
            onPressed: _apply,
          ),
          if (_applyError != null) ...[
            const SizedBox(height: 8),
            _errorRow(_applyError!),
          ],
          if (_preflightMessage != null) ...[
            const SizedBox(height: 10),
            _ResultRow(
              label: 'PREFLIGHT',
              passed: _preflightPassed ?? false,
              detail: _preflightMessage!,
            ),
          ],
          if (_gainWriteOk != null) ...[
            const SizedBox(height: 4),
            _ResultRow(
              label: 'GAIN WRITE ACK',
              passed: _gainWriteOk!,
              detail: _gainWriteOk! ? 'ACK received.' : 'No ACK.',
            ),
          ],
          if (_freqWriteOk != null) ...[
            const SizedBox(height: 4),
            _ResultRow(
              label: 'FREQ WRITE ACK',
              passed: _freqWriteOk!,
              detail: _freqWriteOk! ? 'ACK received.' : 'No ACK.',
            ),
          ],
          // Only show verification when both writes succeeded and readback returned.
          if (_verifyState != null &&
              (_gainWriteOk ?? false) &&
              (_freqWriteOk ?? false)) ...[
            const SizedBox(height: 10),
            _VerificationCard(
              original: _readState!,
              written: (gain: _appliedGain!, freq: _appliedFreq!),
              readback: _verifyState!,
            ),
          ],
        ],
      ],
    ]);
  }
}

// ── Status bar ────────────────────────────────────────────────────────────────

class _StatusBar extends StatelessWidget {
  final Adau1701TuningTransport transport;
  const _StatusBar({required this.transport});

  @override
  Widget build(BuildContext context) {
    final connected = transport.isConnected;
    final handshake = transport.handshakeComplete;
    final profile = transport.detectedProfile;
    final ready =
        connected && handshake && profile == Icp5FrameCodec.expectedProfile;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: (ready ? kProGreen : kProAmber).withValues(alpha: 0.08),
        border: Border.all(
          color: (ready ? kProGreen : kProAmber).withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(children: [
        Icon(
          ready ? Icons.check_circle_outline : Icons.radio_button_unchecked,
          color: ready ? kProGreen : kProAmber,
          size: 13,
        ),
        const SizedBox(width: 8),
        Text(
          ready
              ? 'ADAU1701 ready — $profile'
              : connected
                  ? (handshake
                      ? 'Profile mismatch: ${profile ?? "none"}'
                      : 'Handshake pending')
                  : 'Not connected',
          style: TextStyle(
            fontSize: 10,
            color: ready ? kProGreen : kProAmber,
            letterSpacing: 0.5,
          ),
        ),
      ]),
    );
  }
}

// ── Original state card ───────────────────────────────────────────────────────

class _OriginalStateCard extends StatelessWidget {
  final Adau1701Ch0Band0OriginalState state;
  const _OriginalStateCard({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kProPanel,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('CURRENT STATE (from hardware)', style: proSubtitle(size: 9)),
        const SizedBox(height: 8),
        _StateRow('Frequency', '${state.frequencyHz} Hz'),
        _StateRow('Gain', '${state.gainDb.toStringAsFixed(1)} dB'),
        _StateRow('Q',
            '${state.q.toStringAsFixed(2)}  (read-only — no write path confirmed)'),
        _StateRow('property08',
            '${state.property08State}  (read-only — semantic unconfirmed)'),
        _StateRow('Device', state.deviceId),
        _StateRow('Captured', state.capturedAt.toIso8601String()),
      ]),
    );
  }
}

class _StateRow extends StatelessWidget {
  final String label;
  final String value;
  const _StateRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: proSubtitle(size: 9, color: const Color(0xFF6B7280))),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: Colors.white70, fontSize: 10)),
          ),
        ]),
      );
}

// ── Verification card ─────────────────────────────────────────────────────────

class _VerificationCard extends StatelessWidget {
  final Adau1701Ch0Band0OriginalState original;
  final ({double gain, int freq}) written;
  final Adau1701Ch0Band0OriginalState readback;

  const _VerificationCard({
    required this.original,
    required this.written,
    required this.readback,
  });

  bool get _gainMatch => (readback.gainDb - written.gain).abs() < 0.15;
  bool get _freqMatch => readback.frequencyHz == written.freq;
  bool get _passed => _gainMatch && _freqMatch;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (_passed ? kProGreen : kProRed).withValues(alpha: 0.07),
        border: Border.all(
          color: (_passed ? kProGreen : kProRed).withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
            _passed ? Icons.check_circle : Icons.cancel,
            color: _passed ? kProGreen : kProRed,
            size: 13,
          ),
          const SizedBox(width: 6),
          Text(
            _passed ? 'VERIFICATION PASS' : 'VERIFICATION FAIL',
            style: TextStyle(
              fontSize: 10,
              color: _passed ? kProGreen : kProRed,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ]),
        const SizedBox(height: 8),
        _VerifyRow(
          field: 'Gain',
          original: '${original.gainDb.toStringAsFixed(1)} dB',
          written: '${written.gain.toStringAsFixed(1)} dB',
          readback: '${readback.gainDb.toStringAsFixed(1)} dB',
          match: _gainMatch,
        ),
        _VerifyRow(
          field: 'Frequency',
          original: '${original.frequencyHz} Hz',
          written: '${written.freq} Hz',
          readback: '${readback.frequencyHz} Hz',
          match: _freqMatch,
        ),
      ]),
    );
  }
}

class _VerifyRow extends StatelessWidget {
  final String field;
  final String original;
  final String written;
  final String readback;
  final bool match;

  const _VerifyRow({
    required this.field,
    required this.original,
    required this.written,
    required this.readback,
    required this.match,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(children: [
          SizedBox(
            width: 70,
            child: Text(field, style: proSubtitle(size: 9)),
          ),
          SizedBox(
            width: 80,
            child: Text('was $original',
                style: const TextStyle(color: Colors.white38, fontSize: 9)),
          ),
          SizedBox(
            width: 80,
            child: Text('→ $written',
                style: const TextStyle(color: Colors.white54, fontSize: 9)),
          ),
          Icon(
            match ? Icons.check : Icons.close,
            size: 10,
            color: match ? kProGreen : kProRed,
          ),
          const SizedBox(width: 4),
          Text(readback,
              style:
                  TextStyle(fontSize: 9, color: match ? kProGreen : kProRed)),
        ]),
      );
}

// ── Result row ────────────────────────────────────────────────────────────────

class _ResultRow extends StatelessWidget {
  final String label;
  final bool passed;
  final String detail;

  const _ResultRow({
    required this.label,
    required this.passed,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            passed ? Icons.check_circle_outline : Icons.error_outline,
            size: 12,
            color: passed ? kProGreen : kProRed,
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(
                    fontSize: 9,
                    color: passed ? kProGreen : kProRed,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(detail,
                style: const TextStyle(color: Colors.white54, fontSize: 9)),
          ),
        ],
      );
}

// ── Field editor ──────────────────────────────────────────────────────────────

class _FieldEditor extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;

  const _FieldEditor({
    required this.label,
    required this.controller,
    required this.hint,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: proSubtitle(size: 8)),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
              filled: true,
              fillColor: kProPanel,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              enabledBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: kProBorder),
                borderRadius: BorderRadius.all(Radius.circular(3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide:
                    BorderSide(color: kProAccent.withValues(alpha: 0.6)),
                borderRadius: const BorderRadius.all(Radius.circular(3)),
              ),
            ),
          ),
        ],
      );
}

// ── Action button ─────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback? onPressed;
  final Color color;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onPressed,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 34,
        child: OutlinedButton.icon(
          onPressed: busy ? null : onPressed,
          icon: busy
              ? SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: color.withValues(alpha: 0.6)),
                )
              : Icon(icon, size: 13, color: color),
          label: Text(label,
              style: TextStyle(
                  fontSize: 10, letterSpacing: 0.8, color: color)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: color.withValues(alpha: 0.4)),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
          ),
        ),
      );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _infoRow(String msg) => Row(
      children: [
        const Icon(Icons.info_outline, size: 12, color: Colors.white38),
        const SizedBox(width: 6),
        Expanded(
          child: Text(msg,
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ),
      ],
    );

Widget _errorRow(String msg) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, size: 12, color: kProRed),
        const SizedBox(width: 6),
        Expanded(
          child: Text(msg,
              style: const TextStyle(color: kProRed, fontSize: 10)),
        ),
      ],
    );
