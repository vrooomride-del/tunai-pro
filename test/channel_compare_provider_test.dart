// TUNAI PRO UI/UX v3 Phase V3-2/V3-3 — Channel Compare Layer + Shared
// Channel Context.
//
// Unit tests for channel_compare_provider.dart: role+side pairing (never DAC
// index), the session-only ChannelCompareNotifier state transitions, and
// (v3-3) resolveSelectedChannelId's fallback resolution.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/channel_compare_provider.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/features/workbench/widgets/graph_overlay_models.dart';

const _kChannels = [
  DriverChannel(
      id: 'ch_tw_l', name: 'Tweeter L', role: DriverRole.tweeter,
      side: DriverSide.left, dspOutputIndex: 1),
  DriverChannel(
      id: 'ch_tw_r', name: 'Tweeter R', role: DriverRole.tweeter,
      side: DriverSide.right, dspOutputIndex: 3),
  DriverChannel(
      id: 'ch_wf_l', name: 'Woofer L', role: DriverRole.woofer,
      side: DriverSide.left, dspOutputIndex: 2),
  DriverChannel(
      id: 'ch_wf_r', name: 'Woofer R', role: DriverRole.woofer,
      side: DriverSide.right, dspOutputIndex: 4),
  DriverChannel(
      id: 'ch_sw', name: 'Subwoofer', role: DriverRole.subwoofer,
      side: DriverSide.mono, dspOutputIndex: 5),
];

