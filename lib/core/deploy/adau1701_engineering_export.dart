// Builds a minimal ADAU1701 export package from the current tuning state
// for engineering manual writes (channel gain, etc.).
//
// Does NOT require protection verification, FRD data, simulation results,
// Factory Sound Profile eligibility, or any correction cycle. This is a
// direct hardware control path for DSP engineers — the same safety chain
// (preflight → write → ACK) still applies.
//
// Only produces ExportBlockType.gain blocks today. PEQ/XO are separate paths
// that share the same executor.

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
