// TUNAI PRO — Phase S: Demo Project Factory tests

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_demo_project_factory.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';

void main() {
  group('createTunaiProDemoProject', () {
    late ProProject demo;

    setUp(() => demo = createTunaiProDemoProject());

    test('creates project with correct name', () {
      expect(demo.name, 'TUNAI ONE Coax Demo');
    });

    test('project id is non-empty', () {
      expect(demo.id, isNotEmpty);
    });

    test('has 4 driver channels', () {
      expect(demo.acousticState.driverChannels.length, 4);
    });

    test('driver channels have expected ids', () {
      final ids = demo.acousticState.driverChannels.map((c) => c.id).toSet();
      expect(ids, containsAll(['ch_tw_l', 'ch_wf_l', 'ch_tw_r', 'ch_wf_r']));
    });

    test('all channels have validated status', () {
      for (final ch in demo.acousticState.driverChannels) {
        expect(ch.measurementStatus, MeasurementStatus.validated,
            reason: '${ch.id} should be validated');
      }
    });

    test('tweeter channels have FRD data', () {
      final tweeters = demo.acousticState.driverChannels
          .where((c) => c.role == DriverRole.coaxTweeter);
      for (final ch in tweeters) {
        expect(ch.hasFrd, isTrue, reason: '${ch.id} should have FRD');
        expect(ch.hasParsedFrd, isTrue, reason: '${ch.id} should have parsed FRD');
        expect(ch.frdData!.points.length, greaterThanOrEqualTo(10));
      }
    });

    test('woofer channels have FRD and ZMA data', () {
      final woofers = demo.acousticState.driverChannels
          .where((c) => c.role == DriverRole.coaxWoofer);
      for (final ch in woofers) {
        expect(ch.hasFrd, isTrue, reason: '${ch.id} should have FRD');
        expect(ch.hasZma, isTrue, reason: '${ch.id} should have ZMA');
        expect(ch.hasParsedFrd, isTrue);
        expect(ch.hasParsedZma, isTrue);
      }
    });

    test('has warm target curve', () {
      expect(demo.acousticState.targetCurve.selectedPreset,
          TargetCurvePreset.warm);
    });

    test('has PEQ bands', () {
      expect(demo.tuningState.totalPeqBands, greaterThan(0));
    });

    test('has crossover channels configured', () {
      expect(demo.tuningState.configuredXoChannels, greaterThan(0));
    });

    test('contains demo note in project notes', () {
      expect(demo.notes, contains('Demo data only'));
    });

    test('profile status is tuned', () {
      expect(demo.profileStatus, ProfileStatus.tuned);
    });

    test('hardware write is always disabled', () {
      expect(demo.hardwareState.isHardwareWriteEnabled, isFalse);
    });

    test('has export package', () {
      expect(demo.exportState.packageCount, greaterThan(0));
    });

    test('serializes to JSON without error', () {
      expect(() => demo.toJson(), returnsNormally);
    });

    test('round-trips JSON preserving name', () {
      final json = demo.toJson();
      final restored = ProProject.fromJson(json);
      expect(restored.name, demo.name);
    });

    test('round-trips JSON preserving driver count', () {
      final json = demo.toJson();
      final restored = ProProject.fromJson(json);
      expect(restored.acousticState.totalDrivers,
          demo.acousticState.totalDrivers);
    });

    test('JSON does not contain hardware write keys', () {
      final jsonStr = demo.toJson().toString().toLowerCase();
      expect(jsonStr, isNot(contains('sendusb')));
      expect(jsonStr, isNot(contains('sendble')));
      expect(jsonStr, isNot(contains('safeloadexecute')));
      expect(jsonStr, isNot(contains('writeregister')));
    });

    test('each call creates unique id', () async {
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final demo2 = createTunaiProDemoProject();
      expect(demo.id, isNot(equals(demo2.id)));
    });
  });
}
