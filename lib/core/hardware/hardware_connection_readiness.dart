// ── TUNAI PRO Phase 3-F1 — ADAU1701 hardware connection readiness ──────────
//
// A typed read model over the connection state the app ALREADY establishes.
// It introduces no new notion of "connected": every verdict below is composed
// from two existing production signals, exactly as
// HardwareDeviceStatusCard/project_status_bar already combine them —
//
//   liveContext  = activeAdau1701ContextProvider
//                  In-memory, session-scoped. Null on every app restart until
//                  a real BLE/USB connect flow repopulates it, and set to null
//                  by the disconnect callbacks. This is what makes a stale
//                  persisted flag unable to read as connected.
//
//   context.isReady = transport.isConnected
//                     && transport.handshakeComplete
//                     && transport.detectedProfile != null
//                  The existing ADAU1701 readiness contract — the same one
//                  the write port fails closed on at preflight.
//
//   project.connection == HardwareConnection.connected
//                  The persisted identity confirmation, already gated on a
//                  real PASS_HANDSHAKE by hardware_tab's sync.
//
// A non-null transport object, or a Bluetooth socket merely existing, is
// never sufficient on its own.
//
// This model says only "can the current DSP session be used". Whether a
// SPECIFIC correction package was actually written and readback-verified is a
// different question that RoomAfterGate alone answers — the two must never be
// merged.

library;

/// Everything this model can prove about the current hardware session.
enum HardwareConnectionState {
  /// No project, or a project whose DSP target has no runtime connection
  /// path implemented. Not a failure — nobody has checked.
  unknown,

  /// The target is supported but no live session exists.
  disconnected,

  /// A session exists but has not completed identity handshake yet.
  connecting,

  /// Handshake-verified session, but the project's persisted identity
  /// confirmation is not in place — usable, not yet deploy-ready.
  connected,

  /// A verified session for this project's DSP target.
  readyForDeploy,

  /// A live session exists, but for a different DSP than the project targets.
  incompatible,

  /// The connection reported an error.
  error,
}

/// Why the hardware is not ready. Typed so the UI never matches strings.
enum HardwareReadinessBlocker {
  noProject,

  /// The project's DSP target has no runtime connection implementation yet
  /// (currently everything other than ADAU1701, e.g. ADAU1466).
  targetNotSupported,

  notConnected,
  handshakeIncomplete,

  /// Connected and handshaken, but this project's identity confirmation is
  /// not recorded — see [HardwareConnectionReadiness.handshakeVerified].
  identityNotConfirmed,

  targetMismatch,
  connectionError,
}

/// The DSP targets this model knows how to reason about. Deliberately a
/// closed set: an unrecognised target is reported as unsupported rather than
/// optimistically treated as ADAU1701.
enum HardwareDspTarget {
  adau1701,
  adau1466,
  other;

  static HardwareDspTarget parse(String? raw) {
    final t = (raw ?? '').toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (t.contains('ADAU1701')) return HardwareDspTarget.adau1701;
    if (t.contains('ADAU1466')) return HardwareDspTarget.adau1466;
    return HardwareDspTarget.other;
  }
}

class HardwareConnectionReadiness {
  final HardwareConnectionState state;

  /// What the PROJECT targets.
  final HardwareDspTarget projectTarget;

  /// What the live session actually is, or null when there is no session.
  /// The only runtime path implemented today is ADAU1701 ICP5 (BLE/USB).
  final HardwareDspTarget? activeTarget;

  /// `'icp5'`, `'icp5-ble'`, … taken from the live context, or null.
  final String? transportKind;

  /// The existing ADAU1701 readiness contract held AND this project's
  /// persisted identity confirmation is present.
  final bool handshakeVerified;

  /// The live session (if any) is for the project's own DSP target.
  final bool targetCompatible;

  final bool readyForDeploy;
  final HardwareReadinessBlocker? blocker;
  final String? errorMessage;

  const HardwareConnectionReadiness({
    required this.state,
    required this.projectTarget,
    this.activeTarget,
    this.transportKind,
    required this.handshakeVerified,
    required this.targetCompatible,
    required this.readyForDeploy,
    this.blocker,
    this.errorMessage,
  });

