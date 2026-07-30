import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';

void main() {
  const adau1701 = HardwareDeviceProfiles.adau1701Icp5;
  const adau1466 = HardwareDeviceProfiles.adau1466Developer;

  group('ADAU1701 ICP5 capability lookup', () {
    test('Band 1 (index 0) gain and frequency are both capture-proven', () {
      expect(adau1701.verificationFor(HardwareParamKind.peqGain, bandIndex: 0),
          HardwareParamVerification.captureProven);
      // Consumer-production-proven: param 0x18 property 0x02 → offset 19:20.
      // Evidence: tunai_codex icp5_peq_command_builder.dart + physical QA fixture.
      expect(
          adau1701.verificationFor(HardwareParamKind.peqFrequency, bandIndex: 0),
          HardwareParamVerification.captureProven);
    });

    test('peqFrequency is captureProven for all bands 0–9 (Consumer-production-proven)', () {
      // Band 0: explicit band-0 entry (PRO readback + Consumer evidence).
      expect(
          adau1701.verificationFor(HardwareParamKind.peqFrequency, bandIndex: 0),
          HardwareParamVerification.captureProven);
      // Bands 1–9: band-agnostic entry (Consumer icp5_peq_command_builder evidence).
      // Port treats bands 1–9 as ACK-only (no PRO readback for non-band-0).
      for (final band in [1, 5, 9]) {
        expect(
            adau1701.verificationFor(HardwareParamKind.peqFrequency,
                bandIndex: band),
            HardwareParamVerification.captureProven,
            reason: 'band $band: Consumer-proven encoding, ACK-only at port');
      }
    });

    test('peqGain is captureProven for all bands 0–9 (Consumer-production-proven)', () {
      for (final band in [0, 1, 5, 9]) {
        expect(
            adau1701.verificationFor(HardwareParamKind.peqGain, bandIndex: band),
            HardwareParamVerification.captureProven,
            reason: 'band $band');
      }
    });

    test('peqQ is captureProven for all bands (Consumer-production-proven, ACK-only at port)', () {
      expect(adau1701.verificationFor(HardwareParamKind.peqQ, bandIndex: 0),
          HardwareParamVerification.captureProven);
      expect(adau1701.verificationFor(HardwareParamKind.peqQ, bandIndex: 4),
          HardwareParamVerification.captureProven);
      expect(adau1701.verificationFor(HardwareParamKind.peqQ),
          HardwareParamVerification.captureProven);
    });

    test('delay is unavailable; channelGain and XO frequency are captureProven', () {
      expect(adau1701.verificationFor(HardwareParamKind.channelDelay),
          HardwareParamVerification.unavailable);
      // channelGain: ICP5 parameter-ID 0x14 + float32 LE + channel byte confirmed.
      expect(adau1701.verificationFor(HardwareParamKind.channelGain),
          HardwareParamVerification.captureProven);
      // crossoverHighPass/LowPass: param-ID 0x15, band 0, capture-proven via
      // filter cutoff TEST/RESTORE pairs for channels 0–3.
      expect(adau1701.verificationFor(HardwareParamKind.crossoverHighPass),
          HardwareParamVerification.captureProven);
      expect(adau1701.verificationFor(HardwareParamKind.crossoverLowPass),
          HardwareParamVerification.captureProven);
    });

    test('band-agnostic gain lookup returns captureProven (Consumer-proven for all bands)', () {
      expect(adau1701.verificationFor(HardwareParamKind.peqGain),
          HardwareParamVerification.captureProven);
    });
  });

  group('verification status correctness', () {
    test('only captureProven is write-eligible', () {
      expect(HardwareParamVerification.captureProven.isWriteEligible, isTrue);
      expect(HardwareParamVerification.unverified.isWriteEligible, isFalse);
      expect(HardwareParamVerification.unavailable.isWriteEligible, isFalse);
    });

    test('isWriteEligible mirrors the proven set only', () {
      // peqGain: all bands 0–9 captureProven (Consumer-production-proven).
      expect(adau1701.isWriteEligible(HardwareParamKind.peqGain, bandIndex: 0),
          isTrue);
      expect(adau1701.isWriteEligible(HardwareParamKind.peqGain, bandIndex: 3),
          isTrue);
      // peqQ: captureProven for all bands (Consumer-production-proven).
      expect(adau1701.isWriteEligible(HardwareParamKind.peqQ, bandIndex: 0),
          isTrue);
      // channelDelay: unavailable — no write path.
      expect(adau1701.isWriteEligible(HardwareParamKind.channelDelay),
          isFalse);
      // peqFrequency: captureProven for all bands.
      expect(adau1701.isWriteEligible(HardwareParamKind.peqFrequency, bandIndex: 0),
          isTrue);
      expect(adau1701.isWriteEligible(HardwareParamKind.peqFrequency, bandIndex: 1),
          isTrue);
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
      // channelMute is now captureProven (polarity confirmed)
      expect(adau1701.verificationFor(HardwareParamKind.channelMute),
          HardwareParamVerification.captureProven);
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
