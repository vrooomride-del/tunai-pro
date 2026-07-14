class Adau1466XoCoefficientAudit {
  final String label;
  final int address;
  final int exportedWord;
  const Adau1466XoCoefficientAudit(this.label, this.address, this.exportedWord);
}

class Adau1466MappedXoBlockAudit {
  final String channel;
  final String sigmaCell;
  final String role;
  final String sigmaOutput;
  final String physicalOutput;
  final String slewSymbol;
  final int slewAddress;
  final int slewWord;
  final String coefficientSymbol;
  final List<Adau1466XoCoefficientAudit> coefficients;
  final bool safetyBlock;

  const Adau1466MappedXoBlockAudit(
      {required this.channel,
      required this.sigmaCell,
      required this.role,
      required this.sigmaOutput,
      required this.physicalOutput,
      required this.slewSymbol,
      required this.slewAddress,
      required this.slewWord,
      required this.coefficientSymbol,
      required this.coefficients,
      this.safetyBlock = false});

  String get addressRange =>
      '0x${coefficients.first.address.toRadixString(16).padLeft(4, '0').toUpperCase()}–'
      '0x${coefficients.last.address.toRadixString(16).padLeft(4, '0').toUpperCase()}';
  String get exportOrder => 'b2, b1, b0, a2, a1';
  String get topologyStatus =>
      'one exported stage; filter family/order/cutoff not export-proven';
  String get formatStatus => 'UNPROVEN — export says 8.24 or Sigma integer';
  String get transactionStatus =>
      'SafeLoad required by export; atomic 5-word packet sequence unproven';
  String get bypassStatus =>
      'no mapped bypass/state row; slew-mode exists separately';
  String get blockedReason =>
      'WRITE BLOCKED — coefficient encoding and capture-proven atomic 5-word SafeLoad transaction are missing';
  bool get writeEnabled => false;
}