  /// Tri-state for callers that only need "is it up": null when nobody has
  /// checked, so "unknown" is never rendered as "disconnected".
  bool? get connectedTriState => switch (state) {
        HardwareConnectionState.unknown => null,
        HardwareConnectionState.connected ||
        HardwareConnectionState.readyForDeploy =>
          true,
        _ => false,
      };

  static const HardwareConnectionReadiness none = HardwareConnectionReadiness(
    state: HardwareConnectionState.unknown,
    projectTarget: HardwareDspTarget.other,
    handshakeVerified: false,
    targetCompatible: false,
    readyForDeploy: false,
    blocker: HardwareReadinessBlocker.noProject,
  );
}

/// The inputs, named so the evaluator stays pure and trivially testable.
///
/// [liveContextReady] is `Adau1701HardwareContext.isReady`; [hasLiveContext]
/// is whether `activeAdau1701ContextProvider` holds anything at all. They are
/// separate because "a session exists but has not handshaken" is a real,
/// distinct state the user should see as connecting rather than disconnected.
abstract final class HardwareConnectionEvaluator {
  static HardwareConnectionReadiness evaluate({
    required String? projectDspTarget,
    required bool hasLiveContext,
    required bool liveContextReady,
    required String? transportKind,
    required bool persistedConnected,
    required bool persistedError,
  }) {
    if (projectDspTarget == null) return HardwareConnectionReadiness.none;

    final target = HardwareDspTarget.parse(projectDspTarget);
    // The only runtime connection path that exists is ADAU1701 ICP5, so a
    // live context is always an ADAU1701 session.
    final activeTarget = hasLiveContext ? HardwareDspTarget.adau1701 : null;
    // ADAU1701 is the only runtime connection path implemented, so a project
    // is compatible exactly when that is what it targets.
    final compatible = target == HardwareDspTarget.adau1701;

    HardwareConnectionReadiness build(
      HardwareConnectionState state, {
      HardwareReadinessBlocker? blocker,
      bool handshakeVerified = false,
      bool readyForDeploy = false,
    }) =>
        HardwareConnectionReadiness(
          state: state,
          projectTarget: target,
          activeTarget: activeTarget,
          transportKind: hasLiveContext ? transportKind : null,
          handshakeVerified: handshakeVerified,
          targetCompatible: compatible,
          readyForDeploy: readyForDeploy,
          blocker: blocker,
        );

    // ── A project this build cannot connect for ─────────────────────────
    if (target != HardwareDspTarget.adau1701) {
      // An ADAU1701 session must never be reported as ready for an
      // ADAU1466 (or unknown-target) project.
      return build(
        hasLiveContext
            ? HardwareConnectionState.incompatible
            : HardwareConnectionState.unknown,
        blocker: hasLiveContext
            ? HardwareReadinessBlocker.targetMismatch
            : HardwareReadinessBlocker.targetNotSupported,
      );
    }

    // ── ADAU1701 ────────────────────────────────────────────────────────
    if (persistedError) {
      return build(HardwareConnectionState.error,
          blocker: HardwareReadinessBlocker.connectionError);
    }

    // No live context: the session is gone (or was never opened this run).
    // A persisted `connected` flag alone can NEVER hold this open — that is
    // precisely how a restart, a disconnect callback or an onDone leaves
    // things, and reporting it as connected would be a lie.
    if (!hasLiveContext) {
      return build(HardwareConnectionState.disconnected,
          blocker: HardwareReadinessBlocker.notConnected);
    }

    if (!liveContextReady) {
      return build(HardwareConnectionState.connecting,
          blocker: HardwareReadinessBlocker.handshakeIncomplete);
    }

    if (!persistedConnected) {
      return build(HardwareConnectionState.connected,
          blocker: HardwareReadinessBlocker.identityNotConfirmed,
          handshakeVerified: false);
    }

    return build(HardwareConnectionState.readyForDeploy,
        handshakeVerified: true, readyForDeploy: true);
  }
}
