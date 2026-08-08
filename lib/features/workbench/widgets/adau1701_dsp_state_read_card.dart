// ADAU1701 DSP State Read Card — BLE Live Readback + 4-Output MiUMAX Comparison
//
// Reads the current ADAU1701 hardware state over BLE via ICP5 0x2201/0x2202,
// decodes all 10 PEQ bands for all 4 output channels, and compares against the
// known MiUMAX reference for each output (Tweeter L/R and Woofer L/R).
//
// Read-only. Never writes to DSP. Never modifies project state.
// Ch0 Band 1: capture-proven. Ch0 Bands 2-10: stride-6 candidate.
// Ch1-3 all bands: channel-layout candidate (stride-60 structural hypothesis).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/adau1701_peq_response.dart';
import '../../../core/transport/adau1701_ch0_band0_read_service.dart';
import '../../../core/transport/adau1701_peq_band_decoder.dart';
import '../../../core/transport/icp5_raw_state_read.dart';
import '../../../core/transport/icp5_transports.dart'
    show Icp5BluetoothTransport;
import '../../../core/dsp/adau1701/readback/adau1701_state_decoder.dart';
import '../../../core/dsp/adau1701/readback/adau1701_output_role.dart';
import '../../../core/dsp/adau1701/readback/adau1701_peq_reference.dart';
import '../../../core/dsp/adau1701/readback/adau1701_dsp_comparison.dart';
import '../../../shared/pro_widgets.dart';
import 'adau1701_peq_response_graph.dart';
import 'graph_overlay_models.dart';

// ── Graph display mode ────────────────────────────────────────────────────────

enum _GraphDisplayMode { referenceOnly, readbackOnly, compareDifference }

extension _GraphDisplayModeLabel on _GraphDisplayMode {
  String get label => switch (this) {
        _GraphDisplayMode.referenceOnly => 'Reference Only',
        _GraphDisplayMode.readbackOnly => 'Readback Only',
        _GraphDisplayMode.compareDifference => 'Compare Difference',
      };
}

// ── Internal result model ─────────────────────────────────────────────────────

enum _ReadStatus { reading, success, failure }

enum _FailureKind {
  transportNotConnected,
  handshakeNotPassed,
  rawStateReadTimeout,
  invalidPageLength,
  payloadNot513Bytes,
  decoderFailure,
  unknown,
}

extension _FailureKindLabel on _FailureKind {
  String get label => switch (this) {
        _FailureKind.transportNotConnected => 'transport not connected',
        _FailureKind.handshakeNotPassed => 'handshake not passed',
        _FailureKind.rawStateReadTimeout => 'raw state read timeout',
        _FailureKind.invalidPageLength => 'invalid page length',
        _FailureKind.payloadNot513Bytes => 'payload not 513 bytes',
        _FailureKind.decoderFailure => 'decoder failure',
        _FailureKind.unknown => 'read failed',
      };
}

class _DspReadResult {
  final _ReadStatus status;
  final Adau1701StateSnapshot? stateSnapshot;
  final _FailureKind? failureKind;
  final String? failureDetail;

  const _DspReadResult._({
    required this.status,
    this.stateSnapshot,
    this.failureKind,
    this.failureDetail,
  });

  factory _DspReadResult.success(Adau1701StateSnapshot snapshot) =>
      _DspReadResult._(status: _ReadStatus.success, stateSnapshot: snapshot);

  factory _DspReadResult.failure(_FailureKind kind, {String? detail}) =>
      _DspReadResult._(
          status: _ReadStatus.failure,
          failureKind: kind,
          failureDetail: detail);
}

// ── Graph data helpers ────────────────────────────────────────────────────────

/// Converts decoded [PeqBandState] list to [PeqResponseBand] for graph
/// rendering. All bands enabled=true — confidence badges are labels only.
List<PeqResponseBand> peqBandsToResponseBands(List<PeqBandState> bands) => [
      for (final b in bands)
        PeqResponseBand(
          frequencyHz: b.frequencyHz.toDouble(),
          gainDb: b.gainDb,
          q: b.q,
          enabled: true,
        ),
    ];

/// Converts [PeqBandReference] list to [PeqResponseBand] for the MiUMAX
/// reference overlay curve. All bands enabled.
List<PeqResponseBand> peqReferenceToBands(List<PeqBandReference> refs) => [
      for (final r in refs)
        PeqResponseBand(
          frequencyHz: r.frequencyHz.toDouble(),
          gainDb: r.gainDb,
          q: r.q,
          enabled: true,
        ),
    ];

// ── Channel offset scan result ────────────────────────────────────────────────

class _ChannelScanHit {
  final int offset;
  final bool isWoofer;
  final String label;
  final bool band2match;
  final bool band3match;

  bool get fullyConfirmed => isWoofer ? (band2match && band3match) : true;

  const _ChannelScanHit({
    required this.offset,
    required this.isWoofer,
    required this.label,
    required this.band2match,
    required this.band3match,
  });
}

// ── Payload diff helpers ──────────────────────────────────────────────────────

typedef PayloadDiffEntry = ({int offset, int before, int after});

/// Compares two 513-byte payloads byte by byte and returns every position that
/// differs. Empty when identical. Exported so tests can verify the logic.
List<PayloadDiffEntry> computePayloadDiff(
    List<int> baseline, List<int> current) {
  final diffs = <PayloadDiffEntry>[];
  final len =
      baseline.length < current.length ? baseline.length : current.length;
  for (var i = 0; i < len; i++) {
    if (baseline[i] != current[i]) {
      diffs.add((offset: i, before: baseline[i], after: current[i]));
    }
  }
  return diffs;
}

// Known PEQ band layout inside the 513-byte 0x2202 payload.
// Ch0 base=19 is hardware-confirmed (MiUMAX Band1 capture-proven).
// Ch1-3 use stride-83 scanner-discovered offsets:
//   Woofer L (Ch2) Band1 (60Hz/+0.5dB/Q1.0) scanner-found at offset 185.
//   Woofer R (Ch3) Band1 scanner-found at offset 268.  Stride = 268−185 = 83.
//   Ch1 = 19+83=102, Ch2 = 19+166=185, Ch3 = 19+249=268.
const _kDspChBases = [19, 102, 185, 268];
const _kDspBandStride = 6;
const _kDspBandCount = 10;
const _kDspFieldNames = ['freq-lo', 'freq-hi', 'gain', 'pad', 'Q', 'prop08'];

/// Maps a raw byte [offset] to a human-readable DSP mapping label.
/// Exported so tests can verify the annotation logic independently.
String dspOffsetAnnotation(int offset) {
  for (var ch = 0; ch < _kDspChBases.length; ch++) {
    final base = _kDspChBases[ch];
    final rangeEnd = base + _kDspBandCount * _kDspBandStride;
    if (offset >= base && offset < rangeEnd) {
      final rel = offset - base;
      final band = rel ~/ _kDspBandStride;
      final field = rel % _kDspBandStride;
      final fieldName = _kDspFieldNames[field];
      final confirmed = ch == 0 && band == 0;
      final channelConfirmed = ch == 0;
      final confidence = confirmed
          ? 'confirmed'
          : channelConfirmed
              ? 'band-cand'
              : 'ch-cand';
      return 'Ch${ch + 1} Band${band + 1} $fieldName [$confidence]';
    }
  }
  // Note: page-2 marker (154) is now inside Ch1 range [102..161] and unreachable.
  // Note: page-3 marker (308) is now inside Ch3 range [268..327] and unreachable.
  if (offset == 462) return 'page-4 marker';
  return '— (unknown)';
}

