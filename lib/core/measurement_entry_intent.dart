// ── TUNAI PRO Phase 3-E P0 §5 — Measurement entry intent ───────────────────
//
// Home's Continue Tuning does more than switch tabs: it says WHICH part of
// the Measure tab the user was sent for. Landing on a dense professional tab
// and having to hunt for the microphone settings is the bug this closes.
//
// Strictly one-shot and typed:
//   - no string matching, no delayed/timer hack to open a dialog;
//   - carries the projectId it was raised for, so a request cannot leak
//     across a project switch;
//   - carries a monotonic id, so consuming is an explicit compare-and-clear
//     rather than "whatever is in the provider right now";
//   - cleared the moment it is consumed, so a rebuild never reopens a dialog
//     and closing one never triggers it again.
//
// This is not a second navigation system: the tab change still goes through
// workbenchTabProvider. This only says what to do once you get there.

library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the user was sent to the Measure tab to do.
enum MeasurementEntryIntent {
  /// Choose or register a measurement microphone.
  manageMicrophone,

  /// Fix/import the selected microphone's calibration.
  manageCalibration,

  /// Choose the input device (lives in Guided Measurement Setup).
  selectInputDevice,

  /// Run the Guided Measurement Setup check.
  runSetupCheck,

  /// Factory (per-driver) capture.
  factoryMeasurement,

  /// Room Before capture.
  roomBefore,

  /// Room After capture.
  roomAfter,

  /// Review the Closed Loop verdict.
  closedLoopReview,
}

/// A single pending request. Immutable; replaced wholesale, never mutated.
class MeasurementEntryRequest {
  final MeasurementEntryIntent intent;

  /// The project this was raised for. A request for another project is
  /// ignored rather than applied to whatever happens to be open.
  final String projectId;

  /// Distinguishes two consecutive identical requests, so "the same intent
  /// again" is still a new request and consuming is unambiguous.
  final int id;

  const MeasurementEntryRequest({
    required this.intent,
    required this.projectId,
    required this.id,
  });

  bool matches(String otherProjectId) => projectId == otherProjectId;

  @override
  String toString() => 'MeasurementEntryRequest($intent, $projectId, #$id)';
}

class MeasurementEntryIntentNotifier
    extends StateNotifier<MeasurementEntryRequest?> {
  MeasurementEntryIntentNotifier() : super(null);

  int _seq = 0;

  /// Raises a request. Replaces any unconsumed one — the newest instruction
  /// is the only one that can still be what the user meant.
  void request(MeasurementEntryIntent intent, {required String projectId}) {
    state = MeasurementEntryRequest(
      intent: intent,
      projectId: projectId,
      id: ++_seq,
    );
  }

  /// Consumes the pending request for [projectId], or returns null.
  ///
  /// Clearing happens here, inside the same call that hands the value out,
  /// so a caller cannot read it twice and a rebuild cannot re-trigger it.
  ///
  /// A request naming a DIFFERENT project (or any request at all when
  /// [projectId] is null, i.e. no project is open) is discarded rather than
  /// kept: this is a navigation command describing one journey the user just
  /// started, not persisted workflow state. Holding it would let a stale
  /// instruction fire late — open project A's CTA, detour through project B,
  /// come back to A, and a dialog the user had moved on from would appear.
  /// Requesting the same intent again simply issues a new request.
  MeasurementEntryIntent? consume(String? projectId) {
    final pending = state;
    if (pending == null) return null;
    if (projectId == null || !pending.matches(projectId)) {
      state = null;
      return null;
    }
    state = null;
    return pending.intent;
  }

  /// Drops any pending request without acting on it.
  void clear() => state = null;
}

final measurementEntryIntentProvider = StateNotifierProvider<
    MeasurementEntryIntentNotifier, MeasurementEntryRequest?>(
  (ref) => MeasurementEntryIntentNotifier(),
);
