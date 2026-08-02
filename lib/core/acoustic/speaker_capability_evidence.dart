import '../pro_project.dart';

enum SpeakerCapabilityStatus { known, unknown, unsafe }

/// Immutable, channel-scoped evidence. Null means the project did not prove
/// the value; no capability default is inferred.
class SpeakerCapabilityEvidence {
  final String channelId;
  final SpeakerCapabilityStatus status;
  final double? maxHeadroomDb;
  final double? protectionLimitDb;
  final List<String> evidenceRefs;

  const SpeakerCapabilityEvidence({
    required this.channelId,
    required this.status,
    this.maxHeadroomDb,
    this.protectionLimitDb,
    this.evidenceRefs = const [],
  });

  double? get protectionMarginDb => protectionLimitDb;

  bool permitsGain(double gainDb) {
    if (status == SpeakerCapabilityStatus.unsafe) return false;
    if (status != SpeakerCapabilityStatus.known) return true;
    if (maxHeadroomDb != null && gainDb > maxHeadroomDb!) return false;
    if (protectionLimitDb != null && gainDb < -protectionLimitDb!) return false;
    return true;
  }

  static Map<String, SpeakerCapabilityEvidence> fromProject(ProProject project) {
    final result = <String, SpeakerCapabilityEvidence>{};
    for (final channel in project.acousticState.driverChannels) {
      final refs = <String>[];
      if (channel.zmaData?.hasImpedance == true) refs.add(channel.zmaData!.id);
      final rules = project.protectionState.rules.where((r) => r.enabled).toList();
      final headroom = rules.where((r) => r.type.name == 'headroomReserve').firstOrNull;
      final maxCut = rules.where((r) => r.type.name == 'maxCut').firstOrNull;
      final headroomDb = headroom?.threshold.isFinite == true ? headroom!.threshold : null;
      final protectionDb = maxCut?.threshold.isFinite == true && maxCut!.threshold < 0
          ? maxCut.threshold.abs()
          : null;
      final status = channel.zmaData?.hasImpedance == true &&
              (headroomDb != null || protectionDb != null)
          ? SpeakerCapabilityStatus.known
          : SpeakerCapabilityStatus.unknown;
      result[channel.id] = SpeakerCapabilityEvidence(
        channelId: channel.id,
        status: status,
        maxHeadroomDb: headroomDb,
        protectionLimitDb: protectionDb,
        evidenceRefs: List.unmodifiable(refs),
      );
    }
    return Map.unmodifiable(result);
  }
}
