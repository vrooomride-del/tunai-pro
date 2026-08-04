// ── TUNAI PRO — Hardware Write Executor adapter (orchestration only) ──────────
// Consumes an APPROVED HardwareWriteApproval and drives the EXISTING ADAU1701
// ICP5 safety chain per operation. It owns no device logic: the actual
// preflight → executor → deployment-report chain lives behind [Icp5PeqWritePort],
// which a real binding implements with the existing gate + executor unchanged.
//
// This adapter modifies no transport, gate, executor, codec, or address map.
// It only validates the approval, filters to supported operations, delegates to
// the port, and aggregates the existing per-attempt reports.

import 'dart:async';

import '../transport/adau1701_deployment_report.dart';
import 'pro_hardware_capability.dart';
import 'pro_hardware_write_approval.dart';
import 'pro_hardware_write_plan.dart';

/// Port over the existing ADAU1701 ICP5 write chain
/// (`Adau1701PeqDeploymentGate.runPreflight` → existing executor →
/// `Adau1701DeploymentReport`). Defining/implementing this abstraction changes
/// none of those components.
abstract interface class Icp5PeqWritePort {
  /// Runs the full existing safety chain for a single supported operation and
  /// returns the resulting deployment report.
  Future<Adau1701DeploymentReport> preflightAndWrite(HardwareWriteOp op);
}

/// Per-operation outcome after (attempted) execution.
enum HardwareWriteOpStatus {
  /// The write reached the device and readback confirmed the value.
  written,

  /// The existing preflight refused the write (chain ran, no write).
  blockedByPreflight,

  /// Preflight passed but the write did not succeed.
  failed,

  /// No executor exists for this operation — failed closed, chain not invoked.
  unsupported,

  /// Write ACKed by the device; no readback available for this operation.
  /// Consumer-production-proven path; considered successful (not a failure).
  ackOnly,

  /// port.preflightAndWrite did not complete within the per-operation timeout.
  timedOut;

  String get label => switch (this) {
        HardwareWriteOpStatus.written => 'Written',
        HardwareWriteOpStatus.ackOnly => 'ACK only (no readback)',
        HardwareWriteOpStatus.blockedByPreflight => 'Blocked by preflight',
        HardwareWriteOpStatus.failed => 'Failed',
        HardwareWriteOpStatus.unsupported => 'Unsupported (fail-closed)',
        HardwareWriteOpStatus.timedOut => 'Timed out',
      };
}

class HardwareWriteOpOutcome {
  final HardwareWriteOp op;
  final HardwareWriteOpStatus status;

  /// The existing deployment report, when the safety chain was invoked.
  final Adau1701DeploymentReport? report;
  final String message;

  const HardwareWriteOpOutcome({
    required this.op,
    required this.status,
    required this.report,
    required this.message,
  });

  bool get succeeded =>
      status == HardwareWriteOpStatus.written ||
      status == HardwareWriteOpStatus.ackOnly;

  bool get isFailure =>
      status == HardwareWriteOpStatus.failed ||
      status == HardwareWriteOpStatus.timedOut ||
      status == HardwareWriteOpStatus.blockedByPreflight;

  bool get isTerminalFailure =>
      status == HardwareWriteOpStatus.timedOut ||
      status == HardwareWriteOpStatus.failed;

  Map<String, dynamic> toJson() => {
        'channelId': op.channelId,
        'parameterKind': op.parameterKind.toJson(),
        if (op.bandIndex != null) 'bandIndex': op.bandIndex,
        'status': status.name,
        if (report != null) ...{
          'preflightStatus': report!.preflightStatus.name,
          'deploymentAllowed': report!.deploymentAllowed,
          'deploymentSucceeded': report!.deploymentSucceeded,
        },
        'message': message,
      };
}

class HardwareWriteExecutionResult {
  final String planId;

  /// False when the whole approval was refused up-front (no port calls made).
  final bool executed;
  final String? rejectionReason;
  final List<HardwareWriteOpOutcome> outcomes;

  const HardwareWriteExecutionResult({
    required this.planId,
    required this.executed,
    required this.rejectionReason,
    required this.outcomes,
  });

  int get writtenCount =>
      outcomes.where((o) => o.status == HardwareWriteOpStatus.written).length;
  int get ackOnlyCount =>
      outcomes.where((o) => o.status == HardwareWriteOpStatus.ackOnly).length;
  int get blockedCount => outcomes
      .where((o) => o.status == HardwareWriteOpStatus.blockedByPreflight)
      .length;
  List<HardwareWriteOpOutcome> get failures =>
      outcomes.where((o) => o.isFailure).toList(growable: false);
  int get failedCount => failures.length;
  int get unsupportedCount => outcomes
      .where((o) => o.status == HardwareWriteOpStatus.unsupported)
      .length;

