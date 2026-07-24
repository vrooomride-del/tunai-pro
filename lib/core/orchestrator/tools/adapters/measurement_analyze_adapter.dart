import '../../../pro_acoustic_data.dart'
    show AcousticFileType, MeasurementParseResult;
import '../../../pro_measurement_parser.dart';
import '../../pro_orchestrator_plan.dart';
import '../../pro_orchestrator_result.dart';
import '../../pro_orchestrator_types.dart';
import '../pro_tool_artifact_store.dart';
import '../pro_tool_execution.dart';
import '../pro_tool_registry.dart';

/// `measurementAnalyze` → [ProMeasurementParser].
///
/// Resolves a local [ProMeasurementSource] from the step's single inputRef,
/// picks the parser by the source's declared format (FRD/ZMA; anything else
/// fails closed), calls the existing parser unchanged, and stores the result as
/// a [MeasurementArtifact] at the step's outputRef. The Cloud-facing result
/// carries only references. The parser's own free text (fileName/content) comes
/// only from the resolved local source — never from the plan.
class MeasurementAnalyzeAdapter implements ProToolAdapter {
  const MeasurementAnalyzeAdapter();

  @override
  ProOrchestratorToolId get toolId => ProOrchestratorToolId.measurementAnalyze;

  @override
  ProOrchestratorResult run(
      ProToolExecutionContext ctx, ProOrchestratorStep step) {
    final ref = singleInputRef(step);
    final source = ctx.resolver.resolveMeasurementSource(ctx.projectId, ref);

    final parsed = switch (source.format) {
      AcousticFileType.frd => ProMeasurementParser.parseFrd(
          fileName: source.fileName, content: source.content),
      AcousticFileType.zma => ProMeasurementParser.parseZma(
          fileName: source.fileName, content: source.content),
      _ => throw ProToolException(
          ProToolFailureCode.unknownFormat,
          'measurementAnalyze supports FRD/ZMA only, got '
          '${source.format.name}.'),
    };

    ctx.store.put(ctx.projectId, step.outputRef, MeasurementArtifact(parsed));
    return referenceResult(step, confidence: _confidence(parsed));
  }

  /// Coarse confidence from the parse outcome — errors low, warnings medium,
  /// clean high. Never a number.
  ProConfidence _confidence(MeasurementParseResult r) {
    if (r.errors.isNotEmpty) return ProConfidence.low;
    if (r.warnings.isNotEmpty) return ProConfidence.medium;
    return ProConfidence.high;
  }
}
