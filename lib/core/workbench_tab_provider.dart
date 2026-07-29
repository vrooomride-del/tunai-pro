// Cross-tab navigation for WorkbenchShell.
//
// WorkbenchShell watches this provider and switches its IndexedStack index
// when a child widget calls WorkbenchTabNotifier.go(). No second navigation
// system is introduced — the sidebar still works the same way.

import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Tab index constants (must stay in sync with WorkbenchShell._tabs) ─────────

const kTabProject   = 0;
const kTabMeasure   = 1;
const kTabImport    = 2;
const kTabTarget    = 3;
const kTabOptimizer = 4;
const kTabGuidedAi  = 5;
const kTabPeq       = 6;
const kTabXo        = 7;
const kTabPhase     = 8;
const kTabDelay     = 9;
const kTabGain      = 10;
const kTabMute      = 11;
const kTabSimulation = 12;
const kTabProtection = 13;
const kTabExport    = 14;
const kTabHardware  = 15;
const kTabDeploy    = 16;
const kTabReport    = 17;

// ── Provider ──────────────────────────────────────────────────────────────────

class WorkbenchTabNotifier extends StateNotifier<int> {
  WorkbenchTabNotifier() : super(0);

  void go(int index) => state = index;
}

final workbenchTabProvider =
    StateNotifierProvider<WorkbenchTabNotifier, int>(
  (ref) => WorkbenchTabNotifier(),
);

// ── Deploy scroll target ───────────────────────────────────────────────────────

enum DeployScrollTarget { factoryProfile }

final deployScrollTargetProvider = StateProvider<DeployScrollTarget?>((ref) => null);
