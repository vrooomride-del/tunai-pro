// ── TUNAI PRO Phase F — Protection / Verification Data Models ─────────────────
// AOS protects. No DSP write. No SafeLoad. No register addresses.

// ── Enums ─────────────────────────────────────────────────────────────────────

enum ProtectionRuleType {
  maxBoost,
  maxCut,
  minHighPass,
  maxOutputGain,
  maxDelay,
  headroomReserve,
  polarityConsistency,
  measurementCompleteness,
  exportLock;

  String get label => switch (this) {
    ProtectionRuleType.maxBoost                => 'Max PEQ Boost',
    ProtectionRuleType.maxCut                  => 'Max PEQ Cut',
    ProtectionRuleType.minHighPass             => 'Min High-Pass',
    ProtectionRuleType.maxOutputGain           => 'Max Output Gain',
    ProtectionRuleType.maxDelay               => 'Max Delay',
    ProtectionRuleType.headroomReserve         => 'Headroom Reserve',
    ProtectionRuleType.polarityConsistency     => 'Polarity Consistency',
    ProtectionRuleType.measurementCompleteness => 'Measurement Completeness',
    ProtectionRuleType.exportLock              => 'Export Lock',
  };

  String toJson() => name;
  static ProtectionRuleType fromJson(String s) =>
      ProtectionRuleType.values.firstWhere((e) => e.name == s,
          orElse: () => ProtectionRuleType.maxBoost);
}

enum ProtectionSeverity {
  info,
  warning,
  critical;

  String get label => switch (this) {
    ProtectionSeverity.info     => 'Info',
    ProtectionSeverity.warning  => 'Warning',
    ProtectionSeverity.critical => 'Critical',
  };

  String toJson() => name;
  static ProtectionSeverity fromJson(String s) =>
      ProtectionSeverity.values.firstWhere((e) => e.name == s,
          orElse: () => ProtectionSeverity.info);
}

enum ProtectionRuleStatus {
  enabled,
  bypassed,
  triggered,
  passed;

  String get label => switch (this) {
    ProtectionRuleStatus.enabled   => 'Enabled',
    ProtectionRuleStatus.bypassed  => 'Bypassed',
    ProtectionRuleStatus.triggered => 'Triggered',
    ProtectionRuleStatus.passed    => 'Passed',
  };

  String toJson() => name;
  static ProtectionRuleStatus fromJson(String s) =>
      ProtectionRuleStatus.values.firstWhere((e) => e.name == s,
          orElse: () => ProtectionRuleStatus.enabled);
}

enum VerificationStatus {
  notReady,
  passedWithWarnings,
  failed,
  passed;

  String get label => switch (this) {
    VerificationStatus.notReady           => 'Not Ready',
    VerificationStatus.passedWithWarnings => 'Passed with Warnings',
    VerificationStatus.failed             => 'Failed',
    VerificationStatus.passed             => 'Passed',
  };

  String toJson() => name;
  static VerificationStatus fromJson(String s) =>
      VerificationStatus.values.firstWhere((e) => e.name == s,
          orElse: () => VerificationStatus.notReady);
}

// ── Models ────────────────────────────────────────────────────────────────────

class ProtectionRule {
  final String id;
  final ProtectionRuleType type;
  final bool enabled;
  final ProtectionSeverity severity;
  final double threshold;
  final String unit;
  final String title;
  final String description;
  final String? note;

  const ProtectionRule({
    required this.id,
    required this.type,
    this.enabled = true,
    this.severity = ProtectionSeverity.warning,
    this.threshold = 0.0,
    this.unit = '',
    required this.title,
    required this.description,
    this.note,
  });

  ProtectionRule copyWith({
    bool? enabled,
    ProtectionSeverity? severity,
    double? threshold,
    String? unit,
    String? title,
    String? description,
    String? note,
  }) => ProtectionRule(
    id: id,
    type: type,
    enabled: enabled ?? this.enabled,
    severity: severity ?? this.severity,
    threshold: threshold ?? this.threshold,
    unit: unit ?? this.unit,
    title: title ?? this.title,
    description: description ?? this.description,
    note: note ?? this.note,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.toJson(),
    'enabled': enabled,
    'severity': severity.toJson(),
    'threshold': threshold,
    'unit': unit,
    'title': title,
    'description': description,
    if (note != null) 'note': note,
  };

