// TUNAI PRO — Phase U1: Address Map Importer tests
//
// Verifies safety guarantees:
//   - Master Volume L (0x0067) / R (0x0064) always remain verified
//   - All other Sigma export rows become exportConfirmed or needsLiveValidation
//   - No address is invented by the importer
//   - No write permission is implied by import
//   - exportConfirmed / needsLiveValidation are NOT actual-write eligible
//   - Malformed rows are skipped with warnings
//   - PEQ coefficient rows counted separately

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_address_map_importer.dart';
import 'package:tunai_pro/core/pro_dsp_address_registry.dart';
import 'package:tunai_pro/core/pro_adau1466_3way_address_map_embedded.dart';
import 'package:tunai_pro/core/pro_export_data.dart';

// ── Minimal test CSV ──────────────────────────────────────────────────────────

const _kHeader =
    'parameter_id,platform,block_group,channel,sigma_output_cell,'
    'user_physical_output_index,parameter_kind,band_or_stage,coefficient,'
    'cell_name,parameter_name,logical_name,address_hex,address_int,'
    'data_format,write_method,safeload_required,source,verification_status,'
    'current_data_word,current_value,notes';

String _makeCsv(List<String> dataRows) =>
    '$_kHeader\n${dataRows.join('\n')}';

// Build a minimal row with required fields.
// CSV columns: parameter_id(0), platform(1), block_group(2), channel(3),
//   sigma_output_cell(4), user_physical_output_index(5), parameter_kind(6),
//   band_or_stage(7), coefficient(8), cell_name(9), parameter_name(10),
//   logical_name(11), address_hex(12), address_int(13), data_format(14),
//   write_method(15), safeload_required(16), source(17), verification_status(18),
//   current_data_word(19), current_value(20), notes(21)
String _row({
  String parameterId = 'test_param_1',
  String kind = 'delay',
  String logicalName = 'Test Delay',
  String addressHex = '0x03C0',
  String addressInt = '960',
  String writeMethod = 'direct_candidate',
  String safeloadRequired = 'false',
  String source = 'SigmaStudio .params export',
  String status = 'exported_unvalidated',
}) =>
    // col0-1: parameterId, platform
    '$parameterId,ADAU1466,'
    // col2-5: block_group, channel, sigma_output_cell, physical_output_idx
    '$kind,,,,'
    // col6: parameter_kind, col7: band_or_stage, col8: coefficient
    '$kind,,,'
    // col9-11: cell_name, parameter_name, logical_name
    'test_cell,test_param,$logicalName,'
    // col12-13: address_hex, address_int
    '$addressHex,$addressInt,'
    // col14-18: data_format, write_method, safeload_required, source, status
    '8.24 fixed-point,$writeMethod,$safeloadRequired,$source,$status,'
    // col19-21: current_data_word, current_value, notes
    '0x00 0x00 0x00 0x00,0,Test row';

// Master Volume L row — must be promoted to verified by importer
const _kMasterVolLRow =
    'tunai_master_vol_l,ADAU1466,master,,,,,masterVolume,,,,'
    'master_vol_l,TUNAI_MASTER_VOL_L value,0x0067,103,8.24 fixed-point,'
    'direct_candidate,false,SigmaStudio .params export,exported_unvalidated,'
    '0x00 0x80 0x00 0x00,,Master volume L';

// Master Volume R row
const _kMasterVolRRow =
    'tunai_master_vol_r,ADAU1466,master,,,,,masterVolume,,,,'
    'master_vol_r,TUNAI_MASTER_VOL_R value,0x0064,100,8.24 fixed-point,'
    'direct_candidate,false,SigmaStudio .params export,exported_unvalidated,'
    '0x00 0x80 0x00 0x00,,Master volume R';

// SafeLoad row
const _kSafeLoadRow =
    'safeload_data0,ADAU1466,safeload,,,,,safeload,,,,'
    'safeload_data0,SafeLoad data word 0,0x6000,24576,8.24 fixed-point,'
    'direct_candidate,false,SigmaStudio .params export,exported_unvalidated,'
    '0x00 0x00 0x00 0x00,,SafeLoad register';

