// ── TUNAI PRO Phase Q / T2 — Hardware Connection Guard Data ──────────────────
// Dry-run hardware planning models. No USB/BLE/SafeLoad/EEPROM write.
// DO NOT write to hardware. DO NOT send USB or BLE packets.
// AI suggests. Expert verifies. AOS protects. DSP executes.

import 'pro_export_data.dart';
import 'pro_dsp_address_registry.dart';
import 'pro_hardware_transport.dart';

// ── Enums ─────────────────────────────────────────────────────────────────────

enum HardwareTransportType {
  none,
  usbi,
  ble,
  usbAudio,
  networkPlaceholder,
  simulationOnly;

  String toJson() => name;
  static HardwareTransportType fromJson(String s) =>
      HardwareTransportType.values.firstWhere((e) => e.name == s,
          orElse: () => HardwareTransportType.none);

  String get label => switch (this) {
    HardwareTransportType.none               => 'None',
    HardwareTransportType.usbi               => 'USBi',
    HardwareTransportType.ble                => 'BLE',
    HardwareTransportType.usbAudio           => 'USB Audio',
    HardwareTransportType.networkPlaceholder => 'Network (Placeholder)',
    HardwareTransportType.simulationOnly     => 'Simulation Only',
  };
}

enum HardwareConnectionStatus {
  disconnected,
  simulated,
  detected,
  connected,
  unauthorized,
  driverMissing,
  incompatible,
  error;

  String toJson() => name;
  static HardwareConnectionStatus fromJson(String s) =>
      HardwareConnectionStatus.values.firstWhere((e) => e.name == s,
          orElse: () => HardwareConnectionStatus.disconnected);

  String get label => switch (this) {
    HardwareConnectionStatus.disconnected => 'Disconnected',
    HardwareConnectionStatus.simulated    => 'Simulated',
    HardwareConnectionStatus.detected     => 'Detected',
    HardwareConnectionStatus.connected    => 'Connected',
    HardwareConnectionStatus.unauthorized => 'Unauthorized',
    HardwareConnectionStatus.driverMissing => 'Driver Missing',
    HardwareConnectionStatus.incompatible  => 'Incompatible',
    HardwareConnectionStatus.error         => 'Error',
  };
}

enum HardwareTargetDevice {
  simulation,
  adau1701,
  adau1466,
  aosBox,
  unknown;

  String toJson() => name;
  static HardwareTargetDevice fromJson(String s) =>
      HardwareTargetDevice.values.firstWhere((e) => e.name == s,
          orElse: () => HardwareTargetDevice.simulation);

  String get label => switch (this) {
    HardwareTargetDevice.simulation => 'Simulation',
    HardwareTargetDevice.adau1701   => 'ADAU1701',
    HardwareTargetDevice.adau1466   => 'ADAU1466',
    HardwareTargetDevice.aosBox     => 'AOS Box',
    HardwareTargetDevice.unknown    => 'Unknown',
  };
}

enum HardwareWriteMode {
  dryRunOnly,
  guardedWriteDisabled,
  safeloadPlaceholder,
  futureHardwareWrite;

  String toJson() => name;
  static HardwareWriteMode fromJson(String s) =>
      HardwareWriteMode.values.firstWhere((e) => e.name == s,
          orElse: () => HardwareWriteMode.dryRunOnly);

  String get label => switch (this) {
    HardwareWriteMode.dryRunOnly          => 'Dry Run Only',
    HardwareWriteMode.guardedWriteDisabled => 'Guarded Write (Disabled)',
    HardwareWriteMode.safeloadPlaceholder  => 'SafeLoad Placeholder',
    HardwareWriteMode.futureHardwareWrite  => 'Future Hardware Write',
  };
}

enum HardwareGuardStatus {
  pass,
  warning,
  blocked,
  notApplicable;

  String toJson() => name;
  static HardwareGuardStatus fromJson(String s) =>
      HardwareGuardStatus.values.firstWhere((e) => e.name == s,
          orElse: () => HardwareGuardStatus.notApplicable);

  String get label => switch (this) {
    HardwareGuardStatus.pass          => 'Pass',
    HardwareGuardStatus.warning       => 'Warning',
    HardwareGuardStatus.blocked       => 'Blocked',
    HardwareGuardStatus.notApplicable => 'N/A',
  };
}

// ── HardwareConnectionState ───────────────────────────────────────────────────

class HardwareConnectionState {
  final HardwareTransportType transportType;
  final HardwareConnectionStatus connectionStatus;
  final HardwareTargetDevice targetDevice;
  final String? deviceName;
  final String? vid;
  final String? pid;
  final String? driverName;
  final String? firmwareVersion;
  final DateTime? lastCheckedAt;
  final String? notes;

