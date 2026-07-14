class Adau1466PeqOutputAudit {
  final String channel;
  final String sigmaOutput;
  final String physicalOutput;
  final String cellName;

  const Adau1466PeqOutputAudit({required this.channel,
    required this.sigmaOutput, required this.physicalOutput,
    required this.cellName});
}

class Adau1466PeqCoefficientRow {
  final String channel;
  final String cellName;
  final String parameterName;
  final int bandNumber;
  final String coefficient;
  final int address;
  final int rawWord;
  final String sourceFile;
  final int sourceLine;

  const Adau1466PeqCoefficientRow({required this.channel,
    required this.cellName, required this.parameterName,
    required this.bandNumber, required this.coefficient,
    required this.address, required this.rawWord, required this.sourceFile,
    required this.sourceLine});

  String get addressHex =>
      '0x${address.toRadixString(16).padLeft(4, '0').toUpperCase()}';
  String get wordHex =>
      '0x${rawWord.toRadixString(16).padLeft(8, '0').toUpperCase()}';
  String get provenance => '$sourceFile:$sourceLine';
}

class Adau1466PeqBandAudit {
  final Adau1466PeqOutputAudit output;
  final int bandNumber;
  final List<Adau1466PeqCoefficientRow> coefficients;
  const Adau1466PeqBandAudit({required this.output,
    required this.bandNumber, required this.coefficients});

  int? get slewAddress => null; // ISIB export has no separate slew parameter.
  int get targetStartAddress => coefficients.first.address;
  List<int> get addresses => coefficients.map((row) => row.address).toList();
  List<int> get words => coefficients.map((row) => row.rawWord).toList();
  String get addressRange =>
      '${coefficients.first.addressHex}–${coefficients.last.addressHex}';
}

class ProAdau1466PeqAuditRegistry {
  static const sourceAsset =
      'evidence/sigmastudio/v0_9_final/TUNAI_ADAU1466_v0_9_Final.params';
  static const corroboratingParamHeader =
      'evidence/sigmastudio/v0_9_final/TUNAI_ADAU1466_v0_9_Final_IC_1_PARAM.h';
  static const corroboratingXml =
      'evidence/sigmastudio/v0_9_final/TUNAI_ADAU1466_v0_9_Final_NetList.xml';
  static const fullOriginalExportFound = true;
  static const recoveredPeqRowCount = 800;
  static const coefficientOrder = ['b2', 'b1', 'b0', 'a2', 'a1'];
  static const baselineFrequencyGainQExplicit = false;
  static const writeEnabledAddresses = <int>{};

  static const outputs = <Adau1466PeqOutputAudit>[
    Adau1466PeqOutputAudit(channel: 'WFL', sigmaOutput: 'Output1',
      physicalOutput: 'OUT3', cellName: 'L_WOOFER_PEQ 20-band'),
    Adau1466PeqOutputAudit(channel: 'MID_L', sigmaOutput: 'Output2',
      physicalOutput: 'OUT2', cellName: 'L_MID_PEQ_20B'),
    Adau1466PeqOutputAudit(channel: 'TWL', sigmaOutput: 'Output3',
      physicalOutput: 'OUT1', cellName: 'L_TWEETER_PEQ 20-band'),
    Adau1466PeqOutputAudit(channel: 'WFR', sigmaOutput: 'Output4',
      physicalOutput: 'OUT8', cellName: 'R_WOOFER_PEQ 20-band'),
    Adau1466PeqOutputAudit(channel: 'MID_R', sigmaOutput: 'Output5',
      physicalOutput: 'OUT7', cellName: 'R_MID_PEQ_20B'),
    Adau1466PeqOutputAudit(channel: 'TWR', sigmaOutput: 'Output6',
      physicalOutput: 'OUT4', cellName: 'R_TWEETER_PEQ 20-band'),
    Adau1466PeqOutputAudit(channel: 'GLOBAL_L', sigmaOutput: 'Global L',
      physicalOutput: 'L bus', cellName: 'TUNAI_GLOBAL_PEQ_L'),
    Adau1466PeqOutputAudit(channel: 'GLOBAL_R', sigmaOutput: 'Global R',
      physicalOutput: 'R bus', cellName: 'TUNAI_GLOBAL_PEQ_R'),
  ];

