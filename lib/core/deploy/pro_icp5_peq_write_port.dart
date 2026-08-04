// ── TUNAI PRO — Real Icp5PeqWritePort binding ─────────────────────────────────
// Binds the gated executor's Icp5PeqWritePort to the EXISTING ADAU1701 ICP5
// chain: Adau1701PeqDeploymentGate (preflight) → Adau1701TuningTransport
// (writePeqGain / writePeqFrequency; XO uses writeFilterFrequency)
// → Adau1701Ch0Band0ReadService (readback) → Adau1701DeploymentReport.
//
// This is a binding/adapter. It modifies none of those components, the DSP
// codec, address mapping, BLE/GATT, or the USBi executor — it only composes
// them for a single capture-proven operation.

import '../transport/adau1701_ch0_band0_read_service.dart';
import '../transport/adau1701_deployment_preflight.dart';
import '../transport/adau1701_deployment_report.dart';
import '../transport/adau1701_peq_deployment_gate.dart';
import '../transport/adau1701_tuning_transport.dart';
import '../transport/icp5_transports.dart';
import '../transport/icp5_frame_codec.dart';
import 'pro_hardware_capability.dart';
import 'pro_hardware_write_executor.dart';
import 'pro_hardware_write_plan.dart';

/// Resolves a plan channel id to a 0-based ADAU1701 output channel index.
/// Returns a negative value when the id cannot be resolved.
typedef Icp5ChannelResolver = int Function(String channelId);

/// Thrown when an operation is outside the supported set (ADAU1701 ICP5,
/// Band 1 gain/frequency, capture-proven). Fail-closed: no device I/O occurs.
class UnsupportedIcp5WriteOperation implements Exception {
  final HardwareWriteOp op;
  final String reason;
  const UnsupportedIcp5WriteOperation(this.op, this.reason);

  @override
  String toString() => 'UnsupportedIcp5WriteOperation('
      '${op.parameterKind.name}, band ${op.bandIndex}): $reason';
}

class Adau1701Icp5PeqWritePort implements Icp5PeqWritePort {
  final Adau1701TuningTransport transport;
  final Adau1701PeqDeploymentGate gate;
  final Adau1701Ch0Band0ReadService readService;
  final Icp5ChannelResolver channelResolver;
  final DateTime Function() _clock;

  /// Readback tolerances used to confirm the written value took effect.
  final double gainToleranceDb;
  final int frequencyToleranceHz;

  /// Maximum readback attempts for frequency verification after a successful
  /// write ACK. The device may need a short settling time before the snapshot
  /// reflects the new value. Attempts are spaced by [readbackRetryDelay].
  final int maxReadbackAttempts;
  final Duration readbackRetryDelay;

  Adau1701Icp5PeqWritePort({
    required this.transport,
    required this.gate,
    required this.readService,
    required this.channelResolver,
    DateTime Function()? clock,
    this.gainToleranceDb = 0.15,
    this.frequencyToleranceHz = 2,
    this.maxReadbackAttempts = 3,
    this.readbackRetryDelay = const Duration(milliseconds: 80),
  }) : _clock = clock ?? DateTime.now;

