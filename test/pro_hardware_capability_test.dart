import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';

void main() {
  const adau1701 = HardwareDeviceProfiles.adau1701Icp5;
  const adau1466 = HardwareDeviceProfiles.adau1466Developer;

  group('ADAU1701 ICP5 capability lookup', () {
    test('Band 1 (index 0) gain + frequency are capture-proven', () {
      expect(adau1701.verificationFor(HardwareParamKind.peqGain, bandIndex: 0),
          HardwareParamVerification.captureProven);
      expect(
          adau1701.verificationFor(HardwareParamKind.peqFrequency, bandIndex: 0),
          HardwareParamVerification.captureProven);
    });

    test('Bands 2–10 gain/frequency are unverified', () {
      for (final band in [1, 5, 9]) {
        expect(
            adau1701.verificationFor(HardwareParamKind.peqGain, bandIndex: band),
            HardwareParamVerification.unverified);
        expect(
            adau1701.verificationFor(HardwareParamKind.peqFrequency,
                bandIndex: band),
            HardwareParamVerification.unverified);
      }
    });

    test('Q is unverified on every band (incl. band 0)', () {
      expect(adau1701.verificationFor(HardwareParamKind.peqQ, bandIndex: 0),
          HardwareParamVerification.unverified);
      expect(adau1701.verificationFor(HardwareParamKind.peqQ, bandIndex: 4),
          HardwareParamVerification.unverified);
      expect(adau1701.verificationFor(HardwareParamKind.peqQ),
          HardwareParamVerification.unverified);
    });

    test('XO, delay, and gain stages are unavailable', () {
      expect(adau1701.verificationFor(HardwareParamKind.crossoverHighPass),
          HardwareParamVerification.unavailable);
      expect(adau1701.verificationFor(HardwareParamKind.crossoverLowPass),
          HardwareParamVerification.unavailable);
      expect(adau1701.verificationFor(HardwareParamKind.channelDelay),
          HardwareParamVerification.unavailable);
      expect(adau1701.verificationFor(HardwareParamKind.channelGain),
          HardwareParamVerification.unavailable);
    });

    test('band-agnostic gain lookup falls back to unverified', () {
      expect(adau1701.verificationFor(HardwareParamKind.peqGain),
          HardwareParamVerification.unverified);
    });
  });

  group('verification status correctness', () {
    test('only captureProven is write-eligible', () {
      expect(HardwareParamVerification.captureProven.isWriteEligible, isTrue);
      expect(HardwareParamVerification.unverified.isWriteEligible, isFalse);
      expect(HardwareParamVerification.unavailable.isWriteEligible, isFalse);
    });

    test('isWriteEligible mirrors the proven set only', () {
      expect(
          adau1701.isWriteEligible(HardwareParamKind.peqGain, bandIndex: 0),
          isTrue);
      expect(
          adau1701.isWriteEligible(HardwareParamKind.peqGain, bandIndex: 3),
          isFalse); // unverified
      expect(adau1701.isWriteEligible(HardwareParamKind.peqQ, bandIndex: 0),
          isFalse); // unverified
      expect(adau1701.isWriteEligible(HardwareParamKind.channelDelay),
          isFalse); // unavailable
    });

    test('enum JSON round-trips; unknown decodes to unavailable', () {
      for (final v in HardwareParamVerification.values) {
        expect(HardwareParamVerification.fromJson(v.toJson()), v);
      }
      expect(HardwareParamVerification.fromJson('bogus'),
          HardwareParamVerification.unavailable);
    });
  });

  group('fail-closed behaviour', () {
    test('parameters with no ADAU1701 entry resolve to unavailable', () {
      expect(adau1701.verificationFor(HardwareParamKind.channelMute),
          HardwareParamVerification.unavailable);
      expect(adau1701.verificationFor(HardwareParamKind.channelPolarity),
          HardwareParamVerification.unavailable);
    });

    test('ADAU1466 developer profile assumes nothing writable', () {
      expect(adau1466.capabilities, isEmpty);
      for (final kind in HardwareParamKind.values) {
        expect(adau1466.verificationFor(kind),
            HardwareParamVerification.unavailable);
        expect(adau1466.verificationFor(kind, bandIndex: 0),
            HardwareParamVerification.unavailable);
        expect(adau1466.isWriteEligible(kind), isFalse);
      }
    });

    test('unknown parameter kind string does not resolve to a kind', () {
      expect(HardwareParamKind.fromJson('nonexistent'), isNull);
    });
  });

  group('profile registry', () {
    test('byId returns known profiles and null for unknown', () {
      expect(HardwareDeviceProfiles.byId('adau1701-icp5'), same(adau1701));
      expect(HardwareDeviceProfiles.byId('adau1466-developer'), same(adau1466));
      expect(HardwareDeviceProfiles.byId('unknown-device'), isNull);
    });

    test('profiles are kept separate with distinct transports', () {
      expect(adau1701.transport, HardwareTransportType.icp5);
      expect(adau1466.transport, HardwareTransportType.usbiDeveloper);
      expect(HardwareDeviceProfiles.all, hasLength(2));
    });

    test('profile serializes to JSON', () {
      final json = adau1701.toJson();
      expect(json['deviceId'], 'adau1701-icp5');
      expect(json['transport'], 'icp5');
      expect((json['capabilities'] as List), isNotEmpty);
    });
  });
}
