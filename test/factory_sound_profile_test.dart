// Tests for FactorySoundProfile, FactoryProfileBuilder, FactoryProfileExporter.
//
// Groups A–I match the task specification.
// No DSP write, no hardware reference, no I/O in the code under test.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tunai_pro/core/factory_profile_builder.dart';
import 'package:tunai_pro/core/factory_profile_exporter.dart';
import 'package:tunai_pro/core/factory_sound_profile.dart';
import 'package:tunai_pro/core/pro_correction_cycle.dart';
import 'package:tunai_pro/core/pro_measurement_store.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_project_store.dart';
import 'package:tunai_pro/core/pro_protection_data.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/core/pro_tuning_report_data.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// A [ProProject] that satisfies all eligibility rules by default.
ProProject _eligibleProject({
  String id = 'proj_1',
  String dspTarget = 'ADAU1701',
  List<PeqChannelState>? peqChannels,
  List<CorrectionCycle>? correctionCycles,
  ProtectionProjectState? protectionState,
  List<FactorySoundProfile>? factoryProfiles,
  SafetyStatus safetyStatus = SafetyStatus.verified,
}) {
  final now = DateTime.now();
  final tuning = TuningProjectState(
    peqChannels: peqChannels ??
        [
          PeqChannelState.empty('ch_wf'),
          PeqChannelState.empty('ch_tw'),
        ],
  );
  final protection = protectionState ??
      ProtectionProjectState(
        exportLocked: false,
        verificationStatus: VerificationStatus.passed,
      );
  final cycles = correctionCycles ?? [_completedCycle(projectId: id)];

  return ProProject(
    id: id,
    name: 'Test Project',
    createdAt: now,
    updatedAt: now,
    dspTarget: dspTarget,
    tuningState: tuning,
    protectionState: protection,
    correctionCycles: cycles,
    factoryProfiles: factoryProfiles ?? const [],
    safetyStatus: safetyStatus,
  );
}

CorrectionCycle _completedCycle({String projectId = 'proj_1'}) {
  final now = DateTime.now();
  const metrics = CorrectionCycleMetrics(
    commonFreqMinHz: 100,
    commonFreqMaxHz: 10000,
    commonPointCount: 10,
    meanAbsResidualBefore: 4.0,
    meanAbsResidualAfter: 0.5,
    improvementDelta: 3.5,
    peakErrorBefore: 4.0,
    peakErrorBeforeHz: 1000,
    peakErrorAfter: 0.5,
    peakErrorAfterHz: 2000,
    worsenedBandCount: 0,
    improvementCoverage: 1.0,
  );
  return CorrectionCycle(
    projectId: projectId,
    channelId: 'ch_wf',
    cycleNumber: 1,
    beforeMeasurementRef: 'before_ref',
    peqSnapshot: PeqChannelState.empty('ch_wf'),
    createdAt: now,
  ).withAfterResult(
    afterMeasurementRef: 'after_ref',
    afterMeasurementFileName: 'after.frd',
    metrics: metrics,
    decision: CorrectionCycleDecision.improvedAndComplete,
    reasons: ['improvement delta 3.50 dB >= complete threshold 2.0 dB.'],
  );
}

