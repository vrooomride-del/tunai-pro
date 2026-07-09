// ── TUNAI PRO Phase K — Crossover Topology / Filter Cascade Foundation ────────
// Topology-aware XO cascade planner. Floating-point draft only.
// No hardware write. No ADAU fixed-point. No SigmaStudio addresses.
// AI suggests. Expert verifies. AOS protects. DSP executes.

import 'pro_biquad_engine.dart';
import 'pro_tuning_data.dart' show CrossoverFilterType, CrossoverSlope, FilterSide;

// ── Enums ─────────────────────────────────────────────────────────────────────

enum CrossoverFilterFamily {
  butterworth,
  linkwitzRiley,
  bessel,
  custom,
  unknown;

  String get label => switch (this) {
    CrossoverFilterFamily.butterworth   => 'Butterworth',
    CrossoverFilterFamily.linkwitzRiley => 'Linkwitz-Riley',
    CrossoverFilterFamily.bessel        => 'Bessel',
    CrossoverFilterFamily.custom        => 'Custom',
    CrossoverFilterFamily.unknown       => 'Unknown',
  };

  String get short => switch (this) {
    CrossoverFilterFamily.butterworth   => 'BW',
    CrossoverFilterFamily.linkwitzRiley => 'LR',
    CrossoverFilterFamily.bessel        => 'BSL',
    CrossoverFilterFamily.custom        => 'CUST',
    CrossoverFilterFamily.unknown       => '?',
  };

  String toJson() => name;
  static CrossoverFilterFamily fromJson(String s) =>
      CrossoverFilterFamily.values.firstWhere((e) => e.name == s,
          orElse: () => CrossoverFilterFamily.unknown);

  static CrossoverFilterFamily fromExisting(CrossoverFilterType t) => switch (t) {
    CrossoverFilterType.linkwitzRiley          => CrossoverFilterFamily.linkwitzRiley,
    CrossoverFilterType.butterworth            => CrossoverFilterFamily.butterworth,
    CrossoverFilterType.bessel                 => CrossoverFilterFamily.bessel,
    CrossoverFilterType.linearPhasePlaceholder => CrossoverFilterFamily.custom,
  };
}

enum CrossoverFilterShape {
  highPass,
  lowPass,
  bandPass,
  bypass;

  String get label => switch (this) {
    CrossoverFilterShape.highPass => 'HPF',
    CrossoverFilterShape.lowPass  => 'LPF',
    CrossoverFilterShape.bandPass => 'BPF',
    CrossoverFilterShape.bypass   => 'Bypass',
  };

  String toJson() => name;
  static CrossoverFilterShape fromJson(String s) =>
      CrossoverFilterShape.values.firstWhere((e) => e.name == s,
          orElse: () => CrossoverFilterShape.bypass);

  static CrossoverFilterShape fromSide(FilterSide side) =>
      side == FilterSide.highPass
          ? CrossoverFilterShape.highPass
          : CrossoverFilterShape.lowPass;

  BiquadFilterType get biquadType => switch (this) {
    CrossoverFilterShape.highPass => BiquadFilterType.highPass,
    CrossoverFilterShape.lowPass  => BiquadFilterType.lowPass,
    _                             => BiquadFilterType.bypass,
  };
}

enum XoSlope {
  slope6,
  slope12,
  slope18,
  slope24,
  slope36,
  slope48,
  custom;

  String get label => switch (this) {
    XoSlope.slope6  => '6 dB/oct',
    XoSlope.slope12 => '12 dB/oct',
    XoSlope.slope18 => '18 dB/oct',
    XoSlope.slope24 => '24 dB/oct',
    XoSlope.slope36 => '36 dB/oct',
    XoSlope.slope48 => '48 dB/oct',
    XoSlope.custom  => 'Custom',
  };

  String get short => switch (this) {
    XoSlope.slope6  => '6',
    XoSlope.slope12 => '12',
    XoSlope.slope18 => '18',
    XoSlope.slope24 => '24',
    XoSlope.slope36 => '36',
    XoSlope.slope48 => '48',
    XoSlope.custom  => '?',
  };

  int get ordersPerBiquad => 2;

