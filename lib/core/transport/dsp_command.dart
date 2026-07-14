/// Transport-independent DSP writes. Addresses and values describe the board
/// command; transport framing belongs to a [DspTransport] implementation.
enum DspCommandKind { directParameterWrite, oneWordSafeLoad, fiveWordSafeLoad }

class DspWriteBody {
  final int startAddress;
  final List<int> dataBytes;

  DspWriteBody({required this.startAddress, required List<int> dataBytes})
      : dataBytes = List<int>.unmodifiable(dataBytes) {
    if (startAddress < 0 || startAddress > 0xFFFF) {
      throw ArgumentError.value(startAddress, 'startAddress');
    }
    if (dataBytes.isEmpty || dataBytes.any((byte) => byte < 0 || byte > 0xFF)) {
      throw ArgumentError.value(dataBytes, 'dataBytes');
    }
  }

  List<int> get addressAndData => [
        (startAddress >> 8) & 0xFF,
        startAddress & 0xFF,
        ...dataBytes,
      ];
}

class DspCommand {
  final String boardId;
  final String label;
  final DspCommandKind kind;
  final List<DspWriteBody> writes;

  DspCommand({
    required this.boardId,
    required this.label,
    required this.kind,
    required List<DspWriteBody> writes,
  }) : writes = List<DspWriteBody>.unmodifiable(writes) {
    if (writes.isEmpty) {
      throw ArgumentError('A DSP command needs a write body.');
    }
  }
}
