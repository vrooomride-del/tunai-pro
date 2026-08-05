// TUNAI PRO UI/UX v3 Phase V3-1 — Graph Overlay Foundation.
//
// Session-only UI state for which mode a PEQ response graph is displaying
// (single/overlay/difference). NOT persisted to ProProjectStore/ProProject —
// resets on app restart, exactly like the existing ephemeral providers this
// mirrors (workbenchTabProvider, deployScrollTargetProvider,
// activeAdau1701ContextProvider). Carries no PEQ data of its own; it is only
// the currently-selected display mode for whichever graph reads it.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/workbench/widgets/graph_overlay_models.dart';

final graphOverlayModeProvider =
    StateProvider<PeqGraphMode>((ref) => PeqGraphMode.single);
