import '../acoustic/full_system_candidate_evaluator.dart';
import '../pro_acoustic_data.dart';
import '../pro_project.dart';

/// Collects post-Deploy FRDs without replacing the factory (Before) project.
class FullSystemAfterFrdInput {
  final ProProject beforeProject;
  final Map<String, ParsedMeasurementData> _afterByChannel = {};

  FullSystemAfterFrdInput(this.beforeProject);

  Map<String, ParsedMeasurementData> get afterByChannel =>
      Map.unmodifiable(_afterByChannel);

  bool get isComplete =>
      _afterByChannel.length ==
          FullSystemCandidateEvaluator.requiredChannelIds.length &&
      FullSystemCandidateEvaluator.requiredChannelIds
          .every(_afterByChannel.containsKey);

  void add({
    required String channelId,
    required ParsedMeasurementData afterFrd,
  }) {
    if (!FullSystemCandidateEvaluator.requiredChannelIds.contains(channelId)) {
      throw ArgumentError.value(channelId, 'channelId', 'unexpected channel');
    }
    if (_afterByChannel.containsKey(channelId)) {
      throw StateError('After FRD already loaded for $channelId.');
    }
    if (!afterFrd.hasMagnitude) {
      throw StateError('After FRD has no magnitude data for $channelId.');
    }
    final before = beforeProject.acousticState.driverChannels
        .where((channel) => channel.id == channelId)
        .toList();
    if (before.length != 1 || before.single.frdData == null) {
      throw StateError(
          'Factory Before FRD is missing or duplicated for $channelId.');
    }
    if (before.single.frdData!.id == afterFrd.id) {
      throw StateError('Before and After FRD identities must be different.');
    }
    _afterByChannel[channelId] = afterFrd;
  }

  ProProject buildAfterProject() {
    if (!isComplete) {
      throw StateError('All four channel After FRDs are required.');
    }
    final channels = beforeProject.acousticState.driverChannels.map((channel) {
      final after = _afterByChannel[channel.id];
      return after == null
          ? channel
          : channel.copyWith(
              frdData: after,
              measurementStatus: MeasurementStatus.imported,
            );
    }).toList(growable: false);
    return beforeProject.copyWith(
      acousticState:
          beforeProject.acousticState.copyWith(driverChannels: channels),
    );
  }

  Map<String, String> get beforeEvidenceRefs => {
        for (final id in FullSystemCandidateEvaluator.requiredChannelIds)
          id: beforeProject.acousticState.driverChannels
              .singleWhere((channel) => channel.id == id)
              .frdData!
              .id,
      };

  Map<String, String> get afterEvidenceRefs => {
        for (final id in FullSystemCandidateEvaluator.requiredChannelIds)
          if (_afterByChannel[id] != null) id: _afterByChannel[id]!.id,
      };
}