// ── JSON export builder ───────────────────────────────────────────────────────

Map<String, dynamic> _buildExportJson(Adau1701StateSnapshot snap) {
  return {
    'device': 'ADAU1701',
    'capturedAt': snap.rawSnapshot.timestamp.toIso8601String(),
    'outputs': [
      for (final output in snap.outputs)
        {
          'index': output.outputIndex,
          'name': miuMaxOutputRoles[output.outputIndex].shortLabel,
          'channelLayoutProven': output.isChannelLayoutProven,
          'peq': [
            for (final band in output.peqBands)
              {
                'band': band.bandIndex + 1,
                'freqHz': band.frequencyHz,
                'gainDb': band.gainDb,
                'q': band.q,
                'confidence': switch (band.verificationStatus) {
                  PeqBandVerificationStatus.verified => 'hardwareConfirmed',
                  PeqBandVerificationStatus.mappingCandidate =>
                    'candidateMapping',
                  PeqBandVerificationStatus.channelLayoutCandidate => 'unknown',
                },
              },
          ],
        },
    ],
  };
}

// ── Card widget ───────────────────────────────────────────────────────────────

/// BLE live readback diagnostic card with 4-output MiUMAX comparison.
///
/// Shows READ button, output selector (with speaker role labels), EQ response
/// graph (Reference Only / Readback Only / Compare Difference modes), per-output
/// match score, PEQ comparison table, and JSON export. Never writes to DSP or
/// modifies project state.
class Adau1701DspStateReadCard extends StatefulWidget {
  final Adau1701RawReadTransport transport;

  const Adau1701DspStateReadCard({super.key, required this.transport});

  @override
  State<Adau1701DspStateReadCard> createState() =>
      _Adau1701DspStateReadCardState();
}

class _Adau1701DspStateReadCardState extends State<Adau1701DspStateReadCard> {
  _DspReadResult? _result;
  bool _showExport = false;
  bool _copiedToClipboard = false;
  bool _copiedJson = false;
  int _selectedOutput = 0;
  _GraphDisplayMode _graphMode = _GraphDisplayMode.readbackOnly;

  // Hex diff: baseline snapshot payload + computed diff after next READ.
  List<int>? _baselinePayload;
  List<PayloadDiffEntry>? _payloadDiff;

  // MiUMAX channel offset scan results — populated after each READ.
  List<_ChannelScanHit> _channelScanHits = [];
  bool _wooferSignatureFound = false;

  bool get _isReading => _result?.status == _ReadStatus.reading;

  bool get _canRead =>
      !_isReading &&
      widget.transport.isConnected &&
      widget.transport.handshakeComplete;

  Future<void> _runRead() async {
    if (_isReading) return;
    setState(() {
      _result = const _DspReadResult._(status: _ReadStatus.reading);
      _showExport = false;
      _copiedToClipboard = false;
      _copiedJson = false;
      _selectedOutput = 0;
      _graphMode = _GraphDisplayMode.readbackOnly;
    });

    if (!widget.transport.isConnected) {
      if (mounted) {
        setState(() => _result =
            _DspReadResult.failure(_FailureKind.transportNotConnected));
      }
      return;
    }
    if (!widget.transport.handshakeComplete) {
      if (mounted) {
        setState(() =>
            _result = _DspReadResult.failure(_FailureKind.handshakeNotPassed));
      }
      return;
    }

    // P0-2 — suspend the BLE heartbeat for the duration of this multi-
    // exchange raw-state read, exactly like deploy_dialog.dart's proven
    // mitigation: a heartbeat tick firing mid-sequence grabs _busy and the
    // read fails with "Another ICP5 transaction is active." USB has no
    // heartbeat timer, so this is a no-op there.
    final bleTransport = widget.transport is Icp5BluetoothTransport
        ? widget.transport as Icp5BluetoothTransport
        : null;
    bleTransport?.pauseHeartbeat();
    if (bleTransport != null) {
      const pollInterval = Duration(milliseconds: 50);
      var waited = 0;
      while (bleTransport.busy && waited < 3500) {
        await Future.delayed(pollInterval);
        waited += 50;
      }
    }

    final RawDspStateSnapshot snapshot;
    try {
      try {
        snapshot = await widget.transport.readRawDspState();
      } on TimeoutException catch (e) {
        if (mounted) {
          setState(() => _result = _DspReadResult.failure(
              _FailureKind.rawStateReadTimeout,
              detail: '$e'));
        }
        return;
      } on FormatException catch (e) {
        final msg = e.message.toLowerCase();
        final kind = msg.contains('length')
            ? _FailureKind.invalidPageLength
            : msg.contains('payload') || msg.contains('513')
                ? _FailureKind.payloadNot513Bytes
                : _FailureKind.unknown;
        if (mounted) {
          setState(
              () => _result = _DspReadResult.failure(kind, detail: e.message));
        }
        return;
      } on StateError catch (e) {
        final msg = e.message.toLowerCase();
        final kind = msg.contains('timeout') || msg.contains('response')
            ? _FailureKind.rawStateReadTimeout
            : _FailureKind.unknown;
        if (mounted) {
          setState(
              () => _result = _DspReadResult.failure(kind, detail: e.message));
        }
        return;
      } on ArgumentError catch (e) {
        if (mounted) {
          setState(() => _result = _DspReadResult.failure(
              _FailureKind.payloadNot513Bytes,
              detail: '${e.message}'));
        }
        return;
      } catch (e) {
        if (mounted) {
          setState(() => _result =
              _DspReadResult.failure(_FailureKind.unknown, detail: '$e'));
        }
        return;
      }
    } finally {
      bleTransport?.resumeHeartbeat();
    }

    if (snapshot.payload.length != 513) {
      if (mounted) {
        setState(() => _result = _DspReadResult.failure(
            _FailureKind.payloadNot513Bytes,
            detail: 'payload is ${snapshot.payload.length} bytes'));
      }
      return;
    }

    final Adau1701StateSnapshot stateSnapshot;
    try {
      stateSnapshot = Adau1701StateDecoder.decode(snapshot);
    } on FormatException catch (e) {
      if (mounted) {
        setState(() => _result = _DspReadResult.failure(
            _FailureKind.decoderFailure,
            detail: e.message));
      }
      return;
    }

    // Full 4-output log with per-band verification status.
    for (var ch = 0; ch < stateSnapshot.outputs.length; ch++) {
      final output = stateSnapshot.outputs[ch];
      final role = miuMaxOutputRoles[ch].shortLabel;
      final layoutLabel = output.isChannelLayoutProven
          ? 'hardware-confirmed'
          : 'candidate-offset';
      debugPrint('[DSP READBACK] Output${ch + 1} ($role) [$layoutLabel]');
      for (final band in output.peqBands) {
        final statusLabel = switch (band.verificationStatus) {
          PeqBandVerificationStatus.verified => 'confirmed',
          PeqBandVerificationStatus.mappingCandidate => 'band-cand',
          PeqBandVerificationStatus.channelLayoutCandidate => 'not-verified',
        };
        debugPrint(
          '  Band${band.bandIndex + 1}'
          '  ${band.frequencyHz}Hz'
          '  ${band.gainDb.toStringAsFixed(1)}dB'
          '  Q${band.q.toStringAsFixed(2)}'
          '  [$statusLabel]',
        );
      }
    }

    // MiUMAX channel offset scan — searches the raw payload for known EQ
    // signatures from hardware screenshots to find actual Ch2/Ch3 base offsets.
    final scanHits = _scanMiuMaxChannelOffsets(snapshot.payload);

    // Compute byte diff against captured baseline (if any).
    final diff = _baselinePayload != null
        ? computePayloadDiff(_baselinePayload!, snapshot.payload)
        : null;
    if (diff != null && diff.isNotEmpty) {
      debugPrint('[DSP READBACK] ${diff.length} byte(s) changed vs baseline:');
      for (final e in diff) {
        final label = dspOffsetAnnotation(e.offset);
        debugPrint(
          '  0x${e.offset.toRadixString(16).padLeft(3, '0')}'
          ' (${e.offset})'
          '  0x${e.before.toRadixString(16).padLeft(2, '0')}'
          ' → 0x${e.after.toRadixString(16).padLeft(2, '0')}'
          '  $label',
        );
      }
    } else if (diff != null) {
      debugPrint('[DSP READBACK] No changes vs baseline.');
    }

    if (mounted) {
      setState(() {
        _result = _DspReadResult.success(stateSnapshot);
        _payloadDiff = diff;
        _channelScanHits = scanHits;
        _wooferSignatureFound = scanHits.any((h) => h.isWoofer);
      });
    }
  }