class ProAdau1466XoAuditRegistry {
  static const blocks = <Adau1466MappedXoBlockAudit>[
    Adau1466MappedXoBlockAudit(
        channel: 'WFL',
        sigmaCell: 'LPF_2',
        role: 'LPF',
        sigmaOutput: 'Output1',
        physicalOutput: 'OUT3',
        slewSymbol: 'EQS300MultiDPHWSlewP1Alg1_slewmode',
        slewAddress: 0x01FA,
        slewWord: 0x0000208A,
        coefficientSymbol: 'EQS300MultiDPHWSlewP1Alg1Targ_B2_1',
        coefficients: [
          Adau1466XoCoefficientAudit('b2', 0x618D, 0x000015BA),
          Adau1466XoCoefficientAudit('b1', 0x618E, 0x00002B73),
          Adau1466XoCoefficientAudit('b0', 0x618F, 0x000015BA),
          Adau1466XoCoefficientAudit('a2', 0x6190, 0xFF069155),
          Adau1466XoCoefficientAudit('a1', 0x6191, 0x01F917C5),
        ]),
    Adau1466MappedXoBlockAudit(
        channel: 'MID_L',
        sigmaCell: 'HPF_2',
        role: 'HPF',
        sigmaOutput: 'Output2',
        physicalOutput: 'OUT2',
        slewSymbol: 'EQS300MultiDPHWSlewP1Alg2_slewmode',
        slewAddress: 0x0200,
        slewWord: 0x0000208A,
        coefficientSymbol: 'EQS300MultiDPHWSlewP1Alg2Targ_B2_1',
        coefficients: [
          Adau1466XoCoefficientAudit('b2', 0x6192, 0x00FCA19C),
          Adau1466XoCoefficientAudit('b1', 0x6193, 0xFE06BCC8),
          Adau1466XoCoefficientAudit('b0', 0x6194, 0x00FCA19C),
          Adau1466XoCoefficientAudit('a2', 0x6195, 0xFF069155),
          Adau1466XoCoefficientAudit('a1', 0x6196, 0x01F917C5),
        ]),
    Adau1466MappedXoBlockAudit(
        channel: 'MID_L',
        sigmaCell: 'LPF_3',
        role: 'LPF',
        sigmaOutput: 'Output2',
        physicalOutput: 'OUT2',
        slewSymbol: 'EQS300MultiDPHWSlewP1Alg3_slewmode',
        slewAddress: 0x02ED,
        slewWord: 0x0000208A,
        coefficientSymbol: 'EQS300MultiDPHWSlewP1Alg3Targ_B2_1',
        coefficients: [
          Adau1466XoCoefficientAudit('b2', 0x6278, 0x00089446),
          Adau1466XoCoefficientAudit('b1', 0x6279, 0x0011288C),
          Adau1466XoCoefficientAudit('b0', 0x627A, 0x00089446),
          Adau1466XoCoefficientAudit('a2', 0x627B, 0xFF3D2D94),
          Adau1466XoCoefficientAudit('a1', 0x627C, 0x01A08153),
        ]),
    Adau1466MappedXoBlockAudit(
        channel: 'TWL',
        sigmaCell: 'HPF_3',
        role: 'HPF',
        sigmaOutput: 'Output3',
        physicalOutput: 'OUT1',
        slewSymbol: 'EQS300MultiDPHWSlewP1Alg4_slewmode',
        slewAddress: 0x0206,
        slewWord: 0x0000208A,
        coefficientSymbol: 'EQS300MultiDPHWSlewP1Alg4Targ_B2_1',
        coefficients: [
          Adau1466XoCoefficientAudit('b2', 0x6197, 0x00D8D4F0),
          Adau1466XoCoefficientAudit('b1', 0x6198, 0xFE4E5621),
          Adau1466XoCoefficientAudit('b0', 0x6199, 0x00D8D4F0),
          Adau1466XoCoefficientAudit('a2', 0x619A, 0xFF3D2D94),
          Adau1466XoCoefficientAudit('a1', 0x619B, 0x01A08153),
        ]),
    Adau1466MappedXoBlockAudit(
        channel: 'TWL',
        sigmaCell: 'Safety HPF_5',
        role: 'HPF',
        sigmaOutput: 'Output3',
        physicalOutput: 'OUT1',
        safetyBlock: true,
        slewSymbol: 'EQS300MultiDPHWSlewP1Alg11_slewmode',
        slewAddress: 0x0365,
        slewWord: 0x0000208A,
        coefficientSymbol: 'EQS300MultiDPHWSlewP1Alg11Targ_B2_1',
        coefficients: [
          Adau1466XoCoefficientAudit('b2', 0x62EB, 0x00E67C13),
          Adau1466XoCoefficientAudit('b1', 0x62EC, 0xFE3307DA),
          Adau1466XoCoefficientAudit('b0', 0x62ED, 0x00E67C13),
          Adau1466XoCoefficientAudit('a2', 0x62EE, 0xFF2B0A7D),
          Adau1466XoCoefficientAudit('a1', 0x62EF, 0x01C4FACA),
        ]),
    Adau1466MappedXoBlockAudit(
        channel: 'WFR',
        sigmaCell: 'LPF_4',
        role: 'LPF',
        sigmaOutput: 'Output4',
        physicalOutput: 'OUT8',
        slewSymbol: 'EQS300MultiDPHWSlewP1Alg7_slewmode',
        slewAddress: 0x020C,
        slewWord: 0x0000208A,
        coefficientSymbol: 'EQS300MultiDPHWSlewP1Alg7Targ_B2_1',
        coefficients: [
          Adau1466XoCoefficientAudit('b2', 0x619C, 0x000015BA),
          Adau1466XoCoefficientAudit('b1', 0x619D, 0x00002B73),
          Adau1466XoCoefficientAudit('b0', 0x619E, 0x000015BA),
          Adau1466XoCoefficientAudit('a2', 0x619F, 0xFF069155),
          Adau1466XoCoefficientAudit('a1', 0x61A0, 0x01F917C5),
        ]),
    Adau1466MappedXoBlockAudit(
        channel: 'MID_R',
        sigmaCell: 'HPF_4',
        role: 'HPF',
        sigmaOutput: 'Output5',
        physicalOutput: 'OUT7',
        slewSymbol: 'EQS300MultiDPHWSlewP1Alg8_slewmode',
        slewAddress: 0x0212,
        slewWord: 0x0000208A,
        coefficientSymbol: 'EQS300MultiDPHWSlewP1Alg8Targ_B2_1',
        coefficients: [
          Adau1466XoCoefficientAudit('b2', 0x61A1, 0x00FCA19C),
          Adau1466XoCoefficientAudit('b1', 0x61A2, 0xFE06BCC8),
          Adau1466XoCoefficientAudit('b0', 0x61A3, 0x00FCA19C),
          Adau1466XoCoefficientAudit('a2', 0x61A4, 0xFF069155),
          Adau1466XoCoefficientAudit('a1', 0x61A5, 0x01F917C5),
        ]),
    Adau1466MappedXoBlockAudit(
        channel: 'MID_R',
        sigmaCell: 'LPF_5',
        role: 'LPF',
        sigmaOutput: 'Output5',
        physicalOutput: 'OUT7',
        slewSymbol: 'EQS300MultiDPHWSlewP1Alg9_slewmode',
        slewAddress: 0x02F3,
        slewWord: 0x0000208A,
        coefficientSymbol: 'EQS300MultiDPHWSlewP1Alg9Targ_B2_1',
        coefficients: [
          Adau1466XoCoefficientAudit('b2', 0x627D, 0x00089446),
          Adau1466XoCoefficientAudit('b1', 0x627E, 0x0011288C),
          Adau1466XoCoefficientAudit('b0', 0x627F, 0x00089446),
          Adau1466XoCoefficientAudit('a2', 0x6280, 0xFF3D2D94),
          Adau1466XoCoefficientAudit('a1', 0x6281, 0x01A08153),
        ]),
    Adau1466MappedXoBlockAudit(
        channel: 'TWR',
        sigmaCell: 'HPF_5',
        role: 'HPF',
        sigmaOutput: 'Output6',
        physicalOutput: 'OUT4',
        slewSymbol: 'EQS300MultiDPHWSlewP1Alg10_slewmode',
        slewAddress: 0x0218,
        slewWord: 0x0000208A,
        coefficientSymbol: 'EQS300MultiDPHWSlewP1Alg10Targ_B2_1',
        coefficients: [
          Adau1466XoCoefficientAudit('b2', 0x61A6, 0x00D8D4F0),
          Adau1466XoCoefficientAudit('b1', 0x61A7, 0xFE4E5621),
          Adau1466XoCoefficientAudit('b0', 0x61A8, 0x00D8D4F0),
          Adau1466XoCoefficientAudit('a2', 0x61A9, 0xFF3D2D94),
          Adau1466XoCoefficientAudit('a1', 0x61AA, 0x01A08153),
        ]),
    Adau1466MappedXoBlockAudit(
        channel: 'TWR',
        sigmaCell: 'Safefty HPF_5',
        role: 'HPF',
        sigmaOutput: 'Output6',
        physicalOutput: 'OUT4',
        safetyBlock: true,
        slewSymbol: 'EQS300MultiDPHWSlewP1Alg12_slewmode',
        slewAddress: 0x036B,
        slewWord: 0x0000208A,
        coefficientSymbol: 'EQS300MultiDPHWSlewP1Alg12Targ_B2_1',
        coefficients: [
          Adau1466XoCoefficientAudit('b2', 0x62F0, 0x00E67C13),
          Adau1466XoCoefficientAudit('b1', 0x62F1, 0xFE3307DA),
          Adau1466XoCoefficientAudit('b0', 0x62F2, 0x00E67C13),
          Adau1466XoCoefficientAudit('a2', 0x62F3, 0xFF2B0A7D),
          Adau1466XoCoefficientAudit('a1', 0x62F4, 0x01C4FACA),
        ]),
  ];