  // Number of 2nd-order biquad stages needed for this slope
  int get biquadStageCount => switch (this) {
    XoSlope.slope6  => 1, // approximated as 1-pole, packed in 1 biquad draft
    XoSlope.slope12 => 1,
    XoSlope.slope18 => 2, // approximated
    XoSlope.slope24 => 2,
    XoSlope.slope36 => 3,
    XoSlope.slope48 => 4,
    XoSlope.custom  => 0,
  };

  String toJson() => name;
  static XoSlope fromJson(String s) =>
      XoSlope.values.firstWhere((e) => e.name == s,
          orElse: () => XoSlope.slope24);

  static XoSlope fromExisting(CrossoverSlope s) => switch (s) {
    CrossoverSlope.db12 => XoSlope.slope12,
    CrossoverSlope.db24 => XoSlope.slope24,
    CrossoverSlope.db36 => XoSlope.slope36,
    CrossoverSlope.db48 => XoSlope.slope48,
  };
}

enum CrossoverTopologyStatus {
  ready,
  draft,
  placeholder,
  requiresVerification,
  unsupported;

  String get label => switch (this) {
    CrossoverTopologyStatus.ready                => 'Ready',
    CrossoverTopologyStatus.draft                => 'Draft',
    CrossoverTopologyStatus.placeholder          => 'Placeholder',
    CrossoverTopologyStatus.requiresVerification => 'Requires Verification',
    CrossoverTopologyStatus.unsupported          => 'Unsupported',
  };

  String toJson() => name;
  static CrossoverTopologyStatus fromJson(String s) =>
      CrossoverTopologyStatus.values.firstWhere((e) => e.name == s,
          orElse: () => CrossoverTopologyStatus.placeholder);
}

// ── Models ────────────────────────────────────────────────────────────────────

class CrossoverTopologyInput {
  final String channelId;
  final CrossoverFilterShape shape;
  final CrossoverFilterFamily family;
  final XoSlope slope;
  final double frequencyHz;
  final double? q;
  final double sampleRateHz;
  final String sourceBlockId;
  final String? sourceDescription;

  const CrossoverTopologyInput({
    required this.channelId,
    required this.shape,
    required this.family,
    required this.slope,
    required this.frequencyHz,
    this.q,
    required this.sampleRateHz,
    required this.sourceBlockId,
    this.sourceDescription,
  });
}

class CrossoverCascadeStagePlan {
  final String id;
  final String channelId;
  final CrossoverFilterShape shape;
  final CrossoverFilterFamily family;
  final XoSlope slope;
  final int stageIndex;
  final int totalStages;
  final double frequencyHz;
  final double q;
  final BiquadFilterType filterType;
  final CrossoverTopologyStatus status;
  final String summary;
  final String? warning;

  const CrossoverCascadeStagePlan({
    required this.id,
    required this.channelId,
    required this.shape,
    required this.family,
    required this.slope,
    required this.stageIndex,
    required this.totalStages,
    required this.frequencyHz,
    required this.q,
    required this.filterType,
    required this.status,
    required this.summary,
    this.warning,
  });

  String get stageLabel =>
      '${shape.label} ${family.short}${slope.short} '
      'Stage ${stageIndex + 1}/$totalStages';

  Map<String, dynamic> toJson() => {
    'id': id,
    'channelId': channelId,
    'shape': shape.toJson(),
    'family': family.toJson(),
    'slope': slope.toJson(),
    'stageIndex': stageIndex,
    'totalStages': totalStages,
    'frequencyHz': frequencyHz,
    'q': q,
    'filterType': filterType.toJson(),
    'status': status.toJson(),
    'summary': summary,
    if (warning != null) 'warning': warning,
  };

  factory CrossoverCascadeStagePlan.fromJson(Map<String, dynamic> j) =>
      CrossoverCascadeStagePlan(
        id: j['id'] as String? ?? '',
        channelId: j['channelId'] as String? ?? '',
        shape: CrossoverFilterShape.fromJson(j['shape'] as String? ?? 'bypass'),
        family: CrossoverFilterFamily.fromJson(j['family'] as String? ?? 'unknown'),
        slope: XoSlope.fromJson(j['slope'] as String? ?? 'slope24'),
        stageIndex: j['stageIndex'] as int? ?? 0,
        totalStages: j['totalStages'] as int? ?? 1,
        frequencyHz: (j['frequencyHz'] as num?)?.toDouble() ?? 1000.0,
        q: (j['q'] as num?)?.toDouble() ?? 0.707,
        filterType: BiquadFilterType.fromJson(j['filterType'] as String? ?? 'bypass'),
        status: CrossoverTopologyStatus.fromJson(
            j['status'] as String? ?? 'placeholder'),
        summary: j['summary'] as String? ?? '',
        warning: j['warning'] as String?,
      );
}

