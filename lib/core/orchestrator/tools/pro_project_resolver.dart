import '../../adau1701_peq_response.dart' show PeqResponseBand;
import '../../pro_acoustic_data.dart' show MeasurementProjectState;
import '../../pro_project.dart' show ProProject;
import '../../pro_tuning_data.dart' show PeqBandStatus;
import 'pro_tool_execution.dart';
import 'pro_tool_reference_resolver.dart';

// TRUST BOUNDARY. Engine layer. No Riverpod import, no Ref, no WidgetRef.
// The caller (UI layer) reads from Riverpod and passes a plain [ProProject]
// snapshot. Everything below is synchronous and pure.

/// A session-scoped resolver backed by a [ProProject] snapshot.
///
/// Built in the UI layer from the current Riverpod state before the
/// orchestration run starts. The engine (adapters, orchestrator) never
/// references Riverpod directly — it holds only this plain object.
///
/// Supports:
///   - [resolveMeasurementProjectState]: returns [ProProject.acousticState].
///   - [resolveSimulationInput]: returns driver + active PEQ bands + freq grid.
///
/// Does NOT support [resolveMeasurementSource] (raw FRD/ZMA text content).
/// That path requires a separate content-aware resolver built on top of an
/// import-time content cache; it is out of scope for this phase.
class ProProjectResolver implements ProToolReferenceResolver {
  final ProProject _project;

  const ProProjectResolver({required ProProject project}) : _project = project;

  // ── ProToolReferenceResolver ───────────────────────────────────────────────

  /// Returns this project's [MeasurementProjectState].
  ///
  /// [ref] is accepted for interface compatibility but is not inspected —
  /// there is exactly one [MeasurementProjectState] per project.
  @override
  MeasurementProjectState resolveMeasurementProjectState(
      String projectId, String ref) {
    _guard(projectId);
    return _project.acousticState;
  }

  /// Resolves driver + active PEQ bands + frequency grid for [ref].
  ///
  /// [ref] must be a [DriverChannel.id] that exists in this project's
  /// [MeasurementProjectState.driverChannels]. The frequency grid is built
  /// from the driver's parsed FRD data (`frdData.points`); it is empty when
  /// no FRD has been imported.
  ///
  /// PEQ band selection:
  ///   - The [PeqChannelState] whose `channelId` matches [ref] is located in
  ///     [TuningProjectState.peqChannels].
  ///   - If no match exists, or the channel-level [PeqChannelState.bypassed]
  ///     flag is set, an empty band list is returned (no error).
  ///   - Individual bands are included only when `enabled == true` AND
  ///     `status != PeqBandStatus.bypassed`.
  @override
  ProSimulationInput resolveSimulationInput(String projectId, String ref) {
    _guard(projectId);

    final driver = _project.acousticState.driverChannels
        .where((d) => d.id == ref)
        .firstOrNull;
    if (driver == null) {
      throw ProToolException(
        ProToolFailureCode.missingReference,
        'no driver channel for simulation ref "$ref" in project $projectId.',
      );
    }

    final freqs = [
      for (final p in driver.frdData?.points ?? const []) p.frequencyHz,
    ];

    final peqChannel = _project.tuningState.peqChannels
        .where((ch) => ch.channelId == ref)
        .firstOrNull;

    final List<PeqResponseBand> bands;
    if (peqChannel == null || peqChannel.bypassed) {
      bands = const [];
    } else {
      bands = [
        for (final b in peqChannel.bands)
          if (b.enabled && b.status != PeqBandStatus.bypassed)
            PeqResponseBand(
              frequencyHz: b.frequencyHz,
              gainDb: b.gainDb,
              q: b.q,
            ),
      ];
    }

    return ProSimulationInput(
        driver: driver, bands: bands, freqs: List<double>.unmodifiable(freqs));
  }

  @override
  ProProject? resolveProjectSnapshot(String projectId) {
    _guard(projectId);
    return _project;
  }

  /// Not supported — raw measurement file content is not stored in
  /// [ProProject]. Use a content-aware resolver for `measurementAnalyze`.
  @override
  ProMeasurementSource resolveMeasurementSource(String projectId, String ref) {
    throw ProToolException(
      ProToolFailureCode.unsupportedTool,
      'ProProjectResolver does not support raw measurement content '
      '(ref "$ref"). Use a content-aware resolver for measurementAnalyze.',
    );
  }

  // ── Private ────────────────────────────────────────────────────────────────

  void _guard(String projectId) {
    if (projectId != _project.id) {
      throw ProToolException(
        ProToolFailureCode.missingReference,
        'resolver is scoped to project ${_project.id}, '
        'but requested project $projectId.',
      );
    }
  }
}