  // Scans the 513-byte payload for known MiUMAX PEQ signatures from hardware
  // screenshots, to discover the actual byte offsets for Ch1-Ch3.
  //
  // Confirmed from MiUMAX software screenshots:
  //   Tweeter L (Ch0 offset 19): Band1 = 1800 Hz / 0.0 dB / Q 1.2
  //   Woofer L  (Ch2 offset ??): Band1 = 60 Hz   / +0.5 dB / Q 1.0
  //                               Band2 = 120 Hz  / 0.0 dB  / Q 1.0
  //                               Band3 = 220 Hz  / 0.0 dB  / Q 0.8
  //
  // Returns structured hits for display in the read card UI.
  List<_ChannelScanHit> _scanMiuMaxChannelOffsets(List<int> payload) {
    final hits = <_ChannelScanHit>[];

    // Verify Ch0 (Tweeter L) at confirmed offset 19.
    if (payload.length > 23) {
      final f = payload[19] | (payload[20] << 8);
      final rawG = payload[21];
      final g = rawG >= 0x80 ? rawG - 256 : rawG;
      final q10 = payload[23];
      debugPrint(
          '[DSP SCAN] Ch0 @ 19: ${f}Hz / ${(g / 10.0).toStringAsFixed(1)}dB'
          ' / Q${(q10 / 10.0).toStringAsFixed(1)}  (expect 1800Hz/0.0dB/Q1.2)');
      hits.add(_ChannelScanHit(
        offset: 19,
        isWoofer: false,
        label: 'Tweeter L (Ch0) @ offset 19  ✓ confirmed',
        band2match: true,
        band3match: true,
      ));
    }

    // Search for Woofer L Band1: 60Hz (0x3C,0x00) / +0.5dB (0x05) / Q1.0 (0x0A).
    bool wooferFound = false;
    for (var i = 0; i + 4 < payload.length; i++) {
      if (payload[i] == 0x3C &&
          payload[i + 1] == 0x00 &&
          payload[i + 2] == 0x05 &&
          payload[i + 4] == 0x0A) {
        wooferFound = true;
        bool band2ok = false;
        bool band3ok = false;
        if (i + 10 < payload.length) {
          final b2 = i + 6;
          final f2 = payload[b2] | (payload[b2 + 1] << 8);
          final rawG2 = payload[b2 + 2];
          final g2 = rawG2 >= 0x80 ? rawG2 - 256 : rawG2;
          final q2 = payload[b2 + 4];
          band2ok = f2 == 120 && g2 == 0 && q2 == 0x0A;
          debugPrint('[DSP SCAN] WOOFER Band2 @ ${i + 6}: ${f2}Hz'
              ' / ${(g2 / 10.0).toStringAsFixed(1)}dB'
              ' / Q${(q2 / 10.0).toStringAsFixed(1)}'
              '  ${band2ok ? "✓ MATCH" : "✗ expect 120Hz/0.0dB/Q1.0"}');
        }
        if (i + 16 < payload.length) {
          final b3 = i + 12;
          final f3 = payload[b3] | (payload[b3 + 1] << 8);
          final rawG3 = payload[b3 + 2];
          final g3 = rawG3 >= 0x80 ? rawG3 - 256 : rawG3;
          final q3 = payload[b3 + 4];
          band3ok = f3 == 220 && g3 == 0 && q3 == 0x08;
          debugPrint('[DSP SCAN] WOOFER Band3 @ ${i + 12}: ${f3}Hz'
              ' / ${(g3 / 10.0).toStringAsFixed(1)}dB'
              ' / Q${(q3 / 10.0).toStringAsFixed(1)}'
              '  ${band3ok ? "✓ MATCH" : "✗ expect 220Hz/0.0dB/Q0.8"}');
        }
        final confirmed = band2ok && band3ok;
        debugPrint('[DSP SCAN] WOOFER Band1 @ offset $i'
            '  ${confirmed ? "→ Ch2 CONFIRMED" : "→ partial match"}');
        hits.add(_ChannelScanHit(
          offset: i,
          isWoofer: true,
          label: confirmed
              ? 'Woofer L (Ch2) @ offset $i  ✓ Band1+2+3 match'
              : 'Woofer Band1 @ offset $i  ⚠ Band2/3 mismatch',
          band2match: band2ok,
          band3match: band3ok,
        ));
      }
    }

    if (!wooferFound) {
      debugPrint('[DSP SCAN] WOOFER Band1 (60Hz/+0.5dB/Q1.0) — NOT FOUND');
      debugPrint(
          '[DSP SCAN] → Use hex diff: CAPTURE BASELINE → change Woofer band'
          ' in MiUMAX → READ → diff shows Ch2 offset');
    }

    // Search for Tweeter R (Ch1) — same Band1 as Tweeter L but different offset.
    for (var i = 0; i + 4 < payload.length; i++) {
      if (i == 19) continue;
      if (payload[i] == 0x08 &&
          payload[i + 1] == 0x07 &&
          payload[i + 2] == 0x00 &&
          payload[i + 4] == 0x0C) {
        debugPrint(
            '[DSP SCAN] TWEETER duplicate @ offset $i  ← Ch1 (Tweeter R) candidate');
        hits.add(_ChannelScanHit(
          offset: i,
          isWoofer: false,
          label: 'Tweeter R (Ch1) candidate @ offset $i  (1800Hz/0dB/Q1.2)',
          band2match: false,
          band3match: false,
        ));
      }
    }

    return hits;
  }

  Future<void> _copyHexDump() async {
    final snap = _result?.stateSnapshot?.rawSnapshot;
    if (snap == null) return;
    await Clipboard.setData(ClipboardData(text: snap.rawHexDump()));
    if (mounted) setState(() => _copiedToClipboard = true);
  }

