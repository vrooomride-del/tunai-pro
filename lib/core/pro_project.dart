import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'factory_sound_profile.dart';
import 'pro_acoustic_data.dart';
import 'pro_correction_cycle.dart';
import 'pro_tuning_data.dart';
import 'pro_protection_data.dart';
import 'pro_optimizer_data.dart';
import 'pro_export_data.dart';
import 'pro_simulation_data.dart';
import 'pro_hardware_connection_data.dart';
import 'pro_deploy_package_data.dart';
import 'pro_address_validation_data.dart';
import 'room_measurement_data.dart';
import 'calibration/calibration_types.dart';
import 'measurement/measurement_input_device.dart';
import 'measurement/measurement_setup_readiness.dart';

enum ProfileStatus { draft, measured, tuned, verified, deployed }

enum SafetyStatus { notVerified, verified, warning, blocked }

enum HardwareConnection { disconnected, connected, simulation, error }

extension ProfileStatusX on ProfileStatus {
  String get label => switch (this) {
        ProfileStatus.draft => 'Draft',
        ProfileStatus.measured => 'Measured',
        ProfileStatus.tuned => 'Tuned',
        ProfileStatus.verified => 'Verified',
        ProfileStatus.deployed => 'Deployed',
      };

  bool isAtLeast(ProfileStatus other) => index >= other.index;

  String toJson() => name;
  static ProfileStatus fromJson(String s) => ProfileStatus.values
      .firstWhere((e) => e.name == s, orElse: () => ProfileStatus.draft);
}

extension SafetyStatusX on SafetyStatus {
  String get label => switch (this) {
        SafetyStatus.notVerified => 'Not verified',
        SafetyStatus.verified => 'Verified',
        SafetyStatus.warning => 'Warning',
        SafetyStatus.blocked => 'Blocked',
      };

  String toJson() => name;
  static SafetyStatus fromJson(String s) => SafetyStatus.values
      .firstWhere((e) => e.name == s, orElse: () => SafetyStatus.notVerified);
}

extension HardwareConnectionX on HardwareConnection {
  String get label => switch (this) {
        HardwareConnection.disconnected => 'Not connected',
        HardwareConnection.connected => 'Connected',
        HardwareConnection.simulation => 'Simulation',
        HardwareConnection.error => 'Error',
      };

  String toJson() => name;
  static HardwareConnection fromJson(String s) =>
      HardwareConnection.values.firstWhere((e) => e.name == s,
          orElse: () => HardwareConnection.disconnected);
}

class ProProject {
  final String id;
  final String name;
  final String speakerModel;
  final String roomName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int sampleRate;
  final String dspTarget;
  final String channelConfig;
  final ProfileStatus profileStatus;
  final SafetyStatus safetyStatus;
  final HardwareConnection connection;
  final String? notes;
  final int measurementCount;
  final String? activeProfileName;
  final MeasurementProjectState acousticState;
  final TuningProjectState tuningState;
  final ProtectionProjectState protectionState;
  final OptimizerProjectState optimizerState;
  final ExportProjectState exportState;
  final SimulationProjectState simulationState;
  final HardwareProjectState hardwareState;
  final DeployProjectState deployState;
  final AddressValidationProjectState addressValidationState;
  final RoomMeasurementProjectState roomState;

  /// The measurement microphone currently selected for THIS project only —
  /// never shared with or inherited by any other project. Null means no
  /// microphone has been selected; this phase never fabricates a default
  /// profile (calibrated or otherwise) to fill that gap.
  ///
  /// Changing this only affects readiness for NEW measurements going
  /// forward — every past measurement already carries its own immutable
  /// [MeasurementMicrophoneSnapshot] (see ParsedMeasurementData
  /// .microphoneSnapshot / RoomSystemMeasurement.frd.microphoneSnapshot),
  /// so editing or replacing this field can never retroactively change what
  /// an already-captured measurement means.
  final MeasurementMicrophoneProfile? selectedMicrophoneProfile;

  /// This project's user-managed microphone profile roster (Phase 3-C
  /// Profile Manager) — every profile the user has registered for this
  /// project, independent of which one (if any) is currently
  /// [selectedMicrophoneProfile]. Never shared with or inherited by any
  /// other project. Selecting a roster entry copies its CURRENT value into
  /// [selectedMicrophoneProfile]; editing a roster entry afterward never
  /// retroactively changes a measurement already captured under the
  /// previous value (see [MeasurementMicrophoneSnapshot]).
  final List<MeasurementMicrophoneProfile> microphoneProfiles;