  @override
  Future<Adau1701DeploymentReport> preflightAndWrite(HardwareWriteOp op) async {
    // 1. Validate — everything outside the supported set fails closed (throws)
    //    before any device I/O.
    _validateSupported(op);
    final channel = channelResolver(op.channelId);
    if (channel < 0) {
      throw UnsupportedIcp5WriteOperation(
          op, 'Channel id "${op.channelId}" could not be resolved.');
    }

    // channelMute path: param 0x12, polarity confirmed (State 0=MUTED, State 1=UNMUTED).
    // ACK-only — no readback service for mute.
    if (op.parameterKind == HardwareParamKind.channelMute) {
      final preflight =
          await gate.runPreflight(Adau1701PeqWriteFields(gain: true));
      final attemptedAt = _clock();
      if (!preflight.passed) {
        return _report(preflight, attemptedAt, allowed: false, result: null);
      }
      final muted = op.targetValue != 0; // targetValue=1 from export block muted:true
      final ack = await transport.writeMasterMute(muted);
      final result = Icp5PhaseCResult(
        success: ack.success,
        wasActualWrite: ack.success,
        writeMayHaveReachedDevice: ack.success,
        message: ack.success
            ? 'Mute ACK — State ${muted ? 0 : 1} sent (${muted ? "MUTED" : "UNMUTED"}).'
            : 'Mute write NACK: ${ack.message}',
      );
      return _report(preflight, attemptedAt, allowed: true, result: result,
          isAckOnly: ack.success);
    }

    // crossoverHighPass / crossoverLowPass path: param 0x15, ACK-only.
    // XO has no readback via the PEQ read service — comparing the PEQ CH0/Band0
    // readback to an XO target always mismatches. Write is accepted on ACK only.
    if (op.parameterKind == HardwareParamKind.crossoverHighPass ||
        op.parameterKind == HardwareParamKind.crossoverLowPass) {
      final preflight =
          await gate.runPreflight(Adau1701PeqWriteFields(gain: true));
      final attemptedAt = _clock();
      if (!preflight.passed) {
        return _report(preflight, attemptedAt, allowed: false, result: null);
      }
      final ack = await transport.writeFilterFrequency(
          channel, op.targetValue.round(),
          band: 0,
          isHighPass: op.parameterKind == HardwareParamKind.crossoverHighPass);
      final result = Icp5PhaseCResult(
        success: ack.success,
        wasActualWrite: ack.success,
        writeMayHaveReachedDevice: ack.success,
        message: ack.success
            ? 'ACK received — crossover readback not yet available.'
            : 'Crossover write NACK: ${ack.message}',
      );
      return _report(preflight, attemptedAt, allowed: true, result: result,
          isAckOnly: ack.success);
    }

    // channelGain path: preflight + write + ACK-only (no readback service yet).
    if (op.parameterKind == HardwareParamKind.channelGain) {
      final preflight =
          await gate.runPreflight(Adau1701PeqWriteFields(gain: true));
      final attemptedAt = _clock();
      if (!preflight.passed) {
        return _report(preflight, attemptedAt, allowed: false, result: null);
      }
      final ack =
          await transport.writeOutputGain(channel, op.targetValue.toDouble());
      final result = Icp5PhaseCResult(
        success: ack.success,
        wasActualWrite: ack.success,
        writeMayHaveReachedDevice: ack.success,
        message: ack.success
            ? 'Channel gain write ACKed (no readback).'
            : 'Channel gain write NACK: ${ack.message}',
      );
      return _report(preflight, attemptedAt, allowed: true, result: result,
          isAckOnly: ack.success);
    }

    // peqQ path (any band): Consumer-production-proven param 0x18 property 0x00.
    // No PRO readback for Q → ACK-only.
    if (op.parameterKind == HardwareParamKind.peqQ) {
      final attemptedAt = _clock();
      if (!_ackOnlyTransportReady) {
        return _report(null, attemptedAt, allowed: false, result: null);
      }
      final ack = await transport.writePeqQ(channel, op.targetValue.toDouble(),
          band: op.bandIndex!);
      final result = Icp5PhaseCResult(
        success: ack.success,
        wasActualWrite: ack.success,
        writeMayHaveReachedDevice: ack.success,
        message: ack.success
            ? 'ACK received — PEQ Q readback not yet available.'
            : 'PEQ Q write NACK: ${ack.message}',
      );
      return _report(null, attemptedAt, allowed: true, result: result,
          isAckOnly: ack.success);
    }

    final isGain = op.parameterKind == HardwareParamKind.peqGain;
    final band = op.bandIndex!;

    // PEQ gain/frequency bands 1–9: Consumer-production-proven frame encoding.
    // No PRO readback for non-band-0 → ACK-only.
    if (band > 0) {
      final attemptedAt = _clock();
      if (!_ackOnlyTransportReady) {
        return _report(null, attemptedAt, allowed: false, result: null);
      }
      final Adau1701WriteAck ack = isGain
          ? await transport.writePeqGain(channel, op.targetValue.toDouble(),
              band: band)
          : await transport.writePeqFrequency(channel, op.targetValue.round(),
              band: band);
      final result = Icp5PhaseCResult(
        success: ack.success,
        wasActualWrite: ack.success,
        writeMayHaveReachedDevice: ack.success,
        message: ack.success
            ? 'ACK received — PEQ band $band readback not yet available.'
            : 'PEQ ${isGain ? 'gain' : 'frequency'} band $band write NACK: ${ack.message}',
      );
      return _report(null, attemptedAt, allowed: true, result: result,
          isAckOnly: ack.success);
    }

    // PEQ gain/frequency band 0 — channel guard:
    // The readback service decodes Ch0/Band0 offsets (19–24) from the 513-byte
    // 0x2202 snapshot exclusively. Writing to channel 1–3 at band 0 then
    // comparing ch0 readback produces a guaranteed mismatch (different DSP slot).
    // Channels 1–3 / band 0 → ACK-only, same as bands 1–9.
    if (channel != 0) {
      final attemptedAt = _clock();
      if (!_ackOnlyTransportReady) {
        return _report(null, attemptedAt, allowed: false, result: null);
      }
      final Adau1701WriteAck ack = isGain
          ? await transport.writePeqGain(channel, op.targetValue.toDouble(),
              band: 0)
          : await transport.writePeqFrequency(channel, op.targetValue.round(),
              band: 0);
      final result = Icp5PhaseCResult(
        success: ack.success,
        wasActualWrite: ack.success,
        writeMayHaveReachedDevice: ack.success,
        message: ack.success
            ? 'ACK received — PEQ ch$channel/band 0 readback not available (ch0 only).'
            : 'PEQ ${isGain ? 'gain' : 'frequency'} ch$channel/band 0 write NACK: ${ack.message}',
      );
      return _report(null, attemptedAt, allowed: true, result: result,
          isAckOnly: ack.success);
    }

    // Channel 0 + Band 0: full preflight + write + readback-verified path.

    // 2. Preflight for exactly the field being written (band 0 coverage).
    final preflight = await gate
        .runPreflight(Adau1701PeqWriteFields(gain: isGain, frequency: !isGain));
    final attemptedAt = _clock();

    // 3. Preflight must pass before any write.
    if (!preflight.passed) {
      return _report(preflight, attemptedAt, allowed: false, result: null);
    }

    // Write the single field via the transport.
    // peqGain: param 0x18 property 0x01.  peqFrequency: param 0x18 property 0x02.
    final Adau1701WriteAck ack = isGain
        ? await transport.writePeqGain(channel, op.targetValue.toDouble(),
            band: 0)
        : await transport.writePeqFrequency(channel, op.targetValue.round(),
            band: 0);

    // 4. Read back and verify the written value took effect.
    final bool verified;
    final String verifyMsg;
    if (isGain) {
      final read = await readService.readOriginalState();
      verified =
          ack.success && read.succeeded && _matches(op, read.originalState!);
      verifyMsg = _composeMessage(ack, read, verified);
    } else {
      final r = await _verifyFreq(ack, op.targetValue.round());
      verified = r.verified;
      verifyMsg = r.message;
    }

    // 5. Compose the deployment report. Store preflight.originalState as the
    //    pre-write baseline for PEQ band 0 restore.
    final result = Icp5PhaseCResult(
      success: verified,
      wasActualWrite: ack.success,
      writeMayHaveReachedDevice: ack.success,
      message: verifyMsg,
    );
    return _report(preflight, attemptedAt, allowed: true, result: result,
        capturedOriginalState: preflight.originalState);
  }