  Future<void> _copyJsonExport() async {
    final snap = _result?.stateSnapshot;
    if (snap == null) return;
    final json = jsonEncode(_buildExportJson(snap));
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) setState(() => _copiedJson = true);
  }

  void _captureBaseline() {
    final snap = _result?.stateSnapshot?.rawSnapshot;
    if (snap == null) return;
    setState(() {
      _baselinePayload = List<int>.from(snap.payload);
      _payloadDiff = null; // diff is stale until next READ
    });
  }

  void _clearBaseline() {
    setState(() {
      _baselinePayload = null;
      _payloadDiff = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final connected =
        widget.transport.isConnected && widget.transport.handshakeComplete;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
              Icons.memory_outlined,
              size: 13,
              color:
                  connected ? kProGreen.withValues(alpha: 0.8) : Colors.white24,
            ),
            const SizedBox(width: 8),
            Text('ADAU1701 LIVE DSP STATE', style: proTitle(size: 12)),
            const Spacer(),
            _TransportStatusBadge(
              connected: widget.transport.isConnected,
              handshaked: widget.transport.handshakeComplete,
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            'Read-only · 4-output PEQ · MiUMAX comparison (Tweeter + Woofer)',
            style: proSubtitle(size: 10),
          ),
          const SizedBox(height: 12),
          Row(children: [
            _ReadButton(
              canRead: _canRead,
              isReading: _isReading,
              onTap: _canRead ? _runRead : null,
            ),
            if (_result?.status == _ReadStatus.success) ...[
              const SizedBox(width: 10),
              _ExportButton(
                showExport: _showExport,
                copied: _copiedToClipboard,
                onToggle: () => setState(() {
                  _showExport = !_showExport;
                  _copiedToClipboard = false;
                }),
                onCopy: _copyHexDump,
              ),
              const SizedBox(width: 6),
              _JsonCopyButton(copied: _copiedJson, onCopy: _copyJsonExport),
            ],
          ]),
          if (_result?.status == _ReadStatus.success) ...[
            const SizedBox(height: 8),
            Row(children: [
              _BaselineButton(
                hasBaseline: _baselinePayload != null,
                onCapture: _captureBaseline,
              ),
              if (_baselinePayload != null) ...[
                const SizedBox(width: 6),
                _ClearBaselineButton(onClear: _clearBaseline),
              ],
              if (_payloadDiff != null) ...[
                const SizedBox(width: 8),
                Icon(Icons.compare_arrows_outlined,
                    size: 11, color: kProAmber.withValues(alpha: 0.8)),
                const SizedBox(width: 4),
                Text(
                  _payloadDiff!.isEmpty
                      ? 'No changes'
                      : '${_payloadDiff!.length} byte(s) changed',
                  style: TextStyle(
                    fontSize: 10,
                    color: _payloadDiff!.isEmpty ? kProGreen : kProAmber,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ]),
          ],
          if (!connected && !_isReading) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.info_outline, size: 11, color: Colors.white38),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  !widget.transport.isConnected
                      ? 'BLE not connected — connect via TRANSPORT ARCHITECTURE above.'
                      : 'BLE handshake not passed — reconnect to complete identity check.',
                  style: proSubtitle(size: 10),
                ),
              ),
            ]),
          ],
          if (_result != null && !_isReading) ...[
            const SizedBox(height: 14),
            const Divider(color: Color(0xFF1E2832), height: 1),
            const SizedBox(height: 12),
            if (_result!.status == _ReadStatus.success) ...[
              _SuccessDisplay(
                stateSnapshot: _result!.stateSnapshot!,
                showExport: _showExport,
                selectedOutput: _selectedOutput,
                onOutputSelected: (i) => setState(() {
                  _selectedOutput = i;
                  _graphMode = _GraphDisplayMode.readbackOnly;
                }),
                graphMode: _graphMode,
                onGraphModeChanged: (m) => setState(() => _graphMode = m),
              ),
              // Channel offset scan results — always shown after a READ.
              if (_channelScanHits.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Divider(color: Color(0xFF1E2832), height: 1),
                const SizedBox(height: 10),
                _ChannelScanSection(
                  hits: _channelScanHits,
                  wooferFound: _wooferSignatureFound,
                ),
              ],
              // Hex diff section — only when a baseline is captured.
              if (_baselinePayload != null) ...[
                const SizedBox(height: 14),
                const Divider(color: Color(0xFF1E2832), height: 1),
                const SizedBox(height: 10),
                _HexDiffSection(diff: _payloadDiff),
              ],
            ] else
              _FailureDisplay(result: _result!),
          ],
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _TransportStatusBadge extends StatelessWidget {
  final bool connected;
  final bool handshaked;
  const _TransportStatusBadge(
      {required this.connected, required this.handshaked});

  @override
  Widget build(BuildContext context) {
    final ready = connected && handshaked;
    final label = ready
        ? 'BLE READY'
        : connected
            ? 'HANDSHAKE PENDING'
            : 'NOT CONNECTED';
    final color = ready ? kProGreen : kProAmber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 9,
              color: color,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.7)),
    );
  }
}

class _ReadButton extends StatelessWidget {
  final bool canRead;
  final bool isReading;
  final VoidCallback? onTap;
  const _ReadButton(
      {required this.canRead, required this.isReading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: canRead ? kProAccent.withValues(alpha: 0.08) : kProSurface,
          border: Border.all(
              color: canRead ? kProAccent.withValues(alpha: 0.45) : kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (isReading) ...[
            SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: kProAccent.withValues(alpha: 0.7)),
            ),
            const SizedBox(width: 8),
          ] else ...[
            Icon(Icons.download_outlined,
                size: 13, color: canRead ? kProAccent : Colors.white24),
            const SizedBox(width: 8),
          ],
          Text(
            isReading ? 'Reading DSP state…' : 'READ CURRENT DSP STATE',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: canRead ? kProAccent : Colors.white24),
          ),
        ]),
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  final bool showExport;
  final bool copied;
  final VoidCallback onToggle;
  final VoidCallback onCopy;
  const _ExportButton(
      {required this.showExport,
      required this.copied,
      required this.onToggle,
      required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              border: Border.all(color: kProBorder),
              borderRadius: BorderRadius.circular(4)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
                showExport
                    ? Icons.visibility_off_outlined
                    : Icons.data_object_outlined,
                size: 12,
                color: Colors.white38),
            const SizedBox(width: 6),
            Text(showExport ? 'HIDE HEX DUMP' : 'EXPORT RAW DSP STATE',
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: Colors.white38)),
          ]),
        ),
      ),
      if (showExport) ...[
        const SizedBox(width: 6),
        GestureDetector(
          onTap: onCopy,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: copied
                  ? kProGreen.withValues(alpha: 0.08)
                  : Colors.transparent,
              border: Border.all(
                  color:
                      copied ? kProGreen.withValues(alpha: 0.35) : kProBorder),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(copied ? 'COPIED' : 'COPY',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: copied ? kProGreen : Colors.white38)),
          ),
        ),
      ],
    ]);
  }
}