  // ── Phase T2: Multi-transport fields ──────────────────────────────────────
  final HardwareTransportBackend selectedTransportBackend;
  final List<HardwareTransportInfo> availableTransports;

  HardwareConnectionState({
    this.transportType = HardwareTransportType.simulationOnly,
    this.connectionStatus = HardwareConnectionStatus.simulated,
    this.targetDevice = HardwareTargetDevice.simulation,
    this.deviceName,
    this.vid,
    this.pid,
    this.driverName,
    this.firmwareVersion,
    this.lastCheckedAt,
    this.notes,
    this.selectedTransportBackend = HardwareTransportBackend.simulation,
    List<HardwareTransportInfo>? availableTransports,
  }) : availableTransports =
           availableTransports ?? HardwareTransportInfo.defaultAvailableTransports;

  HardwareTransportInfo? get selectedTransportInfo =>
      availableTransports.where((t) => t.backend == selectedTransportBackend)
          .firstOrNull;

  HardwareConnectionState copyWith({
    HardwareTransportType? transportType,
    HardwareConnectionStatus? connectionStatus,
    HardwareTargetDevice? targetDevice,
    String? deviceName,
    String? vid,
    String? pid,
    String? driverName,
    String? firmwareVersion,
    DateTime? lastCheckedAt,
    String? notes,
    HardwareTransportBackend? selectedTransportBackend,
    List<HardwareTransportInfo>? availableTransports,
  }) => HardwareConnectionState(
    transportType: transportType ?? this.transportType,
    connectionStatus: connectionStatus ?? this.connectionStatus,
    targetDevice: targetDevice ?? this.targetDevice,
    deviceName: deviceName ?? this.deviceName,
    vid: vid ?? this.vid,
    pid: pid ?? this.pid,
    driverName: driverName ?? this.driverName,
    firmwareVersion: firmwareVersion ?? this.firmwareVersion,
    lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    notes: notes ?? this.notes,
    selectedTransportBackend:
        selectedTransportBackend ?? this.selectedTransportBackend,
    availableTransports: availableTransports ?? this.availableTransports,
  );

  Map<String, dynamic> toJson() => {
    'transportType': transportType.toJson(),
    'connectionStatus': connectionStatus.toJson(),
    'targetDevice': targetDevice.toJson(),
    if (deviceName != null) 'deviceName': deviceName,
    if (vid != null) 'vid': vid,
    if (pid != null) 'pid': pid,
    if (driverName != null) 'driverName': driverName,
    if (firmwareVersion != null) 'firmwareVersion': firmwareVersion,
    if (lastCheckedAt != null) 'lastCheckedAt': lastCheckedAt!.toIso8601String(),
    if (notes != null) 'notes': notes,
    'selectedTransportBackend': selectedTransportBackend.toJson(),
    'availableTransports': availableTransports.map((t) => t.toJson()).toList(),
  };

  factory HardwareConnectionState.fromJson(Map<String, dynamic> j) =>
      HardwareConnectionState(
        transportType: HardwareTransportType.fromJson(
            j['transportType'] as String? ?? 'simulationOnly'),
        connectionStatus: HardwareConnectionStatus.fromJson(
            j['connectionStatus'] as String? ?? 'simulated'),
        targetDevice: HardwareTargetDevice.fromJson(
            j['targetDevice'] as String? ?? 'simulation'),
        deviceName: j['deviceName'] as String?,
        vid: j['vid'] as String?,
        pid: j['pid'] as String?,
        driverName: j['driverName'] as String?,
        firmwareVersion: j['firmwareVersion'] as String?,
        lastCheckedAt: j['lastCheckedAt'] != null
            ? DateTime.tryParse(j['lastCheckedAt'] as String)
            : null,
        notes: j['notes'] as String?,
        selectedTransportBackend: HardwareTransportBackend.fromJson(
            j['selectedTransportBackend'] as String? ?? 'simulation'),
        availableTransports: j['availableTransports'] != null
            ? (j['availableTransports'] as List)
                .map((e) => HardwareTransportInfo.fromJson(
                    Map<String, dynamic>.from(e as Map)))
                .toList()
            : null,
      );
}

// ── HardwareGuardCheck ────────────────────────────────────────────────────────

class HardwareGuardCheck {
  final String id;
  final String title;
  final HardwareGuardStatus status;
  final String description;
  final String? recommendation;
  final String? relatedBlockId;

