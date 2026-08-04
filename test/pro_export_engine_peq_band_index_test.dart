// Export band-index preservation fix — generateDspExportDraft() previously
// re-derived PEQ band_$i keys from `enabledBands.asMap()`, the position
// within the FILTERED (enabled-only) list, not the original DSP slot index.
// `PeqBand` carries no `index` field (only `id: 'band_$index'`, set by
// PeqBand.slot() — never read back by the old builder), so once a band was
// filtered out, its true slot position was lost.
//
// Concretely: Band 1 (index 0) disabled + Band 9 (index 8) enabled used to
// export Band 9's actual frequency/gain/Q data under the key `band_0` —
// letting unproven Band-9 data pass buildHardwareWritePlan's capability gate
// disguised as the one truly capture-proven band (Band 1 / index 0).
//
// Fixed: iterate the full, unfiltered `ch.bands` list and skip disabled
// slots in place, so band_$i always names the true DSP slot index.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_export_data.dart';
import 'package:tunai_pro/core/pro_export_engine.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_protection_data.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';

const _kChannels = [
  DriverChannel(
      id: 'ch_tw_l', name: 'Tweeter L', role: DriverRole.tweeter,
      side: DriverSide.left, dspOutputIndex: 1),
  DriverChannel(
      id: 'ch_wf_r', name: 'Woofer R', role: DriverRole.woofer,
      side: DriverSide.right, dspOutputIndex: 4),
  DriverChannel(
      id: 'ch_tw_r', name: 'Tweeter R', role: DriverRole.tweeter,
      side: DriverSide.right, dspOutputIndex: 3),
];

ProProject _projectWithPeq(TuningProjectState tuning) => ProProject(
      id: 'p1',
      name: 'Export band index test',
      createdAt: DateTime.utc(2026, 8, 4),
      updatedAt: DateTime.utc(2026, 8, 4),
      acousticState: MeasurementProjectState.createDefault()
          .copyWith(driverChannels: _kChannels),
      protectionState: ProtectionProjectState(
          verificationStatus: VerificationStatus.passed),
      tuningState: tuning,
    );

ExportParameterBlock _peqBlockFor(DspExportPackage pkg, String channelId) =>
    pkg.parameterBlocks.firstWhere(
        (b) => b.type == ExportBlockType.peq && b.channelId == channelId);

void main() {
  test(
      'Band 1 disabled + Band 9 enabled → exports as band_8, never band_0',
      () {
    final base = PeqChannelState.fixed('ch_tw_l');
    final bands = List<PeqBand>.from(base.bands);
    // Band 1 (index 0): stays disabled (default from .fixed()).
    // Band 9 (index 8): enable with distinctive values.
    bands[8] = bands[8].copyWith(
      enabled: true,
      frequencyHz: 6300.0,
      gainDb: 2.5,
      q: 0.9,
    );

    final tuning = TuningProjectState(
      peqChannels: [base.copyWith(bands: bands)],
      crossoverChannels: const [],
    );

    final pkg = generateDspExportDraft(project: _projectWithPeq(tuning));
    final block = _peqBlockFor(pkg, 'ch_tw_l');
    final bandsJson = block.parameters['bands'] as Map;

    expect(bandsJson.containsKey('band_8'), isTrue,
        reason: 'Band 9 (index 8) must be exported as band_8');
    expect(bandsJson.containsKey('band_0'), isFalse,
        reason: 'Band 1 (index 0) is disabled — must not appear at all, '
            'and Band 9 data must never be relabelled as band_0');

    final band8 = bandsJson['band_8'] as Map;
    expect(band8['freq_hz'], 6300.0);
    expect(band8['gain_db'], 2.5);
    expect(band8['q'], 0.9);
  });

  test(
      'multiple gaps preserved: bands 2, 5, 9 enabled (indices 1, 4, 8) — '
      'each keeps its own original slot index', () {
    final base = PeqChannelState.fixed('ch_wf_r');
    final bands = List<PeqBand>.from(base.bands);
    bands[1] = bands[1].copyWith(enabled: true, frequencyHz: 200.0, gainDb: -1.0, q: 1.0);
    bands[4] = bands[4].copyWith(enabled: true, frequencyHz: 800.0, gainDb: 1.0, q: 1.1);
    bands[8] = bands[8].copyWith(enabled: true, frequencyHz: 9000.0, gainDb: 3.0, q: 0.8);

    final tuning = TuningProjectState(
      peqChannels: [base.copyWith(bands: bands)],
      crossoverChannels: const [],
    );

    final pkg = generateDspExportDraft(project: _projectWithPeq(tuning));
    final block = _peqBlockFor(pkg, 'ch_wf_r');
    final bandsJson = block.parameters['bands'] as Map;

    expect(bandsJson.keys.toSet(), {'band_1', 'band_4', 'band_8'});
    expect((bandsJson['band_1'] as Map)['freq_hz'], 200.0);
    expect((bandsJson['band_4'] as Map)['freq_hz'], 800.0);
    expect((bandsJson['band_8'] as Map)['freq_hz'], 9000.0);
  });

  test('all bands disabled → no PEQ block emitted for that channel', () {
    final base = PeqChannelState.fixed('ch_tw_r');
    final tuning = TuningProjectState(
      peqChannels: [base],
      crossoverChannels: const [],
    );

    final pkg = generateDspExportDraft(project: _projectWithPeq(tuning));
    expect(
        pkg.parameterBlocks.any(
            (b) => b.type == ExportBlockType.peq && b.channelId == 'ch_tw_r'),
        isFalse);
  });
}