class _JsonCopyButton extends StatelessWidget {
  final bool copied;
  final VoidCallback onCopy;
  const _JsonCopyButton({required this.copied, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onCopy,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color:
              copied ? kProGreen.withValues(alpha: 0.08) : Colors.transparent,
          border: Border.all(
              color: copied ? kProGreen.withValues(alpha: 0.35) : kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.file_download_outlined,
              size: 12, color: copied ? kProGreen : Colors.white38),
          const SizedBox(width: 5),
          Text(copied ? 'JSON COPIED' : 'COPY JSON',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: copied ? kProGreen : Colors.white38)),
        ]),
      ),
    );
  }
}

// ── Success display ───────────────────────────────────────────────────────────

class _SuccessDisplay extends StatelessWidget {
  final Adau1701StateSnapshot stateSnapshot;
  final bool showExport;
  final int selectedOutput;
  final ValueChanged<int> onOutputSelected;
  final _GraphDisplayMode graphMode;
  final ValueChanged<_GraphDisplayMode> onGraphModeChanged;

  const _SuccessDisplay({
    required this.stateSnapshot,
    required this.showExport,
    required this.selectedOutput,
    required this.onOutputSelected,
    required this.graphMode,
    required this.onGraphModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final ts = stateSnapshot.rawSnapshot.timestamp;
    final comparison = Adau1701DspComparison.compare(stateSnapshot);
    final selectedOutputData = stateSnapshot.outputs[selectedOutput];
    final selectedComparison = comparison.outputs[selectedOutput];
    final refs = Adau1701MiuMaxPeqReference.forChannel(selectedOutput);
    final roleLabel = miuMaxOutputTabLabel(selectedOutput);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // LIVE badge + timestamp
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: kProGreen.withValues(alpha: 0.10),
            border: Border.all(color: kProGreen.withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: const Text('LIVE DSP STATE',
              style: TextStyle(
                  fontSize: 9,
                  color: kProGreen,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.7)),
        ),
        const SizedBox(width: 8),
        Text('captured ${ts.toLocal().toString().substring(11, 19)}',
            style: proSubtitle(size: 9)),
      ]),
      const SizedBox(height: 10),

      // Output selector — scrollable to fit role labels
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: _OutputSelectorRow(
            selectedOutput: selectedOutput, onSelected: onOutputSelected),
      ),
      const SizedBox(height: 10),

      // Per-output match score summary (always visible — all 4 outputs)
      _MatchScoreSection(comparison: comparison),
      const SizedBox(height: 12),

      const Divider(color: Color(0xFF1E2832), height: 1),
      const SizedBox(height: 12),

      // Detail for selected output
      // Channel layout warning banner for Ch1-3 (shown above content, not replacing it)
      if (selectedOutput > 0)
        _ChannelLayoutWarningBanner(outputIndex: selectedOutput),
      if (selectedOutput > 0) const SizedBox(height: 10),

      // Graph
      _LiveGraphSection(
        outputIndex: selectedOutput,
        peqBands: selectedOutputData.peqBands,
        referenceBands: refs,
        hasComparableReference: selectedComparison.hasComparableReference,
        graphMode: graphMode,
        onModeChanged: onGraphModeChanged,
      ),
      const SizedBox(height: 14),

      // Comparison table
      if (selectedComparison.bandComparisons != null) ...[
        Text('$roleLabel  ·  PEQ Comparison',
            style: proTitle(size: 11, color: Colors.white70)),
        const SizedBox(height: 4),
        if (!selectedComparison.hasComparableReference) _GainQPendingNote(),
        const SizedBox(height: 6),
        _ComparisonTable(comparisons: selectedComparison.bandComparisons!),
        const SizedBox(height: 14),
      ],

      // Full band table (raw readback values + confidence badges)
      Text('$roleLabel  ·  EQ (All Bands)',
          style: proTitle(size: 11, color: Colors.white70)),
      const SizedBox(height: 8),
      _BandHeaderRow(),
      const SizedBox(height: 4),
      for (final band in selectedOutputData.peqBands) ...[
        _BandRow(band: band),
        const SizedBox(height: 3),
      ],
      const SizedBox(height: 14),

      _PendingCaptureSection(label: 'Output Gain / Mute / Delay / Phase / XO'),

      // Hex dump
      if (showExport) ...[
        const SizedBox(height: 14),
        const Divider(color: Color(0xFF1E2832), height: 1),
        const SizedBox(height: 10),
        Text('RAW HEX DUMP  (513 bytes)',
            style: proSubtitle(size: 9, color: Colors.white38)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF080E14),
            border: Border.all(color: kProBorder),
            borderRadius: BorderRadius.circular(3),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              stateSnapshot.rawSnapshot.rawHexDump(),
              style: const TextStyle(
                  fontSize: 9,
                  color: Colors.white54,
                  fontFamily: 'monospace',
                  height: 1.6),
            ),
          ),
        ),
      ],
    ]);
  }
}

// ── Per-output match score ────────────────────────────────────────────────────

class _MatchScoreSection extends StatelessWidget {
  final DspComparisonSummary comparison;
  const _MatchScoreSection({required this.comparison});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('MATCH VS MIUMAX ENGINEERING REFERENCE',
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Colors.white38)),
        const SizedBox(height: 4),
        // P0-D — this compares live readback against a FIXED MiUMAX
        // factory-default reference, never this project's actual current
        // tuning. A low score here means "differs from the MiUMAX
        // baseline" (expected once you've customized PEQ), not "DSP
        // readback failed" — Full DSP Readback above already proves the
        // hardware read succeeded regardless of this score.
        Text(
          'Fixed engineering baseline, not this project\'s current tuning — '
          'a low score is expected once PEQ has been customized.',
          style: proSubtitle(size: 9, color: Colors.white30),
        ),
        const SizedBox(height: 8),
        for (final out in comparison.outputs) ...[
          _OutputScoreRow(outputResult: out),
          if (out != comparison.outputs.last) const SizedBox(height: 6),
        ],
      ]),
    );
  }
}

class _OutputScoreRow extends StatelessWidget {
  final OutputComparisonResult outputResult;
  const _OutputScoreRow({required this.outputResult});

  @override
  Widget build(BuildContext context) {
    final role = outputResult.role;
    final hasComp = outputResult.hasComparableReference;
    final layoutUnconfirmed = outputResult.outputIndex > 0;

    if (!hasComp) {
      // Woofer: Gain/Q pending
      return Row(children: [
        SizedBox(
          width: 80,
          child: Text(role.shortLabel,
              style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white54,
                  fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Text('Gain/Q pending capture',
              style: proSubtitle(size: 9, color: Colors.white30)),
        ),
      ]);
    }

    final matched = outputResult.matchCount;
    final total = outputResult.totalComparable;
    final pct = outputResult.matchScorePercent;
    final scoreColor = pct >= 90
        ? kProGreen
        : pct >= 60
            ? kProAmber
            : kProRed;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        SizedBox(
          width: 80,
          child: Text(role.shortLabel,
              style: TextStyle(
                  fontSize: 10,
                  color: scoreColor,
                  fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : matched / total,
              backgroundColor: scoreColor.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(scoreColor),
              minHeight: 3,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('$matched/$total  ${pct.toStringAsFixed(0)}%',
            style: TextStyle(
                fontSize: 10,
                color: scoreColor,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()])),
        if (layoutUnconfirmed) ...[
          const SizedBox(width: 4),
          Icon(Icons.warning_amber_outlined,
              size: 10, color: kProAmber.withValues(alpha: 0.7)),
        ],
      ]),
    ]);
  }
}

