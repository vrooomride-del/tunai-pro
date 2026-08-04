// TUNAI PRO UI/UX v3 Phase V3-2/V3-3 — Channel Compare Layer + Shared
// Channel Context.
//
// Session-only UI state for (a) which driver channel is currently selected
// across PEQ/XO/Gain/Delay tabs (v3-3, [ChannelCompareState.currentChannelId])
// and (b) comparing that channel against one or more "compare" channels
// (v3-2, e.g. Woofer L vs Woofer R) on the PEQ response graph. NOT persisted
// to ProProjectStore/ProProject — mirrors the existing ephemeral-provider
// pattern (workbenchTabProvider, graphOverlayModeProvider from v3-1). Carries
// no PEQ/tuning data of its own — only channelId references and the
// mode/enabled flags a tab uses to build overlayCurves.
//
// v3-3: [currentChannelId] replaces what each of peq_tab.dart/xo_tab.dart/
// gain_tab.dart/delay_tab.dart previously tracked as a private, per-tab
// `_selectedChannelId` — selecting a channel in one tab now persists when
// opening another. Only the channelId (String) is ever stored here — never
// a DriverChannel object (see the audit: DriverChannel carries frdData/
// zmaData that can go stale independently of this session-only provider).
// Each tab is still responsible for re-deriving the DriverChannel/tuning
// data for that id from proProjectStoreProvider on every build, exactly as
// before this migration.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/workbench/widgets/graph_overlay_models.dart';
import 'pro_acoustic_data.dart';

class ChannelCompareState {
  /// The channel currently selected across PEQ/XO/Gain/Delay tabs. Null
  /// before any selection has been made (or after [ChannelCompareNotifier.reset]).
  final String? currentChannelId;

  /// Additional channel ids to compare against [currentChannelId] on the PEQ
  /// response graph. Order is preserved for stable curve coloring/legend
  /// order.
  final List<String> compareChannelIds;

  /// Whether compare mode is currently on. When false, callers should show
  /// the graph exactly as before v3-1 (no overlayCurves).
  final bool compareEnabled;

  /// Overlay/difference selection while compare is enabled. Compare is never
  /// shown in [PeqGraphMode.single] — enabling compare with mode left at
  /// single defaults display to overlay (see [ChannelCompareNotifier.setCompareEnabled]).
  final PeqGraphMode mode;

  const ChannelCompareState({
    this.currentChannelId,
    this.compareChannelIds = const [],
    this.compareEnabled = false,
    this.mode = PeqGraphMode.overlay,
  });

  ChannelCompareState copyWith({
    List<String>? compareChannelIds,
    bool? compareEnabled,
    PeqGraphMode? mode,
  }) =>
      ChannelCompareState(
        currentChannelId: currentChannelId,
        compareChannelIds: compareChannelIds ?? this.compareChannelIds,
        compareEnabled: compareEnabled ?? this.compareEnabled,
        mode: mode ?? this.mode,
      );
}

class ChannelCompareNotifier extends StateNotifier<ChannelCompareState> {
  ChannelCompareNotifier() : super(const ChannelCompareState());

  /// Sets the shared current channel. Pass null to clear the selection
  /// (equivalent to [reset] for that one field, but keeps compareEnabled/mode
  /// — prefer [reset] when a project changes).
  void setCurrentChannel(String? channelId) {
    if (state.currentChannelId == channelId) return;
    // Switching the current channel clears any stale compare selection —
    // a compare channel picked for the previous selection rarely still
    // makes sense (e.g. leaving Woofer L's "compare Woofer R" set while
    // switching to a Tweeter). compareEnabled/mode are left as-is.
    state = ChannelCompareState(
      currentChannelId: channelId,
      compareChannelIds: const [],
      compareEnabled: state.compareEnabled,
      mode: state.mode,
    );
  }

  /// Full reset back to the initial state — no current channel, no compare
  /// selection, compare off, default mode. Intended for a project switch,
  /// where any previously-selected channelId belongs to a different project
  /// and must not leak into the newly-opened one.
  void reset() {
    state = const ChannelCompareState();
  }