  void _validateSupported(HardwareWriteOp op) {
    if (op.verification != HardwareParamVerification.captureProven ||
        !op.writable) {
      throw UnsupportedIcp5WriteOperation(
          op, 'Operation is not capture-proven.');
    }
    // Non-banded kinds: channelGain, channelMute, crossoverHighPass, crossoverLowPass.
    if (op.parameterKind == HardwareParamKind.channelGain ||
        op.parameterKind == HardwareParamKind.channelMute ||
        op.parameterKind == HardwareParamKind.crossoverHighPass ||
        op.parameterKind == HardwareParamKind.crossoverLowPass) return;
    // PEQ kinds: gain/frequency/Q for bands 0–9 (Consumer-production-proven).
    if (op.bandIndex == null || op.bandIndex! < 0 || op.bandIndex! > 9) {
      throw UnsupportedIcp5WriteOperation(
          op, 'PEQ bandIndex must be 0–9 (got ${op.bandIndex}).');
    }
    if (op.parameterKind != HardwareParamKind.peqGain &&
        op.parameterKind != HardwareParamKind.peqFrequency &&
        op.parameterKind != HardwareParamKind.peqQ) {
      throw UnsupportedIcp5WriteOperation(op,
          'Only PEQ gain/frequency/Q (bands 0–9), channelGain, and crossover frequency are supported.');
    }
  }

