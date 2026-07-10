// ── TUNAI PRO Phase U2 — Address Live Validation Data ────────────────────────
// Data model for DSP address live validation workflow.
// Does NOT write to hardware. Does NOT send USB/BLE. Does NOT execute SafeLoad.
// All validation tasks are dry-run only in Phase U2.
// AI suggests. Expert verifies. AOS protects. DSP executes.

enum AddressValidationStatus {
  notQueued,
  queued,
  readyForDryRun,
  dryRunGenerated,
  waitingForHardware,
  validationAttempted,
  liveWriteVerified,
  failed,
  blocked;

  String toJson() => name;

  static AddressValidationStatus fromJson(String s) =>
      AddressValidationStatus.values.firstWhere(
        (e) => e.name == s,
        orElse: () => AddressValidationStatus.notQueued,
      );

  String get label => switch (this) {
    AddressValidationStatus.notQueued          => 'Not Queued',
    AddressValidationStatus.queued             => 'Queued',
    AddressValidationStatus.readyForDryRun     => 'Ready for Dry-Run',
    AddressValidationStatus.dryRunGenerated    => 'Dry-Run Generated',
    AddressValidationStatus.waitingForHardware => 'Waiting for Hardware',
    AddressValidationStatus.validationAttempted => 'Validation Attempted',
    AddressValidationStatus.liveWriteVerified  => 'Live Write Verified',
    AddressValidationStatus.failed             => 'Failed',
    AddressValidationStatus.blocked            => 'Blocked',
  };

  bool get isTerminal => this == liveWriteVerified || this == failed || this == blocked;
}

enum AddressValidationRisk {
  low,
  medium,
  high,
  critical;

  String toJson() => name;

  static AddressValidationRisk fromJson(String s) =>
      AddressValidationRisk.values.firstWhere(
        (e) => e.name == s,
        orElse: () => AddressValidationRisk.high,
      );

  String get label => switch (this) {
    AddressValidationRisk.low      => 'Low',
    AddressValidationRisk.medium   => 'Medium',
    AddressValidationRisk.high     => 'High',
    AddressValidationRisk.critical => 'Critical',
  };
}

enum AddressValidationGroup {
  masterVolume,
  safeLoad,
  mute,
  gain,
  delay,
  peq,
  crossover,
  polarity,
  outputRouting,
  limiter,
  unknown;

  String toJson() => name;

  static AddressValidationGroup fromJson(String s) =>
      AddressValidationGroup.values.firstWhere(
        (e) => e.name == s,
        orElse: () => AddressValidationGroup.unknown,
      );

  String get label => switch (this) {
    AddressValidationGroup.masterVolume  => 'Master Volume',
    AddressValidationGroup.safeLoad      => 'SafeLoad',
    AddressValidationGroup.mute          => 'Mute',
    AddressValidationGroup.gain          => 'Gain / Driver',
    AddressValidationGroup.delay         => 'Delay',
    AddressValidationGroup.peq           => 'PEQ',
    AddressValidationGroup.crossover     => 'Crossover',
    AddressValidationGroup.polarity      => 'Polarity',
    AddressValidationGroup.outputRouting => 'Output Routing',
    AddressValidationGroup.limiter       => 'Limiter',
    AddressValidationGroup.unknown       => 'Unknown',
  };

  // Recommended order: lower index = validate first
  int get recommendedOrder => switch (this) {
    AddressValidationGroup.masterVolume  => 0,
    AddressValidationGroup.safeLoad      => 1,
    AddressValidationGroup.mute          => 2,
    AddressValidationGroup.gain          => 3,
    AddressValidationGroup.delay         => 4,
    AddressValidationGroup.peq           => 5,
    AddressValidationGroup.crossover     => 6,
    AddressValidationGroup.polarity      => 7,
    AddressValidationGroup.outputRouting => 8,
    AddressValidationGroup.limiter       => 9,
    AddressValidationGroup.unknown       => 99,
  };
}

// ── AddressValidationTask ─────────────────────────────────────────────────────