  /// True when every op was written with readback verification.
  bool get allWritten =>
      executed && outcomes.isNotEmpty && outcomes.every((o) => o.succeeded);

  /// True when every op succeeded (written OR ack-only). Use for UI PASS_ACK.
  bool get allPassed => executed && outcomes.isNotEmpty && failedCount == 0;

  Map<String, dynamic> toJson() => {
        'planId': planId,
        'executed': executed,
        if (rejectionReason != null) 'rejectionReason': rejectionReason,
        'writtenCount': writtenCount,
        'ackOnlyCount': ackOnlyCount,
        'blockedCount': blockedCount,
        'failedCount': failedCount,
        'unsupportedCount': unsupportedCount,
        'outcomes': outcomes.map((o) => o.toJson()).toList(),
      };
}

/// Progress update emitted after each operation attempt during [execute].
class HardwareWriteProgress {
  /// Number of operations fully processed (succeeded, failed, or skipped).
  final int completed;

  /// Total number of approved operations to process.
  final int total;

  /// The operation currently being attempted.
  final HardwareWriteOp current;

  const HardwareWriteProgress({
    required this.completed,
    required this.total,
    required this.current,
  });

  String get label => '${current.channelId} · ${current.parameterKind.name}'
      '${current.bandIndex != null ? ' band ${current.bandIndex}' : ''}';
}

/// Gated executor adapter. Only ever acts on an approved approval, and only
/// invokes the port for supported operations.
class HardwareWriteExecutor {
  final Icp5PeqWritePort port;

  /// Per-operation timeout applied to every [port.preflightAndWrite] call.
  /// Defaults to 10 s — enough for a BLE round-trip + readback retries.
  final Duration opTimeout;

  /// BLE deploy-stability fix: a small settle delay inserted after a
  /// successful operation, before the next write is issued. Audit found no
  /// pacing at all between back-to-back operations across a long (e.g.
  /// 128-op) sequential deploy — a plausible contributor to occasional
  /// late-ACK/quarantine misses (see ADAU1701 Deploy Stability
  /// Investigation). Does not affect operation order, retry, timeout, or
  /// frame content — it only delays when the next write is sent.
  static const Duration _interOpSettleDelay = Duration(milliseconds: 50);

  const HardwareWriteExecutor(
    this.port, {
    this.opTimeout = const Duration(seconds: 10),
  });

  /// Supported set: ADAU1701 ICP5.
  /// - channelGain, crossoverHighPass, crossoverLowPass (non-banded)
  /// - peqGain, peqFrequency, peqQ for bands 0–9 (Consumer-production-proven)
  ///   Band 0 gain/freq: readback-verified. All others: ACK-only.
  /// Everything else fails closed.
  static bool isSupported(HardwareWriteApproval approval, HardwareWriteOp op) {
    if (approval.deviceProfile.deviceId !=
        HardwareDeviceProfiles.adau1701Icp5.deviceId) return false;
    if (op.bandIndex == null) {
      return op.parameterKind == HardwareParamKind.channelGain ||
          op.parameterKind == HardwareParamKind.channelMute ||
          op.parameterKind == HardwareParamKind.crossoverHighPass ||
          op.parameterKind == HardwareParamKind.crossoverLowPass;
    }
    final band = op.bandIndex!;
    return band >= 0 &&
        band <= 9 &&
        (op.parameterKind == HardwareParamKind.peqFrequency ||
            op.parameterKind == HardwareParamKind.peqGain ||
            op.parameterKind == HardwareParamKind.peqQ);
  }

