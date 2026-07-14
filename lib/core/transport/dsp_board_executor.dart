import 'dsp_command.dart';
import 'dsp_transport.dart';

/// Board policy is deliberately separate from transport identity and framing.
/// Existing proven ADAU1466 registries can supply this allowlist incrementally.
class DspBoardCommandRegistry {
  final String boardId;
  final Set<int> writableAddresses;

  DspBoardCommandRegistry({
    required this.boardId,
    required Set<int> writableAddresses,
  }) : writableAddresses = Set<int>.unmodifiable(writableAddresses);

  bool accepts(DspCommand command) =>
      command.boardId == boardId &&
      command.writes.every((write) => writableAddresses.contains(write.startAddress));
}

class DspBoardExecutor {
  final DspBoardCommandRegistry registry;
  final DspTransportRouter router;

  const DspBoardExecutor({required this.registry, required this.router});

  Future<DspTransportResult> execute(DspCommand command) async {
    if (!registry.accepts(command)) {
      return const DspTransportResult(
        success: false,
        failure: DspTransportFailure.unsupportedCapability,
        message: 'Board registry rejected this command.',
      );
    }
    return router.execute(command);
  }
}