  const HardwareGuardCheck({
    required this.id,
    required this.title,
    required this.status,
    required this.description,
    this.recommendation,
    this.relatedBlockId,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'status': status.toJson(),
    'description': description,
    if (recommendation != null) 'recommendation': recommendation,
    if (relatedBlockId != null) 'relatedBlockId': relatedBlockId,
  };

  factory HardwareGuardCheck.fromJson(Map<String, dynamic> j) =>
      HardwareGuardCheck(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        status: HardwareGuardStatus.fromJson(j['status'] as String? ?? 'notApplicable'),
        description: j['description'] as String? ?? '',
        recommendation: j['recommendation'] as String?,
        relatedBlockId: j['relatedBlockId'] as String?,
      );
}

// ── HardwareWritePlanStep ─────────────────────────────────────────────────────

class HardwareWritePlanStep {
  final String id;
  final int order;
  final ExportBlockType blockType;
  final String logicalName;
  final DspParameterKind? parameterKind;
  final String? channelId;
  final String? addressHex;
  final bool addressVerified;
  final String? valuePreview;
  final String? fixedPointHex;
  final HardwareWriteMode mode;
  final HardwareGuardStatus status;
  final String? warning;

  const HardwareWritePlanStep({
    required this.id,
    required this.order,
    required this.blockType,
    required this.logicalName,
    this.parameterKind,
    this.channelId,
    this.addressHex,
    required this.addressVerified,
    this.valuePreview,
    this.fixedPointHex,
    required this.mode,
    required this.status,
    this.warning,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'order': order,
    'blockType': blockType.toJson(),
    'logicalName': logicalName,
    if (parameterKind != null) 'parameterKind': parameterKind!.toJson(),
    if (channelId != null) 'channelId': channelId,
    if (addressHex != null) 'addressHex': addressHex,
    'addressVerified': addressVerified,
    if (valuePreview != null) 'valuePreview': valuePreview,
    if (fixedPointHex != null) 'fixedPointHex': fixedPointHex,
    'mode': mode.toJson(),
    'status': status.toJson(),
    if (warning != null) 'warning': warning,
  };

  factory HardwareWritePlanStep.fromJson(Map<String, dynamic> j) =>
      HardwareWritePlanStep(
        id: j['id'] as String,
        order: j['order'] as int? ?? 0,
        blockType: ExportBlockType.fromJson(j['blockType'] as String? ?? 'peq'),
        logicalName: j['logicalName'] as String? ?? '',
        parameterKind: j['parameterKind'] != null
            ? DspParameterKind.fromJson(j['parameterKind'] as String)
            : null,
        channelId: j['channelId'] as String?,
        addressHex: j['addressHex'] as String?,
        addressVerified: j['addressVerified'] as bool? ?? false,
        valuePreview: j['valuePreview'] as String?,
        fixedPointHex: j['fixedPointHex'] as String?,
        mode: HardwareWriteMode.fromJson(j['mode'] as String? ?? 'dryRunOnly'),
        status: HardwareGuardStatus.fromJson(j['status'] as String? ?? 'blocked'),
        warning: j['warning'] as String?,
      );
}

// ── HardwareWritePlan ─────────────────────────────────────────────────────────

class HardwareWritePlan {
  final String id;
  final DateTime createdAt;
  final DspTargetPlatform targetPlatform;
  final HardwareTransportType transportType;
  final HardwareWriteMode mode;
  final String? packageId;
  final List<HardwareWritePlanStep> steps;
  final List<HardwareGuardCheck> guardChecks;
  final List<String> warnings;
  final String? blockedReason;
  final String summary;
  final bool dryRunOnly;

  HardwareWritePlan({
    required this.id,
    DateTime? createdAt,
    required this.targetPlatform,
    required this.transportType,
    required this.mode,
    this.packageId,
    required this.steps,
    required this.guardChecks,
    required this.warnings,
    this.blockedReason,
    required this.summary,
    required this.dryRunOnly,
  }) : createdAt = createdAt ?? DateTime.now();

  int get totalStepCount => steps.length;
  int get verifiedStepCount =>
      steps.where((s) => s.addressVerified).length;
  int get blockedStepCount =>
      steps.where((s) => s.status == HardwareGuardStatus.blocked).length;
  int get blockedCheckCount =>
      guardChecks.where((c) => c.status == HardwareGuardStatus.blocked).length;
  int get warningCheckCount =>
      guardChecks.where((c) => c.status == HardwareGuardStatus.warning).length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'targetPlatform': targetPlatform.toJson(),
    'transportType': transportType.toJson(),
    'mode': mode.toJson(),
    if (packageId != null) 'packageId': packageId,
    'steps': steps.map((s) => s.toJson()).toList(),
    'guardChecks': guardChecks.map((c) => c.toJson()).toList(),
    'warnings': warnings,
    if (blockedReason != null) 'blockedReason': blockedReason,
    'summary': summary,
    'dryRunOnly': dryRunOnly,
  };