  /// Executes all approved operations sequentially.
  ///
  /// [onProgress] is called before each operation with the current progress.
  /// Each port call is wrapped in [opTimeout]; a hung call produces a
  /// [HardwareWriteOpStatus.timedOut] outcome and execution stops early —
  /// already-written operations are not re-attempted.
  Future<HardwareWriteExecutionResult> execute(
    HardwareWriteApproval approval, {
    void Function(HardwareWriteProgress)? onProgress,
  }) async {
    // Rule 1 — reject empty / rejected / non-approved up front. No port calls.
    if (approval.status != HardwareApprovalStatus.approved) {
      return HardwareWriteExecutionResult(
        planId: approval.planId,
        executed: false,
        rejectionReason:
            'Approval is not approved (${approval.status.label}); refusing to execute.',
        outcomes: const [],
      );
    }
    if (approval.approvedOperations.isEmpty) {
      return HardwareWriteExecutionResult(
        planId: approval.planId,
        executed: false,
        rejectionReason: 'Approval contains no approved operations.',
        outcomes: const [],
      );
    }

    final ops = approval.approvedOperations;
    final total = ops.length;
    final outcomes = <HardwareWriteOpOutcome>[];

    for (var i = 0; i < ops.length; i++) {
      final op = ops[i];
      onProgress?.call(HardwareWriteProgress(
        completed: outcomes.length,
        total: total,
        current: op,
      ));

      // Defence in depth: an approval must only carry writable ops.
      if (!op.writable) {
        outcomes.add(HardwareWriteOpOutcome(
          op: op,
          status: HardwareWriteOpStatus.unsupported,
          report: null,
          message: 'Operation is not capture-proven; fail closed.',
        ));
        continue;
      }
      // Device envelope guard: never send an out-of-range ADAU1701 PEQ gain
      // to the existing write port, even if an invalid approval was assembled.
      if (approval.deviceProfile.deviceId ==
              HardwareDeviceProfiles.adau1701Icp5.deviceId &&
          op.parameterKind == HardwareParamKind.peqGain &&
          (op.targetValue < -6.0 || op.targetValue > 3.0)) {
        outcomes.add(HardwareWriteOpOutcome(
          op: op,
          status: HardwareWriteOpStatus.unsupported,
          report: null,
          message: 'ADAU1701 PEQ gain outside -6.0…+3.0 dB envelope.',
        ));
        continue;
      }
      // Rule 5 — only ADAU1701 Band 1 gain/frequency has an executor.
      if (!isSupported(approval, op)) {
        outcomes.add(HardwareWriteOpOutcome(
          op: op,
          status: HardwareWriteOpStatus.unsupported,
          report: null,
          message:
              'No executor for ${op.parameterKind.name} (band ${op.bandIndex}) '
              'on ${approval.deviceProfile.deviceName}; fail closed.',
        ));
        continue;
      }

      // Rule 3 — delegate to the existing safety chain via the port.
      // Apply per-operation timeout so a hung future does not block forever.
      try {
        final report = await port.preflightAndWrite(op).timeout(opTimeout);
        outcomes.add(_mapReport(op, report));
        // Settle delay after a successful ACK, before the next write — see
        // _interOpSettleDelay doc comment. Skipped after the last operation
        // (nothing left to protect). Operation order is unchanged: this only
        // delays *when* the next iteration's write is issued.
        if (outcomes.last.succeeded && i < ops.length - 1) {
          await Future<void>.delayed(_interOpSettleDelay);
        }
      } on TimeoutException {
        final successCount = outcomes.where((o) => o.succeeded).length;
        outcomes.add(HardwareWriteOpOutcome(
          op: op,
          status: HardwareWriteOpStatus.timedOut,
          report: null,
          message: 'Operation timed out after ${opTimeout.inSeconds}s '
              '(${op.channelId}·${op.parameterKind.name}'
              '${op.bandIndex != null ? '·band${op.bandIndex}' : ''}). '
              '$successCount/$total completed.',
        ));
        break; // stop; do not re-attempt already-written ops
      } catch (e) {
        final successCount = outcomes.where((o) => o.succeeded).length;
        outcomes.add(HardwareWriteOpOutcome(
          op: op,
          status: HardwareWriteOpStatus.failed,
          report: null,
          message: 'Unexpected error: $e '
              '(${op.channelId}·${op.parameterKind.name}'
              '${op.bandIndex != null ? '·band${op.bandIndex}' : ''}). '
              '$successCount/$total completed.',
        ));
        break;
      }
    }

    return HardwareWriteExecutionResult(
      planId: approval.planId,
      executed: true,
      rejectionReason: null,
      outcomes: outcomes,
    );
  }

  HardwareWriteOpOutcome _mapReport(
      HardwareWriteOp op, Adau1701DeploymentReport report) {
    if (!report.deploymentAllowed) {
      return HardwareWriteOpOutcome(
        op: op,
        status: HardwareWriteOpStatus.blockedByPreflight,
        report: report,
        message: report.preflightFailureReason ??
            'Preflight did not pass (${report.preflightStatus.name}).',
      );
    }
    if (report.isAckOnly && report.deploymentSucceeded) {
      return HardwareWriteOpOutcome(
        op: op,
        status: HardwareWriteOpStatus.ackOnly,
        report: report,
        message: report.deploymentResult?.message ??
            'ACK received — readback not available.',
      );
    }
    if (report.deploymentSucceeded) {
      return HardwareWriteOpOutcome(
        op: op,
        status: HardwareWriteOpStatus.written,
        report: report,
        message: 'Write reported success.',
      );
    }
    return HardwareWriteOpOutcome(
      op: op,
      status: HardwareWriteOpStatus.failed,
      report: report,
      message: report.deploymentResult?.message ?? 'Write did not succeed.',
    );
  }
}