class CrossoverTopologyPlan {
  final String id;
  final String channelId;
  final String sourceBlockId;
  final CrossoverFilterShape shape;
  final CrossoverFilterFamily family;
  final XoSlope slope;
  final double frequencyHz;
  final double sampleRateHz;
  final List<CrossoverCascadeStagePlan> stages;
  final CrossoverTopologyStatus status;
  final List<String> warnings;
  final String summary;

  const CrossoverTopologyPlan({
    required this.id,
    required this.channelId,
    required this.sourceBlockId,
    required this.shape,
    required this.family,
    required this.slope,
    required this.frequencyHz,
    required this.sampleRateHz,
    required this.stages,
    required this.status,
    required this.warnings,
    required this.summary,
  });

  int get stageCount => stages.length;

  bool get requiresVerification =>
      status == CrossoverTopologyStatus.requiresVerification ||
      stages.any((s) =>
          s.status == CrossoverTopologyStatus.requiresVerification ||
          s.status == CrossoverTopologyStatus.unsupported);

  bool get hasUnsupportedStages =>
      stages.any((s) => s.status == CrossoverTopologyStatus.unsupported);

  Map<String, dynamic> toJson() => {
    'id': id,
    'channelId': channelId,
    'sourceBlockId': sourceBlockId,
    'shape': shape.toJson(),
    'family': family.toJson(),
    'slope': slope.toJson(),
    'frequencyHz': frequencyHz,
    'sampleRateHz': sampleRateHz,
    'stages': stages.map((s) => s.toJson()).toList(),
    'status': status.toJson(),
    'warnings': warnings,
    'summary': summary,
  };

  factory CrossoverTopologyPlan.fromJson(Map<String, dynamic> j) =>
      CrossoverTopologyPlan(
        id: j['id'] as String? ?? '',
        channelId: j['channelId'] as String? ?? '',
        sourceBlockId: j['sourceBlockId'] as String? ?? '',
        shape: CrossoverFilterShape.fromJson(j['shape'] as String? ?? 'bypass'),
        family: CrossoverFilterFamily.fromJson(
            j['family'] as String? ?? 'unknown'),
        slope: XoSlope.fromJson(j['slope'] as String? ?? 'slope24'),
        frequencyHz: (j['frequencyHz'] as num?)?.toDouble() ?? 1000.0,
        sampleRateHz: (j['sampleRateHz'] as num?)?.toDouble() ?? 48000.0,
        stages: (j['stages'] as List? ?? [])
            .map((e) => CrossoverCascadeStagePlan.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
        status: CrossoverTopologyStatus.fromJson(
            j['status'] as String? ?? 'placeholder'),
        warnings: List<String>.from(j['warnings'] as List? ?? []),
        summary: j['summary'] as String? ?? '',
      );
}

// ── Planner ───────────────────────────────────────────────────────────────────

class CrossoverTopologyPlanner {
  static const _draftNote =
      'Floating-point draft only. Not ADAU fixed-point. No hardware address.';

  // ── Butterworth Q tables (exact polynomial roots) ─────────────────────────
  // These are standard Butterworth biquad Q values per pole pair.
  // Still floating-point draft — not converted to fixed-point format.
  static const _bwQ4 = [0.5412, 1.3066]; // 4th-order (24 dB/oct)
  static const _bwQ6 = [0.5177, 0.7071, 1.9319]; // 6th-order (36 dB/oct)
  static const _bwQ8 = [0.5098, 0.6013, 0.8999, 2.5628]; // 8th-order (48 dB/oct)