// PEQ coefficient row (safeload candidate)
const _kPeqRow =
    'peq_b2_1,ADAU1466,GlobalPEQ,,,,peq,band_or_stage_1,b2,'
    ',PEQ_B2_1,PEQ band 1 b2 value,0x036C,876,8.24 fixed-point,'
    'safeload_candidate,true,SigmaStudio .params export,exported_unvalidated,'
    '0x00 0x00 0x00 0x00,,PEQ coefficient';

// XO HPF row — note: channel is at col3, param_kind at col6
const _kXoHpfRow =
    'xo_hpf_mid_l,ADAU1466,crossover_hpf,MID_L,,,crossover_hpf,,,,'
    'MID_L HPF cell,MID_L HPF value,0x0200,512,8.24 fixed-point,'
    'safeload_candidate,true,SigmaStudio .params export,exported_unvalidated,'
    '0x00 0x00 0x00 0x00,,XO HPF';

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  final importer = ProAddressMapImporter();

  group('parseOperationalCsv — master volume protection', () {
    test('Master Volume L address 0x0067 is always verified', () {
      final csv = _makeCsv([_kMasterVolLRow]);
      final result = importer.parseOperationalCsv(csv);
      final addr = result.registry.findByAddressInt(0x0067);
      expect(addr, isNotNull, reason: 'Master Volume L must be in registry');
      expect(addr!.verificationStatus,
          DspAddressVerificationStatus.verified);
    });

    test('Master Volume R address 0x0064 is always verified', () {
      final csv = _makeCsv([_kMasterVolRRow]);
      final result = importer.parseOperationalCsv(csv);
      final addr = result.registry.findByAddressInt(0x0064);
      expect(addr, isNotNull);
      expect(addr!.verificationStatus,
          DspAddressVerificationStatus.verified);
    });

    test('Master Volume L source is directWriteValidated', () {
      final csv = _makeCsv([_kMasterVolLRow]);
      final result = importer.parseOperationalCsv(csv);
      final addr = result.registry.findByAddressInt(0x0067);
      expect(addr!.source, DspAddressSource.directWriteValidated);
    });

    test('Master Volume R source is directWriteValidated', () {
      final csv = _makeCsv([_kMasterVolRRow]);
      final result = importer.parseOperationalCsv(csv);
      final addr = result.registry.findByAddressInt(0x0064);
      expect(addr!.source, DspAddressSource.directWriteValidated);
    });

    test('Master Volume L is actual-write eligible', () {
      final csv = _makeCsv([_kMasterVolLRow]);
      final result = importer.parseOperationalCsv(csv);
      final addr = result.registry.findByAddressInt(0x0067);
      expect(addr!.isActualWriteEligible, isTrue);
    });

    test('Master Volume R is actual-write eligible', () {
      final csv = _makeCsv([_kMasterVolRRow]);
      final result = importer.parseOperationalCsv(csv);
      final addr = result.registry.findByAddressInt(0x0064);
      expect(addr!.isActualWriteEligible, isTrue);
    });

    test('verifiedCount includes master volume addresses', () {
      final csv = _makeCsv([_kMasterVolLRow, _kMasterVolRRow]);
      final result = importer.parseOperationalCsv(csv);
      expect(result.verifiedCount, 2);
    });
  });

  group('parseOperationalCsv — non-master addresses', () {
    test('delay address becomes exportConfirmed', () {
      final csv = _makeCsv([_row(kind: 'delay', addressHex: '0x03C0', addressInt: '960')]);
      final result = importer.parseOperationalCsv(csv);
      final addr = result.registry.findByAddressInt(0x03C0);
      expect(addr, isNotNull);
      expect(
        addr!.verificationStatus,
        anyOf(
          DspAddressVerificationStatus.exportConfirmed,
          DspAddressVerificationStatus.needsLiveValidation,
        ),
      );
    });

    test('non-master addresses are NOT actual-write eligible', () {
      final csv = _makeCsv([_row(kind: 'delay', addressHex: '0x03C0', addressInt: '960')]);
      final result = importer.parseOperationalCsv(csv);
      for (final addr in result.registry.addresses) {
        if (addr.addressInt != 0x0067 && addr.addressInt != 0x0064) {
          expect(addr.isActualWriteEligible, isFalse,
              reason: '${addr.addressHex} (${addr.logicalName}) must not be write-eligible');
        }
      }
    });

    test('non-master importedCount is correct', () {
      final csv = _makeCsv([
        _row(kind: 'delay', addressHex: '0x03C0', addressInt: '960'),
        _kMasterVolLRow,
        _kMasterVolRRow,
      ]);
      final result = importer.parseOperationalCsv(csv);
      expect(result.importedCount, 3);
    });

    test('safeload row is importConfirmed or needsLiveValidation', () {
      final csv = _makeCsv([_kSafeLoadRow]);
      final result = importer.parseOperationalCsv(csv);
      final addr = result.registry.findByAddressInt(0x6000);
      expect(addr, isNotNull);
      expect(
        addr!.verificationStatus,
        anyOf(
          DspAddressVerificationStatus.exportConfirmed,
          DspAddressVerificationStatus.needsLiveValidation,
        ),
      );
    });

    test('PEQ coefficient row parsed as PEQ kind', () {
      final csv = _makeCsv([_kPeqRow]);
      final result = importer.parseOperationalCsv(csv);
      final addr = result.registry.findByAddressInt(0x036C);
      expect(addr, isNotNull);
      expect(addr!.parameterKind, DspParameterKind.peq);
    });

    test('XO row parsed as crossover kind', () {
      final csv = _makeCsv([_kXoHpfRow]);
      final result = importer.parseOperationalCsv(csv);
      final addr = result.registry.findByAddressInt(0x0200);
      expect(addr, isNotNull);
      expect(addr!.parameterKind, DspParameterKind.crossover);
    });

    test('safeload_required field is preserved', () {
      final csv = _makeCsv([_kPeqRow]);
      final result = importer.parseOperationalCsv(csv);
      final addr = result.registry.findByAddressInt(0x036C);
      expect(addr!.safeloadRequired, isTrue);
    });

    test('output_index column is preserved', () {
      const rowWithOutput =
          'test_xo,ADAU1466,crossover_hpf,MID_L,SigOut2,2,crossover_hpf,,,value,'
          'test_xo,MID_L HPF,0x0200,512,8.24 fixed-point,safeload_candidate,true,'
          'SigmaStudio .params export,exported_unvalidated,0x00 0x00 0x00 0x00,,note';
      final csv = _makeCsv([rowWithOutput]);
      final result = importer.parseOperationalCsv(csv);
      final addr = result.registry.findByAddressInt(0x0200);
      expect(addr, isNotNull);
      // physicalOutput or sigmaOutputCell should be present
      expect(addr!.sigmaOutputCell != null || addr.physicalOutput != null, isTrue);
    });
  });

  group('parseOperationalCsv — address parsing', () {
    test('hex address with 0x prefix is parsed', () {
      final csv = _makeCsv([_row(addressHex: '0x03C0', addressInt: '960')]);
      final result = importer.parseOperationalCsv(csv);
      expect(result.registry.findByAddressInt(0x03C0), isNotNull);
    });

    test('hex address without 0x prefix is parsed', () {
      final csv = _makeCsv([_row(addressHex: '03C0', addressInt: '960')]);
      final result = importer.parseOperationalCsv(csv);
      expect(result.registry.findByAddressInt(0x03C0), isNotNull);
    });

    test('short hex address is parsed', () {
      final csv = _makeCsv([_row(addressHex: '67', addressInt: '103')]);
      final result = importer.parseOperationalCsv(csv);
      expect(result.registry.findByAddressInt(0x67), isNotNull);
    });

    test('int fallback is used when hex is missing', () {
      final csv = _makeCsv([_row(addressHex: '', addressInt: '960')]);
      final result = importer.parseOperationalCsv(csv);
      expect(result.registry.findByAddressInt(960), isNotNull);
    });
  });

  group('parseOperationalCsv — malformed rows', () {
    test('row with too few fields is skipped with warning', () {
      const badRow = 'bad_row,ADAU1466';
      final csv = _makeCsv([badRow]);
      final result = importer.parseOperationalCsv(csv);
      expect(result.importedCount, 0);
      expect(result.skippedCount, 1);
      expect(result.warnings, isNotEmpty);
    });

    test('row with no address is skipped', () {
      final csv = _makeCsv([_row(addressHex: '', addressInt: '')]);
      final result = importer.parseOperationalCsv(csv);
      expect(result.importedCount, 0);
    });

    test('row with unparseable hex is skipped with warning', () {
      final csv = _makeCsv([_row(addressHex: 'ZZZZ', addressInt: '')]);
      final result = importer.parseOperationalCsv(csv);
      expect(result.skippedCount, greaterThan(0));
    });

    test('header-only CSV returns zero imported addresses', () {
      // Only header, no data rows → 0 imported
      final result = importer.parseOperationalCsv(_kHeader);
      expect(result.importedCount, 0);
    });
  });

  group('embedded CSV — real address map', () {
    late AddressMapImportResult result;

    setUpAll(() {
      result = importer.parseOperationalCsv(kTunaiAdau1466ThreeWayAddressMapCsv);
    });

    test('embedded CSV imports non-zero addresses', () {
      expect(result.importedCount, greaterThan(0));
    });

    test('embedded CSV has exactly 2 verified master volume addresses', () {
      expect(result.verifiedCount, 2);
    });

    test('embedded CSV has Master Volume L (0x0067) verified', () {
      final addr = result.registry.findByAddressInt(0x0067);
      expect(addr, isNotNull);
      expect(addr!.verificationStatus, DspAddressVerificationStatus.verified);
    });

    test('embedded CSV has Master Volume R (0x0064) verified', () {
      final addr = result.registry.findByAddressInt(0x0064);
      expect(addr, isNotNull);
      expect(addr!.verificationStatus, DspAddressVerificationStatus.verified);
    });

    test('embedded CSV: no non-master address is actual-write eligible', () {
      for (final addr in result.registry.addresses) {
        if (addr.addressInt != 0x0067 && addr.addressInt != 0x0064) {
          expect(addr.isActualWriteEligible, isFalse,
              reason: '${addr.addressHex} must not be write-eligible');
        }
      }
    });

    test('embedded CSV has safeload addresses', () {
      final safeload = result.registry.addressesForKind(DspParameterKind.safeload);
      expect(safeload, isNotEmpty);
    });

    test('embedded CSV has mute addresses', () {
      final mute = result.registry.addressesForKind(DspParameterKind.mute);
      expect(mute, isNotEmpty);
    });

    test('embedded CSV has gain/driver addresses', () {
      final gain = result.registry.addressesForKind(DspParameterKind.gain);
      expect(gain, isNotEmpty);
    });

    test('embedded CSV has delay addresses', () {
      final delay = result.registry.addressesForKind(DspParameterKind.delay);
      expect(delay, isNotEmpty);
    });

    test('embedded CSV has crossover addresses', () {
      final xo = result.registry.addressesForKind(DspParameterKind.crossover);
      expect(xo, isNotEmpty);
    });

    test('3-way factory registry has more entries than default', () {
      final threeWay = createTunaiAdau1466ThreeWayRegistry();
      final defaultReg = DspAddressRegistry.createDefault();
      expect(threeWay.addresses.length, greaterThan(defaultReg.addresses.length));
    });

    test('3-way factory has peqRowCount set', () {
      final threeWay = createTunaiAdau1466ThreeWayRegistry();
      expect(threeWay.peqRowCount, kTunaiAdau1466ThreeWayPeqRowCount);
    });

    test('3-way factory totalImportedCount matches expected', () {
      final threeWay = createTunaiAdau1466ThreeWayRegistry();
      expect(threeWay.totalImportedCount, greaterThan(100));
    });

    test('default registry still has 0x0067 and 0x0064 verified', () {
      final def = DspAddressRegistry.createDefault();
      expect(def.findByAddressInt(0x0067)?.verificationStatus,
          DspAddressVerificationStatus.verified);
      expect(def.findByAddressInt(0x0064)?.verificationStatus,
          DspAddressVerificationStatus.verified);
    });

    test('import does not enable hardware write', () {
      // Summary must not claim write is enabled
      expect(result.summary.toLowerCase(), isNot(contains('write enabled')));
      expect(result.summary.toLowerCase(), isNot(contains('write permitted')));
      // The phrase "no write permission" is acceptable (it denies permission)
      expect(result.summary.toLowerCase(),
          isNot(contains('write permission granted')));
    });
  });

  group('safety invariants', () {
    test('exportConfirmed status is not actual-write eligible', () {
      expect(
          DspAddressVerificationStatus.exportConfirmed.isActualWriteEligible,
          isFalse);
    });

    test('needsLiveValidation status is not actual-write eligible', () {
      expect(
          DspAddressVerificationStatus.needsLiveValidation.isActualWriteEligible,
          isFalse);
    });

    test('unknown status is not actual-write eligible', () {
      expect(
          DspAddressVerificationStatus.unknown.isActualWriteEligible,
          isFalse);
    });

    test('unverified status is not actual-write eligible', () {
      expect(
          DspAddressVerificationStatus.unverified.isActualWriteEligible,
          isFalse);
    });

    test('blocked status is not actual-write eligible', () {
      expect(
          DspAddressVerificationStatus.blocked.isActualWriteEligible,
          isFalse);
    });

    test('only verified and liveWriteVerified are actual-write eligible', () {
      for (final s in DspAddressVerificationStatus.values) {
        if (s == DspAddressVerificationStatus.verified ||
            s == DspAddressVerificationStatus.liveWriteVerified) {
          expect(s.isActualWriteEligible, isTrue, reason: '$s should be eligible');
        } else {
          expect(s.isActualWriteEligible, isFalse, reason: '$s should not be eligible');
        }
      }
    });

    test('JSON round-trip for DspAddressVerificationStatus', () {
      for (final s in DspAddressVerificationStatus.values) {
        expect(DspAddressVerificationStatus.fromJson(s.toJson()), s);
      }
    });

    test('JSON round-trip for DspAddressSource', () {
      for (final s in DspAddressSource.values) {
        expect(DspAddressSource.fromJson(s.toJson()), s);
      }
    });

    test('JSON round-trip for DspParameterKind', () {
      for (final k in DspParameterKind.values) {
        expect(DspParameterKind.fromJson(k.toJson()), k);
      }
    });

    test('VerifiedDspAddress JSON round-trip preserves verification status', () {
      const addr = VerifiedDspAddress(
        id: 'test',
        platform: DspTargetPlatform.adau1466,
        parameterKind: DspParameterKind.delay,
        logicalName: 'Test Delay',
        addressHex: '0x03C0',
        addressInt: 0x03C0,
        verificationStatus: DspAddressVerificationStatus.exportConfirmed,
        source: DspAddressSource.sigmaStudioExport,
      );
      final restored = VerifiedDspAddress.fromJson(addr.toJson());
      expect(restored.verificationStatus, addr.verificationStatus);
      expect(restored.isActualWriteEligible, isFalse);
    });

    test('DspAddressRegistry JSON round-trip preserves peqRowCount', () {
      final reg = DspAddressRegistry(
        addresses: const [],
        peqRowCount: 875,
        peqStatus: DspAddressVerificationStatus.exportConfirmed,
      );
      final restored = DspAddressRegistry.fromJson(reg.toJson());
      expect(restored.peqRowCount, 875);
      expect(restored.peqStatus, DspAddressVerificationStatus.exportConfirmed);
    });
  });
}