  factory ProtectionRule.fromJson(Map<String, dynamic> j) => ProtectionRule(
    id: j['id'] as String,
    type: ProtectionRuleType.fromJson(j['type'] as String? ?? 'maxBoost'),
    enabled: j['enabled'] as bool? ?? true,
    severity: ProtectionSeverity.fromJson(j['severity'] as String? ?? 'warning'),
    threshold: (j['threshold'] as num?)?.toDouble() ?? 0.0,
    unit: j['unit'] as String? ?? '',
    title: j['title'] as String? ?? '',
    description: j['description'] as String? ?? '',
    note: j['note'] as String?,
  );
}

class VerificationIssue {
  final String id;
  final String ruleId;
  final ProtectionSeverity severity;
  final String message;
  final String? channelId;
  final double? value;
  final double? threshold;

  const VerificationIssue({
    required this.id,
    required this.ruleId,
    required this.severity,
    required this.message,
    this.channelId,
    this.value,
    this.threshold,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'ruleId': ruleId,
    'severity': severity.toJson(),
    'message': message,
    if (channelId != null) 'channelId': channelId,
    if (value != null) 'value': value,
    if (threshold != null) 'threshold': threshold,
  };

  factory VerificationIssue.fromJson(Map<String, dynamic> j) => VerificationIssue(
    id: j['id'] as String,
    ruleId: j['ruleId'] as String? ?? '',
    severity: ProtectionSeverity.fromJson(j['severity'] as String? ?? 'warning'),
    message: j['message'] as String? ?? '',
    channelId: j['channelId'] as String?,
    value: (j['value'] as num?)?.toDouble(),
    threshold: (j['threshold'] as num?)?.toDouble(),
  );
}

class ProtectionProjectState {
  final List<ProtectionRule> rules;
  final List<VerificationIssue> issues;
  final VerificationStatus verificationStatus;
  final DateTime updatedAt;
  final int revision;
  final bool exportLocked;

  ProtectionProjectState({
    this.rules = const [],
    this.issues = const [],
    this.verificationStatus = VerificationStatus.notReady,
    DateTime? updatedAt,
    this.revision = 0,
    this.exportLocked = true,
  }) : updatedAt = updatedAt ?? DateTime.now();

  // ── Computed getters ──────────────────────────────────────────────────────

  int get activeRuleCount => rules.where((r) => r.enabled).length;
  int get triggeredIssueCount => issues.length;
  int get warningCount =>
      issues.where((i) => i.severity == ProtectionSeverity.warning).length;
  int get criticalCount =>
      issues.where((i) => i.severity == ProtectionSeverity.critical).length;
  bool get passed => verificationStatus == VerificationStatus.passed ||
      verificationStatus == VerificationStatus.passedWithWarnings;

  String get readinessLabel => switch (verificationStatus) {
    VerificationStatus.notReady           => 'Not verified',
    VerificationStatus.failed             => 'Verification failed',
    VerificationStatus.passedWithWarnings => 'Passed with warnings',
    VerificationStatus.passed             => 'Verification passed',
  };

  // ── Persistence ───────────────────────────────────────────────────────────

  ProtectionProjectState copyWith({
    List<ProtectionRule>? rules,
    List<VerificationIssue>? issues,
    VerificationStatus? verificationStatus,
    DateTime? updatedAt,
    int? revision,
    bool? exportLocked,
  }) => ProtectionProjectState(
    rules: rules ?? this.rules,
    issues: issues ?? this.issues,
    verificationStatus: verificationStatus ?? this.verificationStatus,
    updatedAt: updatedAt ?? DateTime.now(),
    revision: revision ?? this.revision,
    exportLocked: exportLocked ?? this.exportLocked,
  );