  static CrossoverTopologyPlan plan(CrossoverTopologyInput input) {
    int seq = 0;
    String nextId() =>
        'xo_${DateTime.now().millisecondsSinceEpoch}_${seq++}';

    if (input.shape == CrossoverFilterShape.bypass ||
        input.shape == CrossoverFilterShape.bandPass) {
      return _bypass(input, nextId());
    }

    if (input.frequencyHz <= 0 ||
        input.frequencyHz >= input.sampleRateHz / 2.0) {
      return _invalid(input, nextId(),
          'Crossover frequency ${input.frequencyHz.toStringAsFixed(1)} Hz is '
          'invalid for sample rate ${input.sampleRateHz.toStringAsFixed(0)} Hz.');
    }

    return switch (input.family) {
      CrossoverFilterFamily.butterworth   => _butterworth(input, nextId),
      CrossoverFilterFamily.linkwitzRiley => _linkwitzRiley(input, nextId),
      CrossoverFilterFamily.bessel        => _unimplemented(input, nextId(),
          'Bessel topology constants are not implemented in Phase K.'),
      CrossoverFilterFamily.custom        => _unimplemented(input, nextId(),
          'Custom crossover topology requires manual coefficient definition.'),
      CrossoverFilterFamily.unknown       => _unimplemented(input, nextId(),
          'Unknown crossover family — cannot generate cascade.'),
    };
  }

  // ── Butterworth ───────────────────────────────────────────────────────────

  static CrossoverTopologyPlan _butterworth(
      CrossoverTopologyInput inp, String Function() nextId) {
    final warnings = <String>[];

    switch (inp.slope) {
      case XoSlope.slope12:
        final q = inp.q ?? 0.7071;
        return _buildPlan(
          input: inp,
          id: nextId(),
          qValues: [q],
          status: CrossoverTopologyStatus.draft,
          warnings: warnings,
          warning: _draftNote,
        );

      case XoSlope.slope24:
        warnings.add(
            'Draft Butterworth cascade. '
            'Final topology constants require verification.');
        return _buildPlan(
          input: inp,
          id: nextId(),
          qValues: _bwQ4.toList(),
          status: CrossoverTopologyStatus.draft,
          warnings: warnings,
          warning: 'BW24 cascade Stage. $_draftNote',
        );

      case XoSlope.slope36:
        warnings.add(
            'Draft Butterworth 36 dB/oct cascade. '
            'Final topology constants require verification.');
        return _buildPlan(
          input: inp,
          id: nextId(),
          qValues: _bwQ6.toList(),
          status: CrossoverTopologyStatus.draft,
          warnings: warnings,
          warning: 'BW36 cascade Stage. $_draftNote',
        );

      case XoSlope.slope48:
        warnings.add(
            'Draft Butterworth 48 dB/oct cascade. '
            'Final topology constants require verification.');
        return _buildPlan(
          input: inp,
          id: nextId(),
          qValues: _bwQ8.toList(),
          status: CrossoverTopologyStatus.draft,
          warnings: warnings,
          warning: 'BW48 cascade Stage. $_draftNote',
        );

      case XoSlope.slope6:
      case XoSlope.slope18:
      case XoSlope.custom:
        return _unimplemented(
            inp, nextId(),
            'Butterworth ${inp.slope.label} is not supported in Phase K cascade planner.');
    }
  }

  // ── Linkwitz-Riley ────────────────────────────────────────────────────────