  factory HardwareWritePlan.fromJson(Map<String, dynamic> j) => HardwareWritePlan(
    id: j['id'] as String,
    createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    targetPlatform: DspTargetPlatform.fromJson(
        j['targetPlatform'] as String? ?? 'simulationOnly'),
    transportType: HardwareTransportType.fromJson(
        j['transportType'] as String? ?? 'simulationOnly'),
    mode: HardwareWriteMode.fromJson(j['mode'] as String? ?? 'dryRunOnly'),
    packageId: j['packageId'] as String?,
    steps: (j['steps'] as List? ?? [])
        .map((e) => HardwareWritePlanStep.fromJson(
            Map<String, dynamic>.from(e as Map)))
        .toList(),
    guardChecks: (j['guardChecks'] as List? ?? [])
        .map((e) => HardwareGuardCheck.fromJson(
            Map<String, dynamic>.from(e as Map)))
        .toList(),
    warnings: List<String>.from(j['warnings'] as List? ?? []),
    blockedReason: j['blockedReason'] as String?,
    summary: j['summary'] as String? ?? '',
    dryRunOnly: j['dryRunOnly'] as bool? ?? true,
  );
}

// ── HardwareProjectState ──────────────────────────────────────────────────────

class HardwareProjectState {
  final HardwareConnectionState connectionState;
  final List<HardwareWritePlan> writePlans;
  final String? activePlanId;
  final DateTime updatedAt;
  final int revision;

  HardwareProjectState({
    HardwareConnectionState? connectionState,
    this.writePlans = const [],
    this.activePlanId,
    DateTime? updatedAt,
    this.revision = 0,
  }) : connectionState = connectionState ?? HardwareConnectionState(),
       updatedAt = updatedAt ?? DateTime.now();

  // ── Computed getters ──────────────────────────────────────────────────────

  HardwareWritePlan? get activePlan {
    if (activePlanId == null) return writePlans.isEmpty ? null : writePlans.last;
    try {
      return writePlans.firstWhere((p) => p.id == activePlanId);
    } catch (_) {
      return writePlans.isEmpty ? null : writePlans.last;
    }
  }

  int get planCount => writePlans.length;

  int get blockedCheckCount => activePlan?.blockedCheckCount ?? 0;

  int get warningCheckCount => activePlan?.warningCheckCount ?? 0;

  /// Phase Q: hardware write is always disabled.
  bool get isHardwareWriteEnabled => false;

  String get readinessLabel {
    final plan = activePlan;
    if (plan == null) return 'No export package';
    if (plan.blockedReason != null) return 'Unverified mappings block write';
    if (plan.blockedStepCount > 0) return 'Unverified mappings block write';
    if (plan.dryRunOnly) return 'Dry-run plan ready';
    return 'Hardware write disabled';
  }

  // ── copyWith ──────────────────────────────────────────────────────────────

  HardwareProjectState copyWith({
    HardwareConnectionState? connectionState,
    List<HardwareWritePlan>? writePlans,
    String? activePlanId,
    DateTime? updatedAt,
    int? revision,
  }) => HardwareProjectState(
    connectionState: connectionState ?? this.connectionState,
    writePlans: writePlans ?? this.writePlans,
    activePlanId: activePlanId ?? this.activePlanId,
    updatedAt: updatedAt ?? this.updatedAt,
    revision: revision ?? this.revision,
  );

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'connectionState': connectionState.toJson(),
    'writePlans': writePlans.map((p) => p.toJson()).toList(),
    if (activePlanId != null) 'activePlanId': activePlanId,
    'updatedAt': updatedAt.toIso8601String(),
    'revision': revision,
  };

  factory HardwareProjectState.fromJson(Map<String, dynamic> j) =>
      HardwareProjectState(
        connectionState: j['connectionState'] != null
            ? HardwareConnectionState.fromJson(
                Map<String, dynamic>.from(j['connectionState'] as Map))
            : null,
        writePlans: (j['writePlans'] as List? ?? [])
            .map((e) => HardwareWritePlan.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
        activePlanId: j['activePlanId'] as String?,
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ??
            DateTime.now(),
        revision: j['revision'] as int? ?? 0,
      );

  factory HardwareProjectState.createDefault() => HardwareProjectState(
    connectionState: HardwareConnectionState(
      transportType: HardwareTransportType.simulationOnly,
      connectionStatus: HardwareConnectionStatus.simulated,
      targetDevice: HardwareTargetDevice.simulation,
      selectedTransportBackend: HardwareTransportBackend.simulation,
    ),
    writePlans: const [],
    revision: 0,
  );
}
