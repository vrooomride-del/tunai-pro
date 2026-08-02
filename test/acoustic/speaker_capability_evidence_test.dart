import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/speaker_capability_evidence.dart';

void main() {
  test('known evidence calculates margin and permits within limit', () {
    const evidence = SpeakerCapabilityEvidence(
      channelId: 'ch_tw_l',
      status: SpeakerCapabilityStatus.known,
      maxHeadroomDb: 3,
      protectionLimitDb: 6,
    );
    expect(evidence.protectionMarginDb, 6);
    expect(evidence.permitsGain(-6), isTrue);
    expect(evidence.permitsGain(-6.1), isFalse);
  });

  test('unknown evidence is neutral and unsafe evidence rejects', () {
    const unknown = SpeakerCapabilityEvidence(
        channelId: 'ch_wf_l', status: SpeakerCapabilityStatus.unknown);
    const unsafe = SpeakerCapabilityEvidence(
        channelId: 'ch_wf_r', status: SpeakerCapabilityStatus.unsafe);
    expect(unknown.permitsGain(-6), isTrue);
    expect(unsafe.permitsGain(-1), isFalse);
  });

  test('channel IDs remain explicit for four-channel evidence', () {
    final map = {
      for (final id in ['ch_tw_l', 'ch_wf_l', 'ch_tw_r', 'ch_wf_r'])
        id: SpeakerCapabilityEvidence(
            channelId: id, status: SpeakerCapabilityStatus.unknown),
    };
    expect(map.keys, containsAll(['ch_tw_l', 'ch_wf_l', 'ch_tw_r', 'ch_wf_r']));
  });
}