void main() {
// ── A: Valid completed project ────────────────────────────────────────────────

  group('A — valid completed project', () {
    test('A1: profile created from eligible project', () {
      final project = _eligibleProject();
      final profile = FactoryProfileBuilder.build(project);

      expect(profile, isNotNull);
      expect(profile!.projectId, equals('proj_1'));
      expect(profile.hardwareTarget, equals('ADAU1701'));
      expect(profile.version, equals(1));
      expect(profile.completedCycleNumbers, contains(1));
    });

    test('A2: snapshot contains exact PEQ channel state', () {
      final peqChannel = PeqChannelState.fixed('ch_wf');
      final project = _eligibleProject(peqChannels: [peqChannel]);
      final profile = FactoryProfileBuilder.build(project)!;

      expect(profile.tuningSnapshot.peqChannels.length, equals(1));
      expect(
          profile.tuningSnapshot.peqChannels.first.channelId, equals('ch_wf'));
      expect(
        profile.tuningSnapshot.peqChannels.first.bands.length,
        equals(peqChannel.bands.length),
      );
    });

    test('A3: snapshot contains exact protection state', () {
      final protection = ProtectionProjectState(
        exportLocked: false,
        verificationStatus: VerificationStatus.passedWithWarnings,
      );
      final project = _eligibleProject(protectionState: protection);
      final profile = FactoryProfileBuilder.build(project)!;

      expect(profile.protectionSnapshot.verificationStatus,
          equals(VerificationStatus.passedWithWarnings));
      expect(profile.validationStatus, equals('passedWithWarnings'));
    });

    test('A4: profileId, projectId, hardwareTarget, sampleRate present', () {
      final project = _eligibleProject();
      final profile = FactoryProfileBuilder.build(project)!;

      expect(profile.profileId, isNotEmpty);
      expect(profile.projectId, equals('proj_1'));
      expect(profile.hardwareTarget, equals('ADAU1701'));
      expect(profile.sampleRate, equals(48000));
      expect(profile.channelConfig, isNotEmpty);
    });
  });

// ── B: Project changes after profile creation ─────────────────────────────────

  group('B — immutability after project changes', () {
    test('B1: profile snapshot channel count independent of later project edits',
        () {
      final project =
          _eligibleProject(peqChannels: [PeqChannelState.empty('ch_wf')]);
      final profile = FactoryProfileBuilder.build(project)!;

      // Simulate what a later project update would look like.
      final updatedTuning = TuningProjectState(
        peqChannels: [
          PeqChannelState.empty('ch_wf'),
          PeqChannelState.empty('ch_tw'),
        ],
      );

      // Profile snapshot is frozen at build time — still has 1 channel.
      expect(profile.tuningSnapshot.peqChannels.length, equals(1));
      expect(updatedTuning.peqChannels.length, equals(2));
    });

    test('B2: profile JSON round-trip preserves all fields', () {
      final project = _eligibleProject();
      final profile = FactoryProfileBuilder.build(project)!;

      final json = profile.toJson();
      final restored = FactorySoundProfile.fromJson(json);

      expect(restored.profileId, equals(profile.profileId));
      expect(restored.version, equals(profile.version));
      expect(restored.projectFingerprint, equals(profile.projectFingerprint));
      expect(restored.hardwareTarget, equals(profile.hardwareTarget));
      expect(restored.completedCycleNumbers,
          equals(profile.completedCycleNumbers));
      expect(restored.tuningSnapshot.peqChannels.length,
          equals(profile.tuningSnapshot.peqChannels.length));
    });
  });

// ── C: Unchanged re-export ────────────────────────────────────────────────────

  group('C — unchanged fingerprint detection', () {
    test('C1: same project state produces same fingerprint', () {
      final project = _eligibleProject();
      final profile1 = FactoryProfileBuilder.build(project)!;
      final profile2 = FactoryProfileBuilder.build(project)!;

      expect(profile1.projectFingerprint, equals(profile2.projectFingerprint));
    });

    test('C2: isUnchanged returns true when DSP state identical', () {
      final project = _eligibleProject();
      final profile = FactoryProfileBuilder.build(project)!;

      expect(FactoryProfileBuilder.isUnchanged(project, profile), isTrue);
    });
  });

// ── D: Changed project state ──────────────────────────────────────────────────

  group('D — changed project state', () {
    test('D1: different tuning state produces different fingerprint', () {
      final project1 =
          _eligibleProject(peqChannels: [PeqChannelState.empty('ch_wf')]);
      final project2 =
          _eligibleProject(peqChannels: [PeqChannelState.fixed('ch_wf')]);

      final profile1 = FactoryProfileBuilder.build(project1)!;
      final profile2 = FactoryProfileBuilder.build(project2)!;

      // fixed() creates different band configuration than empty().
      expect(profile1.projectFingerprint,
          isNot(equals(profile2.projectFingerprint)));
    });

    test('D2: version increments when existing profiles are present', () {
      final existingProfile =
          FactoryProfileBuilder.build(_eligibleProject())!;
      final project = _eligibleProject(factoryProfiles: [existingProfile]);
      final nextProfile = FactoryProfileBuilder.build(project)!;

      // version = factoryProfiles.length + 1 = 2
      expect(nextProfile.version, equals(2));
    });

    test('D3: isUnchanged returns false after tuning change', () {
      final project1 =
          _eligibleProject(peqChannels: [PeqChannelState.empty('ch_wf')]);
      final profile = FactoryProfileBuilder.build(project1)!;

      final project2 =
          _eligibleProject(peqChannels: [PeqChannelState.fixed('ch_wf')]);

      expect(FactoryProfileBuilder.isUnchanged(project2, profile), isFalse);
    });
  });

// ── E: Missing completed cycle / failed eligibility ───────────────────────────

  group('E — eligibility blocked results', () {
    test('E1: no completed cycle → blocked, reason mentions cycle', () {
      final project = _eligibleProject(correctionCycles: []);
      final elig = FactoryProfileBuilder.checkEligibility(project);

      expect(elig.isApproved, isFalse);
      expect(elig.reasons.any((r) => r.toLowerCase().contains('cycle')),
          isTrue);
    });

    test('E1b: no completed cycle → build() returns null', () {
      final project = _eligibleProject(correctionCycles: []);
      expect(FactoryProfileBuilder.build(project), isNull);
    });

    test('E2: exportLocked → blocked, reason mentions lock', () {
      final locked = ProtectionProjectState(exportLocked: true);
      final project = _eligibleProject(protectionState: locked);
      final elig = FactoryProfileBuilder.checkEligibility(project);

      expect(elig.isApproved, isFalse);
      expect(elig.reasons.any((r) => r.toLowerCase().contains('lock')), isTrue);
    });

    test('E3: unknown hardware target → blocked, reason mentions target', () {
      final project = _eligibleProject(dspTarget: 'Unknown_DSP');
      final elig = FactoryProfileBuilder.checkEligibility(project);

      expect(elig.isApproved, isFalse);
      expect(elig.reasons.any((r) => r.contains('Unknown_DSP')), isTrue);
    });

    test('E4: empty peqChannels → blocked', () {
      final project = _eligibleProject(peqChannels: []);
      final elig = FactoryProfileBuilder.checkEligibility(project);

      expect(elig.isApproved, isFalse);
      expect(elig.reasons.any((r) => r.toLowerCase().contains('peq')), isTrue);
    });

    test('E5: manualApproval=true bypasses missing cycle requirement', () {
      final project = _eligibleProject(correctionCycles: []);
      final elig = FactoryProfileBuilder.checkEligibility(project,
          manualApproval: true);

      expect(elig.isApproved, isTrue);
    });

    // Phase 4-C-4A: safetyStatus == verified is now a required rule — this
    // is what closes the gap where a software-rolled-back project (whose
    // safetyStatus is reset to notVerified) could otherwise still produce a
    // new Factory Sound Profile.

    test('E6: verified project remains eligible (all other rules default)',
        () {
      final project = _eligibleProject(safetyStatus: SafetyStatus.verified);
      final elig = FactoryProfileBuilder.checkEligibility(project);

      expect(elig.isApproved, isTrue);
      expect(FactoryProfileBuilder.build(project), isNotNull);
    });

    test(
        'E7: notVerified project (e.g. just software-rolled-back) is '
        'blocked, reason mentions safety/verif', () {
      final project =
          _eligibleProject(safetyStatus: SafetyStatus.notVerified);
      final elig = FactoryProfileBuilder.checkEligibility(project);

      expect(elig.isApproved, isFalse);
      expect(
          elig.reasons
              .any((r) => r.toLowerCase().contains('verif')),
          isTrue);
      expect(FactoryProfileBuilder.build(project), isNull);
    });

    test('E8: notVerified is not bypassed by manualApproval=true — safety '
        'verification is independent of the completed-cycle bypass', () {
      final project =
          _eligibleProject(safetyStatus: SafetyStatus.notVerified);
      final elig = FactoryProfileBuilder.checkEligibility(project,
          manualApproval: true);

      expect(elig.isApproved, isFalse);
      expect(
          elig.reasons.any((r) => r.toLowerCase().contains('verif')), isTrue);
    });

    test('E9: warning/blocked safetyStatus are also not eligible (only '
        'verified passes)', () {
      for (final status in [SafetyStatus.warning, SafetyStatus.blocked]) {
        final project = _eligibleProject(safetyStatus: status);
        final elig = FactoryProfileBuilder.checkEligibility(project);
        expect(elig.isApproved, isFalse, reason: 'status=$status');
      }
    });

    test(
        'E10: all pre-existing eligibility rules remain intact alongside '
        'the new safety rule (multiple failures each still reported)', () {
      final project = _eligibleProject(
        dspTarget: 'Unknown_DSP',
        peqChannels: [],
        correctionCycles: [],
        protectionState: ProtectionProjectState(exportLocked: true),
        safetyStatus: SafetyStatus.notVerified,
      );
      final elig = FactoryProfileBuilder.checkEligibility(project);

      expect(elig.isApproved, isFalse);
      expect(elig.reasons.any((r) => r.contains('Unknown_DSP')), isTrue);
      expect(elig.reasons.any((r) => r.toLowerCase().contains('peq')), isTrue);
      expect(
          elig.reasons.any((r) => r.toLowerCase().contains('cycle')), isTrue);
      expect(elig.reasons.any((r) => r.toLowerCase().contains('lock')), isTrue);
      expect(
          elig.reasons.any((r) => r.toLowerCase().contains('verif')), isTrue);
    });
  });

// ── F: Persistence / reload ───────────────────────────────────────────────────

  group('F — persistence and reload', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('F1: factory profile saved and reloaded exactly', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(proProjectStoreProvider);
      await pumpEventQueue();

      final now = DateTime.now();
      final project = ProProject(
        id: 'proj_f1',
        name: 'F1 Project',
        createdAt: now,
        updatedAt: now,
        dspTarget: 'ADAU1701',
        tuningState: TuningProjectState(
            peqChannels: [PeqChannelState.empty('ch_wf')]),
        protectionState: ProtectionProjectState(
            exportLocked: false,
            verificationStatus: VerificationStatus.passed),
        correctionCycles: [_completedCycle(projectId: 'proj_f1')],
        safetyStatus: SafetyStatus.verified,
      );
      await container
          .read(proProjectStoreProvider.notifier)
          .addProject(project);

      final savedProject = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj_f1');
      final profile = FactoryProfileBuilder.build(savedProject)!;

      await container
          .read(proProjectStoreProvider.notifier)
          .addFactoryProfile('proj_f1', profile);

      // Reload in a fresh container.
      container.dispose();
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      c2.read(proProjectStoreProvider);
      await pumpEventQueue();

      final reloaded = c2
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj_f1');

      expect(reloaded.factoryProfiles.length, equals(1));
      final rp = reloaded.factoryProfiles.first;
      expect(rp.profileId, equals(profile.profileId));
      expect(rp.projectFingerprint, equals(profile.projectFingerprint));
      expect(rp.hardwareTarget, equals('ADAU1701'));
      expect(rp.tuningSnapshot.peqChannels.length, equals(1));
    });

    test('F2: multiple profiles listed in insertion order', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(proProjectStoreProvider);
      await pumpEventQueue();

      final now = DateTime.now();
      final project = ProProject(
        id: 'proj_f2',
        name: 'F2 Project',
        createdAt: now,
        updatedAt: now,
        dspTarget: 'ADAU1701',
        tuningState: TuningProjectState(
            peqChannels: [PeqChannelState.empty('ch_wf')]),
        protectionState: ProtectionProjectState(
            exportLocked: false,
            verificationStatus: VerificationStatus.passed),
        correctionCycles: [_completedCycle(projectId: 'proj_f2')],
        safetyStatus: SafetyStatus.verified,
      );
      await container
          .read(proProjectStoreProvider.notifier)
          .addProject(project);

      final p0 = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj_f2');

      final p1 = FactoryProfileBuilder.build(p0, profileName: 'Profile 1')!;
      await container
          .read(proProjectStoreProvider.notifier)
          .addFactoryProfile('proj_f2', p1);

      final p1Saved = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj_f2');

      final p2 =
          FactoryProfileBuilder.build(p1Saved, profileName: 'Profile 2')!;
      await container
          .read(proProjectStoreProvider.notifier)
          .addFactoryProfile('proj_f2', p2);

      final saved = container
          .read(proProjectStoreProvider)
          .projects
          .firstWhere((p) => p.id == 'proj_f2');

      expect(saved.factoryProfiles.length, equals(2));
      expect(saved.factoryProfiles[0].profileName, equals('Profile 1'));
      expect(saved.factoryProfiles[1].profileName, equals('Profile 2'));
      expect(saved.factoryProfiles[1].version, equals(2));
    });
  });

