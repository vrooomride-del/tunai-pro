import '../../adau1701_peq_response.dart' show PeqResponseBand;
import '../../pro_acoustic_data.dart'
    show AcousticFileType, DriverChannel, FrdSweepEntry, MeasurementProjectState;
import '../../pro_project.dart' show ProProject;
import 'pro_tool_execution.dart';

/// A local, typed measurement source for `measurementAnalyze`. The fileName and
/// content come ONLY from a resolved local reference — never from Cloud plan
/// free text.
class ProMeasurementSource {
  final String fileName;
  final String content;
  final AcousticFileType format;
  /// Additional repeated FRD sweeps for multi-sweep repeatability evidence.
  /// Empty list = single-sweep (analysis-only path).
  final List<FrdSweepEntry> additionalSweeps;
  const ProMeasurementSource({
    required this.fileName,
    required this.content,
    required this.format,
    this.additionalSweeps = const [],
  });
}

/// A local, typed input for `simulate`. The driver, bands and frequency grid
/// are real local objects owned by the project — never numbers read from a
/// Cloud plan or explanation.
class ProSimulationInput {
  final DriverChannel driver;
  final List<PeqResponseBand> bands;
  final List<double> freqs;
  const ProSimulationInput({
    required this.driver,
    required this.bands,
    required this.freqs,
  });
}

/// Resolves opaque plan references to real local typed inputs.
///
/// One typed method per input kind — there is deliberately NO
/// `resolve(String): dynamic`. Each resolve validates projectId scope and fails
/// with a typed [ProToolException]: an unknown ref is
/// [ProToolFailureCode.missingReference]; a ref registered under a different
/// project is invisible here (also a missingReference in this project's
/// namespace); a ref bound to a different type is
/// [ProToolFailureCode.typeMismatch].
abstract interface class ProToolReferenceResolver {
  ProMeasurementSource resolveMeasurementSource(String projectId, String ref);
  MeasurementProjectState resolveMeasurementProjectState(
      String projectId, String ref);
  ProSimulationInput resolveSimulationInput(String projectId, String ref);

  /// Returns the full project snapshot when the resolver is backed by a live
  /// project (e.g. [ProProjectResolver]). Returns null for in-memory/test
  /// resolvers that are not connected to a project.
  ProProject? resolveProjectSnapshot(String projectId);
}

/// A session-scoped, in-memory resolver. NOT wired to ProjectStore/Riverpod —
/// that binding is a later commit. Values are placed via [put] under a
/// projectId namespace; anything not placed fails closed.
class InMemoryProToolReferenceResolver implements ProToolReferenceResolver {
  final Map<String, Map<String, Object>> _byProject = {};

  /// Registers a typed local value under [projectId] + [ref] for later
  /// resolution. Test/host code owns what goes in; adapters only read.
  void put(String projectId, String ref, Object value) {
    _byProject.putIfAbsent(projectId, () => {})[ref] = value;
  }

  T _resolve<T>(String projectId, String ref) {
    final value = _byProject[projectId]?[ref];
    if (value == null) {
      throw ProToolException(ProToolFailureCode.missingReference,
          'no reference "$ref" in project $projectId.');
    }
    if (value is! T) {
      throw ProToolException(
          ProToolFailureCode.typeMismatch,
          'reference "$ref" in project $projectId is ${value.runtimeType}, '
          'not $T.');
    }
    return value as T;
  }

  @override
  ProMeasurementSource resolveMeasurementSource(String projectId, String ref) =>
      _resolve<ProMeasurementSource>(projectId, ref);

  @override
  MeasurementProjectState resolveMeasurementProjectState(
          String projectId, String ref) =>
      _resolve<MeasurementProjectState>(projectId, ref);

  @override
  ProSimulationInput resolveSimulationInput(String projectId, String ref) =>
      _resolve<ProSimulationInput>(projectId, ref);

  @override
  ProProject? resolveProjectSnapshot(String projectId) => null;
}