  static final coefficientAddressAllowlist = <int>{
    for (final block in blocks)
      for (final coefficient in block.coefficients) coefficient.address,
  };
  static const writeEnabledAddresses = <int>{};
  static bool acceptsWrite(int address, List<int> words) => false;
  const ProAdau1466XoAuditRegistry._();
}

class ProAdau1466WflLpf2DiagnosticEvidence {
  static const channel = 'WFL';
  static const block = 'LPF_2';
  static const slewAddress = 0x01FA;
  static const slewWord = 0x0000208A;
  static const coefficientOrder = ['b2', 'b1', 'b0', 'a2', 'a1'];
  static const coefficientAddresses = {
    0x618D,
    0x618E,
    0x618F,
    0x6190,
    0x6191,
  };
  static const baseline280Hz = <int>[
    0x000015BA,
    0x00002B73,
    0x000015BA,
    0xFF069155,
    0x01F917C5,
  ];
  static const test281Hz = <int>[
    0x000015E1,
    0x00002BC2,
    0x000015E1,
    0xFF069742,
    0x01F9113A,
  ];
  static const baselinePayload = <int>[
    0x00,
    0x00,
    0x15,
    0xBA,
    0x00,
    0x00,
    0x2B,
    0x73,
    0x00,
    0x00,
    0x15,
    0xBA,
    0xFF,
    0x06,
    0x91,
    0x55,
    0x01,
    0xF9,
    0x17,
    0xC5,
  ];
  static const testPayload = <int>[
    0x00,
    0x00,
    0x15,
    0xE1,
    0x00,
    0x00,
    0x2B,
    0xC2,
    0x00,
    0x00,
    0x15,
    0xE1,
    0xFF,
    0x06,
    0x97,
    0x42,
    0x01,
    0xF9,
    0x11,
    0x3A,
  ];
  static const transactionShapeProven = true;
  static const writeEnabledAddresses = <int>{
    0x01FA,
    0x618D,
    0x618E,
    0x618F,
    0x6190,
    0x6191,
  };
  static const unresolvedTrigger =
      'Resolved: lower-memory count 5, upper-memory count 0.';
  static bool acceptsTransaction(
      int slew, Set<int> addresses, List<int> coefficients) {
    if (slew != slewAddress ||
        addresses.length != coefficientAddresses.length ||
        !addresses.containsAll(coefficientAddresses)) {
      return false;
    }
    bool matches(List<int> expected) =>
        coefficients.length == expected.length &&
        List.generate(expected.length,
                (index) => coefficients[index] == expected[index])
            .every((value) => value);
    return matches(baseline280Hz) || matches(test281Hz);
  }

  const ProAdau1466WflLpf2DiagnosticEvidence._();
}