// ── G: Export JSON ────────────────────────────────────────────────────────────

  group('G — JSON export', () {
    test('G1: required schema fields present in export', () {
      final profile = FactoryProfileBuilder.build(_eligibleProject())!;
      final json = FactoryProfileExporter.toJson(profile);

      expect(json['schemaVersion'], isNotNull);
      expect(json['profileId'], isNotEmpty);
      expect(json['profileName'], isNotEmpty);
      expect(json['profileVersion'], isNotNull);
      expect(json['projectId'], isNotNull);
      expect(json['hardware'], isA<Map>());
      expect(json['channels'], isA<List>());
      expect(json['validation'], isA<Map>());
      expect(json['correctionCycles'], isA<Map>());
      expect(json['projectFingerprint'], isNotEmpty);
    });

    test('G2: no raw DSP address fields in export', () {
      final profile = FactoryProfileBuilder.build(_eligibleProject())!;
      final jsonStr = jsonEncode(FactoryProfileExporter.toJson(profile));

      expect(jsonStr.contains('safeLoad'), isFalse);
      expect(jsonStr.contains('registerAddress'), isFalse);
      expect(jsonStr.contains('transport'), isFalse);
      expect(jsonStr.contains('blePayload'), isFalse);
      expect(jsonStr.contains('usbPacket'), isFalse);
    });

    test('G3: channels list contains PEQ bands', () {
      final project =
          _eligibleProject(peqChannels: [PeqChannelState.fixed('ch_wf')]);
      final profile = FactoryProfileBuilder.build(project)!;
      final json = FactoryProfileExporter.toJson(profile);
      final channels = json['channels'] as List;

      expect(channels, isNotEmpty);
      final ch = channels.first as Map;
      expect(ch['channelId'], equals('ch_wf'));
      expect(ch['peq'], isA<Map>());
    });

    test('G4: export is deterministic — same profile produces same JSON', () {
      final profile = FactoryProfileBuilder.build(_eligibleProject())!;
      final json1 = FactoryProfileExporter.toJson(profile);
      final json2 = FactoryProfileExporter.toJson(profile);

      expect(jsonEncode(json1), equals(jsonEncode(json2)));
    });
  });