  /// This project's current OS input-device selection (Phase 3-D1
  /// foundation) — never shared with or inherited by any other project.
  /// Null means no selection has been made (legacy or never-set project);
  /// this is distinct from an explicit system-default selection, which is
  /// represented by a non-null [MeasurementInputDeviceSelection] with
  /// `useSystemDefault: true`. Not yet consulted by any capture/gate path
  /// in this phase — persistence only.
  final MeasurementInputDeviceSelection? selectedInputDevice;

  /// This project's most recent Guided Measurement Setup check (Phase
  /// 3-D2) — never shared across projects. A snapshot's own `isStaleFor`/
  /// `isExpired`/`isUsableNow` (see MeasurementSetupReadinessSnapshot) must
  /// always be re-checked against the project's CURRENT identity before
  /// treating it as usable — this field may hold a snapshot that has since
  /// gone stale or expired; storing it does not mean it is still valid.
  /// Not yet consulted by any Capture gate in this phase — persistence and
  /// display only (see MicrophoneStatusCard / GuidedMeasurementSetupDialog).
  final MeasurementSetupReadinessSnapshot? currentSetupReadiness;

  /// Closed-loop correction cycles for this project.
  /// Each entry records one before/apply/deploy/after pass.
  final List<CorrectionCycle> correctionCycles;

  /// Immutable Factory Sound Profile snapshots for this project.
  /// Profiles are append-only: existing entries are never modified after creation.
  final List<FactorySoundProfile> factoryProfiles;

  ProProject({
    required this.id,
    required this.name,
    this.speakerModel = 'TUNAI ONE',
    this.roomName = 'Desk',
    required this.createdAt,
    required this.updatedAt,
    this.sampleRate = 48000,
    this.dspTarget = 'ADAU1701',
    this.channelConfig = '2-way stereo',
    this.profileStatus = ProfileStatus.draft,
    this.safetyStatus = SafetyStatus.notVerified,
    this.connection = HardwareConnection.disconnected,
    this.notes,
    this.measurementCount = 0,
    this.activeProfileName,
    MeasurementProjectState? acousticState,
    TuningProjectState? tuningState,
    ProtectionProjectState? protectionState,
    OptimizerProjectState? optimizerState,
    ExportProjectState? exportState,
    SimulationProjectState? simulationState,
    HardwareProjectState? hardwareState,
    DeployProjectState? deployState,
    AddressValidationProjectState? addressValidationState,
    RoomMeasurementProjectState? roomState,
    this.selectedMicrophoneProfile,
    this.microphoneProfiles = const [],
    this.selectedInputDevice,
    this.currentSetupReadiness,
    this.correctionCycles = const [],
    this.factoryProfiles = const [],
  })  : acousticState =
            acousticState ?? MeasurementProjectState.createDefault(),
        tuningState = tuningState ?? TuningProjectState.createDefault(),
        protectionState =
            protectionState ?? ProtectionProjectState.createDefault(),
        optimizerState =
            optimizerState ?? OptimizerProjectState.createDefault(),
        exportState = exportState ?? ExportProjectState.createDefault(),
        simulationState =
            simulationState ?? SimulationProjectState.createDefault(),
        hardwareState = hardwareState ?? HardwareProjectState.createDefault(),
        deployState = deployState ?? DeployProjectState.createDefault(),
        addressValidationState = addressValidationState ??
            AddressValidationProjectState.createDefault(),
        roomState = roomState ?? RoomMeasurementProjectState.createDefault();

  factory ProProject.create({
    required String name,
    String speakerModel = 'TUNAI ONE',
    String roomName = 'Desk',
    int sampleRate = 48000,
    String dspTarget = 'ADAU1701',
    String channelConfig = '2-way stereo',
  }) {
    final now = DateTime.now();
    return ProProject(
      id: now.millisecondsSinceEpoch.toString(),
      name: name,
      speakerModel: speakerModel,
      roomName: roomName,
      createdAt: now,
      updatedAt: now,
      sampleRate: sampleRate,
      dspTarget: dspTarget,
      channelConfig: channelConfig,
    );
  }

