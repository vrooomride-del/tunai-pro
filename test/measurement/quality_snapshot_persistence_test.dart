// Phase 3-D3B §11/§12 — quality snapshot persistence safety + simulated-
// measurement isolation.
//
// Proves the full ProProject JSON round-trip preserves qualitySnapshot on
// BOTH the Factory (driverChannels[i].frdData) and Room (roomState.before)
// paths, that a corrupt qualitySnapshot never destroys the enclosing
// measurement/project decode, that legacy projects (no qualitySnapshot key
// at all) still decode, that imported FRD without a snapshot stays valid,
// and that no raw PCM/WAV payload is ever present in the encoded JSON.
//
// Also pins (source-contract) that MeasurementSession.simulateCapture() —
// the older simulated-measurement mechanism — is structurally isolated
// from MeasurementCaptureProvenance/MeasurementQualitySnapshot: it must
// never be able to produce data this phase's Room Auto PEQ gate would
// accept as live-measurement quality provenance.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/calibration/calibration_types.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/core/room_measurement_data.dart';
import '../support/room_quality_fixtures.dart';

DriverChannel _channelWithQualityFrd(String id, String projectId) =>
    DriverChannel(
      id: id,
      name: id,
      role: DriverRole.woofer,
      side: DriverSide.left,
      frdData: ParsedMeasurementData(
        id: '$id-frd',
        sourceFileName: '$id.frd',
        fileType: AcousticFileType.frd,
        importedAt: DateTime.utc(2026, 1, 1),
        points: const [
          MeasurementDataPoint(frequencyHz: 100, magnitudeDb: -1.0)
        ],
        calibrationStatus: CalibrationStatus.calibrated,
        microphoneSnapshot: roomQualityFixtureMicSnapshot(),
        qualitySnapshot: roomQualityFixtureSnapshot(projectId: projectId),
      ),
    );

RoomSystemMeasurement _roomMeasurementWithQuality(
        RoomSystemSide side, String projectId) =>
    RoomSystemMeasurement(
      side: side,
      phase: RoomMeasurementPhase.before,
      frd: ParsedMeasurementData(
        id: '${side.name}-frd',
        sourceFileName: '${side.name}.frd',
        fileType: AcousticFileType.frd,
        importedAt: DateTime.utc(2026, 1, 1),
        points: const [
          MeasurementDataPoint(frequencyHz: 100, magnitudeDb: -1.0)
        ],
        calibrationStatus: CalibrationStatus.calibrated,
        microphoneSnapshot: roomQualityFixtureMicSnapshot(),
        qualitySnapshot: roomQualityFixtureSnapshot(projectId: projectId),
      ),
      capturedAt: DateTime.utc(2026, 1, 1),
      sampleRate: 48000,
      source: RoomMeasurementSource.live,
      projectId: projectId,
    );

ProProject _project(String id) => ProProject(
      id: id,
      name: 'Quality Persistence Test',
      dspTarget: 'ADAU1701',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      acousticState: MeasurementProjectState(
          driverChannels: [_channelWithQualityFrd('ch1', id)]),
      tuningState: TuningProjectState(peqChannels: const []),
      roomState: RoomMeasurementProjectState(
        before: RoomMeasurementSnapshot(
          leftSystemFrd: _roomMeasurementWithQuality(RoomSystemSide.left, id),
          rightSystemFrd: _roomMeasurementWithQuality(RoomSystemSide.right, id),
        ),
      ),
    );

