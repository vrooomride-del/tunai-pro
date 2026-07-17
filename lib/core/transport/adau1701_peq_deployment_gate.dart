import 'adau1701_ch0_band0_read_service.dart';
import 'adau1701_deployment_preflight.dart';

/// Stateful gate that runs the deployment preflight and holds the result.
///
/// Callers must call [runPreflight] before any PEQ write. The gate remembers
/// the last result so the UI can display diagnostics without re-running.
/// Call [invalidate] on disconnect so a stale result never authorises a write.
class Adau1701PeqDeploymentGate {
  final Adau1701DeploymentPreflight _preflight;

  Adau1701PreflightResult? _lastResult;

  Adau1701PeqDeploymentGate({required Adau1701RawReadTransport transport})
      : _preflight = Adau1701DeploymentPreflight(transport: transport);

  /// Last preflight result. Null until [runPreflight] has completed at least once.
  Adau1701PreflightResult? get lastResult => _lastResult;

  /// True only when the last preflight passed and has not been invalidated.
  bool get isDeploymentAllowed => _lastResult?.passed == true;

  /// Runs the preflight for [writePlan], stores the result, and returns it.
  Future<Adau1701PreflightResult> runPreflight(
    Adau1701PeqWriteFields writePlan,
  ) async {
    final result = await _preflight.run(writePlan: writePlan);
    _lastResult = result;
    return result;
  }

  /// Clears the last result. Must be called on disconnect so a stale PASS
  /// cannot authorise writes after reconnect.
  void invalidate() => _lastResult = null;
}

/// Full diagnostics report extracted from a completed preflight result.
class Adau1701PreflightDiagnostics {
  final Adau1701PreflightStatus status;
  final String message;
  final String? dspIdentity;
  final DateTime? snapshotCapturedAt;
  final int? frequencyHz;
  final double? gainDb;
  final double? q;
  final int? property08State;
  final bool? coverageIsCovered;
  final List<String> missingFields;

  const Adau1701PreflightDiagnostics({
    required this.status,
    required this.message,
    this.dspIdentity,
    this.snapshotCapturedAt,
    this.frequencyHz,
    this.gainDb,
    this.q,
    this.property08State,
    this.coverageIsCovered,
    this.missingFields = const [],
  });

  bool get passed => status == Adau1701PreflightStatus.passed;

  factory Adau1701PreflightDiagnostics.fromResult(
    Adau1701PreflightResult result,
  ) {
    final state = result.originalState;
    final coverage = result.coverage;
    return Adau1701PreflightDiagnostics(
      status: result.status,
      message: result.message,
      dspIdentity: result.confirmedDeviceId,
      snapshotCapturedAt: result.snapshotCapturedAt,
      frequencyHz: state?.frequencyHz,
      gainDb: state?.gainDb,
      q: state?.q,
      property08State: state?.property08State,
      coverageIsCovered: coverage?.isCovered,
      missingFields: coverage?.missingFields ?? const [],
    );
  }
}