  ProProject copyWith({
    String? name,
    String? speakerModel,
    String? roomName,
    DateTime? updatedAt,
    int? sampleRate,
    String? dspTarget,
    String? channelConfig,
    ProfileStatus? profileStatus,
    SafetyStatus? safetyStatus,
    HardwareConnection? connection,
    String? notes,
    int? measurementCount,
    String? activeProfileName,
    MeasurementProjectState? acousticState,
    TuningProjectState? tuningState,
    ProtectionProjectState? protectionState,
    OptimizerProjectState? optimizerState,
    ExportProjectState? exportState,
    SimulationProjectState? simulationState,
    HardwareProjectState? hardwareState,
    DeployProjectState? deployState,
    AddressValidationProjectState? addressValidationState,
    RoomMeasurementProjectState? roomState,
    MeasurementMicrophoneProfile? selectedMicrophoneProfile,
    bool clearSelectedMicrophoneProfile = false,
    List<MeasurementMicrophoneProfile>? microphoneProfiles,
    MeasurementInputDeviceSelection? selectedInputDevice,
    bool clearSelectedInputDevice = false,
    MeasurementSetupReadinessSnapshot? currentSetupReadiness,
    bool clearCurrentSetupReadiness = false,
    List<CorrectionCycle>? correctionCycles,
    List<FactorySoundProfile>? factoryProfiles,
  }) =>
      ProProject(
        id: id,
        name: name ?? this.name,
        speakerModel: speakerModel ?? this.speakerModel,
        roomName: roomName ?? this.roomName,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        sampleRate: sampleRate ?? this.sampleRate,
        dspTarget: dspTarget ?? this.dspTarget,
        channelConfig: channelConfig ?? this.channelConfig,
        profileStatus: profileStatus ?? this.profileStatus,
        safetyStatus: safetyStatus ?? this.safetyStatus,
        connection: connection ?? this.connection,
        notes: notes ?? this.notes,
        measurementCount: measurementCount ?? this.measurementCount,
        activeProfileName: activeProfileName ?? this.activeProfileName,
        acousticState: acousticState ?? this.acousticState,
        tuningState: tuningState ?? this.tuningState,
        protectionState: protectionState ?? this.protectionState,
        optimizerState: optimizerState ?? this.optimizerState,
        exportState: exportState ?? this.exportState,
        simulationState: simulationState ?? this.simulationState,
        hardwareState: hardwareState ?? this.hardwareState,
        deployState: deployState ?? this.deployState,
        addressValidationState:
            addressValidationState ?? this.addressValidationState,
        roomState: roomState ?? this.roomState,
        selectedMicrophoneProfile: clearSelectedMicrophoneProfile
            ? null
            : (selectedMicrophoneProfile ?? this.selectedMicrophoneProfile),
        microphoneProfiles: microphoneProfiles ?? this.microphoneProfiles,
        selectedInputDevice: clearSelectedInputDevice
            ? null
            : (selectedInputDevice ?? this.selectedInputDevice),
        currentSetupReadiness: clearCurrentSetupReadiness
            ? null
            : (currentSetupReadiness ?? this.currentSetupReadiness),
        correctionCycles: correctionCycles ?? this.correctionCycles,
        factoryProfiles: factoryProfiles ?? this.factoryProfiles,
      );

  ProProject touch() => copyWith(updatedAt: DateTime.now());