void main() {
  group('full ProProject round-trip', () {
    test('Factory driverChannels[i].frdData.qualitySnapshot survives', () {
      final original = _project('proj-persist-1');
      final decoded = ProProject.fromJson(
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>);

      final snap =
          decoded.acousticState.driverChannels.first.frdData?.qualitySnapshot;
      expect(snap, isNotNull);
      expect(snap!.provenance.projectId, 'proj-persist-1');
      expect(snap.provenance.microphoneProfileChecksum,
          'room-quality-fixture-checksum');
      expect(snap.setupPeakDbFs, isNotNull);
    });

    test('Room Before Left/Right qualitySnapshot survives, both sides', () {
      final original = _project('proj-persist-2');
      final decoded = ProProject.fromJson(
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>);

      final left = decoded.roomState.before.leftSystemFrd?.frd.qualitySnapshot;
      final right =
          decoded.roomState.before.rightSystemFrd?.frd.qualitySnapshot;
      expect(left, isNotNull);
      expect(right, isNotNull);
      expect(left!.provenance.projectId, 'proj-persist-2');
      expect(right!.provenance.projectId, 'proj-persist-2');
    });

    test(
        'raw/calibrated points and microphoneSnapshot survive alongside '
        'qualitySnapshot', () {
      final original = _project('proj-persist-3');
      final decoded = ProProject.fromJson(
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>);

      final frd = decoded.acousticState.driverChannels.first.frdData!;
      expect(frd.points, isNotEmpty);
      expect(frd.microphoneSnapshot, isNotNull);
      expect(frd.qualitySnapshot, isNotNull);
    });
  });

  group('corrupt qualitySnapshot does not destroy the enclosing decode', () {
    test(
        'malformed qualitySnapshot JSON -> ParsedMeasurementData still '
        'decodes, qualitySnapshot falls back to null', () {
      final original = _project('proj-corrupt-1');
      final json = original.toJson();
      // Corrupt the Factory channel's qualitySnapshot in place.
      final channels = (json['acousticState'] as Map)['driverChannels'] as List;
      final frd = (channels.first as Map)['frdData'] as Map;
      frd['qualitySnapshot'] = 'not-a-map';

      final decoded = ProProject.fromJson(Map<String, dynamic>.from(json));
      expect(decoded.acousticState.driverChannels.first.frdData, isNotNull);
      expect(
          decoded.acousticState.driverChannels.first.frdData!.qualitySnapshot,
          isNull);
      // Everything else on the project survives untouched.
      expect(decoded.id, 'proj-corrupt-1');
      expect(decoded.roomState.before.isComplete, isTrue);
    });
  });

  group('legacy / import compatibility', () {
    test('project JSON without any qualitySnapshot key decodes fine', () {
      final json = {
        'id': 'legacy-proj',
        'name': 'Legacy',
        'dspTarget': 'ADAU1701',
        'createdAt': DateTime.utc(2024, 1, 1).toIso8601String(),
        'updatedAt': DateTime.utc(2024, 1, 1).toIso8601String(),
      };
      final decoded = ProProject.fromJson(json);
      expect(decoded.id, 'legacy-proj');
      // Default-constructed driver channels (no FRD data on any of them) —
      // the point of this test is that decode succeeds at all without a
      // qualitySnapshot key anywhere, not the channel count.
      expect(
          decoded.acousticState.driverChannels
              .every((c) => c.frdData?.qualitySnapshot == null),
          isTrue);
    });

    test(
        'imported FRD without qualitySnapshot stays valid (not forced '
        'invalid)', () {
      final imported = ParsedMeasurementData(
        id: 'imported-1',
        sourceFileName: 'imported.frd',
        fileType: AcousticFileType.frd,
        importedAt: DateTime.utc(2026, 1, 1),
        points: const [
          MeasurementDataPoint(frequencyHz: 100, magnitudeDb: -1.0)
        ],
      );
      expect(imported.qualitySnapshot, isNull);
      final decoded = ParsedMeasurementData.fromJson(
          jsonDecode(jsonEncode(imported.toJson())) as Map<String, dynamic>);
      expect(decoded.qualitySnapshot, isNull);
      expect(decoded.points, isNotEmpty);
    });
  });

  group('no PCM/WAV payload anywhere in a full project encode', () {
    test('encoded project JSON never contains raw audio sample data', () {
      final original = _project('proj-no-pcm');
      final jsonString = jsonEncode(original.toJson());
      const forbiddenKeys = ['"pcm"', '"wav"', '"samples"', '"audioBytes"'];
      for (final key in forbiddenKeys) {
        expect(jsonString.contains(key), isFalse, reason: 'found $key');
      }
    });
  });

  group('simulated-measurement isolation (Phase 3-D3B §12)', () {
    test(
        'MeasurementSession/simulateCapture never references '
        'MeasurementCaptureProvenance or MeasurementQualitySnapshot', () {
      final source =
          File('lib/core/pro_measurement_store.dart').readAsStringSync();
      expect(source.contains('MeasurementCaptureProvenance'), isFalse,
          reason:
              'simulateCapture()\'s file must stay structurally isolated from '
              'the real capture provenance/quality types — if this legitimately '
              'changes, verify by hand that simulated data still cannot satisfy '
              'RoomMeasurementQualityGate before updating this test.');
      expect(source.contains('MeasurementQualitySnapshot'), isFalse);
    });
  });
}
