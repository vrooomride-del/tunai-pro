// ── TUNAI PRO Phase U1 — DSP Address Map Importer ────────────────────────────
// Parses the operational ADAU1466 address map CSV and builds a DspAddressRegistry.
//
// Safety rules enforced during import:
//   - Master Volume L (0x0067) and R (0x0064) are promoted to verified/directWriteValidated.
//   - All other Sigma export rows default to exportConfirmed or needsLiveValidation.
//   - No address is invented or inferred. Only rows present in the CSV are imported.
//   - No write permission is implied by import.
//   - exportConfirmed / needsLiveValidation addresses are NOT actual-write eligible.
//   - AI suggests. Expert verifies. AOS protects. DSP executes.

import 'pro_dsp_address_registry.dart';
import 'pro_export_data.dart';

// ── Column indices ────────────────────────────────────────────────────────────
// Matches the CSV header:
// parameter_id, platform, block_group, channel, sigma_output_cell,
// user_physical_output_index, parameter_kind, band_or_stage, coefficient,
// cell_name, parameter_name, logical_name, address_hex, address_int,
// data_format, write_method, safeload_required, source, verification_status,
// current_data_word, current_value, notes

const _colParameterId        = 0;
const _colPlatform           = 1;
const _colBlockGroup         = 2;
const _colChannel            = 3;
const _colSigmaOutputCell    = 4;
const _colPhysicalOutputIdx  = 5;
const _colParameterKind      = 6;
const _colBandOrStage        = 7;
const _colCoefficient        = 8;
// const _colCellName        = 9;  // not used
const _colParameterName      = 10;
const _colLogicalName        = 11;
const _colAddressHex         = 12;
const _colAddressInt         = 13;
const _colDataFormat         = 14;
const _colWriteMethod        = 15;
const _colSafeloadRequired   = 16;
const _colSource             = 17;
const _colVerificationStatus = 18;
const _colCurrentDataWord    = 19;
// const _colCurrentValue    = 20;  // not used
const _colNotes              = 21;

// Verified master volume addresses — these always stay verified/directWriteValidated.
const _kVerifiedMasterVolL = 0x0067;  // 103
const _kVerifiedMasterVolR = 0x0064;  // 100

// ── Result model ──────────────────────────────────────────────────────────────

class AddressMapImportResult {
  final DspAddressRegistry registry;
  final int importedCount;
  final int verifiedCount;
  final int exportConfirmedCount;
  final int needsLiveValidationCount;
  final int skippedCount;
  final Map<DspParameterKind, int> countByKind;
  final List<String> warnings;
  final List<String> errors;
  final String summary;

  const AddressMapImportResult({
    required this.registry,
    required this.importedCount,
    required this.verifiedCount,
    required this.exportConfirmedCount,
    required this.needsLiveValidationCount,
    required this.skippedCount,
    required this.countByKind,
    required this.warnings,
    required this.errors,
    required this.summary,
  });

  Map<String, dynamic> toJson() => {
    'importedCount':            importedCount,
    'verifiedCount':            verifiedCount,
    'exportConfirmedCount':     exportConfirmedCount,
    'needsLiveValidationCount': needsLiveValidationCount,
    'skippedCount':             skippedCount,
    'countByKind':              countByKind.map(
        (k, v) => MapEntry(k.toJson(), v)),
    'warnings':                 warnings,
    'errors':                   errors,
    'summary':                  summary,
  };
}

// ── ProAddressMapImporter ─────────────────────────────────────────────────────

class ProAddressMapImporter {