// ── Output selector ───────────────────────────────────────────────────────────

class _OutputSelectorRow extends StatelessWidget {
  static const _outputCount = 4;
  final int selectedOutput;
  final ValueChanged<int> onSelected;
  const _OutputSelectorRow(
      {required this.selectedOutput, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _outputCount; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          _OutputTab(
            label: miuMaxOutputTabLabel(i),
            selected: selectedOutput == i,
            isProven: i == 0,
            onTap: () => onSelected(i),
          ),
        ],
      ],
    );
  }
}

class _OutputTab extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isProven;
  final VoidCallback onTap;
  const _OutputTab(
      {required this.label,
      required this.selected,
      required this.isProven,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final activeColor = isProven ? kProAccent : kProAmber;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? activeColor.withValues(alpha: 0.10)
              : Colors.transparent,
          border: Border.all(color: selected ? activeColor : kProBorder),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: selected ? activeColor : Colors.white38)),
      ),
    );
  }
}

// ── Live graph section ────────────────────────────────────────────────────────

class _LiveGraphSection extends StatelessWidget {
  final int outputIndex;
  final List<PeqBandState> peqBands;
  final List<PeqBandReference>? referenceBands;
  final bool hasComparableReference;
  final _GraphDisplayMode graphMode;
  final ValueChanged<_GraphDisplayMode> onModeChanged;

  const _LiveGraphSection({
    required this.outputIndex,
    required this.peqBands,
    required this.referenceBands,
    required this.hasComparableReference,
    required this.graphMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final liveBands = peqBandsToResponseBands(peqBands);
    final refBands = referenceBands != null
        ? peqReferenceToBands(referenceBands!)
        : <PeqResponseBand>[];

    // Map display mode to graph parameters.
    final List<PeqResponseBand> graphBands;
    List<PeqGraphCurve>? overlayCurves;
    PeqGraphMode graphWidgetMode;

    switch (graphMode) {
      case _GraphDisplayMode.referenceOnly:
        graphBands = refBands.isNotEmpty ? refBands : liveBands;
        overlayCurves = null;
        graphWidgetMode = PeqGraphMode.single;
      case _GraphDisplayMode.readbackOnly:
        graphBands = liveBands;
        overlayCurves = null;
        graphWidgetMode = PeqGraphMode.single;
      case _GraphDisplayMode.compareDifference:
        graphBands = liveBands;
        overlayCurves = refBands.isNotEmpty
            ? [
                PeqGraphCurve(
                    label: 'Readback', bands: liveBands, color: kProAccent),
                PeqGraphCurve(
                    label: 'MiUMAX', bands: refBands, color: kProAmber),
              ]
            : null;
        graphWidgetMode = overlayCurves != null
            ? PeqGraphMode.difference
            : PeqGraphMode.single;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Mode toggle row
      Row(children: [
        for (final mode in _GraphDisplayMode.values) ...[
          if (mode != _GraphDisplayMode.values.first) const SizedBox(width: 5),
          _GraphModeButton(
            label: mode.label,
            selected: graphMode == mode,
            onTap: () => onModeChanged(mode),
          ),
        ],
      ]),
      if (!hasComparableReference &&
          graphMode == _GraphDisplayMode.referenceOnly)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
              'Reference curve: frequency positions only · Gain/Q pending',
              style: proSubtitle(size: 9, color: Colors.white30)),
        ),
      const SizedBox(height: 8),
      Adau1701PeqResponseGraph(
        key: ValueKey('live_graph_ch$outputIndex'),
        bands: graphBands,
        height: 200,
        autoScale: true,
        overlayCurves: overlayCurves,
        mode: graphWidgetMode,
      ),
    ]);
  }
}

class _GraphModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _GraphModeButton(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? kProAccent.withValues(alpha: 0.10)
              : Colors.transparent,
          border: Border.all(
              color:
                  selected ? kProAccent.withValues(alpha: 0.45) : kProBorder),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: selected ? kProAccent : Colors.white30)),
      ),
    );
  }
}

// ── Channel layout warning banner (compact, non-blocking) ─────────────────────

class _ChannelLayoutWarningBanner extends StatelessWidget {
  final int outputIndex;
  const _ChannelLayoutWarningBanner({required this.outputIndex});

  @override
  Widget build(BuildContext context) {
    final base = Adau1701PeqBandDecoder.band0BaseOffset +
        Adau1701PeqBandDecoder.candidateChannelStride * outputIndex;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: kProAmber.withValues(alpha: 0.04),
        border: Border.all(color: kProAmber.withValues(alpha: 0.30)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(children: [
        Icon(Icons.warning_amber_outlined,
            size: 12, color: kProAmber.withValues(alpha: 0.8)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Ch$outputIndex layout candidate · offset $base–${base + 59} unconfirmed · '
            'readback values may not reflect this output\'s actual DSP state.',
            style:
                proSubtitle(size: 9, color: kProAmber.withValues(alpha: 0.75)),
          ),
        ),
      ]),
    );
  }
}

// ── Gain/Q pending note ───────────────────────────────────────────────────────

class _GainQPendingNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const Icon(Icons.hourglass_empty_outlined,
          size: 11, color: Colors.white30),
      const SizedBox(width: 6),
      Text(
          'Reference Gain/Q: pending hardware capture · frequency positions only',
          style: proSubtitle(size: 9, color: Colors.white30)),
    ]);
  }
}

// ── Pending capture placeholder ───────────────────────────────────────────────

class _PendingCaptureSection extends StatelessWidget {
  final String label;
  const _PendingCaptureSection({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(children: [
        const Icon(Icons.hourglass_empty_outlined,
            size: 12, color: Colors.white30),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$label  ·  Pending hardware capture — byte offsets not yet confirmed.',
            style: proSubtitle(size: 9, color: Colors.white30),
          ),
        ),
      ]),
    );
  }
}

// ── Comparison table ──────────────────────────────────────────────────────────

class _ComparisonTable extends StatelessWidget {
  final List<PeqBandComparisonResult> comparisons;
  const _ComparisonTable({required this.comparisons});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ComparisonHeaderRow(),
          const SizedBox(height: 4),
          for (final c in comparisons) ...[
            _ComparisonRow(result: c),
            const SizedBox(height: 3),
          ],
        ],
      ),
    );
  }
}

class _ComparisonHeaderRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = proSubtitle(size: 9, color: Colors.white38);
    return Row(children: [
      SizedBox(width: 44, child: Text('Band', style: s)),
      SizedBox(width: 62, child: Text('Ref Freq', style: s)),
      SizedBox(width: 50, child: Text('Ref Gain', style: s)),
      SizedBox(width: 40, child: Text('Ref Q', style: s)),
      SizedBox(width: 62, child: Text('Read Freq', style: s)),
      SizedBox(width: 50, child: Text('Read Gain', style: s)),
      SizedBox(width: 40, child: Text('Read Q', style: s)),
      SizedBox(width: 58, child: Text('ΔFreq', style: s)),
      SizedBox(width: 48, child: Text('ΔGain', style: s)),
      SizedBox(width: 36, child: Text('ΔQ', style: s)),
      const SizedBox(width: 30),
    ]);
  }
}

class _ComparisonRow extends StatelessWidget {
  final PeqBandComparisonResult result;
  const _ComparisonRow({required this.result});