  static CrossoverTopologyPlan _linkwitzRiley(
      CrossoverTopologyInput inp, String Function() nextId) {
    final warnings = <String>[];

    switch (inp.slope) {
      case XoSlope.slope12:
        // LR12 = two 1st-order Butterworth cascaded, approximated as 1 biquad draft
        warnings.add('LR12 draft topology requires acoustic verification.');
        return _buildPlan(
          input: inp,
          id: nextId(),
          qValues: [0.5], // approximate for 1st-order cascade packed into biquad
          status: CrossoverTopologyStatus.draft,
          warnings: warnings,
          warning: 'LR12 draft — 1-pole approximation in biquad form. $_draftNote',
        );

      case XoSlope.slope24:
        // LR24 = two cascaded 2nd-order Butterworth Q=0.7071 each
        warnings.add(
            'LR24 draft cascade generated as two 2nd-order sections. '
            'Final acoustic summation requires verification.');
        return _buildPlan(
          input: inp,
          id: nextId(),
          qValues: [0.7071, 0.7071],
          status: CrossoverTopologyStatus.draft,
          warnings: warnings,
          warning: 'LR24 cascade Stage. $_draftNote',
        );

      case XoSlope.slope48:
        // LR48 = four cascaded 2nd-order Butterworth Q=0.7071 each
        warnings.add(
            'LR48 cascade is placeholder-grade and requires verification.');
        return _buildPlan(
          input: inp,
          id: nextId(),
          qValues: [0.7071, 0.7071, 0.7071, 0.7071],
          status: CrossoverTopologyStatus.requiresVerification,
          warnings: warnings,
          warning: 'LR48 cascade Stage. Placeholder-grade. $_draftNote',
        );

      case XoSlope.slope36:
        // LR36 not a standard LR slope
        warnings.add('LR36 is not a standard Linkwitz-Riley slope. Requires verification.');
        return _buildPlan(
          input: inp,
          id: nextId(),
          qValues: [0.7071, 0.7071, 0.7071],
          status: CrossoverTopologyStatus.requiresVerification,
          warnings: warnings,
          warning: 'LR36 non-standard. $_draftNote',
        );

      case XoSlope.slope6:
      case XoSlope.slope18:
      case XoSlope.custom:
        return _unimplemented(
            inp, nextId(),
            'Linkwitz-Riley ${inp.slope.label} is not supported in Phase K.');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static CrossoverTopologyPlan _buildPlan({
    required CrossoverTopologyInput input,
    required String id,
    required List<double> qValues,
    required CrossoverTopologyStatus status,
    required List<String> warnings,
    String? warning,
  }) {
    final stages = <CrossoverCascadeStagePlan>[];
    final total = qValues.length;

    for (var i = 0; i < total; i++) {
      stages.add(CrossoverCascadeStagePlan(
        id: '${id}_s$i',
        channelId: input.channelId,
        shape: input.shape,
        family: input.family,
        slope: input.slope,
        stageIndex: i,
        totalStages: total,
        frequencyHz: input.frequencyHz,
        q: qValues[i],
        filterType: input.shape.biquadType,
        status: status,
        summary: '${input.shape.label} ${input.family.short}${input.slope.short} '
            'Stage ${i + 1}/$total  '
            '${input.frequencyHz.toStringAsFixed(0)} Hz  Q${qValues[i].toStringAsFixed(4)}  '
            '@ ${(input.sampleRateHz / 1000).toStringAsFixed(0)} kHz',
        warning: warning,
      ));
    }

    return CrossoverTopologyPlan(
      id: id,
      channelId: input.channelId,
      sourceBlockId: input.sourceBlockId,
      shape: input.shape,
      family: input.family,
      slope: input.slope,
      frequencyHz: input.frequencyHz,
      sampleRateHz: input.sampleRateHz,
      stages: stages,
      status: status,
      warnings: warnings,
      summary: '${input.shape.label} ${input.family.label} ${input.slope.label} '
          '— $total stage(s)  '
          '${input.frequencyHz.toStringAsFixed(0)} Hz  '
          '@ ${(input.sampleRateHz / 1000).toStringAsFixed(0)} kHz',
    );
  }

  static CrossoverTopologyPlan _bypass(
      CrossoverTopologyInput input, String id) =>
      CrossoverTopologyPlan(
        id: id,
        channelId: input.channelId,
        sourceBlockId: input.sourceBlockId,
        shape: input.shape,
        family: input.family,
        slope: input.slope,
        frequencyHz: input.frequencyHz,
        sampleRateHz: input.sampleRateHz,
        stages: const [],
        status: CrossoverTopologyStatus.placeholder,
        warnings: const ['Bypass or bandpass — no cascade stages generated.'],
        summary: 'Bypass',
      );

  static CrossoverTopologyPlan _invalid(
      CrossoverTopologyInput input, String id, String reason) =>
      CrossoverTopologyPlan(
        id: id,
        channelId: input.channelId,
        sourceBlockId: input.sourceBlockId,
        shape: input.shape,
        family: input.family,
        slope: input.slope,
        frequencyHz: input.frequencyHz,
        sampleRateHz: input.sampleRateHz,
        stages: const [],
        status: CrossoverTopologyStatus.unsupported,
        warnings: [reason],
        summary: 'Invalid: $reason',
      );

  static CrossoverTopologyPlan _unimplemented(
      CrossoverTopologyInput input, String id, String reason) =>
      CrossoverTopologyPlan(
        id: id,
        channelId: input.channelId,
        sourceBlockId: input.sourceBlockId,
        shape: input.shape,
        family: input.family,
        slope: input.slope,
        frequencyHz: input.frequencyHz,
        sampleRateHz: input.sampleRateHz,
        stages: const [],
        status: CrossoverTopologyStatus.requiresVerification,
        warnings: [reason, _draftNote],
        summary: 'Unsupported: $reason',
      );
}
