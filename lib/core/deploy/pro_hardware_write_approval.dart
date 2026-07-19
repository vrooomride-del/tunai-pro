// ── TUNAI PRO — Hardware Write Approval (gate model only) ─────────────────────
// An explicit, auditable approval record that sits between a HardwareWritePlan
// and any FUTURE execution. It can only ever approve capture-proven
// (writable) operations; blocked/unverified/unavailable ops are refused.
//
// This layer records intent and authorization. It performs NO writes and makes
// NO transport, preflight, executor, or DSP-codec calls.

import 'pro_hardware_capability.dart';
import 'pro_hardware_write_plan.dart';

/// Outcome of an approval attempt.
enum HardwareApprovalStatus {
  /// At least one writable operation was approved.
  approved,

  /// The request included operations that are not writable — nothing approved.
  rejected,

  /// No writable operations were available to approve (fail-closed default).
  empty;

  String get label => switch (this) {
        HardwareApprovalStatus.approved => 'Approved',
        HardwareApprovalStatus.rejected => 'Rejected',
        HardwareApprovalStatus.empty => 'Nothing to approve',
      };

  String toJson() => name;

  static HardwareApprovalStatus fromJson(String s) =>
      HardwareApprovalStatus.values.firstWhere(
        (e) => e.name == s,
        orElse: () => HardwareApprovalStatus.empty,
      );
}

/// An approval decision over a specific write plan. Only capture-proven
/// operations can appear in [approvedOperations].
class HardwareWriteApproval {
  final String planId;
  final HardwareDeviceProfile deviceProfile;
  final DateTime approvedAt;
  final List<HardwareWriteOp> approvedOperations;
  final HardwareApprovalStatus status;

  /// Who authorized the approval (label only — no identity/auth is implied).
  final String approver;

  /// Populated when [status] is not [HardwareApprovalStatus.approved].
  final String? rejectionReason;

  const HardwareWriteApproval._({
    required this.planId,
    required this.deviceProfile,
    required this.approvedAt,
    required this.approvedOperations,
    required this.status,
    required this.approver,
    this.rejectionReason,
  });

  bool get isApproved => status == HardwareApprovalStatus.approved;
  int get approvedCount => approvedOperations.length;

  /// Stable identifier for a plan (it carries no id of its own).
  static String planIdFor(HardwareWritePlan plan) =>
      '${plan.sourceExportPackageId}@${plan.generatedAt.toIso8601String()}';

  /// Builds an approval over [plan].
  ///
  /// - With no [selection], every capture-proven (writable) operation is
  ///   approved.
  /// - With a [selection], each operation must be one of the plan's writable
  ///   operations; if any is not, the whole approval is **rejected** and
  ///   nothing is approved.
  /// - When there is nothing approvable, the result is [HardwareApprovalStatus.empty]
  ///   (fail-closed).
  ///
  /// Never writes hardware; produces a record only.
  factory HardwareWriteApproval.approve(
    HardwareWritePlan plan, {
    String approver = 'unspecified',
    DateTime? approvedAt,
    List<HardwareWriteOp>? selection,
  }) {
    final at = approvedAt ?? DateTime.now();
    final planId = planIdFor(plan);
    final writable = plan.writableOperations;

    HardwareWriteApproval fail(
            HardwareApprovalStatus status, String reason) =>
        HardwareWriteApproval._(
          planId: planId,
          deviceProfile: plan.deviceProfile,
          approvedAt: at,
          approvedOperations: const [],
          status: status,
          approver: approver,
          rejectionReason: reason,
        );

    // Fail closed: nothing writable to approve at all.
    if (writable.isEmpty) {
      return fail(HardwareApprovalStatus.empty,
          'No capture-proven operations available to approve.');
    }

    final requested = selection ?? writable;

    if (requested.isEmpty) {
      return fail(HardwareApprovalStatus.empty,
          'No operations selected for approval.');
    }

    // Reject if any requested op is not a writable op of this plan.
    final invalid = requested
        .where((o) => !o.writable || !writable.contains(o))
        .toList();
    if (invalid.isNotEmpty) {
      return fail(
          HardwareApprovalStatus.rejected,
          '${invalid.length} operation(s) are not capture-proven and cannot '
          'be approved.');
    }

    return HardwareWriteApproval._(
      planId: planId,
      deviceProfile: plan.deviceProfile,
      approvedAt: at,
      approvedOperations: List.unmodifiable(requested),
      status: HardwareApprovalStatus.approved,
      approver: approver,
    );
  }

  Map<String, dynamic> toJson() => {
        'planId': planId,
        'deviceId': deviceProfile.deviceId,
        'approvedAt': approvedAt.toIso8601String(),
        'status': status.toJson(),
        'approver': approver,
        'approvedOperations':
            approvedOperations.map((o) => o.toJson()).toList(),
        if (rejectionReason != null) 'rejectionReason': rejectionReason,
      };
}