  @override
  Widget build(BuildContext context) {
    final unknown = !result.isComparable;
    final isMatch = result.isMatch;
    final matchColor = isMatch ? kProGreen : kProRed;
    final refOpacity =
        result.reference.confidence == DataConfidence.hardwareConfirmed
            ? 1.0
            : 0.65;

    TextStyle numStyle(Color c, {double opacity = 1.0}) => TextStyle(
          fontSize: 11,
          color: c.withValues(alpha: opacity),
          fontFeatures: const [FontFeature.tabularFigures()],
        );
    Color diffColor(num v) => v.abs() == 0 ? Colors.white54 : kProAmber;

    return Row(children: [
      SizedBox(
        width: 44,
        child: Text('Band ${result.bandIndex + 1}',
            style: const TextStyle(fontSize: 11, color: Colors.white70)),
      ),
      // Reference columns
      SizedBox(
          width: 62,
          child: Text('${result.reference.frequencyHz} Hz',
              style: numStyle(Colors.white, opacity: refOpacity))),
      SizedBox(
          width: 50,
          child: Text(
              unknown
                  ? '—'
                  : '${result.reference.gainDb.toStringAsFixed(1)} dB',
              style: numStyle(Colors.white, opacity: refOpacity))),
      SizedBox(
          width: 40,
          child: Text(unknown ? '—' : result.reference.q.toStringAsFixed(2),
              style: numStyle(Colors.white, opacity: refOpacity))),
      // TUNAI readback columns
      SizedBox(
          width: 62,
          child: Text('${result.readback.frequencyHz} Hz',
              style: numStyle(Colors.white, opacity: 0.85))),
      SizedBox(
          width: 50,
          child: Text('${result.readback.gainDb.toStringAsFixed(1)} dB',
              style: numStyle(Colors.white, opacity: 0.85))),
      SizedBox(
          width: 40,
          child: Text(result.readback.q.toStringAsFixed(2),
              style: numStyle(Colors.white, opacity: 0.85))),
      // Diff columns
      SizedBox(
          width: 58,
          child: Text(
            unknown
                ? '—'
                : result.freqDiffHz == 0
                    ? '—'
                    : '${result.freqDiffHz > 0 ? '+' : ''}${result.freqDiffHz} Hz',
            style: numStyle(
                unknown ? Colors.white30 : diffColor(result.freqDiffHz)),
          )),
      SizedBox(
          width: 48,
          child: Text(
            unknown
                ? '—'
                : result.gainDiffDb.abs() <= 0.049
                    ? '—'
                    : '${result.gainDiffDb > 0 ? '+' : ''}${result.gainDiffDb.toStringAsFixed(1)} dB',
            style: numStyle(
                unknown ? Colors.white30 : diffColor(result.gainDiffDb)),
          )),
      SizedBox(
          width: 36,
          child: Text(
            unknown
                ? '—'
                : result.qDiff.abs() <= 0.049
                    ? '—'
                    : '${result.qDiff > 0 ? '+' : ''}${result.qDiff.toStringAsFixed(2)}',
            style: numStyle(unknown ? Colors.white30 : diffColor(result.qDiff)),
          )),
      // Match indicator
      SizedBox(
        width: 30,
        child: unknown
            ? const Icon(Icons.remove, size: 11, color: Colors.white24)
            : Icon(
                isMatch ? Icons.check_circle_outline : Icons.cancel_outlined,
                size: 13,
                color: matchColor.withValues(alpha: 0.8),
              ),
      ),
    ]);
  }
}

// ── Band table ────────────────────────────────────────────────────────────────

class _BandHeaderRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      SizedBox(
          width: 50,
          child:
              Text('Band', style: proSubtitle(size: 9, color: Colors.white38))),
      SizedBox(
          width: 70,
          child:
              Text('Freq', style: proSubtitle(size: 9, color: Colors.white38))),
      SizedBox(
          width: 58,
          child:
              Text('Gain', style: proSubtitle(size: 9, color: Colors.white38))),
      SizedBox(
          width: 44,
          child: Text('Q', style: proSubtitle(size: 9, color: Colors.white38))),
      Expanded(
          child: Text('Confidence',
              style: proSubtitle(size: 9, color: Colors.white38))),
    ]);
  }
}

class _BandRow extends StatelessWidget {
  final PeqBandState band;
  const _BandRow({required this.band});

  @override
  Widget build(BuildContext context) {
    final (statusColor, statusLabel) = switch (band.verificationStatus) {
      PeqBandVerificationStatus.verified => (kProGreen, 'Hardware Confirmed'),
      PeqBandVerificationStatus.mappingCandidate => (
          kProAmber,
          'Candidate Mapping'
        ),
      PeqBandVerificationStatus.channelLayoutCandidate => (
          const Color(0xFF9E9E9E),
          'Unknown'
        ),
    };
    final valueColor = Colors.white.withValues(
        alpha: band.verificationStatus == PeqBandVerificationStatus.verified
            ? 1.0
            : 0.70);

    return Row(children: [
      SizedBox(
          width: 50,
          child: Text('Band ${band.bandIndex + 1}',
              style: TextStyle(fontSize: 11, color: valueColor))),
      SizedBox(
          width: 70,
          child: Text('${band.frequencyHz} Hz',
              style: TextStyle(
                  fontSize: 11,
                  color: valueColor,
                  fontFeatures: const [FontFeature.tabularFigures()]))),
      SizedBox(
          width: 58,
          child: Text('${band.gainDb.toStringAsFixed(1)} dB',
              style: TextStyle(
                  fontSize: 11,
                  color: valueColor,
                  fontFeatures: const [FontFeature.tabularFigures()]))),
      SizedBox(
          width: 44,
          child: Text(band.q.toStringAsFixed(2),
              style: TextStyle(
                  fontSize: 11,
                  color: valueColor,
                  fontFeatures: const [FontFeature.tabularFigures()]))),
      Expanded(
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.08),
              border: Border.all(color: statusColor.withValues(alpha: 0.30)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(statusLabel,
                style: TextStyle(
                    fontSize: 9,
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4)),
          ),
          if (!band.withinVerifiedRanges) ...[
            const SizedBox(width: 4),
            const Icon(Icons.warning_amber_outlined,
                size: 10, color: Colors.orange),
          ],
        ]),
      ),
    ]);
  }
}

class _FailureDisplay extends StatelessWidget {
  final _DspReadResult result;
  const _FailureDisplay({required this.result});

  @override
  Widget build(BuildContext context) {
    final kind = result.failureKind ?? _FailureKind.unknown;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.error_outline, size: 12, color: kProRed),
        const SizedBox(width: 6),
        Text(kind.label,
            style: const TextStyle(
                fontSize: 11, color: kProRed, fontWeight: FontWeight.w600)),
      ]),
      if (result.failureDetail != null) ...[
        const SizedBox(height: 4),
        Text(result.failureDetail!, style: proSubtitle(size: 10)),
      ],
    ]);
  }
}

// ── Baseline / diff buttons ───────────────────────────────────────────────────

class _BaselineButton extends StatelessWidget {
  final bool hasBaseline;
  final VoidCallback onCapture;
  const _BaselineButton({required this.hasBaseline, required this.onCapture});