  /// Parses the operational CSV and returns an [AddressMapImportResult].
  /// Does not touch hardware. Does not enable writes.
  AddressMapImportResult parseOperationalCsv(String content) {
    final lines = content.split('\n');
    if (lines.isEmpty) {
      return _emptyResult('CSV content is empty.');
    }

    // Skip header line
    final dataLines = lines.skip(1).where((l) => l.trim().isNotEmpty).toList();

    final imported  = <VerifiedDspAddress>[];
    final warnings  = <String>[];
    final errors    = <String>[];
    int skipped     = 0;
    final kindCounts = <DspParameterKind, int>{};

    for (int i = 0; i < dataLines.length; i++) {
      final lineNum = i + 2; // 1-indexed, +1 for header
      final fields = _splitCsvLine(dataLines[i]);

      if (fields.length < 14) {
        warnings.add('Line $lineNum: too few fields (${fields.length}), skipped.');
        skipped++;
        continue;
      }

      final addressHexRaw = _field(fields, _colAddressHex);
      final addressIntRaw = _field(fields, _colAddressInt);

      if (addressHexRaw.isEmpty && addressIntRaw.isEmpty) {
        skipped++;
        continue;
      }

      final addressInt = _parseAddress(addressHexRaw, addressIntRaw);
      if (addressInt == null) {
        warnings.add('Line $lineNum: cannot parse address '
            '"$addressHexRaw" / "$addressIntRaw", skipped.');
        skipped++;
        continue;
      }

      final addressHex = _normalizeHex(addressHexRaw, addressInt);

      final paramKindStr = _field(fields, _colParameterKind);
      final kind = _parseParameterKind(paramKindStr);

      kindCounts[kind] = (kindCounts[kind] ?? 0) + 1;

      final logicalName = _field(fields, _colLogicalName).isNotEmpty
          ? _field(fields, _colLogicalName)
          : _field(fields, _colParameterName);

      final platformStr = _field(fields, _colPlatform);
      final platform = _parsePlatform(platformStr);

      final sourceStr   = _field(fields, _colSource);
      final statusStr   = _field(fields, _colVerificationStatus);
      final writeMethod = _field(fields, _colWriteMethod);

      final safeloadRequired = _parseBool(_field(fields, _colSafeloadRequired));

      // Special rule: Master Volume L (0x0067) and R (0x0064) stay verified.
      final (status, source) = _resolveStatusSource(
          addressInt: addressInt,
          statusStr: statusStr,
          sourceStr: sourceStr,
      );

      final parameterId = _field(fields, _colParameterId);
      final blockGroup  = _field(fields, _colBlockGroup);
      final channel     = _field(fields, _colChannel);
      final sigmaCell   = _field(fields, _colSigmaOutputCell);
      final physOut     = _field(fields, _colPhysicalOutputIdx);
      final bandOrStage = _field(fields, _colBandOrStage);
      final coefficient = _field(fields, _colCoefficient);
      final dataFormat  = _field(fields, _colDataFormat);
      final dataWord    = _field(fields, _colCurrentDataWord);
      final notes       = fields.length > _colNotes
          ? _field(fields, _colNotes)
          : null;

      // Generate a unique id from parameterId or address + index
      final id = parameterId.isNotEmpty
          ? parameterId.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')
          : 'addr_${addressHex.replaceAll('0x', '')}_$i';

      imported.add(VerifiedDspAddress(
        id:                 id,
        platform:           platform,
        parameterKind:      kind,
        channelId:          channel.isNotEmpty ? channel : null,
        logicalName:        logicalName,
        addressHex:         addressHex,
        addressInt:         addressInt,
        verificationStatus: status,
        source:             source,
        parameterId:        parameterId.isNotEmpty ? parameterId : null,
        blockGroup:         blockGroup.isNotEmpty ? blockGroup : null,
        sigmaOutputCell:    sigmaCell.isNotEmpty ? sigmaCell : null,
        physicalOutput:     physOut.isNotEmpty ? physOut : null,
        bandOrStage:        bandOrStage.isNotEmpty ? bandOrStage : null,
        coefficient:        coefficient.isNotEmpty ? coefficient : null,
        dataFormat:         dataFormat.isNotEmpty ? dataFormat : null,
        writeMethod:        writeMethod.isNotEmpty ? writeMethod : null,
        safeloadRequired:   safeloadRequired,
        currentDataWord:    dataWord.isNotEmpty ? dataWord : null,
        notes: [
          if (notes != null && notes.isNotEmpty) notes,
          if (status == DspAddressVerificationStatus.exportConfirmed)
            'SigmaStudio export address; live write validation required.',
          if (status == DspAddressVerificationStatus.needsLiveValidation)
            'Needs one-parameter capture to confirm expected effect.',
        ].join(' '),
      ));
    }

    final registry = DspAddressRegistry(
      addresses: imported,
      revision: 1,
    );

    final verifiedN = imported
        .where((a) => a.verificationStatus == DspAddressVerificationStatus.verified)
        .length;
    final exportN = imported
        .where((a) => a.verificationStatus == DspAddressVerificationStatus.exportConfirmed)
        .length;
    final validateN = imported
        .where((a) => a.verificationStatus == DspAddressVerificationStatus.needsLiveValidation)
        .length;

    final summary = 'Imported ${imported.length} addresses: '
        '$verifiedN verified, $exportN export-confirmed, '
        '$validateN needs-live-validation. '
        '$skipped skipped. '
        '${warnings.length} warning(s). '
        'No write permission implied by import.';

    return AddressMapImportResult(
      registry:                registry,
      importedCount:           imported.length,
      verifiedCount:           verifiedN,
      exportConfirmedCount:    exportN,
      needsLiveValidationCount: validateN,
      skippedCount:            skipped,
      countByKind:             kindCounts,
      warnings:                warnings,
      errors:                  errors,
      summary:                 summary,
    );
  }

  /// Convenience: parse CSV and return the registry directly.
  DspAddressRegistry importToRegistry(String content) =>
      parseOperationalCsv(content).registry;

  // ── Helpers ────────────────────────────────────────────────────────────────

