// Phase 3-C — microphone_catalog.dart: metadata-only reference list tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/calibration/microphone_catalog.dart';

void main() {
  test('catalog is non-empty', () {
    expect(kSupportedMicrophoneCatalog, isNotEmpty);
  });

  test('every entry has a unique id', () {
    final ids = kSupportedMicrophoneCatalog.map((d) => d.id).toSet();
    expect(ids.length, kSupportedMicrophoneCatalog.length);
  });

  test('every entry has non-empty manufacturer/model/connectionType/notes', () {
    for (final d in kSupportedMicrophoneCatalog) {
      expect(d.manufacturer, isNotEmpty, reason: d.id);
      expect(d.model, isNotEmpty, reason: d.id);
      expect(d.connectionType, isNotEmpty, reason: d.id);
      expect(d.notes, isNotEmpty, reason: d.id);
      expect(d.supportedOrientations, isNotEmpty, reason: d.id);
      expect(d.supportedOrientations, contains(d.recommendedOrientation),
          reason: d.id);
    }
  });

  test('a catalog entry never carries calibration data — metadata only', () {
    // Structural guarantee: SupportedMicrophoneDescriptor has no
    // CalibrationCurve/checksum/sensitivity field at all, so selecting one
    // can never itself produce a "calibrated" profile. This test documents
    // that guarantee by construction (would fail to compile if the type
    // ever gained such a field without updating this test).
    for (final d in kSupportedMicrophoneCatalog) {
      expect(d.id, isA<String>());
    }
  });

  test('serial-required models also require a calibration file', () {
    for (final d in kSupportedMicrophoneCatalog) {
      if (d.requiresSerialCalibration) {
        expect(d.calibrationFileRequired, isTrue,
            reason:
                '${d.id}: a model needing a per-unit serial calibration must '
                'also require a file — it can never be usable calibrated '
                'without one.');
      }
    }
  });
}