  static List<Adau1466PeqCoefficientRow> parse(String source) {
    final lines = source.split(RegExp(r'\r?\n'));
    final accepted = {for (final output in outputs) output.cellName};
    final outputByCell = {for (final output in outputs) output.cellName: output};
    final rows = <Adau1466PeqCoefficientRow>[];
    String? cell;
    String? parameter;
    int? baseAddress;
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (line.startsWith('Cell Name')) {
        cell = line.split('=').skip(1).join('=').trim();
        parameter = null;
        baseAddress = null;
      } else if (line.startsWith('Parameter Name')) {
        parameter = line.split('=').skip(1).join('=').trim();
      } else if (line.startsWith('Parameter Address')) {
        baseAddress = int.parse(line.split('=').last.trim());
      } else if (line.trim() == 'Parameter Data :' &&
          cell != null && accepted.contains(cell) &&
          parameter != null && baseAddress != null) {
        final secondHalf = parameter.endsWith('_20');
        var wordIndex = 0;
        for (var dataLine = index + 1; dataLine < lines.length; dataLine++) {
          final data = lines[dataLine].trim();
          if (data.isEmpty) break;
          final bytes = RegExp(r'0x([0-9A-Fa-f]{2})')
              .allMatches(data).map((match) =>
                  int.parse(match.group(1)!, radix: 16)).toList();
          if (bytes.length != 4) continue;
          final word = (bytes[0] << 24) | (bytes[1] << 16) |
              (bytes[2] << 8) | bytes[3];
          final coefficientIndex = wordIndex % 5;
          rows.add(Adau1466PeqCoefficientRow(
            channel: outputByCell[cell]!.channel, cellName: cell,
            parameterName: parameter,
            bandNumber: (secondHalf ? 11 : 1) + wordIndex ~/ 5,
            coefficient: coefficientOrder[coefficientIndex],
            address: baseAddress + wordIndex, rawWord: word,
            sourceFile: sourceAsset, sourceLine: dataLine + 1));
          wordIndex++;
        }
      }
    }
    return deduplicate(rows);
  }

  static List<Adau1466PeqCoefficientRow> deduplicate(
      Iterable<Adau1466PeqCoefficientRow> input) {
    final byKey = <String, Adau1466PeqCoefficientRow>{};
    for (final row in input) {
      final key = '${row.cellName}|${row.parameterName}|${row.address}';
      final existing = byKey[key];
      if (existing != null && (existing.rawWord != row.rawWord ||
          existing.bandNumber != row.bandNumber ||
          existing.coefficient != row.coefficient)) {
        throw FormatException('Conflicting PEQ row: $key');
      }
      byKey.putIfAbsent(key, () => row);
    }
    final result = byKey.values.toList()
      ..sort((a, b) {
        final cellOrder = a.cellName.compareTo(b.cellName);
        return cellOrder != 0 ? cellOrder : a.address.compareTo(b.address);
      });
    return result;
  }

  static List<Adau1466PeqBandAudit> bands(List<Adau1466PeqCoefficientRow> rows) {
    final result = <Adau1466PeqBandAudit>[];
    for (final output in outputs) {
      for (var band = 1; band <= 20; band++) {
        final group = rows.where((row) => row.cellName == output.cellName &&
            row.bandNumber == band).toList()
          ..sort((a, b) => coefficientOrder.indexOf(a.coefficient)
              .compareTo(coefficientOrder.indexOf(b.coefficient)));
        if (group.isNotEmpty) {
          result.add(Adau1466PeqBandAudit(
              output: output, bandNumber: band, coefficients: group));
        }
      }
    }
    return result;
  }

  static bool acceptsTransaction({required int slewAddress,
    required List<int> coefficientAddresses,
    required List<int> coefficientWords}) => false;

  const ProAdau1466PeqAuditRegistry._();
}
