// ── TUNAI PRO — ADAU1466 Sigma Address Loader ────────────────────────────────
// Parses the embedded CSV and creates Adau1466SigmaCandidate instances.
//
// ABSOLUTE RESTRICTIONS:
//   - No EEPROM. No Selfboot. No WriteAll.
//   - Candidates are read-only classification; write eligibility not granted here.
//   - AI suggests. Expert verifies. AOS protects. DSP executes.

import 'pro_adau1466_sigma_candidate.dart';
import 'pro_adau1466_3way_address_map_embedded.dart';

const _passAckMasterVolumeAddresses = {0x0067, 0x0064};

/// Applies the currently documented ADAU1466 verification evidence.
///
/// ACK-only Master Volume targets remain PASS_ACK. Other Master Volume rows
/// remain candidates (or blocked duplicates) unless measured evidence has been
/// recorded. This also repairs persisted state created by older loader builds
/// that initialized every Master Volume row as VERIFIED.
void normalizeAdau1466VerificationStatuses(
    Iterable<Adau1466SigmaCandidate> candidates) {
  for (final candidate in candidates) {
    if (candidate.kind != CandidateKind.masterVolume) continue;

    final hasDocumentedMeasurement =
        candidate.measurementMethod != null &&
        candidate.measurementMethod != MeasurementMethod.notMeasured &&
        ((candidate.measurementNote?.trim().isNotEmpty ?? false) ||
            (candidate.operatorNote?.trim().isNotEmpty ?? false));
    if (hasDocumentedMeasurement) continue;

    if (_passAckMasterVolumeAddresses.contains(candidate.addressInt)) {
      candidate.validationStatus = CandidateValidationStatus.passAck;
      continue;
    }

    candidate.validationStatus = candidate.isDuplicate
        ? CandidateValidationStatus.blocked
        : CandidateValidationStatus.candidate;
    if (candidate.isDuplicate) {
      candidate.blockedReason =
          'UNVERIFIED_DUPLICATE. Separate audible or measured evidence required.';
    }
  }
}

// ── SigmaLoadResult ───────────────────────────────────────────────────────────

class SigmaLoadResult {
  final List<Adau1466SigmaCandidate> candidates;
  final SigmaExportSignature signature;
  final Map<CandidateKind, int> kindCounts;
  final int unknownCount;
  final int totalLoaded;
  final List<String> sourceFiles;
  final List<String> warnings;

  const SigmaLoadResult({
    required this.candidates,
    required this.signature,
    required this.kindCounts,
    required this.unknownCount,
    required this.totalLoaded,
    required this.sourceFiles,
    required this.warnings,
  });
}

// ── SigmaAddressLoader ────────────────────────────────────────────────────────

class SigmaAddressLoader {
  static SigmaLoadResult load() {
    final warnings = <String>[];
    final candidates = <Adau1466SigmaCandidate>[];
    final seenAddresses = <int, int>{}; // addressInt -> index in candidates

    // Parse embedded CSV
    final lines = kTunaiAdau1466ThreeWayAddressMapCsv.trim().split('\n');
    // Skip header
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      // Split by comma — fields may be empty but no embedded commas
      final cols = line.split(',');
      if (cols.length < 22) {
        warnings.add('Row $i has ${cols.length} columns (expected 22), skipping');
        continue;
      }

      final parameterId    = cols[0].trim();
      // platform = cols[1]
      final blockGroup     = cols[2].trim();
      final channel        = cols[3].trim();
      final sigmaOutputCell= cols[4].trim();
      final physicalOutput = cols[5].trim();
      // parameter_kind = cols[6]
      final bandOrStage    = cols[7].trim();
      final coefficient    = cols[8].trim();
      // cell_name = cols[9]
      final parameterName  = cols[10].trim();
      final logicalName    = cols[11].trim();
      final addressHex     = cols[12].trim();
      final addressIntStr  = cols[13].trim();
      final dataFormat     = cols[14].trim();
      // write_method = cols[15]
      final safeloadReqStr = cols[16].trim();
      // source = cols[17]
      // verification_status = cols[18]
      final currentDataWord= cols[19].trim();
      // current_value = cols[20]
      // notes = cols[21]

      final addressInt = int.tryParse(addressIntStr) ?? 0;
      final safeloadRequired = safeloadReqStr.toLowerCase() == 'true';

      final kind = _classifyKind(blockGroup);
      final region = _classifyRegion(addressInt);
      final risk = _classifyRisk(kind, region, safeloadRequired);

      final isDuplicate = seenAddresses.containsKey(addressInt);
      if (isDuplicate) {
        warnings.add(
            'Duplicate address $addressHex (0x${addressInt.toRadixString(16).toUpperCase().padLeft(4, "0")}) '
            'in row $i — parameter "$parameterName"');
      } else {
        seenAddresses[addressInt] = candidates.length;
      }

      // Initial validation status
      CandidateValidationStatus initStatus;
      String? blockedReason;
      if (kind == CandidateKind.crossover) {
        initStatus = CandidateValidationStatus.blocked;
        blockedReason = 'OUTPUT_MAPPING_NOT_VERIFIED. Actual write disabled.';
      } else if (kind == CandidateKind.peq) {
        initStatus = CandidateValidationStatus.blocked;
        blockedReason = 'SAFELOAD_NOT_VALIDATED + COEFFICIENT_ORDER_UNKNOWN. Actual write disabled.';
      } else if (kind == CandidateKind.safeload) {
        initStatus = CandidateValidationStatus.blocked;
        blockedReason = 'SAFELOAD_NOT_VALIDATED. Sequence requires validation before use.';
      } else if (kind == CandidateKind.masterVolume) {
        // Only the proven write targets have ACK evidence. ACK is not VERIFIED.
        initStatus = _passAckMasterVolumeAddresses.contains(addressInt)
            ? CandidateValidationStatus.passAck
            : isDuplicate
                ? CandidateValidationStatus.blocked
                : CandidateValidationStatus.candidate;
        if (isDuplicate) {
          blockedReason =
              'UNVERIFIED_DUPLICATE. Separate audible or measured evidence required.';
        }
      } else {
        initStatus = CandidateValidationStatus.candidate;
      }

      candidates.add(Adau1466SigmaCandidate(
        id:               'sigma_${addressHex}_$parameterId',
        addressInt:       addressInt,
        addressHex:       addressHex,
        sourceType:       'embedded_csv',
        sourceFile:       'pro_adau1466_3way_address_map_embedded.dart',
        rawName:          parameterName,
        logicalName:      logicalName,
        blockGroup:       blockGroup,
        parameterId:      parameterId,
        coefficient:      coefficient,
        bandOrStage:      bandOrStage,
        kind:             kind,
        guessedChannel:   channel,
        dataFormatHint:   dataFormat,
        sigmaOutputCell:  sigmaOutputCell,
        physicalOutput:   physicalOutput,
        riskLevel:        risk,
        addressRegion:    region,
        exportDefaultHex: currentDataWord,
        safeloadRequired: safeloadRequired,
        isDuplicate:      isDuplicate,
        validationStatus: initStatus,
        blockedReason:    blockedReason,
      ));
    }

