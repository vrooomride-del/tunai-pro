// ── TUNAI PRO Phase T4A — USBi Packet Builder ────────────────────────────────
// Pure byte construction for ADAU1466 parameter write via USBi temporary path.
// No I/O is performed here. No device handles are opened. No writes occur.
//
// Validated USBi packet format (from prior hardware verification):
//   Setup:  40 B2 00 00 01 01 [NN] 00   (NN = byte count of body, typically 06)
//   Body:   [addr_hi, addr_lo, data[0], data[1], data[2], data[3]]
//   ACK rd: C0 B5 00 00 00 00 01 00
//   ACK byte: 0x01 = success
//
// ABSOLUTE RESTRICTIONS:
//   - No I/O. No device access. No USB transfer calls.
//   - Only use for ADAU1466 Master Volume L/R addresses.
//   - Do NOT generalise to other parameters.
//   - USBi is TEMPORARY. ICP5 is the final target.

const int kUsbiSetupByte0 = 0x40;
const int kUsbiSetupByte1 = 0xB2;
const int kUsbiAckByte0   = 0xC0;
const int kUsbiAckByte1   = 0xB5;
const int kExpectedAckByte = 0x01; // Expected response in ACK payload byte 6

// 6-byte body: 2-byte address + 4-byte data
const int kUsbiBodyLength = 6;

/// Builds the 8-byte USBi setup packet for a single-register parameter write.
///
/// [bodyLength] is the number of bytes in the body (default 6).
/// Returns 8 bytes: [0x40, 0xB2, 0x00, 0x00, 0x01, 0x01, NN, 0x00].
List<int> buildParameterWriteSetup({int bodyLength = kUsbiBodyLength}) {
  assert(bodyLength > 0 && bodyLength <= 0xFF,
      'bodyLength must be 1–255, got $bodyLength');
  return [
    kUsbiSetupByte0, kUsbiSetupByte1, 0x00, 0x00,
    0x01,            0x01,            bodyLength, 0x00,
  ];
}

/// Builds the 6-byte USBi body for a parameter write.
///
/// [addressInt]: 16-bit register address (big-endian → [addr_hi, addr_lo]).
/// [fixedPointInt]: 32-bit 8.24 fixed-point value (big-endian → 4 bytes).
/// Returns [addr_hi, addr_lo, data_3, data_2, data_1, data_0].
List<int> buildParameterWriteBody({
  required int addressInt,
  required int fixedPointInt,
}) {
  assert(addressInt >= 0 && addressInt <= 0xFFFF,
      'addressInt out of 16-bit range: 0x${addressInt.toRadixString(16)}');
  assert(fixedPointInt >= 0 && fixedPointInt <= 0x7FFFFFFF,
      'fixedPointInt out of safe positive 32-bit range: '
      '0x${fixedPointInt.toRadixString(16)}');

  final addrHi  = (addressInt  >> 8) & 0xFF;
  final addrLo  =  addressInt        & 0xFF;
  final data3   = (fixedPointInt >> 24) & 0xFF;
  final data2   = (fixedPointInt >> 16) & 0xFF;
  final data1   = (fixedPointInt >>  8) & 0xFF;
  final data0   =  fixedPointInt        & 0xFF;

  return [addrHi, addrLo, data3, data2, data1, data0];
}

/// Builds the 8-byte ACK read request packet.
///
/// Returns [0xC0, 0xB5, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00].
List<int> buildAckReadRequest() => [
  kUsbiAckByte0, kUsbiAckByte1, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00,
];

/// Returns true if [ackPayload] contains the expected ACK byte (0x01) at byte 6
/// (index 6, 0-indexed), matching the known USBi ACK response format.
bool isAckSuccess(List<int> ackPayload) {
  if (ackPayload.length < 7) return false;
  return ackPayload[6] == kExpectedAckByte;
}

/// Formats a byte list as an uppercase hex string for display/logging.
String bytesToHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