  bool _matches(HardwareWriteOp op, Adau1701Ch0Band0OriginalState state) {
    if (op.parameterKind == HardwareParamKind.peqGain) {
      return (state.gainDb - op.targetValue).abs() <= gainToleranceDb;
    }
    return (state.frequencyHz - op.targetValue.round()).abs() <=
        frequencyToleranceHz;
  }

  String _composeMessage(
      Adau1701WriteAck ack, Adau1701Ch0Band0ReadResult read, bool verified) {
    if (!ack.success) return 'Write NACK: ${ack.message}';
    if (!read.succeeded) return 'Write ACKed but readback failed: ${read.message}';
    if (!verified) return 'Write ACKed but readback value did not match target.';
    return 'Write ACKed and readback confirmed.';
  }

  /// Bounded readback verification for frequency writes.
  ///
  /// After a successful write ACK, reads back up to [maxReadbackAttempts] times
  /// with [readbackRetryDelay] between attempts. Exits early on first match.
  /// A NACK skips all reads and returns failure immediately.
  /// A read error stops retrying and returns failure.
  Future<({bool verified, String message})> _verifyFreq(
    Adau1701WriteAck ack,
    int targetHz,
  ) async {
    if (!ack.success) {
      return (verified: false, message: 'Write NACK: ${ack.message}');
    }
    Adau1701Ch0Band0ReadResult? last;
    for (var i = 0; i < maxReadbackAttempts; i++) {
      if (i > 0) await Future.delayed(readbackRetryDelay);
      last = await readService.readOriginalState();
      if (!last.succeeded) {
        return (
          verified: false,
          message: 'Write ACKed but readback failed: ${last.message}',
        );
      }
      final readHz = last.originalState!.frequencyHz;
      if ((readHz - targetHz).abs() <= frequencyToleranceHz) {
        return (
          verified: true,
          message: 'Write ACKed and readback confirmed'
              '${i > 0 ? ' (attempt ${i + 1})' : ''}.',
        );
      }
    }
    final readHz = last!.originalState!.frequencyHz;
    return (
      verified: false,
      message: 'Write ACKed but readback did not match after '
          '$maxReadbackAttempts attempt(s): '
          'target $targetHz Hz, last read $readHz Hz.',
    );
  }

  bool get _ackOnlyTransportReady =>
      transport.isConnected &&
      transport.handshakeComplete &&
      transport.detectedProfile == Icp5FrameCodec.expectedProfile;

  Adau1701DeploymentReport _report(
    Adau1701PreflightResult? preflight,
    DateTime attemptedAt, {
    required bool allowed,
    required Icp5PhaseCResult? result,
    bool isAckOnly = false,
    Adau1701Ch0Band0OriginalState? capturedOriginalState,
  }) {
    return Adau1701DeploymentReport(
      attemptedAt: attemptedAt,
      dspIdentity: preflight?.confirmedDeviceId ?? transport.detectedProfile,
      transportIdentity: transport.detectedProfile,
      snapshotCapturedAt: preflight?.snapshotCapturedAt,
      originalStateAvailable: preflight?.originalState != null,
      coverageResult: preflight?.coverage?.isCovered,
      preflightStatus: preflight?.status ??
          (allowed
              ? Adau1701PreflightStatus.passed
              : Adau1701PreflightStatus.transportNotReady),
      preflightFailureReason: allowed
          ? null
          : (preflight?.message ??
              'ADAU1701 identity handshake is required before ACK-only write.'),
      deploymentAllowed: allowed,
      deploymentResult: result,
      isAckOnly: isAckOnly,
      capturedOriginalState: capturedOriginalState,
    );
  }
}
