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
import '../../../core/adau1701_peq_preset.dart';
import '../../../core/adau1701_peq_response.dart';
import '../../../core/transport/adau1701_ch0_band0_read_service.dart';
import '../../../core/transport/adau1701_peq_band.dart';
import '../../../core/transport/adau1701_peq_deployment_gate.dart';
import '../../../core/transport/adau1701_tuning_transport.dart';
import '../../../core/transport/icp5_frame_codec.dart';
import '../../../shared/pro_widgets.dart';
import '../widgets/adau1701_peq_response_graph.dart';

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
  // Q write is ADOPTED-FROM-CONSUMER and NOT capture-proven; its control is a
  // separate, clearly-labelled unverified path that never touches the proven
  // gain/frequency apply flow above.
  late final TextEditingController _qCtrl;
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

  // After Q APPLY (adopted-from-Consumer, hardware-unverified)
  double? _appliedQ;
  bool? _qWriteOk;
  Adau1701Ch0Band0OriginalState? _qVerifyState;
  String? _qApplyError;

  // Selected PEQ band index (0 = Band 1). Only Band 1 is capture-proven and
  // has a readback path (the confirmed decoder reads Ch0 Band 0); bands 2..10
  // reuse the confirmed band payload byte but are hardware-unverified.
  int _selectedBand = 0;
  bool get _bandIsProven => _selectedBand == 0;
  int _appliedBand = 0;

  // ── PEQ response model (visualisation/editing only) ────────────────────────
  // ADAU1701 PEQ is 4 outputs × 10 fixed bands. This local model feeds the PEQ
  // RESPONSE graph and the edit fields; it introduces no DSP parameter mapping
  // and does not write hardware by itself. `enabled` controls only whether a
  // band contributes to the rendered curve.
  static const int _outputCount = 4;
  int _selectedOutput = 0;
  // Global voicing preset (model/UI only — no DSP write). Flips to `custom` on
  // any manual band edit or after a hardware read.
  Adau1701PeqPreset _selectedPreset = Adau1701PeqPreset.flat;
  late final List<List<PeqResponseBand>> _peqModel;
  // Baseline snapshot captured at READ (the "current" curve), shown behind the
  // edited/total curve when present.
  List<List<PeqResponseBand>>? _baselineModel;

  @override
  void initState() {
    super.initState();
    _gate = Adau1701PeqDeploymentGate(transport: widget.transport);
    _gainCtrl = TextEditingController();
    _freqCtrl = TextEditingController();
    _qCtrl = TextEditingController();
    _peqModel = List.generate(
      _outputCount,
      (_) => List.generate(
        Icp5FrameCodec.peqBandCount,
        (_) => const PeqResponseBand(
            frequencyHz: 1000, gainDb: 0, q: 1.0, enabled: false),
      ),
    );
    // Poll transport status so the status bar reflects live ICP5 connection
    // changes without requiring the parent widget to rebuild.
    // Also clears stale read state on disconnect so the engineer always
    // sees fresh values after reconnect.
    _statusTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!_transportReady && _readState != null) {
        setState(() {
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
          _appliedQ = null;
          _qWriteOk = null;
          _qVerifyState = null;
          _qApplyError = null;
        });
        _gate.invalidate();
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _gainCtrl.dispose();
    _freqCtrl.dispose();
    _qCtrl.dispose();
    super.dispose();
  }

  bool get _transportReady =>
      widget.transport.isConnected &&
      widget.transport.handshakeComplete &&
      widget.transport.detectedProfile == Icp5FrameCodec.expectedProfile;

  PeqResponseBand get _selectedModelBand =>
      _peqModel[_selectedOutput][_selectedBand];

  /// Writes the current gain/freq/Q text into the selected output+band of the
  /// response model (used to keep the graph in sync with live edits).
  void _syncSelectedBandFromControllers({bool? enabled}) {
    final f = double.tryParse(_freqCtrl.text);
    final g = double.tryParse(_gainCtrl.text);
    final q = double.tryParse(_qCtrl.text);
    final cur = _selectedModelBand;
    _peqModel[_selectedOutput][_selectedBand] = cur.copyWith(
      frequencyHz: f ?? cur.frequencyHz,
      gainDb: g ?? cur.gainDb,
      q: q ?? cur.q,
      enabled: enabled ?? cur.enabled,
    );
  }

  /// Loads the selected output+band's model values into the edit controllers.
  void _repopulateControllers() {
    final b = _selectedModelBand;
    _gainCtrl.text = b.gainDb.toStringAsFixed(1);
    _freqCtrl.text = b.frequencyHz.toStringAsFixed(0);
    _qCtrl.text = b.q.toStringAsFixed(1);
  }

  List<List<PeqResponseBand>> _cloneModel() =>
      [for (final out in _peqModel) [...out]];

  /// Applies a global voicing [preset] to the editing model (all outputs).
  /// Model/UI only — no DSP write. `custom` is derived and not applied here.
  void _applyPreset(Adau1701PeqPreset preset) {
    if (!preset.hasCurve) return;
    setState(() {
      final bands = Adau1701PeqPresets.bandsFor(preset);
      for (var output = 0; output < _outputCount; output++) {
        _peqModel[output] = [for (final band in bands) band];
      }
      _selectedPreset = preset;
      _repopulateControllers();
    });
  }

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
      _appliedQ = null;
      _qWriteOk = null;
      _qVerifyState = null;
      _qApplyError = null;
    });
    try {
      final svc = Adau1701Ch0Band0ReadService(transport: widget.transport);
      final result = await svc.readOriginalState();
      if (!mounted) return;
      if (result.succeeded) {
        final s = result.originalState!;
        setState(() {
          _readState = s;
          // The verified read is Output 1 / Band 1 (Ch0 Band0). Load it into the
          // model, enable it, select it, and snapshot the baseline curve.
          _selectedOutput = 0;
          _selectedBand = 0;
          _peqModel[0][0] = PeqResponseBand(
            frequencyHz: s.frequencyHz.toDouble(),
            gainDb: s.gainDb,
            q: s.q,
            enabled: true,
          );
          // Device state does not correspond to a preset curve.
          _selectedPreset = Adau1701PeqPreset.custom;
          _baselineModel = _cloneModel();
          _repopulateControllers();
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

    final band = _selectedBand;
    final output = _selectedOutput;
    setState(() {
      _busy = true;
      _preflightMessage = null;
      _preflightPassed = null;
      // Snapshot intended values at apply time so _VerificationCard has stable data.
      _appliedGain = newGain;
      _appliedFreq = newFreq;
      _appliedBand = band;
      _gainWriteOk = null;
      _freqWriteOk = null;
      _verifyState = null;
      _applyError = null;
      // Reflect the applied values in the response model and enable the band.
      _peqModel[output][band] = _peqModel[output][band].copyWith(
        frequencyHz: newFreq.toDouble(),
        gainDb: newGain,
        enabled: true,
      );
    });

    try {
      // ── 1. Preflight ────────────────────────────────────────────────────
      const writePlan = Adau1701PeqWriteFields(gain: true, frequency: true);
      final preflight = await _gate.runPreflight(writePlan);
      if (!mounted) return;
      setState(() {
        _preflightPassed = preflight.passed;
        _preflightMessage = preflight.message;
        // Preflight does its own hardware read; use that fresh state so the
        // "CURRENT STATE" card stays in sync with actual pre-write values.
        if (preflight.originalState != null) {
          _readState = preflight.originalState;
        }
      });
      if (!preflight.passed) return;

      // ── 2. Write gain (to the selected output + band) ───────────────────
      final gainResult = await widget.transport
          .writePeqGain(output, newGain, band: band);
      if (!mounted) return;
      setState(() => _gainWriteOk = gainResult.success);
      if (!gainResult.success) {
        setState(() => _applyError = 'Gain write failed: ${gainResult.message}');
        return;
      }

      // ── 3. Write frequency (to the selected output + band) ──────────────
      final freqResult = await widget.transport
          .writeFilterFrequency(output, newFreq, band: band);
      if (!mounted) return;
      setState(() => _freqWriteOk = freqResult.success);
      if (!freqResult.success) {
        setState(
            () => _applyError = 'Frequency write failed: ${freqResult.message}');
        return;
      }

      // ── 4. Read-back verification (Output 1 / Band 1 only) ──────────────
      // The confirmed decoder reads Ch0 Band 0, so readback verification is
      // only possible for Output 1 / Band 1. All others are ACK-only.
      if (output != 0 || band != 0) return;
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

  /// Applies an ADAU1701 PEQ Q write. This path is ADOPTED-FROM-CONSUMER and is
  /// NOT capture-proven; hardware ACK + readback verification is PENDING. It is
  /// deliberately independent of [_apply] so the proven gain/frequency flow is
  /// never affected, but it uses the identical preflight gate and the same
  /// transport safety guards ([Icp5UsbTransport.writePeqQ] → _writePhaseC).
  Future<void> _applyQ() async {
    final newQ = double.tryParse(_qCtrl.text);
    if (newQ == null) {
      setState(() => _qApplyError = 'Enter valid Q.');
      return;
    }
    if (newQ < 0.3 || newQ > 10.0) {
      setState(() => _qApplyError = 'Q must be 0.3 .. 10.0.');
      return;
    }

    final band = _selectedBand;
    final output = _selectedOutput;
    setState(() {
      _busy = true;
      _appliedQ = newQ;
      _appliedBand = band;
      _qWriteOk = null;
      _qVerifyState = null;
      _qApplyError = null;
      // Reflect the applied Q in the response model.
      _peqModel[output][band] =
          _peqModel[output][band].copyWith(q: newQ, enabled: true);
    });

    try {
      // Same preflight gate as gain/frequency, declaring a Q write.
      final preflight =
          await _gate.runPreflight(const Adau1701PeqWriteFields(q: true));
      if (!mounted) return;
      if (!preflight.passed) {
        setState(() => _qApplyError = 'Preflight failed: ${preflight.message}');
        return;
      }
      if (preflight.originalState != null) {
        setState(() => _readState = preflight.originalState);
      }

      final qResult =
          await widget.transport.writePeqQ(output, newQ, band: band);
      if (!mounted) return;
      setState(() => _qWriteOk = qResult.success);
      if (!qResult.success) {
        setState(() => _qApplyError = 'Q write failed: ${qResult.message}');
        return;
      }

      // Read-back so hardware verification can compare intended vs actual Q.
      // Only Output 1 / Band 1 has a confirmed read offset; others ACK-only.
      if (output != 0 || band != 0) return;
      final svc = Adau1701Ch0Band0ReadService(transport: widget.transport);
      final verify = await svc.readOriginalState();
      if (!mounted) return;
      if (verify.succeeded) {
        setState(() => _qVerifyState = verify.originalState);
      } else {
        setState(() => _qApplyError = 'Q readback failed: ${verify.message}');
      }
    } catch (e) {
      if (mounted) setState(() => _qApplyError = '$e');
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

          // ── PEQ RESPONSE — primary tuning panel (full width, above cards) ──
          Row(children: [
            Text('PEQ RESPONSE — OUTPUT ${_selectedOutput + 1}',
                style: proSubtitle(size: 9)),
            const Spacer(),
            Text(
                '${Adau1701PeqResponse.enabledCount(_peqModel[_selectedOutput])}'
                ' / ${Icp5FrameCodec.peqBandCount} bands',
                style: proSubtitle(size: 9)),
          ]),
          const SizedBox(height: 6),
          _OutputSelector(
            outputCount: _outputCount,
            selectedOutput: _selectedOutput,
            onSelected: (o) => setState(() {
              _syncSelectedBandFromControllers();
              _selectedOutput = o;
              _repopulateControllers();
            }),
          ),
          const SizedBox(height: 8),
          Adau1701PeqResponseGraph(
            // Pass an immutable point-in-time snapshot so the graph detects
            // per-edit changes (the model is edited in place).
            bands: List.of(_peqModel[_selectedOutput]),
            selectedBandIndex: _selectedBand,
            baselineBands: _baselineModel?[_selectedOutput],
            height: 400,
          ),
          const SizedBox(height: 6),
          Text(
              'Combined curve of enabled bands (peaking model @ '
              '${(Adau1701PeqResponse.sampleRateHz / 1000).toStringAsFixed(0)} kHz). '
              'Editing model — only Output 1 / Band 1 readback is hardware-verified.',
              style: proSubtitle(size: 8)),
          const SizedBox(height: 16),

          _OriginalStateCard(state: _readState!),
          const SizedBox(height: 16),

          // ── PEQ PRESETS (global voicing — model only, no DSP write) ───────
          Text('PEQ PRESET', style: proSubtitle(size: 9)),
          const SizedBox(height: 6),
          _PresetSelector(
            selected: _selectedPreset,
            onSelected: _applyPreset,
          ),
          const SizedBox(height: 16),

          // ── PEQ APPLY (above bands — existing hardware safety gates) ──────
          Text('PEQ APPLY', style: proSubtitle(size: 9)),
          const SizedBox(height: 6),
          Text(
              'Runs preflight, then writes the selected band '
              '(Output ${_selectedOutput + 1} / Band ${_selectedBand + 1}) to the '
              'speaker. Rollback-guarded — nothing is written unless preflight '
              'passes.',
              style: proSubtitle(size: 8)),
          const SizedBox(height: 8),
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
              detail: _gainWriteOk!
                  ? 'ACK received (${Adau1701PeqBand(index: _appliedBand).label}).'
                  : 'No ACK.',
            ),
          ],
          if (_freqWriteOk != null) ...[
            const SizedBox(height: 4),
            _ResultRow(
              label: 'FREQ WRITE ACK',
              passed: _freqWriteOk!,
              detail: _freqWriteOk!
                  ? 'ACK received (${Adau1701PeqBand(index: _appliedBand).label}).'
                  : 'No ACK.',
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
          const SizedBox(height: 20),

          // ── Band selector (Band 1 .. Band 10) ────────────────────────────
          Text('PEQ BAND', style: proSubtitle(size: 9)),
          const SizedBox(height: 6),
          _BandSelector(
            selectedBand: _selectedBand,
            onSelected: (band) => setState(() {
              _syncSelectedBandFromControllers();
              _selectedBand = band;
              _repopulateControllers();
            }),
          ),
          if (!_bandIsProven) ...[
            const SizedBox(height: 8),
            _UnverifiedBanner(
              message:
                  'Band ${_selectedBand + 1} reuses the confirmed band payload '
                  'byte but is NOT capture-proven and has no readback path '
                  '(the decoder reads Band 1 only). Writes are ACK-only — '
                  'confirm on hardware.',
            ),
          ],
          const SizedBox(height: 16),

          // ── Edit section ─────────────────────────────────────────────────
          Row(children: [
            Text('NEW VALUES', style: proSubtitle(size: 9)),
            const Spacer(),
            // Enable/disable the selected band in the response graph.
            _BandEnableToggle(
              enabled: _selectedModelBand.enabled,
              onToggle: () => setState(() {
                _peqModel[_selectedOutput][_selectedBand] = _selectedModelBand
                    .copyWith(enabled: !_selectedModelBand.enabled);
                _selectedPreset = Adau1701PeqPreset.custom;
              }),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: _FieldEditor(
                label: 'GAIN (dB)  −6.0 .. +3.0',
                controller: _gainCtrl,
                hint: '-1.0',
                keyboardType: const TextInputType.numberWithOptions(
                    signed: true, decimal: true),
                onChanged: (_) => setState(() {
                  _syncSelectedBandFromControllers();
                  _selectedPreset = Adau1701PeqPreset.custom;
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _FieldEditor(
                label: 'FREQUENCY (Hz)  20 .. 20 000',
                controller: _freqCtrl,
                hint: '2000',
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {
                  _syncSelectedBandFromControllers();
                  _selectedPreset = Adau1701PeqPreset.custom;
                }),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
              'Edits update the graph live. Use PEQ APPLY above to write the '
              'selected band to the speaker.',
              style: proSubtitle(size: 8)),

          // ── Q (UNVERIFIED — adopted-from-Consumer) ─────────────────────────
          // Separate, clearly-labelled path. Does not affect the proven
          // gain/frequency apply above. Hardware ACK + readback verification
          // is pending; treat any result here as provisional.
          const SizedBox(height: 20),
          const _UnverifiedBanner(
            message:
                'Q write mapping is adopted from the Consumer app and is NOT '
                'capture-proven on ICP5. Hardware ACK + readback verification '
                'is pending — do not treat a PASS here as confirmed.',
          ),
          const SizedBox(height: 8),
          Text('Q (UNVERIFIED WRITE)  0.3 .. 10.0', style: proSubtitle(size: 9)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: _FieldEditor(
                label: 'Q  (adopted-from-Consumer, not capture-proven)',
                controller: _qCtrl,
                hint: '2.0',
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                onChanged: (_) => setState(() {
                  _syncSelectedBandFromControllers();
                  _selectedPreset = Adau1701PeqPreset.custom;
                }),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          _ActionButton(
            label: 'APPLY Q (UNVERIFIED)',
            icon: Icons.science_outlined,
            busy: _busy,
            color: kProAmber,
            onPressed: _applyQ,
          ),
          if (_qApplyError != null) ...[
            const SizedBox(height: 8),
            _errorRow(_qApplyError!),
          ],
          if (_qWriteOk != null) ...[
            const SizedBox(height: 4),
            _ResultRow(
              label: 'Q WRITE ACK',
              passed: _qWriteOk!,
              detail: _qWriteOk!
                  ? 'ACK received (mapping unverified — confirm on hardware).'
                  : 'No ACK.',
            ),
          ],
          if (_qVerifyState != null && (_qWriteOk ?? false)) ...[
            const SizedBox(height: 4),
            _ResultRow(
              label: 'Q READBACK',
              passed: (_qVerifyState!.q - (_appliedQ ?? 0)).abs() < 0.15,
              detail: 'wrote ${(_appliedQ ?? 0).toStringAsFixed(1)} · '
                  'read ${_qVerifyState!.q.toStringAsFixed(1)} '
                  '(hardware confirmation pending).',
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
            '${state.q.toStringAsFixed(2)}  (write path adopted-from-Consumer — UNVERIFIED)'),
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

// ── Unverified-path banner ──────────────────────────────────────────────────────

class _UnverifiedBanner extends StatelessWidget {
  final String message;
  const _UnverifiedBanner({required this.message});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: kProAmber.withValues(alpha: 0.08),
          border: Border.all(color: kProAmber.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(children: [
          const Icon(Icons.warning_amber_outlined, size: 12, color: kProAmber),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                  color: kProAmber.withValues(alpha: 0.9), fontSize: 9),
            ),
          ),
        ]),
      );
}

class _BandSelector extends StatelessWidget {
  final int selectedBand;
  final ValueChanged<int> onSelected;
  const _BandSelector(
      {required this.selectedBand, required this.onSelected});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var band = 0; band < Icp5FrameCodec.peqBandCount; band++)
            ChoiceChip(
              key: ValueKey('peq_band_$band'),
              label: Text('Band ${band + 1}${band == 0 ? '' : ' *'}',
                  style: const TextStyle(fontSize: 10)),
              selected: band == selectedBand,
              onSelected: (_) => onSelected(band),
            ),
        ],
      );
}

// ── Output selector (Output 1 .. 4) ─────────────────────────────────────────────

class _OutputSelector extends StatelessWidget {
  final int outputCount;
  final int selectedOutput;
  final ValueChanged<int> onSelected;
  const _OutputSelector({
    required this.outputCount,
    required this.selectedOutput,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var output = 0; output < outputCount; output++)
            ChoiceChip(
              key: ValueKey('peq_output_$output'),
              label: Text('Output ${output + 1}${output == 0 ? '' : ' *'}',
                  style: const TextStyle(fontSize: 10)),
              selected: output == selectedOutput,
              onSelected: (_) => onSelected(output),
            ),
        ],
      );
}

class _PresetSelector extends StatelessWidget {
  final Adau1701PeqPreset selected;
  final ValueChanged<Adau1701PeqPreset> onSelected;
  const _PresetSelector({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final preset in Adau1701PeqPresets.selectable)
            ChoiceChip(
              key: ValueKey('peq_preset_${preset.name}'),
              label: Text(preset.label, style: const TextStyle(fontSize: 10)),
              selected: selected == preset,
              onSelected: (_) => onSelected(preset),
            ),
          // Custom reflects manual edits; it is derived, not directly applied.
          ChoiceChip(
            key: const ValueKey('peq_preset_custom'),
            label: Text(Adau1701PeqPreset.custom.label,
                style: const TextStyle(fontSize: 10)),
            selected: selected == Adau1701PeqPreset.custom,
            onSelected: (_) {},
          ),
        ],
      );
}

class _BandEnableToggle extends StatelessWidget {
  final bool enabled;
  final VoidCallback onToggle;
  const _BandEnableToggle({required this.enabled, required this.onToggle});

  @override
  Widget build(BuildContext context) => GestureDetector(
        key: const ValueKey('peq_band_enable_toggle'),
        onTap: onToggle,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            enabled ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            size: 13,
            color: enabled ? kProGreen : Colors.white24,
          ),
          const SizedBox(width: 4),
          Text(enabled ? 'ENABLED' : 'DISABLED',
              style: TextStyle(
                  fontSize: 8,
                  letterSpacing: 0.6,
                  color: enabled ? kProGreen : Colors.white38)),
        ]),
      );
}

// ── Field editor ──────────────────────────────────────────────────────────────

class _FieldEditor extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  const _FieldEditor({
    required this.label,
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.onChanged,
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
            onChanged: onChanged,
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