  @override
  Widget build(BuildContext context) {
    final color = hasBaseline ? kProGreen : Colors.white38;
    return GestureDetector(
      onTap: onCapture,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: hasBaseline
              ? kProGreen.withValues(alpha: 0.08)
              : Colors.transparent,
          border: Border.all(
              color:
                  hasBaseline ? kProGreen.withValues(alpha: 0.40) : kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            hasBaseline ? Icons.bookmark_outlined : Icons.bookmark_add_outlined,
            size: 11,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            hasBaseline ? 'BASELINE SET' : 'CAPTURE BASELINE',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: color),
          ),
        ]),
      ),
    );
  }
}

class _ClearBaselineButton extends StatelessWidget {
  final VoidCallback onClear;
  const _ClearBaselineButton({required this.onClear});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onClear,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text('CLEAR',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: Colors.white30)),
      ),
    );
  }
}

// ── Channel offset scan section ───────────────────────────────────────────────

class _ChannelScanSection extends StatelessWidget {
  final List<_ChannelScanHit> hits;
  final bool wooferFound;

  const _ChannelScanSection({
    required this.hits,
    required this.wooferFound,
  });

  @override
  Widget build(BuildContext context) {
    final wooferHit =
        hits.where((h) => h.isWoofer && h.fullyConfirmed).firstOrNull;
    final wooferPartial =
        hits.where((h) => h.isWoofer && !h.fullyConfirmed).firstOrNull;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.radar_outlined,
            size: 12, color: Colors.white.withValues(alpha: 0.6)),
        const SizedBox(width: 6),
        Text('CHANNEL OFFSET SCAN',
            style: proTitle(size: 11, color: Colors.white70)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: wooferFound
                ? kProGreen.withValues(alpha: 0.15)
                : kProAmber.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: wooferFound
                  ? kProGreen.withValues(alpha: 0.4)
                  : kProAmber.withValues(alpha: 0.4),
            ),
          ),
          child: Text(
            wooferFound ? 'WOOFER SIGNATURE FOUND' : 'WOOFER NOT FOUND',
            style: proSubtitle(
              size: 8,
              color: wooferFound ? kProGreen : kProAmber,
            ),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      if (wooferHit != null) ...[
        _ScanResultRow(
          icon: Icons.check_circle_outline,
          iconColor: kProGreen,
          text: wooferHit.label,
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 18),
          child: Text(
            '→ Update candidateChannelStride or _kDspChBases with offset ${wooferHit.offset}',
            style:
                proSubtitle(size: 9, color: kProGreen.withValues(alpha: 0.8)),
          ),
        ),
      ] else if (wooferPartial != null) ...[
        _ScanResultRow(
          icon: Icons.warning_amber_outlined,
          iconColor: kProAmber,
          text: wooferPartial.label,
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 18),
          child: Text(
            'Band2/Band3 mismatch — offset may be wrong or band stride differs',
            style:
                proSubtitle(size: 9, color: kProAmber.withValues(alpha: 0.8)),
          ),
        ),
      ] else ...[
        _ScanResultRow(
          icon: Icons.help_outline,
          iconColor: Colors.white38,
          text: 'Woofer L Band1 (60Hz/+0.5dB/Q1.0) not found in payload',
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 18),
          child: Text(
            'Use hex diff: CAPTURE BASELINE → change a Woofer band in MiUMAX → READ',
            style: proSubtitle(size: 9, color: Colors.white38),
          ),
        ),
      ],
      // Tweeter R hits (Ch1).
      for (final h in hits.where((h) => !h.isWoofer && h.offset != 19)) ...[
        const SizedBox(height: 4),
        _ScanResultRow(
          icon: Icons.radio_button_unchecked,
          iconColor: kProAmber,
          text: h.label,
        ),
      ],
    ]);
  }
}

class _ScanResultRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;

  const _ScanResultRow({
    required this.icon,
    required this.iconColor,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 11, color: iconColor),
      const SizedBox(width: 5),
      Expanded(
        child: Text(
          text,
          style: proSubtitle(size: 9.5, color: Colors.white70),
        ),
      ),
    ]);
  }
}

// ── Hex diff section ──────────────────────────────────────────────────────────

class _HexDiffSection extends StatelessWidget {
  final List<PayloadDiffEntry>? diff;
  const _HexDiffSection({required this.diff});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.compare_arrows_outlined,
            size: 12, color: kProAmber.withValues(alpha: 0.8)),
        const SizedBox(width: 6),
        Text('PAYLOAD DIFF — BASELINE vs CURRENT',
            style: proTitle(size: 11, color: Colors.white70)),
      ]),
      const SizedBox(height: 6),
      if (diff == null) ...[
        Text(
          'Baseline captured. Change a band on MiUMAX, '
          'then tap READ CURRENT DSP STATE to see which bytes changed.',
          style: proSubtitle(size: 9),
        ),
      ] else if (diff!.isEmpty) ...[
        Row(children: [
          const Icon(Icons.check_circle_outline, size: 11, color: kProGreen),
          const SizedBox(width: 6),
          Text('No changes detected — payload is byte-identical to baseline.',
              style: proSubtitle(size: 9, color: kProGreen)),
        ]),
      ] else ...[
        Text('${diff!.length} byte(s) changed:',
            style: proSubtitle(size: 9, color: kProAmber)),
        const SizedBox(height: 8),
        _DiffTable(diff: diff!),
      ],
    ]);
  }
}

class _DiffTable extends StatelessWidget {
  final List<PayloadDiffEntry> diff;
  const _DiffTable({required this.diff});

  @override
  Widget build(BuildContext context) {
    final s = proSubtitle(size: 9, color: Colors.white38);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            SizedBox(width: 88, child: Text('Offset', style: s)),
            SizedBox(width: 52, child: Text('Before', style: s)),
            SizedBox(width: 52, child: Text('After', style: s)),
            SizedBox(width: 260, child: Text('DSP Mapping', style: s)),
          ]),
          const SizedBox(height: 4),
          for (final entry in diff) ...[
            _DiffRow(entry: entry),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

class _DiffRow extends StatelessWidget {
  final PayloadDiffEntry entry;
  const _DiffRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final annotation = dspOffsetAnnotation(entry.offset);
    final isConfirmed = annotation.contains('[confirmed]');
    final isCandidate = annotation.contains('-cand]');
    final labelColor = isConfirmed
        ? kProGreen
        : isCandidate
            ? kProAmber
            : Colors.white38;

    String hex2(int v) => '0x${v.toRadixString(16).padLeft(2, '0')}';
    String hex3(int v) => '0x${v.toRadixString(16).padLeft(3, '0')}';

    const monoStyle = TextStyle(
      fontSize: 10,
      color: Colors.white54,
      fontFamily: 'monospace',
      fontFeatures: [FontFeature.tabularFigures()],
    );

    return Row(children: [
      SizedBox(
        width: 88,
        child:
            Text('${hex3(entry.offset)} (${entry.offset})', style: monoStyle),
      ),
      SizedBox(
        width: 52,
        child: Text(hex2(entry.before), style: monoStyle),
      ),
      SizedBox(
        width: 52,
        child: Text(hex2(entry.after),
            style: monoStyle.copyWith(
                color: kProAmber, fontWeight: FontWeight.w600)),
      ),
      SizedBox(
        width: 260,
        child:
            Text(annotation, style: TextStyle(fontSize: 10, color: labelColor)),
      ),
    ]);
  }
}
