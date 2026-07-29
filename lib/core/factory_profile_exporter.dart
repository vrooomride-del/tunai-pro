// Deterministic JSON export of a FactorySoundProfile.
//
// Output contains no raw DSP register addresses, no BLE/USB transport
// payloads, and no SafeLoad packets. Only logical DSP values (frequencyHz,
// gainDb, q) from the existing TuningProjectState model are included.

import 'factory_sound_profile.dart';
import 'pro_tuning_data.dart';

const _kFactoryProfileSchemaVersion = 1;

/// Known hardware targets that are supported for export.
/// Returns an explicit error when the target is not in this set.
const _kSupportedExportTargets = {
  'ADAU1701',
  'ADAU1466',
  'ADAU1401',
  'ADAU1401A',
};

abstract final class FactoryProfileExporter {
  /// Export [profile] to a JSON-serializable [Map].
  ///
  /// Throws [UnsupportedHardwareExportError] when
  /// [profile.hardwareTarget] is not in the supported set.
  ///
  /// Field order is deterministic: metadata → hardware → channels →
  /// validation → fingerprint → references.
  static Map<String, dynamic> toJson(FactorySoundProfile profile) {
    if (!_kSupportedExportTargets.contains(profile.hardwareTarget)) {
      throw UnsupportedHardwareExportError(profile.hardwareTarget);
    }

    final channels = _exportChannels(profile.tuningSnapshot);

    return {
      'schemaVersion': _kFactoryProfileSchemaVersion,
      'profileId': profile.profileId,
      'profileName': profile.profileName,
      'profileVersion': profile.version,
      'projectId': profile.projectId,
      'createdAt': profile.createdAt.toIso8601String(),
      if (profile.updatedAt != null)
        'updatedAt': profile.updatedAt!.toIso8601String(),
      'hardware': {
        'target': profile.hardwareTarget,
        'sampleRate': profile.sampleRate,
        'channelConfig': profile.channelConfig,
      },
      'channels': channels,
      'validation': {
        'status': profile.validationStatus,
        'notes': profile.validationNotes,
        if (profile.manuallyApproved) ...{
          'manuallyApproved': true,
          if (profile.approvalNote != null)
            'approvalNote': profile.approvalNote,
        },
      },
      'correctionCycles': {
        'completedCycleNumbers': profile.completedCycleNumbers,
        'count': profile.completedCycleNumbers.length,
      },
      'measurementRefs': profile.measurementRefs,
      'projectFingerprint': profile.projectFingerprint,
    };
  }

  static List<Map<String, dynamic>> _exportChannels(
      TuningProjectState tuning) {
    final result = <Map<String, dynamic>>[];

    for (final peq in tuning.peqChannels) {
      final xo = tuning.crossoverChannels
          .where((c) => c.channelId == peq.channelId)
          .firstOrNull;
      final ctrl = tuning.channelControls
          .where((c) => c.channelId == peq.channelId)
          .firstOrNull;

      result.add({
        'channelId': peq.channelId,
        'xo': xo != null ? _xoToJson(xo) : null,
        'peq': _peqToJson(peq),
        'gain': ctrl != null ? _gainToJson(ctrl) : null,
        'delay': ctrl != null ? _delayToJson(ctrl) : null,
        'polarity': ctrl != null ? _polarityToJson(ctrl, xo) : null,
      });
    }

    return result;
  }

  static Map<String, dynamic> _xoToJson(CrossoverChannelState xo) => {
        'channelId': xo.channelId,
        'bypassed': xo.bypassed,
        'polarityInverted': xo.polarityInverted,
        'highPass': xo.highPass != null ? _filterToJson(xo.highPass!) : null,
        'lowPass': xo.lowPass != null ? _filterToJson(xo.lowPass!) : null,
      };

  static Map<String, dynamic> _filterToJson(CrossoverFilter f) => {
        'enabled': f.enabled,
        'side': f.side.name,
        'type': f.type.name,
        'slope': f.slope.name,
        'frequencyHz': f.frequencyHz,
        if (f.note != null) 'note': f.note,
      };

  static Map<String, dynamic> _peqToJson(PeqChannelState peq) => {
        'channelId': peq.channelId,
        'bypassed': peq.bypassed,
        'bands': [
          for (final b in peq.bands)
            if (b.enabled)
              {
                'id': b.id,
                'type': b.type.name,
                'frequencyHz': b.frequencyHz,
                if (b.type.hasGain) 'gainDb': b.gainDb,
                if (b.type.hasQ) 'q': b.q,
                'status': b.status.name,
              },
        ],
      };

  static Map<String, dynamic> _gainToJson(ChannelControlState ctrl) => {
        'channelId': ctrl.channelId,
        'gainDb': ctrl.gainDb,
        'muted': ctrl.muted,
      };

  static Map<String, dynamic> _delayToJson(ChannelControlState ctrl) => {
        'channelId': ctrl.channelId,
        'delayMs': ctrl.delayMs,
      };

  static Map<String, dynamic> _polarityToJson(
    ChannelControlState ctrl,
    CrossoverChannelState? xo,
  ) =>
      {
        'channelId': ctrl.channelId,
        'phaseOffsetDeg': ctrl.phaseOffsetDeg,
        'polarityInverted': xo?.polarityInverted ?? false,
      };
}

// ── Error ─────────────────────────────────────────────────────────────────────

class UnsupportedHardwareExportError implements Exception {
  final String target;
  const UnsupportedHardwareExportError(this.target);

  @override
  String toString() =>
      'UnsupportedHardwareExportError: hardware target "$target" is not '
      'supported for Factory Sound Profile JSON export.';
}
