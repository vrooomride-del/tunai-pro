// ── TUNAI PRO Phase 3-D3A-1 — shared runtime capture preflight ──────────────
//
// The ONE place Factory (LiveMeasurementController) and Room
// (RoomMeasurementController) turn "current project state + live runtime
// facts" into a MeasurementCaptureGateResult. Neither controller re-derives
// availability or re-implements the gate — they call this, so they can never
// disagree about whether a capture is allowed.
//
// Why a separate seam from MeasurementCaptureGate: the gate is pure and
// synchronous by design (so the UI can render it every build). Deciding
// whether to actually start a recorder needs FRESH async facts — permission
// and a live device enumeration — which must be re-read at the moment of
// capture, never taken from whatever the UI happened to cache at render
// time. This class is that async boundary and nothing else; all policy still
// lives in the pure gate.
//
// System-default input keeps its Phase 3-D3A P0 semantics: a non-empty fresh
// enumeration only ever yields `systemDefaultUnverified`, never `available`,
// and the recorder start remains the final fail-closed authority.

library;

import 'measurement_capture_gate.dart';
import 'measurement_capture_gate_types.dart';
import 'measurement_input_device.dart';
import 'measurement_input_device_service.dart';
import 'measurement_quality_policy.dart';
import 'measurement_warning_acknowledgement.dart';
import '../pro_project.dart';

class MeasurementCapturePreflight {
  final MeasurementInputDeviceService inputDeviceService;
  final MeasurementQualityPolicy policy;

  /// Injectable clock so expiry checks are testable without waiting.
  final DateTime Function() nowProvider;

  MeasurementCapturePreflight({
    required this.inputDeviceService,
    MeasurementQualityPolicy? policy,
    DateTime Function()? nowProvider,
  })  : policy = policy ?? MeasurementQualityPolicy.proProvisional(),
        nowProvider = nowProvider ?? DateTime.now;

  /// Re-reads every live fact and evaluates the shared gate.
  ///
  /// Permission and device enumeration are queried here, at capture time —
  /// a value the UI computed during an earlier build is never trusted, so a
  /// device unplugged between render and tap is caught.
  ///
  /// Enumeration failures fail closed: an exception becomes an empty device
  /// list, which resolves to [MeasurementRuntimeInputAvailability.unavailable]
  /// rather than an optimistic "probably still there".
  Future<MeasurementCaptureGateResult> evaluate({
    required ProProject? project,
    MeasurementWarningAcknowledgement? acknowledgement,
  }) async {
    if (project == null) {
      return MeasurementCaptureGate.evaluate(
        project: null,
        now: nowProvider(),
        policy: policy,
      );
    }

    bool? permissionGranted;
    try {
      permissionGranted =
          await inputDeviceService.hasPermission(request: false);
    } catch (_) {
      permissionGranted = null; // unknown -> blocked by the gate
    }

    var freshDevices = const <MeasurementInputDeviceDescriptor>[];
    if (permissionGranted == true) {
      try {
        freshDevices = await inputDeviceService.listAvailableDevices();
      } catch (_) {
        freshDevices = const [];
      }
    }

    final availability = MeasurementCaptureGate.resolveInputAvailability(
      selection: project.selectedInputDevice,
      freshDevices: freshDevices,
    );

    return MeasurementCaptureGate.evaluate(
      project: project,
      now: nowProvider(),
      policy: policy,
      inputAvailability: availability,
      microphonePermissionGranted: permissionGranted,
      acknowledgement: acknowledgement,
    );
  }
}
