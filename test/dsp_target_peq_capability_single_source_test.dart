// Final QA closure #2 — Issue B: Export MAX PEQ/CH, Deploy's allowlist, and
// the PEQ Editor's band count must never independently disagree again.
// DspTargetProfile.adau1701.maxPeqBandsPerChannel now reads directly from
// HardwareDeviceProfiles.adau1701Icp5 (the same source Deploy's write
// allowlist already uses) instead of a separately hardcoded number.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';
import 'package:tunai_pro/core/pro_dsp_target_data.dart';
import 'package:tunai_pro/core/pro_export_data.dart' show DspTargetPlatform;

void main() {
  test(
      'DspTargetProfile.adau1701.maxPeqBandsPerChannel matches '
      'HardwareDeviceProfiles.adau1701Icp5\'s evidenced write-verified band '
      'count exactly — one source, not two', () {
    final profile = DspTargetProfile.forPlatform(DspTargetPlatform.adau1701);
    final authoritative = HardwareDeviceProfiles.adau1701Icp5
        .maxWriteVerifiedPeqBandCount(HardwareParamKind.peqGain);

    expect(profile.maxPeqBandsPerChannel, authoritative);
    // Pinned to the real hardware evidence (Band 1-8 write-proven, Band
    // 9-10 unavailable) so a silent registry regression is caught here,
    // not just via the cross-check above.
    expect(profile.maxPeqBandsPerChannel, 8);
  });

  test(
      'maxWriteVerifiedPeqBandCount stops at the first gap — a device with '
      'no verified bands returns 0, never guesses', () {
    const emptyProfile = HardwareDeviceProfile(
      deviceId: 'test-empty',
      deviceName: 'Test',
      transport: HardwareTransportType.icp5,
      capabilities: [],
    );
    expect(emptyProfile.maxWriteVerifiedPeqBandCount(HardwareParamKind.peqGain),
        0);
  });

  test(
      'maxWriteVerifiedPeqBandCount only counts a CONTIGUOUS run from band '
      '0 — a gap at band 2 stops the count at 2, even if band 3 is '
      'individually verified', () {
    const gappedProfile = HardwareDeviceProfile(
      deviceId: 'test-gapped',
      deviceName: 'Test',
      transport: HardwareTransportType.icp5,
      capabilities: [
        HardwareCapabilityEntry(
            kind: HardwareParamKind.peqGain,
            bandIndex: 0,
            verification: HardwareParamVerification.captureProven),
        HardwareCapabilityEntry(
            kind: HardwareParamKind.peqGain,
            bandIndex: 1,
            verification: HardwareParamVerification.captureProven),
        HardwareCapabilityEntry(
            kind: HardwareParamKind.peqGain,
            bandIndex: 2,
            verification: HardwareParamVerification.unavailable),
        HardwareCapabilityEntry(
            kind: HardwareParamKind.peqGain,
            bandIndex: 3,
            verification: HardwareParamVerification.captureProven),
      ],
    );
    expect(
        gappedProfile.maxWriteVerifiedPeqBandCount(HardwareParamKind.peqGain),
        2);
  });
}
