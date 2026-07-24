import '../../pro_acoustic_data.dart' show MeasurementParseResult;
import '../../pro_impedance_analysis.dart' show ImpedanceAnalysisResult;
import 'pro_tool_execution.dart';

/// A local numeric result produced by a deterministic tool.
///
/// A sealed, TYPED wrapper — never a `Map<String, dynamic>` bag. The store only
/// holds these; there is intentionally no `toJson` here, so a numeric artifact
/// can never be serialised into a Cloud-facing [ProOrchestratorResult]. The
/// Orchestrator sees only the outputRef that points at one of these.
sealed class ProToolArtifact {
  const ProToolArtifact();
}

class MeasurementArtifact extends ProToolArtifact {
  final MeasurementParseResult value;
  const MeasurementArtifact(this.value);
}

class ImpedanceArtifact extends ProToolArtifact {
  final ImpedanceAnalysisResult value;
  const ImpedanceArtifact(this.value);
}

class SimulationArtifact extends ProToolArtifact {
  /// The simulated magnitude curve (dB per frequency point). Owned locally,
  /// never exposed as an array in a Cloud-facing result.
  final List<double> curve;
  SimulationArtifact(List<double> curve)
      : curve = List<double>.unmodifiable(curve);
}

/// Session-scoped, in-memory store of tool artifacts, namespaced by projectId
/// and keyed by the step's opaque `outputRef`.
///
/// - No persistence (session only).
/// - projectId scope is enforced: a get for another project sees an empty
///   namespace and fails [ProToolFailureCode.missingReference].
/// - Writes are write-once: re-using a project + outputRef is an
///   [ProToolFailureCode.outputRefConflict], never a silent overwrite.
/// - Retrieval is TYPED via [getTyped]; a wrong type is a
///   [ProToolFailureCode.typeMismatch]. Nothing is returned as
///   `Object`/`dynamic`.
/// - `outputRef` is treated as an opaque identifier — never parsed as a path or
///   command.
class ProToolArtifactStore {
  final Map<String, Map<String, ProToolArtifact>> _byProject = {};

  /// Stores [artifact] at [projectId] + [outputRef]. Refuses an empty ref and
  /// refuses to overwrite an existing entry.
  void put(String projectId, String outputRef, ProToolArtifact artifact) {
    if (outputRef.isEmpty) {
      throw ProToolException(
          ProToolFailureCode.emptyOutputRef, 'outputRef must not be empty.');
    }
    final ns = _byProject.putIfAbsent(projectId, () => {});
    if (ns.containsKey(outputRef)) {
      throw ProToolException(ProToolFailureCode.outputRefConflict,
          'artifact already exists at $projectId/$outputRef.');
    }
    ns[outputRef] = artifact;
  }

  /// Whether an artifact exists at [projectId] + [outputRef].
  bool has(String projectId, String outputRef) =>
      _byProject[projectId]?.containsKey(outputRef) ?? false;

  /// Typed retrieval. Missing (including another project's namespace) →
  /// [ProToolFailureCode.missingReference]; present-but-wrong-type →
  /// [ProToolFailureCode.typeMismatch].
  T getTyped<T extends ProToolArtifact>(String projectId, String outputRef) {
    final artifact = _byProject[projectId]?[outputRef];
    if (artifact == null) {
      throw ProToolException(ProToolFailureCode.missingReference,
          'no artifact at $projectId/$outputRef.');
    }
    if (artifact is! T) {
      throw ProToolException(
          ProToolFailureCode.typeMismatch,
          'artifact at $projectId/$outputRef is ${artifact.runtimeType}, '
          'not $T.');
    }
    return artifact;
  }
}
