// ── TUNAI PRO Phase 3-E §15 — diagnostics surface visibility ───────────────
//
// The Measure tab's MeasurementSession panels (session list/detail, the
// simulated-capture button, the "SIMULATED DATA" indicator and the
// session-based workflow card) predate the real capture path. They are still
// useful for development, but in the guided production workflow they sit
// directly on the path a beginner is sent down by Home's Continue Tuning —
// where synthetic curves must never be mistaken for a real measurement.
//
// So they are hidden by default and revealed only by an explicit, per-session
// user action. This deletes nothing: the panels, the store and their
// behaviour are unchanged, and toggling this on restores them exactly.
//
// Session-scoped on purpose — never persisted, so a fresh launch is always
// back to the production surface.

library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// False in the production guided workflow. Never written from anywhere but
/// an explicit user toggle.
final diagnosticsVisibleProvider = StateProvider<bool>((ref) => false);
