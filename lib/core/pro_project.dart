import 'dart:convert';
import 'pro_acoustic_data.dart';
import 'pro_tuning_data.dart';
import 'pro_protection_data.dart';

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
  static ProfileStatus fromJson(String s) =>
      ProfileStatus.values.firstWhere((e) => e.name == s, orElse: () => ProfileStatus.draft);
}

extension SafetyStatusX on SafetyStatus {
  String get label => switch (this) {
    SafetyStatus.notVerified => 'Not verified',
    SafetyStatus.verified => 'Verified',
    SafetyStatus.warning => 'Warning',
    SafetyStatus.blocked => 'Blocked',
  };

  String toJson() => name;
  static SafetyStatus fromJson(String s) =>
      SafetyStatus.values.firstWhere((e) => e.name == s, orElse: () => SafetyStatus.notVerified);
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
      HardwareConnection.values.firstWhere((e) => e.name == s, orElse: () => HardwareConnection.disconnected);
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
  }) : acousticState = acousticState ?? MeasurementProjectState.createDefault(),
       tuningState = tuningState ?? TuningProjectState.createDefault(),
       protectionState = protectionState ?? ProtectionProjectState.createDefault();

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
  }) => ProProject(
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
  };

  factory ProProject.fromJson(Map<String, dynamic> j) => ProProject(
    id: j['id'] as String,
    name: j['name'] as String? ?? 'Untitled',
    speakerModel: j['speakerModel'] as String? ?? 'TUNAI ONE',
    roomName: j['roomName'] as String? ?? 'Desk',
    createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
    sampleRate: j['sampleRate'] as int? ?? 48000,
    dspTarget: j['dspTarget'] as String? ?? 'ADAU1701',
    channelConfig: j['channelConfig'] as String? ?? '2-way stereo',
    profileStatus: ProfileStatusX.fromJson(j['profileStatus'] as String? ?? 'draft'),
    safetyStatus: SafetyStatusX.fromJson(j['safetyStatus'] as String? ?? 'notVerified'),
    connection: HardwareConnectionX.fromJson(j['connection'] as String? ?? 'disconnected'),
    notes: j['notes'] as String?,
    measurementCount: j['measurementCount'] as int? ?? 0,
    activeProfileName: j['activeProfileName'] as String?,
    acousticState: j['acousticState'] != null
        ? MeasurementProjectState.fromJson(Map<String, dynamic>.from(j['acousticState'] as Map))
        : null,
    tuningState: j['tuningState'] != null
        ? TuningProjectState.fromJson(Map<String, dynamic>.from(j['tuningState'] as Map))
        : null,
    protectionState: j['protectionState'] != null
        ? ProtectionProjectState.fromJson(Map<String, dynamic>.from(j['protectionState'] as Map))
        : null,
  );

  static String encodeList(List<ProProject> list) =>
      jsonEncode(list.map((p) => p.toJson()).toList());

  static List<ProProject> decodeList(String raw) {
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => ProProject.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return [];
    }
  }
}
