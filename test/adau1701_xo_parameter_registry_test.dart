// Phase 7-5B — Adau1701XoParameterRegistry structure.
// Data-only file, not wired into any write path — these tests just confirm
// the registry's verification status matches the evidence rigor documented
// in the Phase 7-5B report: frequency captureProven (3 checksummed
// captures), slope/type unavailable (claims only, no complete frame).

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/deploy/adau1701_xo_parameter_registry.dart';
import 'package:tunai_pro/core/deploy/pro_hardware_capability.dart';

void main() {
  test('frequency is captureProven', () {
    expect(Adau1701XoParameterRegistry.frequency.verification,
        HardwareParamVerification.captureProven);
    expect(Adau1701XoParameterRegistry.frequency.parameterId, 0x15);
  });

  test('slope and filterType are unavailable — no complete captured frame',
      () {
    expect(Adau1701XoParameterRegistry.slope.verification,
        HardwareParamVerification.unavailable);
    expect(Adau1701XoParameterRegistry.filterType.verification,
        HardwareParamVerification.unavailable);
  });

  test('claimed slope/type value maps are recorded but not treated as proven',
      () {
    expect(Adau1701XoParameterRegistry.slope.valueMap, {
      '6dB': 0x01,
      '12dB': 0x02,
      '24dB': 0x04,
    });
    expect(Adau1701XoParameterRegistry.filterType.valueMap, {
      'butterworth': 0x08,
      'bessel': 0x0A,
    });
    // Neither claimed value map includes Linkwitz-Riley — nothing here was
    // invented beyond what was explicitly provided.
    expect(Adau1701XoParameterRegistry.filterType.valueMap!.keys,
        isNot(contains('lr')));
  });

  test('all three entries share parameter ID 0x15', () {
    for (final m in Adau1701XoParameterRegistry.all) {
      expect(m.parameterId, 0x15);
    }
  });
}
