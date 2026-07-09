// Re-export tabs that have been split into dedicated files
export 'measure_tab.dart';
export 'analyze_tab.dart';
export 'import_tab.dart';
export 'target_tab.dart';
export 'report_tab.dart';
export 'peq_tab.dart';
export 'xo_tab.dart';
export 'gain_tab.dart';
export 'delay_tab.dart';
export 'phase_tab.dart';
export 'protection_tab.dart';
export 'export_tab.dart';
export 'optimizer_tab.dart';
export 'simulation_tab.dart';

// ── Individual Tab Widgets ────────────────────────────────────────────────────
// All tabs have been moved to dedicated files (re-exported above).

// PeqTab → peq_tab.dart (Phase D)
// XoTab (was CrossoverTab) → xo_tab.dart (Phase D)

// DelayPhaseTab, LimiterTab → replaced by PhaseTab, DelayTab, GainTab in Phase E
// ProtectionTab → protection_tab.dart (Phase F)
// DeployTab     → export_tab.dart (Phase F, renamed ExportTab)
