// ADAU1701 release-closure — FrdReadiness single-source-of-truth tests.
//
// ProGuidedAiController.frdReadiness() is the one place that decides whether
// a project has parsed FRD for all four required full-system channels. It
// replaces two previously-duplicated computations:
//   - AutoPeqTab used to gate on `parsedFrdCount > 0` (any single FRD),
//     which let it send the user into Guided AI "ready" when only 1 of 4
//     channels actually had data.
//   - guided_ai_screen.dart re-typed the same 4-channel id list as a local
//     `const requiredChannelIds` literal that could silently drift from
//     ProGuidedAiController.requiredFullSystemChannelIds.
//
// These tests pin the pure, deterministic behaviour of the consolidated
// helper so both call sites can never again show a readiness state that
// doesn't match what start() actually enforces.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/orchestrator/pro_guided_ai_controller.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';

DriverChannel _channelWithFrd(String id, DriverRole role, DriverSide side) =>
    DriverChannel(
      id: id,
      name: id,
      role: role,
      side: side,
      frdData: ParsedMeasurementData(
        id: '$id-frd',
        sourceFileName: '$id.frd',
        fileType: AcousticFileType.frd,
        importedAt: DateTime.utc(2025, 1, 1),
        points: const [
          MeasurementDataPoint(frequencyHz: 1000, magnitudeDb: 85.0),
        ],
      ),
    );

DriverChannel _channelWithoutFrd(String id, DriverRole role, DriverSide side) =>
    DriverChannel(id: id, name: id, role: role, side: side);

ProProject _projectWith(List<DriverChannel> channels) => ProProject(
      id: 'p1',
      name: 'P1',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2025, 1, 1),
      updatedAt: DateTime.utc(2025, 1, 1),
      acousticState: MeasurementProjectState(driverChannels: channels),
    );

void main() {
  group('ProGuidedAiController.frdReadiness — all 4 present', () {
    final project = _projectWith([
      _channelWithFrd('ch_tw_l', DriverRole.tweeter, DriverSide.left),
      _channelWithFrd('ch_wf_l', DriverRole.woofer, DriverSide.left),
      _channelWithFrd('ch_tw_r', DriverRole.tweeter, DriverSide.right),
      _channelWithFrd('ch_wf_r', DriverRole.woofer, DriverSide.right),
    ]);
    final readiness = ProGuidedAiController.frdReadiness(project);

    test('isFullyReady is true', () {
      expect(readiness.isFullyReady, isTrue);
    });

    test('missingChannels is empty', () {
      expect(readiness.missingChannels, isEmpty);
    });

    test('readyCount is 4', () {
      expect(readiness.readyCount, 4);
    });

    test('requiredChannelIds matches the controller constant exactly', () {
      expect(readiness.requiredChannelIds,
          ProGuidedAiController.requiredFullSystemChannelIds);
    });
  });

  group('ProGuidedAiController.frdReadiness — channels missing entirely', () {
    // ch_tw_r and ch_wf_r are not in driverChannels at all (never imported),
    // not merely present-without-FRD — a distinct real-world state.
    final project = _projectWith([
      _channelWithFrd('ch_tw_l', DriverRole.tweeter, DriverSide.left),
      _channelWithFrd('ch_wf_l', DriverRole.woofer, DriverSide.left),
    ]);
    final readiness = ProGuidedAiController.frdReadiness(project);

    test('isFullyReady is false', () {
      expect(readiness.isFullyReady, isFalse);
    });

    test('readyCount is 2', () {
      expect(readiness.readyCount, 2);
    });

    test('missingChannels lists exactly the two absent required ids', () {
      expect(readiness.missingChannels.map((c) => c.id).toSet(),
          {'ch_tw_r', 'ch_wf_r'});
    });

    test(
        'missing channel labels fall back to the raw id when the channel '
        'does not exist to derive a shortLabel from', () {
      for (final c in readiness.missingChannels) {
        expect(c.label, c.id);
      }
    });
  });

  group('ProGuidedAiController.frdReadiness — channel present without FRD', () {
    final project = _projectWith([
      _channelWithFrd('ch_tw_l', DriverRole.tweeter, DriverSide.left),
      _channelWithFrd('ch_wf_l', DriverRole.woofer, DriverSide.left),
      _channelWithFrd('ch_tw_r', DriverRole.tweeter, DriverSide.right),
      // ch_wf_r exists but has no parsed FRD yet.
      _channelWithoutFrd('ch_wf_r', DriverRole.woofer, DriverSide.right),
    ]);
    final readiness = ProGuidedAiController.frdReadiness(project);

    test('the FRD-less channel counts as missing', () {
      expect(readiness.isFullyReady, isFalse);
      expect(readiness.missingChannels.map((c) => c.id), ['ch_wf_r']);
    });

    test('its label uses the real DriverChannel.shortLabel, not the raw id',
        () {
      final missing = readiness.missingChannels.single;
      expect(missing.label, isNot('ch_wf_r'));
      expect(missing.label, contains('R'));
    });
  });

  group('ProGuidedAiController.frdReadiness — no channels at all', () {
    test('all 4 required channels are reported missing', () {
      final readiness = ProGuidedAiController.frdReadiness(_projectWith([]));
      expect(readiness.isFullyReady, isFalse);
      expect(readiness.readyCount, 0);
      expect(readiness.missingChannels.length, 4);
      expect(readiness.missingChannels.map((c) => c.id).toSet(),
          ProGuidedAiController.requiredFullSystemChannelIds.toSet());
    });
  });
}
