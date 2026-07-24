import 'package:dio/dio.dart';

import 'pro_orchestrate_request.dart';
import 'pro_orchestrate_response.dart';
import 'pro_orchestrator_types.dart';

// TRUST BOUNDARY. Network layer only — no engine call, no tool execution,
// no DSP value. Sends ProOrchestrateRequest (references + perceptual intent),
// receives ProOrchestrateResponse (plan + explanation), and converts every
// error — including a Cloud response that tries to smuggle a DSP key — into
// a typed [ProOrchestrateFailure].

const _kFunctionUrl =
    'https://asia-northeast3-tunai-54b7f.cloudfunctions.net/aiOrchestratePro';

// ── Outcome ───────────────────────────────────────────────────────────────────

/// The outcome of one `aiOrchestratePro` Cloud call.
///
/// Exhaustive by construction — no third state is possible.
sealed class ProOrchestrateOutcome {
  const ProOrchestrateOutcome();
}

/// The Cloud returned a valid [ProOrchestrateResponse] that passed
/// [ProContract] validation and the `requestProjectId` check.
final class ProOrchestrateSuccess extends ProOrchestrateOutcome {
  final ProOrchestrateResponse response;
  const ProOrchestrateSuccess(this.response);
}

/// Any failure: network error, server error, or contract violation (including
/// a response that carries a forbidden DSP key or an unknown schema version).
/// [message] is human-readable — never a DSP value.
final class ProOrchestrateFailure extends ProOrchestrateOutcome {
  final String message;
  const ProOrchestrateFailure(this.message);
}

// ── Service ───────────────────────────────────────────────────────────────────

/// HTTPS POST wrapper for the `aiOrchestratePro` Cloud Function.
///
/// Sends [call] → serialises [ProOrchestrateRequest] → parses
/// [ProOrchestrateResponse] → returns a typed [ProOrchestrateOutcome].
///
/// Never throws: every error (network, server 4xx/5xx, [ProContractException],
/// unexpected shape) is converted to [ProOrchestrateFailure]. Callers do not
/// need try/catch.
///
/// Pass [dio] only in tests to inject a stub — production code uses the
/// default Dio instance.
class ProOrchestrateService {
  final Dio _dio;

  ProOrchestrateService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 60),
            ));

  Future<ProOrchestrateOutcome> call(ProOrchestrateRequest request) async {
    try {
      final response = await _dio.post(_kFunctionUrl, data: request.toJson());

      // Unwrap outer envelope: { result: { <ProOrchestrateResponse> } }
      final outer = ProContract.asObject(response.data, 'aiOrchestratePro');
      final inner =
          ProContract.asObject(outer['result'], 'aiOrchestratePro.result');

      final parsed = ProOrchestrateResponse.fromJson(inner,
          requestProjectId: request.projectId);

      return ProOrchestrateSuccess(parsed);
    } on ProContractException catch (e) {
      return ProOrchestrateFailure(e.message);
    } on DioException catch (e) {
      final serverMsg =
          e.response?.data is Map ? (e.response!.data as Map)['error'] : null;
      final msg = serverMsg?.toString() ?? e.message ?? 'network error';
      return ProOrchestrateFailure(msg);
    } catch (e) {
      return ProOrchestrateFailure('AI 응답 오류: $e');
    }
  }
}
