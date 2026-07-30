// Builds minimal ADAU1701 export blocks from the current tuning state
// for engineering manual writes (channel gain, PEQ, crossover).
//
// Does NOT require protection verification, FRD data, simulation results,
// Factory Sound Profile eligibility, or any correction cycle. This is a
// direct hardware control path for DSP engineers — the same safety chain
// (preflight → write → ACK) still applies.

import '../pro_acoustic_data.dart';
import '../pro_export_data.dart';
import '../pro_tuning_data.dart';

/// Builds a writable ADAU1701 export package from channel gains in
/// [tuning] for the channels listed in [channels].
///
/// Returns a `DspExportPackage` with `status = draftReady` and one
/// `ExportBlockType.gain` block per channel that needs a write:
///
/// - Known previous (entry in [previousAppliedGains]): included when changed.
/// - Unknown previous (no entry): included only when [gainDb] is non-zero,
///   because 0.0 dB is the ADAU1701 hardware default and writing it to an
///   untouched channel would silently overwrite any existing DSP state.
DspExportPackage buildAdau1701GainExportPackage({
  required List<DriverChannel> channels,
  required TuningProjectState tuning,
  Map<String, double>? previousAppliedGains,
}) {
  final ts = DateTime.now().millisecondsSinceEpoch;
  int seq = 0;

  final blocks = <ExportParameterBlock>[];
  for (final ch in channels) {
    final ctrl = tuning.getOrCreateControl(ch.id);
    final gainDb = ctrl.gainDb;
    final prev = previousAppliedGains?[ch.id];
    if (prev != null) {
      // Known previous: skip if the gain hasn't changed.
      if ((gainDb - prev).abs() < 0.001) continue;
    } else {
      // Unknown previous: skip 0.0 dB (ADAU1701 hardware default).
      // Writing 0.0 to an untouched channel would silently overwrite
      // whatever the DSP currently holds for that channel.
      if (gainDb.abs() < 0.001) continue;
    }
    blocks.add(ExportParameterBlock(
      id: 'blk_gain_${ch.id}_${ts}_${seq++}',
      type: ExportBlockType.gain,
      channelId: ch.id,
      title: '${ch.name} Gain',
      summary: '${gainDb >= 0 ? '+' : ''}${gainDb.toStringAsFixed(1)} dB',
      parameters: {
        'gainDb': gainDb,
        'channelName': ch.name,
        if (prev != null) 'previousGainDb': prev,
      },
    ));
  }

  return DspExportPackage(
    id: 'eng_gain_$ts',
    targetPlatform: DspTargetPlatform.adau1701,
    format: ExportFormat.hardwareWritePlanPlaceholder,
    status: blocks.isEmpty ? ExportStatus.notReady : ExportStatus.draftReady,
    projectName: 'Engineering gain write',
    tuningRevision: tuning.tuningRevision,
    protectionRevision: 0,
    optimizerRevision: 0,
    blockedReason: blocks.isEmpty ? 'No gain changes to write.' : null,
    parameterBlocks: blocks,
  );
}

/// Builds [ExportParameterBlock]s for PEQ and crossover from [tuning] for
/// the channels listed in [channels]. Channels with no enabled PEQ bands and
/// no configured XO filters are skipped.
///
/// Band indices in the PEQ blocks are the original positions in [PeqChannelState.bands]
/// so that the capability layer (band_0 = Band 1 = capture-proven) resolves
/// correctly.
List<ExportParameterBlock> buildAdau1701PeqXoExportBlocks({
  required List<DriverChannel> channels,
  required TuningProjectState tuning,
}) {
  final ts = DateTime.now().millisecondsSinceEpoch;
  int seq = 0;
  final channelIds = {for (final ch in channels) ch.id};
  final blocks = <ExportParameterBlock>[];

  for (final peqCh in tuning.peqChannels) {
    if (!channelIds.contains(peqCh.channelId)) continue;
    // Preserve original band positions — band_0 = Band 1 = capture-proven.
    final bandsJson = <String, dynamic>{};
    for (var i = 0; i < peqCh.bands.length; i++) {
      final b = peqCh.bands[i];
      if (!b.enabled) continue;
      bandsJson['band_$i'] = {
        'freq_hz': b.frequencyHz,
        'gain_db': b.gainDb,
        'q': b.q,
      };
    }
    if (bandsJson.isEmpty) continue;
    blocks.add(ExportParameterBlock(
      id: 'blk_peq_${peqCh.channelId}_${ts}_${seq++}',
      type: ExportBlockType.peq,
      channelId: peqCh.channelId,
      title: '${peqCh.channelId} PEQ',
      summary: '${bandsJson.length} band(s)',
      parameters: {'bands': bandsJson},
    ));
  }

  for (final xoCh in tuning.crossoverChannels) {
    if (!channelIds.contains(xoCh.channelId)) continue;
    if (!xoCh.isConfigured) continue;
    final params = <String, dynamic>{};
    if (xoCh.hasHighPass) params['highPass'] = {'freq_hz': xoCh.highPass!.frequencyHz};
    if (xoCh.hasLowPass) params['lowPass'] = {'freq_hz': xoCh.lowPass!.frequencyHz};
    blocks.add(ExportParameterBlock(
      id: 'blk_xo_${xoCh.channelId}_${ts}_${seq++}',
      type: ExportBlockType.crossover,
      channelId: xoCh.channelId,
      title: '${xoCh.channelId} XO',
      summary: [
        if (xoCh.hasHighPass) 'HPF @ ${xoCh.highPass!.freqLabel}',
        if (xoCh.hasLowPass) 'LPF @ ${xoCh.lowPass!.freqLabel}',
      ].join(' / '),
      parameters: params,
    ));
  }

  return blocks;
}
