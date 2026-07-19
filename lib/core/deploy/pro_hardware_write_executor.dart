// ── TUNAI PRO — Hardware Write Executor adapter (orchestration only) ──────────
// Consumes an APPROVED HardwareWriteApproval and drives the EXISTING ADAU1701
// ICP5 safety chain per operation. It owns no device logic: the actual
// preflight → executor → deployment-report chain lives behind [Icp5PeqWritePort],
// which a real binding implements with the existing gate + executor unchanged.
//
// This adapter modifies no transport, gate, executor, codec, or address map.
// It only validates the approval, filters to supported operations, delegates to
// the port, and aggregates the existing per-attempt reports.

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
  /// The write reached the device and the chain reported success.
  written,

  /// The existing preflight refused the write (chain ran, no write).
  blockedByPreflight,

  /// Preflight passed but the write did not succeed.
  failed,

  /// No executor exists for this operation — failed closed, chain not invoked.
  unsupported;

  String get label => switch (this) {
        HardwareWriteOpStatus.written => 'Written',
        HardwareWriteOpStatus.blockedByPreflight => 'Blocked by preflight',
        HardwareWriteOpStatus.failed => 'Failed',
        HardwareWriteOpStatus.unsupported => 'Unsupported (fail-closed)',
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

  bool get succeeded => status == HardwareWriteOpStatus.written;

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
  int get blockedCount => outcomes
      .where((o) => o.status == HardwareWriteOpStatus.blockedByPreflight)
      .length;
  int get failedCount =>
      outcomes.where((o) => o.status == HardwareWriteOpStatus.failed).length;
  int get unsupportedCount => outcomes
      .where((o) => o.status == HardwareWriteOpStatus.unsupported)
      .length;

  bool get allWritten =>
      executed && outcomes.isNotEmpty && outcomes.every((o) => o.succeeded);

  Map<String, dynamic> toJson() => {
        'planId': planId,
        'executed': executed,
        if (rejectionReason != null) 'rejectionReason': rejectionReason,
        'writtenCount': writtenCount,
        'blockedCount': blockedCount,
        'failedCount': failedCount,
        'unsupportedCount': unsupportedCount,
        'outcomes': outcomes.map((o) => o.toJson()).toList(),
      };
}

/// Gated executor adapter. Only ever acts on an approved approval, and only
/// invokes the port for supported operations.
class HardwareWriteExecutor {
  final Icp5PeqWritePort port;
  const HardwareWriteExecutor(this.port);

  /// The initial supported set: ADAU1701 ICP5, PEQ Band 1 (index 0) gain and
  /// frequency. Everything else fails closed (no executor exists).
  static bool isSupported(HardwareWriteApproval approval, HardwareWriteOp op) =>
      approval.deviceProfile.deviceId ==
          HardwareDeviceProfiles.adau1701Icp5.deviceId &&
      op.bandIndex == 0 &&
      (op.parameterKind == HardwareParamKind.peqFrequency ||
          op.parameterKind == HardwareParamKind.peqGain);

  Future<HardwareWriteExecutionResult> execute(
      HardwareWriteApproval approval) async {
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

    final outcomes = <HardwareWriteOpOutcome>[];
    for (final op in approval.approvedOperations) {
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
      final report = await port.preflightAndWrite(op);
      outcomes.add(_mapReport(op, report));
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