  String get sampleRateLabel => '${(sampleRate / 1000).toStringAsFixed(0)} kHz';
  String get deviceName => connection.label;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'speakerModel': speakerModel,
        'roomName': roomName,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'sampleRate': sampleRate,
        'dspTarget': dspTarget,
        'channelConfig': channelConfig,
        'profileStatus': profileStatus.toJson(),
        'safetyStatus': safetyStatus.toJson(),
        'connection': connection.toJson(),
        if (notes != null) 'notes': notes,
        'measurementCount': measurementCount,
        if (activeProfileName != null) 'activeProfileName': activeProfileName,
        'acousticState': acousticState.toJson(),
        'tuningState': tuningState.toJson(),
        'protectionState': protectionState.toJson(),
        'optimizerState': optimizerState.toJson(),
        'exportState': exportState.toJson(),
        'simulationState': simulationState.toJson(),
        'hardwareState': hardwareState.toJson(),
        'deployState': deployState.toJson(),
        'addressValidationState': addressValidationState.toJson(),
        'roomState': roomState.toJson(),
        if (selectedMicrophoneProfile != null)
          'selectedMicrophoneProfile': selectedMicrophoneProfile!.toJson(),
        if (microphoneProfiles.isNotEmpty)
          'microphoneProfiles':
              microphoneProfiles.map((p) => p.toJson()).toList(),
        if (selectedInputDevice != null)
          'selectedInputDevice': selectedInputDevice!.toJson(),
        if (currentSetupReadiness != null)
          'currentSetupReadiness': currentSetupReadiness!.toJson(),
        if (correctionCycles.isNotEmpty)
          'correctionCycles': correctionCycles.map((c) => c.toJson()).toList(),
        if (factoryProfiles.isNotEmpty)
          'factoryProfiles': factoryProfiles.map((p) => p.toJson()).toList(),
      };

  factory ProProject.fromJson(Map<String, dynamic> j) => ProProject(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Untitled',
        speakerModel: j['speakerModel'] as String? ?? 'TUNAI ONE',
        roomName: j['roomName'] as String? ?? 'Desk',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ??
            DateTime.now(),
        sampleRate: j['sampleRate'] as int? ?? 48000,
        dspTarget: j['dspTarget'] as String? ?? 'ADAU1701',
        channelConfig: j['channelConfig'] as String? ?? '2-way stereo',
        profileStatus:
            ProfileStatusX.fromJson(j['profileStatus'] as String? ?? 'draft'),
        safetyStatus: SafetyStatusX.fromJson(
            j['safetyStatus'] as String? ?? 'notVerified'),
        connection: HardwareConnectionX.fromJson(
            j['connection'] as String? ?? 'disconnected'),
        notes: j['notes'] as String?,
        measurementCount: j['measurementCount'] as int? ?? 0,
        activeProfileName: j['activeProfileName'] as String?,
        acousticState: j['acousticState'] != null
            ? MeasurementProjectState.fromJson(
                Map<String, dynamic>.from(j['acousticState'] as Map))
            : null,
        tuningState: j['tuningState'] != null
            ? TuningProjectState.fromJson(
                Map<String, dynamic>.from(j['tuningState'] as Map))
            : null,
        protectionState: j['protectionState'] != null
            ? ProtectionProjectState.fromJson(
                Map<String, dynamic>.from(j['protectionState'] as Map))
            : null,
        optimizerState: j['optimizerState'] != null
            ? OptimizerProjectState.fromJson(
                Map<String, dynamic>.from(j['optimizerState'] as Map))
            : null,
        exportState: j['exportState'] != null
            ? ExportProjectState.fromJson(
                Map<String, dynamic>.from(j['exportState'] as Map))
            : null,
        simulationState: j['simulationState'] != null
            ? SimulationProjectState.fromJson(
                Map<String, dynamic>.from(j['simulationState'] as Map))
            : null,
        hardwareState: j['hardwareState'] != null
            ? HardwareProjectState.fromJson(
                Map<String, dynamic>.from(j['hardwareState'] as Map))
            : null,
        deployState: j['deployState'] != null
            ? DeployProjectState.fromJson(
                Map<String, dynamic>.from(j['deployState'] as Map))
            : null,
        addressValidationState: j['addressValidationState'] != null
            ? AddressValidationProjectState.fromJson(
                Map<String, dynamic>.from(j['addressValidationState'] as Map))
            : null,
        roomState: _decodeRoomState(j['roomState']),
        selectedMicrophoneProfile:
            _decodeSelectedMicrophoneProfile(j['selectedMicrophoneProfile']),
        microphoneProfiles: _decodeMicrophoneProfiles(j['microphoneProfiles']),
        selectedInputDevice:
            _decodeSelectedInputDevice(j['selectedInputDevice']),
        currentSetupReadiness:
            _decodeCurrentSetupReadiness(j['currentSetupReadiness']),
        correctionCycles: (j['correctionCycles'] as List? ?? [])
            .map((e) =>
                CorrectionCycle.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        factoryProfiles: (j['factoryProfiles'] as List? ?? [])
            .map((e) => FactorySoundProfile.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  /// Isolated decode: a malformed roomState (e.g. from a future schema this
  /// build doesn't understand) must not fail the whole project decode — the
  /// rest of the project (driverChannels FRD, PEQ, XO, gain, delay) still
  /// needs to load. Falls back to an empty Room state.
  static RoomMeasurementProjectState _decodeRoomState(Object? raw) {
    if (raw == null) return RoomMeasurementProjectState.createDefault();
    try {
      return RoomMeasurementProjectState.fromJson(
          Map<String, dynamic>.from(raw as Map));
    } catch (e) {
      debugPrint('ProProject: skipping unparsable roomState ($e)');
      return RoomMeasurementProjectState.createDefault();
    }
  }

  /// Isolated decode: a corrupt selectedMicrophoneProfile must not fail the
  /// whole project decode, and must never silently become a fabricated
  /// default profile — falls back to null (no microphone selected).
  static MeasurementMicrophoneProfile? _decodeSelectedMicrophoneProfile(
      Object? raw) {
    if (raw == null) return null;
    try {
      return MeasurementMicrophoneProfile.fromJson(
          Map<String, dynamic>.from(raw as Map));
    } catch (e) {
      debugPrint(
          'ProProject: skipping unparsable selectedMicrophoneProfile ($e)');
      return null;
    }
  }

  /// Isolated, per-entry resilient decode: one corrupt roster entry must not
  /// wipe the rest of the roster or fail the whole project decode.
  static List<MeasurementMicrophoneProfile> _decodeMicrophoneProfiles(
      Object? raw) {
    if (raw is! List) return const [];
    final result = <MeasurementMicrophoneProfile>[];
    for (final e in raw) {
      try {
        result.add(MeasurementMicrophoneProfile.fromJson(
            Map<String, dynamic>.from(e as Map)));
      } catch (err) {
        debugPrint(
            'ProProject: skipping unparsable microphoneProfiles entry ($err)');
      }
    }
    return result;
  }

  /// Isolated decode: a corrupt selectedInputDevice must not fail the whole
  /// project decode, and must never silently become a fabricated selection
  /// — falls back to null (no input device selected).
  static MeasurementInputDeviceSelection? _decodeSelectedInputDevice(
      Object? raw) {
    if (raw == null) return null;
    try {
      return MeasurementInputDeviceSelection.fromJson(
          Map<String, dynamic>.from(raw as Map));
    } catch (e) {
      debugPrint('ProProject: skipping unparsable selectedInputDevice ($e)');
      return null;
    }
  }

  /// Isolated decode: a corrupt currentSetupReadiness must not fail the
  /// whole project decode, and must never silently become a fabricated
  /// (worse, falsely-Ready) readiness — falls back to null (no readiness
  /// on record; the UI treats that identically to "never checked").
  static MeasurementSetupReadinessSnapshot? _decodeCurrentSetupReadiness(
      Object? raw) {
    if (raw == null) return null;
    try {
      return MeasurementSetupReadinessSnapshot.fromJson(
          Map<String, dynamic>.from(raw as Map));
    } catch (e) {
      debugPrint('ProProject: skipping unparsable currentSetupReadiness ($e)');
      return null;
    }
  }

  static String encodeList(List<ProProject> list) =>
      jsonEncode(list.map((p) => p.toJson()).toList());

  /// Decodes a persisted project list, isolating each entry's parse so one
  /// corrupt or pre-migration project cannot wipe every other saved project.
  /// Unparsable entries are skipped and logged (no raw JSON/PII in the log).
  static List<ProProject> decodeList(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e) {
      debugPrint(
          'ProProject.decodeList: invalid JSON root, returning empty list ($e)');
      return [];
    }
    if (decoded is! List) {
      debugPrint(
          'ProProject.decodeList: root is not a list (${decoded.runtimeType}), returning empty list');
      return [];
    }
    final result = <ProProject>[];
    for (var i = 0; i < decoded.length; i++) {
      try {
        result.add(
            ProProject.fromJson(Map<String, dynamic>.from(decoded[i] as Map)));
      } catch (e) {
        debugPrint(
            'ProProject.decodeList: skipping unparsable project at index $i ($e)');
      }
    }
    return result;
  }
}
