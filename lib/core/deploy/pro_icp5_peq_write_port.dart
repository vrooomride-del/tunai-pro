// ── TUNAI PRO — Real Icp5PeqWritePort binding ─────────────────────────────────
// Binds the gated executor's Icp5PeqWritePort to the EXISTING ADAU1701 ICP5
// chain: Adau1701PeqDeploymentGate (preflight) → Adau1701TuningTransport
// (writePeqGain / writeFilterFrequency) → Adau1701Ch0Band0ReadService (readback)
// → Adau1701DeploymentReport.
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

  Adau1701Icp5PeqWritePort({
    required this.transport,
    required this.gate,
    required this.readService,
    required this.channelResolver,
    DateTime Function()? clock,
    this.gainToleranceDb = 0.15,
    this.frequencyToleranceHz = 2,
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

    final isGain = op.parameterKind == HardwareParamKind.peqGain;

    // 2. Preflight through the existing gate for exactly the field being written.
    final preflight = await gate
        .runPreflight(Adau1701PeqWriteFields(gain: isGain, frequency: !isGain));
    final attemptedAt = _clock();

    // 3. Preflight must pass before any write.
    if (!preflight.passed) {
      return _report(preflight, attemptedAt, allowed: false, result: null);
    }

    // Write the single field via the existing transport methods (Band 1).
    final Adau1701WriteAck ack = isGain
        ? await transport.writePeqGain(channel, op.targetValue.toDouble(),
            band: 0)
        : await transport.writeFilterFrequency(channel, op.targetValue.round(),
            band: 0);

    // 4. Read back and verify the written value took effect.
    final read = await readService.readOriginalState();
    final verified =
        ack.success && read.succeeded && _matches(op, read.originalState!);

    // 5. Compose the deployment report from preflight + write ACK + readback.
    final result = Icp5PhaseCResult(
      success: verified,
      wasActualWrite: ack.success,
      writeMayHaveReachedDevice: ack.success,
      message: _composeMessage(ack, read, verified),
    );
    return _report(preflight, attemptedAt, allowed: true, result: result);
  }

  void _validateSupported(HardwareWriteOp op) {
    if (op.verification != HardwareParamVerification.captureProven ||
        !op.writable) {
      throw UnsupportedIcp5WriteOperation(
          op, 'Operation is not capture-proven.');
    }
    if (op.bandIndex != 0) {
      throw UnsupportedIcp5WriteOperation(
          op, 'Only PEQ Band 1 (index 0) is supported.');
    }
    if (op.parameterKind != HardwareParamKind.peqGain &&
        op.parameterKind != HardwareParamKind.peqFrequency) {
      throw UnsupportedIcp5WriteOperation(
          op, 'Only PEQ gain and frequency are supported.');
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

  Adau1701DeploymentReport _report(
    Adau1701PreflightResult preflight,
    DateTime attemptedAt, {
    required bool allowed,
    required Icp5PhaseCResult? result,
  }) {
    return Adau1701DeploymentReport(
      attemptedAt: attemptedAt,
      dspIdentity: preflight.confirmedDeviceId,
      transportIdentity: transport.detectedProfile,
      snapshotCapturedAt: preflight.snapshotCapturedAt,
      originalStateAvailable: preflight.originalState != null,
      coverageResult: preflight.coverage?.isCovered,
      preflightStatus: preflight.status,
      preflightFailureReason: allowed ? null : preflight.message,
      deploymentAllowed: allowed,
      deploymentResult: result,
    );
  }
}