  AddressMapImportResult _emptyResult(String reason) => AddressMapImportResult(
    registry:                DspAddressRegistry.createDefault(),
    importedCount:           0,
    verifiedCount:           0,
    exportConfirmedCount:    0,
    needsLiveValidationCount: 0,
    skippedCount:            0,
    countByKind:             {},
    warnings:                [reason],
    errors:                  [],
    summary:                 'Import failed: $reason',
  );

  // Simple CSV line splitter — handles commas within fields where needed.
  // The operational CSV fields do not contain embedded commas in quoted strings,
  // so a simple split is sufficient. Trim whitespace from each field.
  List<String> _splitCsvLine(String line) =>
      line.split(',').map((f) => f.trim()).toList();

  String _field(List<String> fields, int index) =>
      index < fields.length ? fields[index].trim() : '';

  int? _parseAddress(String hexStr, String intStr) {
    // Try hex first (0x0067, 0067, 67)
    if (hexStr.isNotEmpty) {
      final clean = hexStr.toLowerCase().replaceAll('0x', '').trim();
      final parsed = int.tryParse(clean, radix: 16);
      if (parsed != null) return parsed;
    }
    // Fallback to decimal int
    if (intStr.isNotEmpty) {
      return int.tryParse(intStr.trim());
    }
    return null;
  }

  String _normalizeHex(String hexStr, int intVal) {
    if (hexStr.toLowerCase().startsWith('0x')) {
      // Normalize to consistent 4-digit lowercase hex
      return '0x${intVal.toRadixString(16).padLeft(4, '0').toUpperCase()}';
    }
    return '0x${intVal.toRadixString(16).padLeft(4, '0').toUpperCase()}';
  }

  bool? _parseBool(String s) {
    if (s.toLowerCase() == 'true')  return true;
    if (s.toLowerCase() == 'false') return false;
    return null;
  }

  DspTargetPlatform _parsePlatform(String s) {
    switch (s.toUpperCase()) {
      case 'ADAU1466': return DspTargetPlatform.adau1466;
      case 'ADAU1701': return DspTargetPlatform.adau1701;
      default:         return DspTargetPlatform.simulationOnly;
    }
  }

  DspParameterKind _parseParameterKind(String s) {
    switch (s.toLowerCase()) {
      case 'mastervolume':
      case 'master_volume': return DspParameterKind.masterVolume;
      case 'peq':           return DspParameterKind.peq;
      case 'crossover':
      case 'crossover_hpf':
      case 'crossover_lpf': return DspParameterKind.crossover;
      case 'drivergain':
      case 'gain':
      case 'gainslewmode':  return DspParameterKind.gain;
      case 'mute':          return DspParameterKind.mute;
      case 'delay':         return DspParameterKind.delay;
      case 'phase':         return DspParameterKind.phase;
      case 'safeload':      return DspParameterKind.safeload;
      case 'polarity':      return DspParameterKind.polarity;
      case 'protection_limiter':
      case 'protection':    return DspParameterKind.protection;
      case 'router':        return DspParameterKind.router;
      default:              return DspParameterKind.unknown;
    }
  }

  (DspAddressVerificationStatus, DspAddressSource) _resolveStatusSource({
    required int addressInt,
    required String statusStr,
    required String sourceStr,
  }) {
    // Special rule: verified master volume addresses stay verified.
    if (addressInt == _kVerifiedMasterVolL || addressInt == _kVerifiedMasterVolR) {
      return (
        DspAddressVerificationStatus.verified,
        DspAddressSource.directWriteValidated,
      );
    }

    // Map CSV verification_status to enum
    DspAddressVerificationStatus status;
    switch (statusStr.toLowerCase()) {
      case 'verified':
      case 'live_write_verified':
        // Only master vol addresses get verified — others are downgraded.
        status = DspAddressVerificationStatus.needsLiveValidation;
      case 'livewriteverified':
        status = DspAddressVerificationStatus.liveWriteVerified;
      case 'exportconfirmed':
      case 'exported_unvalidated':
      case 'export_confirmed':
        status = DspAddressVerificationStatus.exportConfirmed;
      case 'needslivevalidation':
      case 'needs_live_validation':
      case 'requirescapture':
        status = DspAddressVerificationStatus.needsLiveValidation;
      default:
        status = DspAddressVerificationStatus.exportConfirmed;
    }

    // Map CSV source to enum
    DspAddressSource source;
    switch (sourceStr.toLowerCase()) {
      case 'sigmastudio .params export':
      case 'sigmastudioexport':
      case 'sigma_studio_export':
        source = DspAddressSource.sigmaStudioExport;
      case 'sigmastudiocapture':
      case 'sigma_studio_capture':
        source = DspAddressSource.sigmaStudioCapture;
      case 'directwritevalidated':
      case 'direct_write_validated':
        source = DspAddressSource.directWriteValidated;
      case 'livewritevalidation':
        source = DspAddressSource.liveWriteValidation;
      default:
        source = DspAddressSource.sigmaStudioExport;
    }

    return (status, source);
  }
}
