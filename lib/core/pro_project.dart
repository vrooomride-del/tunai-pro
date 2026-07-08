import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ProfileStatus { draft, reviewing, verified, deployed }
enum SafetyStatus { notVerified, checking, passed, failed }
enum HardwareConnection { none, usb, network, bluetooth }

class ProProject {
  final String name;
  final String deviceName;
  final int sampleRate;
  final String dspTarget;
  final ProfileStatus profileStatus;
  final SafetyStatus safetyStatus;
  final HardwareConnection connection;

  const ProProject({
    this.name = 'Untitled Project',
    this.deviceName = 'Not connected',
    this.sampleRate = 48000,
    this.dspTarget = 'Not selected',
    this.profileStatus = ProfileStatus.draft,
    this.safetyStatus = SafetyStatus.notVerified,
    this.connection = HardwareConnection.none,
  });

  ProProject copyWith({
    String? name,
    String? deviceName,
    int? sampleRate,
    String? dspTarget,
    ProfileStatus? profileStatus,
    SafetyStatus? safetyStatus,
    HardwareConnection? connection,
  }) => ProProject(
    name: name ?? this.name,
    deviceName: deviceName ?? this.deviceName,
    sampleRate: sampleRate ?? this.sampleRate,
    dspTarget: dspTarget ?? this.dspTarget,
    profileStatus: profileStatus ?? this.profileStatus,
    safetyStatus: safetyStatus ?? this.safetyStatus,
    connection: connection ?? this.connection,
  );

  String get sampleRateLabel => '${(sampleRate / 1000).toStringAsFixed(0)} kHz';

  String get profileStatusLabel => switch (profileStatus) {
    ProfileStatus.draft => 'Draft',
    ProfileStatus.reviewing => 'Under Review',
    ProfileStatus.verified => 'Verified',
    ProfileStatus.deployed => 'Deployed',
  };

  String get safetyStatusLabel => switch (safetyStatus) {
    SafetyStatus.notVerified => 'Not verified',
    SafetyStatus.checking => 'Checking...',
    SafetyStatus.passed => 'Passed',
    SafetyStatus.failed => 'Failed',
  };
}

class ProProjectNotifier extends StateNotifier<ProProject> {
  ProProjectNotifier() : super(const ProProject());

  void setName(String name) => state = state.copyWith(name: name);
  void setDspTarget(String target) => state = state.copyWith(dspTarget: target);
  void setProfileStatus(ProfileStatus s) => state = state.copyWith(profileStatus: s);
  void setSafetyStatus(SafetyStatus s) => state = state.copyWith(safetyStatus: s);
  void setConnection(HardwareConnection c, String device) =>
      state = state.copyWith(connection: c, deviceName: device);
  void reset() => state = const ProProject();
}

final proProjectProvider =
    StateNotifierProvider<ProProjectNotifier, ProProject>(
        (ref) => ProProjectNotifier());