class AddressValidationTask {
  final String id;
  final String addressId;
  final String? parameterId;
  final String logicalName;
  final AddressValidationGroup group;
  final AddressValidationRisk risk;
  final AddressValidationStatus currentStatus;
  final String addressHex;
  final String? channel;
  final String? outputIndex;
  final String? coefficient;
  final String? testValue;
  final String? expectedEffect;
  final String? actualObservedEffect;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AddressValidationTask({
    required this.id,
    required this.addressId,
    this.parameterId,
    required this.logicalName,
    required this.group,
    required this.risk,
    required this.currentStatus,
    required this.addressHex,
    this.channel,
    this.outputIndex,
    this.coefficient,
    this.testValue,
    this.expectedEffect,
    this.actualObservedEffect,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  AddressValidationTask copyWith({
    String? parameterId,
    String? logicalName,
    AddressValidationGroup? group,
    AddressValidationRisk? risk,
    AddressValidationStatus? currentStatus,
    String? channel,
    String? outputIndex,
    String? coefficient,
    String? testValue,
    String? expectedEffect,
    String? actualObservedEffect,
    String? notes,
    DateTime? updatedAt,
  }) => AddressValidationTask(
    id:                  id,
    addressId:           addressId,
    parameterId:         parameterId ?? this.parameterId,
    logicalName:         logicalName ?? this.logicalName,
    group:               group ?? this.group,
    risk:                risk ?? this.risk,
    currentStatus:       currentStatus ?? this.currentStatus,
    addressHex:          addressHex,
    channel:             channel ?? this.channel,
    outputIndex:         outputIndex ?? this.outputIndex,
    coefficient:         coefficient ?? this.coefficient,
    testValue:           testValue ?? this.testValue,
    expectedEffect:      expectedEffect ?? this.expectedEffect,
    actualObservedEffect: actualObservedEffect ?? this.actualObservedEffect,
    notes:               notes ?? this.notes,
    createdAt:           createdAt,
    updatedAt:           updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id':                  id,
    'addressId':           addressId,
    if (parameterId != null) 'parameterId': parameterId,
    'logicalName':         logicalName,
    'group':               group.toJson(),
    'risk':                risk.toJson(),
    'currentStatus':       currentStatus.toJson(),
    'addressHex':          addressHex,
    if (channel != null) 'channel': channel,
    if (outputIndex != null) 'outputIndex': outputIndex,
    if (coefficient != null) 'coefficient': coefficient,
    if (testValue != null) 'testValue': testValue,
    if (expectedEffect != null) 'expectedEffect': expectedEffect,
    if (actualObservedEffect != null) 'actualObservedEffect': actualObservedEffect,
    if (notes != null) 'notes': notes,
    'createdAt':           createdAt.toIso8601String(),
    'updatedAt':           updatedAt.toIso8601String(),
  };

  factory AddressValidationTask.fromJson(Map<String, dynamic> j) =>
      AddressValidationTask(
        id:                  j['id'] as String,
        addressId:           j['addressId'] as String,
        parameterId:         j['parameterId'] as String?,
        logicalName:         j['logicalName'] as String? ?? '',
        group:               AddressValidationGroup.fromJson(j['group'] as String? ?? 'unknown'),
        risk:                AddressValidationRisk.fromJson(j['risk'] as String? ?? 'high'),
        currentStatus:       AddressValidationStatus.fromJson(j['currentStatus'] as String? ?? 'notQueued'),
        addressHex:          j['addressHex'] as String? ?? '0x0000',
        channel:             j['channel'] as String?,
        outputIndex:         j['outputIndex'] as String?,
        coefficient:         j['coefficient'] as String?,
        testValue:           j['testValue'] as String?,
        expectedEffect:      j['expectedEffect'] as String?,
        actualObservedEffect: j['actualObservedEffect'] as String?,
        notes:               j['notes'] as String?,
        createdAt:           DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt:           DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

// ── AddressValidationAttempt ──────────────────────────────────────────────────

class AddressValidationAttempt {
  final String id;
  final String taskId;
  final DateTime attemptedAt;
  final bool dryRunOnly;
  final bool wasActualWrite;       // always false in Phase U2
  final bool operatorConfirmed;
  final AddressValidationStatus resultStatus;
  final String? observedEffect;
  final String? error;
  final String? notes;

  const AddressValidationAttempt({
    required this.id,
    required this.taskId,
    required this.attemptedAt,
    this.dryRunOnly = true,
    this.wasActualWrite = false,   // Phase U2: always false
    this.operatorConfirmed = false,
    required this.resultStatus,
    this.observedEffect,
    this.error,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
    'id':                id,
    'taskId':            taskId,
    'attemptedAt':       attemptedAt.toIso8601String(),
    'dryRunOnly':        dryRunOnly,
    'wasActualWrite':    wasActualWrite,
    'operatorConfirmed': operatorConfirmed,
    'resultStatus':      resultStatus.toJson(),
    if (observedEffect != null) 'observedEffect': observedEffect,
    if (error != null) 'error': error,
    if (notes != null) 'notes': notes,
  };

  factory AddressValidationAttempt.fromJson(Map<String, dynamic> j) =>
      AddressValidationAttempt(
        id:                j['id'] as String,
        taskId:            j['taskId'] as String,
        attemptedAt:       DateTime.tryParse(j['attemptedAt'] as String? ?? '') ?? DateTime.now(),
        dryRunOnly:        j['dryRunOnly'] as bool? ?? true,
        wasActualWrite:    j['wasActualWrite'] as bool? ?? false,
        operatorConfirmed: j['operatorConfirmed'] as bool? ?? false,
        resultStatus:      AddressValidationStatus.fromJson(j['resultStatus'] as String? ?? 'validationAttempted'),
        observedEffect:    j['observedEffect'] as String?,
        error:             j['error'] as String?,
        notes:             j['notes'] as String?,
      );
}

// ── AddressValidationProjectState ─────────────────────────────────────────────

class AddressValidationProjectState {
  final List<AddressValidationTask> tasks;
  final List<AddressValidationAttempt> attempts;
  final String? activeTaskId;
  final DateTime updatedAt;
  final int revision;

  const AddressValidationProjectState({
    this.tasks = const [],
    this.attempts = const [],
    this.activeTaskId,
    required this.updatedAt,
    this.revision = 0,
  });

  factory AddressValidationProjectState.createDefault() =>
      AddressValidationProjectState(
        updatedAt: DateTime.utc(2026, 7, 10),
      );

  // ── Computed getters ──────────────────────────────────────────────────────

  int get queuedCount => tasks.where((t) =>
      t.currentStatus == AddressValidationStatus.queued ||
      t.currentStatus == AddressValidationStatus.readyForDryRun ||
      t.currentStatus == AddressValidationStatus.dryRunGenerated ||
      t.currentStatus == AddressValidationStatus.waitingForHardware ||
      t.currentStatus == AddressValidationStatus.validationAttempted).length;

  int get verifiedCount => tasks.where(
      (t) => t.currentStatus == AddressValidationStatus.liveWriteVerified).length;

  int get failedCount => tasks.where(
      (t) => t.currentStatus == AddressValidationStatus.failed).length;

  int get blockedCount => tasks.where(
      (t) => t.currentStatus == AddressValidationStatus.blocked).length;

  int get highRiskCount => tasks.where(
      (t) => t.risk == AddressValidationRisk.high ||
             t.risk == AddressValidationRisk.critical).length;

  AddressValidationGroup? get nextRecommendedGroup {
    final pending = tasks.where((t) =>
        t.currentStatus != AddressValidationStatus.liveWriteVerified &&
        t.currentStatus != AddressValidationStatus.failed &&
        t.currentStatus != AddressValidationStatus.blocked);
    if (pending.isEmpty) return null;
    final sorted = pending.toList()
      ..sort((a, b) => a.group.recommendedOrder.compareTo(b.group.recommendedOrder));
    return sorted.first.group;
  }

  String get readinessLabel {
    if (tasks.isEmpty)       return 'No validation tasks generated';
    if (verifiedCount == tasks.length) return 'All addresses validated';
    if (failedCount > 0 || blockedCount > 0) {
      return 'Blocked — ${failedCount + blockedCount} issue(s) require expert review';
    }
    if (verifiedCount > 0) {
      return 'In progress — $verifiedCount / ${tasks.length} validated';
    }
    return 'Not started — ${tasks.length} task(s) pending';
  }

  AddressValidationProjectState copyWith({
    List<AddressValidationTask>? tasks,
    List<AddressValidationAttempt>? attempts,
    String? activeTaskId,
    bool clearActiveTask = false,
    DateTime? updatedAt,
    int? revision,
  }) => AddressValidationProjectState(
    tasks:        tasks ?? this.tasks,
    attempts:     attempts ?? this.attempts,
    activeTaskId: clearActiveTask ? null : (activeTaskId ?? this.activeTaskId),
    updatedAt:    updatedAt ?? this.updatedAt,
    revision:     revision ?? this.revision,
  );

  Map<String, dynamic> toJson() => {
    'tasks':        tasks.map((t) => t.toJson()).toList(),
    'attempts':     attempts.map((a) => a.toJson()).toList(),
    if (activeTaskId != null) 'activeTaskId': activeTaskId,
    'updatedAt':    updatedAt.toIso8601String(),
    'revision':     revision,
  };

  factory AddressValidationProjectState.fromJson(Map<String, dynamic> j) =>
      AddressValidationProjectState(
        tasks:        (j['tasks'] as List? ?? [])
            .map((e) => AddressValidationTask.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        attempts:     (j['attempts'] as List? ?? [])
            .map((e) => AddressValidationAttempt.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        activeTaskId: j['activeTaskId'] as String?,
        updatedAt:    DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
        revision:     j['revision'] as int? ?? 0,
      );
}