  Map<String, dynamic> toJson() => {
    'rules': rules.map((r) => r.toJson()).toList(),
    'issues': issues.map((i) => i.toJson()).toList(),
    'verificationStatus': verificationStatus.toJson(),
    'updatedAt': updatedAt.toIso8601String(),
    'revision': revision,
    'exportLocked': exportLocked,
  };

  factory ProtectionProjectState.fromJson(Map<String, dynamic> j) =>
      ProtectionProjectState(
        rules: (j['rules'] as List? ?? [])
            .map((e) => ProtectionRule.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        issues: (j['issues'] as List? ?? [])
            .map((e) => VerificationIssue.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        verificationStatus: VerificationStatus.fromJson(
            j['verificationStatus'] as String? ?? 'notReady'),
        updatedAt:
            DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
        revision: j['revision'] as int? ?? 0,
        exportLocked: j['exportLocked'] as bool? ?? true,
      );

  static ProtectionProjectState createDefault() =>
      ProtectionProjectState(rules: _defaultRules());
}

// ── Default rule set ──────────────────────────────────────────────────────────

List<ProtectionRule> _defaultRules() => [
  const ProtectionRule(
    id: 'rule_measurement_completeness',
    type: ProtectionRuleType.measurementCompleteness,
    severity: ProtectionSeverity.warning,
    threshold: 0,
    unit: '',
    title: 'Measurement Completeness',
    description: 'All driver channels must have FRD data imported.',
  ),
  const ProtectionRule(
    id: 'rule_max_boost',
    type: ProtectionRuleType.maxBoost,
    severity: ProtectionSeverity.warning,
    threshold: 6.0,
    unit: 'dB',
    title: 'Max PEQ Boost',
    description: 'PEQ boost above threshold may cause clipping or thermal stress.',
  ),
  const ProtectionRule(
    id: 'rule_max_cut',
    type: ProtectionRuleType.maxCut,
    severity: ProtectionSeverity.warning,
    threshold: -12.0,
    unit: 'dB',
    title: 'Max PEQ Cut',
    description: 'Excessive PEQ cut reduces dynamic range without acoustic benefit.',
  ),
  const ProtectionRule(
    id: 'rule_min_hpf',
    type: ProtectionRuleType.minHighPass,
    severity: ProtectionSeverity.warning,
    threshold: 0,
    unit: '',
    title: 'Min High-Pass',
    description: 'Woofer channels should have an HPF to protect from infrasonic content.',
  ),
  const ProtectionRule(
    id: 'rule_max_output_gain',
    type: ProtectionRuleType.maxOutputGain,
    severity: ProtectionSeverity.warning,
    threshold: 6.0,
    unit: 'dB',
    title: 'Max Output Gain',
    description: 'Output gain trim above threshold reduces headroom.',
  ),
  const ProtectionRule(
    id: 'rule_max_delay',
    type: ProtectionRuleType.maxDelay,
    severity: ProtectionSeverity.warning,
    threshold: 10.0,
    unit: 'ms',
    title: 'Max Delay',
    description: 'Delays above threshold may cause audible pre-ringing artifacts.',
  ),
  const ProtectionRule(
    id: 'rule_headroom',
    type: ProtectionRuleType.headroomReserve,
    severity: ProtectionSeverity.warning,
    threshold: 6.0,
    unit: 'dB',
    title: 'Headroom Reserve',
    description: 'Combined PEQ boost and output gain may limit available headroom.',
  ),
  const ProtectionRule(
    id: 'rule_polarity',
    type: ProtectionRuleType.polarityConsistency,
    severity: ProtectionSeverity.info,
    threshold: 0.5,
    unit: 'ratio',
    title: 'Polarity Consistency',
    description: 'More than half of channels with inverted polarity is unusual.',
  ),
  const ProtectionRule(
    id: 'rule_export_lock',
    type: ProtectionRuleType.exportLock,
    severity: ProtectionSeverity.critical,
    threshold: 0,
    unit: '',
    title: 'Export Lock',
    description: 'Export is locked until verification passes or warnings are acknowledged.',
  ),
];