  /// Safety check a tab calls with the *current project's* driver channel
  /// ids. If [currentChannelId] is set but no longer present among
  /// [validChannelIds] (e.g. the project changed, or a channel was removed),
  /// the whole state is [reset] rather than left pointing at a channel that
  /// no longer exists. No-op when the current selection is still valid (or
  /// unset) — safe to call on every build.
  void validateAgainstDrivers(List<String> validChannelIds) {
    final current = state.currentChannelId;
    if (current != null && !validChannelIds.contains(current)) {
      reset();
    }
  }

  void setCompareEnabled(bool enabled) {
    state = state.copyWith(compareEnabled: enabled);
  }

  void setMode(PeqGraphMode mode) {
    state = state.copyWith(mode: mode);
  }

  void toggleCompareChannel(String channelId) {
    final next = List<String>.from(state.compareChannelIds);
    if (!next.remove(channelId)) next.add(channelId);
    state = state.copyWith(compareChannelIds: next);
  }

  void setCompareChannels(List<String> channelIds) {
    state = state.copyWith(compareChannelIds: channelIds);
  }
}

final channelCompareProvider =
    StateNotifierProvider<ChannelCompareNotifier, ChannelCompareState>(
        (ref) => ChannelCompareNotifier());

// ── v3-3: shared-selection fallback resolution ─────────────────────────────

/// Resolves the effective selected channel id for a tab's current
/// [driverIds] against the shared [state]: returns the shared
/// `currentChannelId` when it's still present among [driverIds], otherwise
/// falls back to the first id — the exact fallback every tab used pre-v3-3
/// (`_selectedChannelId ?? drivers.first.id`). Returns null only when
/// [driverIds] itself is empty (callers already handle the empty-drivers
/// case separately before reaching channel selection).
///
/// Pure — never mutates [state]. A caller that finds the stored id has gone
/// stale (this function fell back) should schedule
/// [ChannelCompareNotifier.validateAgainstDrivers] via a post-frame
/// callback so the shared provider is corrected — state must never be
/// mutated synchronously during a widget's build.
String? resolveSelectedChannelId(
  ChannelCompareState state,
  List<String> driverIds,
) {
  final stored = state.currentChannelId;
  if (stored != null && driverIds.contains(stored)) return stored;
  return driverIds.isEmpty ? null : driverIds.first;
}

/// Resolves the [DriverChannel] for [id] among [drivers], or null when [id]
/// is null or not found. Pure — never stores or caches a DriverChannel;
/// callers (e.g. [CurrentDriverHeader]) must call this fresh on every build,
/// exactly like the per-tab `drivers.firstWhere(...)` lookups this mirrors.
DriverChannel? driverChannelFor(String? id, List<DriverChannel> drivers) {
  if (id == null) return null;
  for (final d in drivers) {
    if (d.id == id) return d;
  }
  return null;
}

// ── Channel pairing (role + side, NEVER DAC index) ────────────────────────

/// The same-role, opposite-side channel id for [channelId] among [channels],
/// or null when [channelId] isn't found, has no left/right side (mono/
/// shared), or has no matching counterpart. Pairing uses only
/// [DriverChannel.role]/[DriverChannel.side] — [DriverChannel.dspOutputIndex]
/// (DAC index) is never consulted.
String? pairChannelIdFor(String channelId, List<DriverChannel> channels) {
  DriverChannel? current;
  for (final c in channels) {
    if (c.id == channelId) {
      current = c;
      break;
    }
  }
  if (current == null) return null;
  final DriverSide opposite;
  switch (current.side) {
    case DriverSide.left:
      opposite = DriverSide.right;
    case DriverSide.right:
      opposite = DriverSide.left;
    case DriverSide.mono:
    case DriverSide.shared:
      return null;
  }
  for (final c in channels) {
    if (c.role == current.role && c.side == opposite) return c.id;
  }
  return null;
}

/// All same-role, opposite-side pairs among [channels] as a
/// `channelId -> pairedChannelId` map (populated both directions, e.g. both
/// `ch_wf_l -> ch_wf_r` and `ch_wf_r -> ch_wf_l`). Channels with no
/// counterpart (mono/shared, or an unpaired role) are simply absent.
Map<String, String> channelPairsByRoleAndSide(List<DriverChannel> channels) {
  final result = <String, String>{};
  for (final c in channels) {
    final pair = pairChannelIdFor(c.id, channels);
    if (pair != null) result[c.id] = pair;
  }
  return result;
}