void main() {
  group('pairChannelIdFor / channelPairsByRoleAndSide — role+side, never DAC index', () {
    test('woofer L pairs with woofer R', () {
      expect(pairChannelIdFor('ch_wf_l', _kChannels), 'ch_wf_r');
      expect(pairChannelIdFor('ch_wf_r', _kChannels), 'ch_wf_l');
    });

    test('tweeter L pairs with tweeter R', () {
      expect(pairChannelIdFor('ch_tw_l', _kChannels), 'ch_tw_r');
      expect(pairChannelIdFor('ch_tw_r', _kChannels), 'ch_tw_l');
    });

    test('mono channel has no pair', () {
      expect(pairChannelIdFor('ch_sw', _kChannels), isNull);
    });

    test('unknown channel id has no pair', () {
      expect(pairChannelIdFor('does_not_exist', _kChannels), isNull);
    });

    test('a role with no opposite-side counterpart has no pair', () {
      const solo = [
        DriverChannel(
            id: 'ch_mid_l', name: 'Mid L', role: DriverRole.midrange,
            side: DriverSide.left, dspOutputIndex: 6),
      ];
      expect(pairChannelIdFor('ch_mid_l', solo), isNull);
    });

    test('pairing never consults dspOutputIndex (DAC index)', () {
      // Deliberately give the "wrong" DAC ordering (R has a lower index than
      // L) — pairing must still resolve purely from role+side.
      const shuffled = [
        DriverChannel(
            id: 'ch_wf_l', name: 'Woofer L', role: DriverRole.woofer,
            side: DriverSide.left, dspOutputIndex: 9),
        DriverChannel(
            id: 'ch_wf_r', name: 'Woofer R', role: DriverRole.woofer,
            side: DriverSide.right, dspOutputIndex: 0),
      ];
      expect(pairChannelIdFor('ch_wf_l', shuffled), 'ch_wf_r');
    });

    test('channelPairsByRoleAndSide populates both directions for every pair',
        () {
      final pairs = channelPairsByRoleAndSide(_kChannels);
      expect(pairs['ch_wf_l'], 'ch_wf_r');
      expect(pairs['ch_wf_r'], 'ch_wf_l');
      expect(pairs['ch_tw_l'], 'ch_tw_r');
      expect(pairs['ch_tw_r'], 'ch_tw_l');
      expect(pairs.containsKey('ch_sw'), isFalse);
    });
  });

  group('ChannelCompareNotifier — session state transitions', () {
    late ProviderContainer container;
    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('initial state: no current channel, no compare channels, compare off, overlay mode', () {
      final state = container.read(channelCompareProvider);
      expect(state.currentChannelId, isNull);
      expect(state.compareChannelIds, isEmpty);
      expect(state.compareEnabled, isFalse);
      expect(state.mode, PeqGraphMode.overlay);
    });

    test('setCurrentChannel updates currentChannelId and clears compare selection', () {
      final notifier = container.read(channelCompareProvider.notifier);
      notifier.toggleCompareChannel('ch_wf_r');
      expect(container.read(channelCompareProvider).compareChannelIds, ['ch_wf_r']);

      notifier.setCurrentChannel('ch_wf_l');
      final state = container.read(channelCompareProvider);
      expect(state.currentChannelId, 'ch_wf_l');
      expect(state.compareChannelIds, isEmpty,
          reason: 'switching the current channel clears a stale compare selection');
    });

    test('setCurrentChannel with the same id is a no-op (keeps compare selection)', () {
      final notifier = container.read(channelCompareProvider.notifier);
      notifier.setCurrentChannel('ch_wf_l');
      notifier.toggleCompareChannel('ch_wf_r');
      notifier.setCurrentChannel('ch_wf_l'); // same id again
      expect(container.read(channelCompareProvider).compareChannelIds, ['ch_wf_r']);
    });

    test('setCurrentChannel(null) clears the selection but keeps compareEnabled/mode', () {
      final notifier = container.read(channelCompareProvider.notifier);
      notifier.setCurrentChannel('ch_wf_l');
      notifier.setCompareEnabled(true);
      notifier.setMode(PeqGraphMode.difference);

      notifier.setCurrentChannel(null);
      final state = container.read(channelCompareProvider);
      expect(state.currentChannelId, isNull);
      expect(state.compareEnabled, isTrue);
      expect(state.mode, PeqGraphMode.difference);
    });

    test('reset() clears everything back to the initial state', () {
      final notifier = container.read(channelCompareProvider.notifier);
      notifier.setCurrentChannel('ch_wf_l');
      notifier.toggleCompareChannel('ch_wf_r');
      notifier.setCompareEnabled(true);
      notifier.setMode(PeqGraphMode.difference);

      notifier.reset();
      final state = container.read(channelCompareProvider);
      expect(state.currentChannelId, isNull);
      expect(state.compareChannelIds, isEmpty);
      expect(state.compareEnabled, isFalse);
      expect(state.mode, PeqGraphMode.overlay);
    });

    test('validateAgainstDrivers resets when the current channel is no longer valid', () {
      final notifier = container.read(channelCompareProvider.notifier);
      notifier.setCurrentChannel('ch_wf_l');
      notifier.toggleCompareChannel('ch_wf_r');

      notifier.validateAgainstDrivers(['ch_tw_l', 'ch_tw_r']); // different project
      final state = container.read(channelCompareProvider);
      expect(state.currentChannelId, isNull);
      expect(state.compareChannelIds, isEmpty);
    });

    test('validateAgainstDrivers is a no-op when the current channel is still valid', () {
      final notifier = container.read(channelCompareProvider.notifier);
      notifier.setCurrentChannel('ch_wf_l');
      notifier.toggleCompareChannel('ch_wf_r');

      notifier.validateAgainstDrivers(['ch_wf_l', 'ch_wf_r']);
      final state = container.read(channelCompareProvider);
      expect(state.currentChannelId, 'ch_wf_l');
      expect(state.compareChannelIds, ['ch_wf_r']);
    });

    test('validateAgainstDrivers is a no-op when there is no current channel', () {
      final notifier = container.read(channelCompareProvider.notifier);
      notifier.validateAgainstDrivers(['ch_wf_l', 'ch_wf_r']);
      expect(container.read(channelCompareProvider).currentChannelId, isNull);
    });

    test('setCompareEnabled toggles compareEnabled only', () {
      final notifier = container.read(channelCompareProvider.notifier);
      notifier.setCompareEnabled(true);
      expect(container.read(channelCompareProvider).compareEnabled, isTrue);
      notifier.setCompareEnabled(false);
      expect(container.read(channelCompareProvider).compareEnabled, isFalse);
    });

    test('toggleCompareChannel adds then removes', () {
      final notifier = container.read(channelCompareProvider.notifier);
      notifier.toggleCompareChannel('ch_wf_r');
      expect(container.read(channelCompareProvider).compareChannelIds, ['ch_wf_r']);
      notifier.toggleCompareChannel('ch_wf_r');
      expect(container.read(channelCompareProvider).compareChannelIds, isEmpty);
    });

    test('setMode updates the overlay/difference selection', () {
      final notifier = container.read(channelCompareProvider.notifier);
      notifier.setMode(PeqGraphMode.difference);
      expect(container.read(channelCompareProvider).mode, PeqGraphMode.difference);
    });
  });

  group('resolveSelectedChannelId — v3-3 shared fallback resolution', () {
    const driverIds = ['ch_wf_l', 'ch_wf_r', 'ch_tw_l'];

    test('returns the stored currentChannelId when it is still valid', () {
      const state = ChannelCompareState(currentChannelId: 'ch_wf_r');
      expect(resolveSelectedChannelId(state, driverIds), 'ch_wf_r');
    });

    test('falls back to the first driver id when currentChannelId is null', () {
      const state = ChannelCompareState();
      expect(resolveSelectedChannelId(state, driverIds), 'ch_wf_l');
    });

    test('falls back to the first driver id when the stored id is stale '
        '(e.g. after a project change)', () {
      const state = ChannelCompareState(currentChannelId: 'ch_from_other_project');
      expect(resolveSelectedChannelId(state, driverIds), 'ch_wf_l');
    });

    test('returns null when driverIds itself is empty', () {
      const state = ChannelCompareState(currentChannelId: 'ch_wf_l');
      expect(resolveSelectedChannelId(state, const []), isNull);
    });

    test('never mutates the passed-in state', () {
      const state = ChannelCompareState(currentChannelId: 'ch_from_other_project');
      resolveSelectedChannelId(state, driverIds);
      // Still the original, unresolved value — resolveSelectedChannelId is pure.
      expect(state.currentChannelId, 'ch_from_other_project');
    });
  });
}