// ── H: Wrong / unsupported hardware ──────────────────────────────────────────

  group('H — unsupported hardware', () {
    test('H1: unsupported dspTarget → eligibility blocked', () {
      final project = _eligibleProject(dspTarget: 'simulationOnly');
      final elig = FactoryProfileBuilder.checkEligibility(project);

      expect(elig.isApproved, isFalse);
      expect(elig.reasons.isNotEmpty, isTrue);
    });

    test(
        'H2: unsupported hardware → export throws UnsupportedHardwareExportError',
        () {
      // Build a valid profile, then craft a copy with an unsupported target
      // to hit the exporter's guard directly.
      final goodProfile = FactoryProfileBuilder.build(_eligibleProject())!;
      final badProfile = FactorySoundProfile(
        profileId: goodProfile.profileId,
        projectId: goodProfile.projectId,
        profileName: goodProfile.profileName,
        version: goodProfile.version,
        createdAt: goodProfile.createdAt,
        hardwareTarget: 'Unknown_DSP_Chip',
        sampleRate: goodProfile.sampleRate,
        channelConfig: goodProfile.channelConfig,
        tuningSnapshot: goodProfile.tuningSnapshot,
        protectionSnapshot: goodProfile.protectionSnapshot,
        validationStatus: goodProfile.validationStatus,
        projectFingerprint: goodProfile.projectFingerprint,
      );

      expect(
        () => FactoryProfileExporter.toJson(badProfile),
        throwsA(isA<UnsupportedHardwareExportError>()),
      );
    });
  });

