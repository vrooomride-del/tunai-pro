import '../../../pro_simulation_optimizer.dart';
import '../../pro_orchestrator_plan.dart';
import '../../pro_orchestrator_result.dart';
import '../../pro_orchestrator_types.dart';
import '../pro_tool_artifact_store.dart';
import '../pro_tool_registry.dart';

/// `simulate` → [ProSimulationOptimizer.simulatedResponse].
///
/// Resolves a local [ProSimulationInput] (driver + bands + frequency grid) from
/// the step's single inputRef and calls the existing pure engine unchanged. No
/// number is read from the plan or explanation. The resulting curve is stored
/// as a [SimulationArtifact]; the Cloud-facing result carries only references.
/// The engine's non-deterministic id paths (`nextId`) are not used — only the
/// pure `simulatedResponse` calculation.
class SimulateAdapter implements ProToolAdapter {
  const SimulateAdapter();

  @override
  ProOrchestratorToolId get toolId => ProOrchestratorToolId.simulate;

  @override
  ProOrchestratorResult run(
      ProToolExecutionContext ctx, ProOrchestratorStep step) {
    final ref = singleInputRef(step);
    final input = ctx.resolver.resolveSimulationInput(ctx.projectId, ref);

    final curve = ProSimulationOptimizer.simulatedResponse(
      driver: input.driver,
      bands: input.bands,
      freqs: input.freqs,
    );

    ctx.store.put(ctx.projectId, step.outputRef, SimulationArtifact(curve));
    return referenceResult(step, confidence: ProConfidence.high);
  }
}