    normalizeAdau1466VerificationStatuses(candidates);

    // Count kinds
    final kindCounts = <CandidateKind, int>{};
    int unknownCount = 0;
    for (final c in candidates) {
      kindCounts[c.kind] = (kindCounts[c.kind] ?? 0) + 1;
      if (c.kind == CandidateKind.unknown) unknownCount++;
    }

    // Build signature
    // Simple checksum: rowCount * 31 XOR first 3 addresses
    var checksum = candidates.length * 31;
    for (var k = 0; k < candidates.length && k < 3; k++) {
      checksum ^= candidates[k].addressInt;
    }
    final signature = SigmaExportSignature(
      sourceLabel: 'TUNAI_ADAU1466_3WAY_embedded_v0_8B',
      rowCount:    candidates.length,
      checksum:    checksum.toRadixString(16).toUpperCase().padLeft(8, '0'),
      timestamp:   DateTime.utc(2026, 7, 10),
    );

    return SigmaLoadResult(
      candidates:   candidates,
      signature:    signature,
      kindCounts:   kindCounts,
      unknownCount: unknownCount,
      totalLoaded:  candidates.length,
      sourceFiles:  const ['pro_adau1466_3way_address_map_embedded.dart'],
      warnings:     warnings,
    );
  }

  // ── Classification helpers ─────────────────────────────────────────────────

  static CandidateKind _classifyKind(String blockGroup) => switch (blockGroup) {
    'masterVolume'  => CandidateKind.masterVolume,
    'driverGain'    => CandidateKind.gain,
    'mute'          => CandidateKind.mute,
    'delay'         => CandidateKind.delay,
    'crossover_lpf' => CandidateKind.crossover,
    'crossover_hpf' => CandidateKind.crossover,
    'safeload'      => CandidateKind.safeload,
    'polarity'      => CandidateKind.polarity,
    _               => CandidateKind.unknown,
  };

  static AddressRegion _classifyRegion(int addressInt) {
    if (addressInt >= 0x6000 && addressInt <= 0x6007) return AddressRegion.safeloadArea;
    if (addressInt >= 0x0000 && addressInt <= 0x5FFF) return AddressRegion.parameterRam;
    if (addressInt >= 0x6008 && addressInt <= 0x7FFF) return AddressRegion.unknown;
    return AddressRegion.unknown;
  }

  static CandidateRisk _classifyRisk(
      CandidateKind kind, AddressRegion region, bool safeloadRequired) {
    if (kind == CandidateKind.masterVolume) return CandidateRisk.low;
    if (kind == CandidateKind.crossover || kind == CandidateKind.safeload) {
      return CandidateRisk.high;
    }
    if (safeloadRequired) return CandidateRisk.high;
    return CandidateRisk.medium;
  }
}