// ── I: Report resolver reads final profile summary ─────────────────────────────

  group('I — report resolver integration', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test(
        'I1: buildTuningReport includes factoryProfile summary when profile exists',
        () {
      final project = _eligibleProject();
      final profile = FactoryProfileBuilder.build(project)!;
      final projectWithProfile =
          project.copyWith(factoryProfiles: [profile]);

      final report = buildTuningReport(
        projectWithProfile,
        const ProMeasurementStore(),
      );

      expect(report.factoryProfile, isNotNull);
      expect(report.factoryProfile!.profileId, equals(profile.profileId));
      expect(report.factoryProfile!.hardwareTarget, equals('ADAU1701'));
      expect(report.factoryProfile!.completedCycleCount,
          equals(profile.completedCycleNumbers.length));
      expect(report.factoryProfile!.projectFingerprint,
          equals(profile.projectFingerprint));
    });

    test('I2: buildTuningReport factoryProfile is null when no profile exists',
        () {
      final project = _eligibleProject();
      final report = buildTuningReport(project, const ProMeasurementStore());

      expect(report.factoryProfile, isNull);
    });

    test('I3: report factoryProfile JSON round-trips correctly', () {
      final project = _eligibleProject();
      final profile = FactoryProfileBuilder.build(project)!;
      final projectWithProfile =
          project.copyWith(factoryProfiles: [profile]);

      final report =
          buildTuningReport(projectWithProfile, const ProMeasurementStore());
      final reportJson = report.toJson();

      expect(reportJson['factoryProfile'], isNotNull);
      final restored = TuningReportData.fromJson(reportJson);
      expect(restored.factoryProfile, isNotNull);
      expect(
          restored.factoryProfile!.profileId, equals(profile.profileId));
    });
  });
}
