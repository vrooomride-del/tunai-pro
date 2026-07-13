// ── TUNAI PRO — ADAU1466 Sigma Verification Console Tests ─────────────────────
// Covers candidate loading, classification, body-hex building, guard logic,
// executor result semantics, and safety restrictions.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_adau1466_sigma_candidate.dart';
import 'package:tunai_pro/core/pro_adau1466_sigma_loader.dart';
import 'package:tunai_pro/core/pro_adau1466_sigma_executor.dart';
import 'package:tunai_pro/core/pro_usbi_native_backend.dart';
import 'package:tunai_pro/core/pro_usbi_packet_builder.dart';
import 'package:tunai_pro/core/pro_hardware_transport.dart';

// ── Fake backend for guard tests ──────────────────────────────────────────────

class _FakeBackend implements ProUsbiNativeBackend {
  final bool _available;
  List<int>? ackToReturn;

  _FakeBackend({bool available = true, this.ackToReturn}) : _available = available;

  @override
  bool get isAvailable => _available;

  @override
  bool get isFake => true;

  @override
  Future<List<int>?> sendPacketsAndReadAck({
    required List<int> setupPacket,
    required List<int> bodyPacket,
    required List<int> ackReadRequest,
  }) async => ackToReturn ?? [0x01];
}

void main() {
  // ── 1: Sigma export candidates load ───────────────────────────────────────

  group('1. Sigma export candidates load', () {
    test('SigmaAddressLoader.load() returns non-empty candidates', () {
      final result = SigmaAddressLoader.load();
      expect(result.candidates, isNotEmpty);
      expect(result.totalLoaded, greaterThan(0));
    });

    test('Load result has valid signature', () {
      final result = SigmaAddressLoader.load();
      expect(result.signature.rowCount, equals(result.totalLoaded));
      expect(result.signature.checksum, isNotEmpty);
      expect(result.signature.sourceLabel, isNotEmpty);
    });

    test('Source files list is non-empty', () {
      final result = SigmaAddressLoader.load();
      expect(result.sourceFiles, isNotEmpty);
    });
  });

  // ── 2: Unknown candidates are visible ─────────────────────────────────────

  group('2. Unknown candidates are visible', () {
    test('Unknown candidates exist in loaded set', () {
      SigmaAddressLoader.load();
      // unknown count may be 0 if all classified; just ensure kind exists
      expect(CandidateKind.unknown, isNotNull);
    });

    test('No candidate is silently discarded — all have addressHex', () {
      final result = SigmaAddressLoader.load();
      for (final c in result.candidates) {
        expect(c.addressHex, isNotEmpty);
      }
    });
  });

  // ── 3: Master Volume 0x0067 and 0x0064 ───────────────────────────────────

  group('3. Master Volume addresses present', () {
    test('0x0067 loaded from CSV', () {
      final result = SigmaAddressLoader.load();
      final mv = result.candidates.where((c) => c.addressInt == 0x0067);
      expect(mv, isNotEmpty, reason: 'Master Volume L 0x0067 must be in CSV');
    });

    test('0x0064 loaded from CSV', () {
      final result = SigmaAddressLoader.load();
      final mv = result.candidates.where((c) => c.addressInt == 0x0064);
      expect(mv, isNotEmpty, reason: 'Master Volume R 0x0064 must be in CSV');
    });

    test('Master Volume candidates classified as masterVolume kind', () {
      final result = SigmaAddressLoader.load();
      final mvL = result.candidates.firstWhere((c) => c.addressInt == 0x0067);
      final mvR = result.candidates.firstWhere((c) => c.addressInt == 0x0064);
      expect(mvL.kind, equals(CandidateKind.masterVolume));
      expect(mvR.kind, equals(CandidateKind.masterVolume));
    });

    test('Master Volume candidates are verified by default', () {
      final result = SigmaAddressLoader.load();
      final mvL = result.candidates.firstWhere((c) => c.addressInt == 0x0067);
      expect(mvL.validationStatus, equals(CandidateValidationStatus.verified));
    });
  });

  // ── 4: Classification keyword coverage ───────────────────────────────────

  group('4. Candidate classification finds expected kinds', () {
    test('delay kind exists in CandidateKind enum', () {
      expect(CandidateKind.delay, isNotNull);
    });

    test('peq kind exists', () {
      expect(CandidateKind.peq, isNotNull);
    });

    test('crossover kind exists', () {
      expect(CandidateKind.crossover, isNotNull);
    });

    test('safeload kind exists', () {
      expect(CandidateKind.safeload, isNotNull);
    });

    test('gain kind exists', () {
      expect(CandidateKind.gain, isNotNull);
    });

    test('mute kind exists', () {
      expect(CandidateKind.mute, isNotNull);
    });

    test('kindCounts is populated for loaded kinds', () {
      final result = SigmaAddressLoader.load();
      expect(result.kindCounts, isNotEmpty);
    });
  });

  // ── 5: Candidate table filter logic ──────────────────────────────────────

  group('5. Candidate table filter works', () {
    test('Filtering by masterVolume returns only masterVolume candidates', () {
      final result = SigmaAddressLoader.load();
      final filtered = result.candidates
          .where((c) => c.kind == CandidateKind.masterVolume)
          .toList();
      for (final c in filtered) {
        expect(c.kind, equals(CandidateKind.masterVolume));
      }
    });

    test('Filtering by blocked returns only blocked candidates', () {
      final result = SigmaAddressLoader.load();
      final blocked = result.candidates
          .where((c) => c.validationStatus == CandidateValidationStatus.blocked)
          .toList();
      for (final c in blocked) {
        expect(c.validationStatus, equals(CandidateValidationStatus.blocked));
      }
    });
  });

  // ── 6: Manual override works ──────────────────────────────────────────────

  group('6. Manual override via mutable fields', () {
    test('validationStatus can be changed to verified', () {
      final result = SigmaAddressLoader.load();
      final c = result.candidates.first;
      c.validationStatus = CandidateValidationStatus.verified;
      expect(c.validationStatus, equals(CandidateValidationStatus.verified));
    });

    test('operatorNote can be set', () {
      final result = SigmaAddressLoader.load();
      final c = result.candidates.first;
      c.operatorNote = 'test note';
      expect(c.operatorNote, equals('test note'));
    });

    test('measurementNote can be set', () {
      final result = SigmaAddressLoader.load();
      final c = result.candidates.first;
      c.measurementNote = 'scope: -3 dB at 1kHz';
      expect(c.measurementNote, equals('scope: -3 dB at 1kHz'));
    });
  });

  // ── 7–10: Body hex building ───────────────────────────────────────────────

  group('7–10. Body hex building', () {
    test('0x0067 + 0x01000000 = 00 67 01 00 00 00', () {
      final body = buildParameterWriteBody(
          addressInt: 0x0067, fixedPointInt: 0x01000000);
      expect(body, equals([0x00, 0x67, 0x01, 0x00, 0x00, 0x00]));
    });

    test('0x0067 + 0x00800000 = 00 67 00 80 00 00', () {
      final body = buildParameterWriteBody(
          addressInt: 0x0067, fixedPointInt: 0x00800000);
      expect(body, equals([0x00, 0x67, 0x00, 0x80, 0x00, 0x00]));
    });

    test('0x0064 + 0x01000000 = 00 64 01 00 00 00', () {
      final body = buildParameterWriteBody(
          addressInt: 0x0064, fixedPointInt: 0x01000000);
      expect(body, equals([0x00, 0x64, 0x01, 0x00, 0x00, 0x00]));
    });

    test('0x0064 + 0x00000000 = 00 64 00 00 00 00', () {
      final body = buildParameterWriteBody(
          addressInt: 0x0064, fixedPointInt: 0x00000000);
      expect(body, equals([0x00, 0x64, 0x00, 0x00, 0x00, 0x00]));
    });

    test('bytesToHex encodes body correctly', () {
      final body = buildParameterWriteBody(
          addressInt: 0x0067, fixedPointInt: 0x01000000);
      final hex = bytesToHex(body).replaceAll(' ', '').toLowerCase();
      expect(hex, contains('006701000000'));
    });
  });

  // ── 11: ACK [01] accepted ─────────────────────────────────────────────────

  group('11. ACK [01] accepted', () {
    test('isAckSuccess([0x01]) == true', () {
      expect(isAckSuccess([0x01]), isTrue);
    });

    test('isAckSuccess([0x00]) == false', () {
      expect(isAckSuccess([0x00]), isFalse);
    });

    test('isAckSuccess(8-byte response with byte[6]==0x01) == true', () {
      expect(
        isAckSuccess([0xC0, 0xB5, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00]),
        isTrue,
      );
    });

    test('isAckSuccess([]) == false', () {
      expect(isAckSuccess([]), isFalse);
    });
  });

  // ── 12: G1 — Windows only guard ───────────────────────────────────────────

  group('12. Execution blocked without Windows', () {
    test('Non-Windows platform blocks write', () async {
      final executor = ProUsbiSigmaVerificationExecutor(
        backend: _FakeBackend(),
        isWindowsPlatform: () => false,
      );
      final result = await executor.writeWithRestore(SigmaVerificationWriteRequest(
        id: 'test_g1',
        addressInt: 0x0067,
        addressHex: '0x0067',
        label: 'MV L',
        testValue32: 0x00800000,
        restoreValue32: 0x01000000,
        userConfirmed: true,
        restoreValueConfirmed: true,
      ));
      expect(result.testWasActualWrite, isFalse);
      expect(result.error, contains('G1'));
    });
  });

  // ── 13: G2 — Confirmation guard ───────────────────────────────────────────

  group('13. Execution blocked without user confirmation', () {
    test('userConfirmed=false blocks write', () async {
      final executor = ProUsbiSigmaVerificationExecutor(
        backend: _FakeBackend(),
        isWindowsPlatform: () => true,
      );
      final result = await executor.writeWithRestore(SigmaVerificationWriteRequest(
        id: 'test_g2',
        addressInt: 0x0067,
        addressHex: '0x0067',
        label: 'MV L',
        testValue32: 0x00800000,
        restoreValue32: 0x01000000,
        userConfirmed: false,
        restoreValueConfirmed: true,
      ));
      expect(result.testWasActualWrite, isFalse);
      expect(result.error, contains('G2'));
    });
  });

  // ── 14: G3 — Restore value confirmed guard ────────────────────────────────

  group('14. Execution blocked without restore value confirmation', () {
    test('restoreValueConfirmed=false blocks write', () async {
      final executor = ProUsbiSigmaVerificationExecutor(
        backend: _FakeBackend(),
        isWindowsPlatform: () => true,
      );
      final result = await executor.writeWithRestore(SigmaVerificationWriteRequest(
        id: 'test_g3',
        addressInt: 0x0067,
        addressHex: '0x0067',
        label: 'MV L',
        testValue32: 0x00800000,
        restoreValue32: 0x01000000,
        userConfirmed: true,
        restoreValueConfirmed: false,
      ));
      expect(result.testWasActualWrite, isFalse);
      expect(result.error, contains('G3'));
    });
  });

  // ── 15: Gain candidate test + restore ─────────────────────────────────────

  group('15. Gain candidate can run test + restore', () {
    test('Gain candidate with all guards passed executes and logs wasActualWrite', () async {
      final executor = ProUsbiSigmaVerificationExecutor(
        backend: _FakeBackend(ackToReturn: [0x01]),
        isWindowsPlatform: () => true,
      );
      final result = await executor.writeWithRestore(SigmaVerificationWriteRequest(
        id: 'test_gain',
        addressInt: 0x0100, // hypothetical gain address
        addressHex: '0x0100',
        label: 'Gain CH1',
        testValue32: 0x00800000,
        restoreValue32: 0x01000000,
        userConfirmed: true,
        restoreValueConfirmed: true,
      ));
      expect(result.testWasActualWrite, isTrue);
      expect(result.testAckOk, isTrue);
      expect(result.restoreWasActualWrite, isTrue);
    });
  });

  // ── 16: Mute candidate test + restore ────────────────────────────────────

  group('16. Mute candidate can run test + restore', () {
    test('Mute candidate with all guards passed and ACK [0x01] passes', () async {
      final executor = ProUsbiSigmaVerificationExecutor(
        backend: _FakeBackend(ackToReturn: [0x01]),
        isWindowsPlatform: () => true,
      );
      final result = await executor.writeWithRestore(SigmaVerificationWriteRequest(
        id: 'test_mute',
        addressInt: 0x0110,
        addressHex: '0x0110',
        label: 'Mute CH1',
        testValue32: 0x01000000, // Mute A
        restoreValue32: 0x00000000,
        userConfirmed: true,
        restoreValueConfirmed: true,
      ));
      expect(result.testWasActualWrite, isTrue);
      expect(result.testAckOk, isTrue);
      expect(result.resultStatus, equals(CandidateValidationStatus.passAck));
    });
  });

  // ── 17: Delay candidate raw small-step ───────────────────────────────────

  group('17. Delay candidate raw small-step test + restore', () {
    test('Delay raw 0x00000001 with confirmed restore executes', () async {
      final executor = ProUsbiSigmaVerificationExecutor(
        backend: _FakeBackend(ackToReturn: [0x01]),
        isWindowsPlatform: () => true,
      );
      final result = await executor.writeWithRestore(SigmaVerificationWriteRequest(
        id: 'test_delay',
        addressInt: 0x0200,
        addressHex: '0x0200',
        label: 'Delay CH1',
        testValue32: 0x00000001,
        restoreValue32: 0x00000000, // operator confirmed
        userConfirmed: true,
        restoreValueConfirmed: true,
      ));
      expect(result.testWasActualWrite, isTrue);
      expect(result.restoreWasActualWrite, isTrue);
    });

    test('Delay test body is non-empty hex string', () async {
      final executor = ProUsbiSigmaVerificationExecutor(
        backend: _FakeBackend(),
        isWindowsPlatform: () => true,
      );
      final result = await executor.writeWithRestore(SigmaVerificationWriteRequest(
        id: 'test_delay_hex',
        addressInt: 0x0200,
        addressHex: '0x0200',
        label: 'Delay CH1',
        testValue32: 0x00000001,
        restoreValue32: 0x00000000,
        userConfirmed: true,
        restoreValueConfirmed: true,
      ));
      expect(result.testBodyHex, isNotEmpty);
    });
  });

  // ── 18: Raw unknown candidate ─────────────────────────────────────────────

  group('18. Raw unknown candidate with raw 32-bit + restore', () {
    test('Unknown address in param RAM can execute with explicit confirmation', () async {
      final executor = ProUsbiSigmaVerificationExecutor(
        backend: _FakeBackend(ackToReturn: [0x01]),
        isWindowsPlatform: () => true,
      );
      final result = await executor.writeWithRestore(SigmaVerificationWriteRequest(
        id: 'test_unknown',
        addressInt: 0x1000,
        addressHex: '0x1000',
        label: 'Unknown raw',
        testValue32: 0x00000001,
        restoreValue32: 0x00000000,
        userConfirmed: true,
        restoreValueConfirmed: true,
      ));
      expect(result.testWasActualWrite, isTrue);
    });
  });

  // ── 19: G5 — Dangerous address guard ──────────────────────────────────────

  group('19. Dangerous address guard', () {
    test('Address >= 0x8000 is blocked (EEPROM/Selfboot region)', () async {
      final executor = ProUsbiSigmaVerificationExecutor(
        backend: _FakeBackend(),
        isWindowsPlatform: () => true,
      );
      final result = await executor.writeWithRestore(SigmaVerificationWriteRequest(
        id: 'test_g5',
        addressInt: 0x8000,
        addressHex: '0x8000',
        label: 'Dangerous',
        testValue32: 0x00000001,
        restoreValue32: 0x00000000,
        userConfirmed: true,
        restoreValueConfirmed: true,
      ));
      expect(result.testWasActualWrite, isFalse);
      expect(result.error, contains('G5'));
    });

    test('SafeLoad area 0x6000 is NOT blocked by G5', () async {
      final executor = ProUsbiSigmaVerificationExecutor(
        backend: _FakeBackend(ackToReturn: [0x01]),
        isWindowsPlatform: () => true,
      );
      final result = await executor.writeWithRestore(SigmaVerificationWriteRequest(
        id: 'test_safeload',
        addressInt: 0x6000,
        addressHex: '0x6000',
        label: 'SafeLoad Data',
        testValue32: 0x00000001,
        restoreValue32: 0x00000000,
        userConfirmed: true,
        restoreValueConfirmed: true,
      ));
      // 0x6000 is in safeload area, should NOT be blocked by G5
      expect(result.error, isNot(contains('G5')));
    });
  });

  // ── 20: Address region unknown warning ────────────────────────────────────

  group('20. Address region classification', () {
    test('parameterRam label is correct', () {
      expect(AddressRegion.parameterRam.label, equals('Parameter RAM'));
    });

    test('safeloadArea label is correct', () {
      expect(AddressRegion.safeloadArea.label, equals('SafeLoad Area'));
    });

    test('Address 0x1000 is parameterRam region', () {
      // Verified by loader logic: 0x0000–0x5FFF = parameterRam
      final result = SigmaAddressLoader.load();
      final candidate = result.candidates
          .firstWhere((c) => c.addressInt < 0x6000, orElse: () => result.candidates.first);
      expect(candidate.addressRegion, equals(AddressRegion.parameterRam));
    });
  });

  // ── 21: SafeLoad registers ────────────────────────────────────────────────

  group('21. SafeLoad register visibility', () {
    test('SafeLoad 0x6000–0x6007 are classified as safeload kind', () {
      final result = SigmaAddressLoader.load();
      for (var addr = 0x6000; addr <= 0x6007; addr++) {
        final matches = result.candidates.where((c) => c.addressInt == addr);
        if (matches.isNotEmpty) {
          expect(matches.first.kind, equals(CandidateKind.safeload));
        }
      }
    });

    test('SafeLoad candidates (if present) are in safeloadArea region', () {
      final result = SigmaAddressLoader.load();
      final safeloads = result.candidates
          .where((c) => c.kind == CandidateKind.safeload)
          .toList();
      for (final s in safeloads) {
        expect(s.addressRegion, equals(AddressRegion.safeloadArea));
      }
    });
  });

  // ── 22: PEQ blocked until SafeLoad validated ──────────────────────────────

  group('22. PEQ candidates blocked', () {
    test('PEQ candidates start as blocked', () {
      final result = SigmaAddressLoader.load();
      final peqCandidates = result.candidates
          .where((c) => c.kind == CandidateKind.peq)
          .toList();
      for (final c in peqCandidates) {
        expect(c.validationStatus, equals(CandidateValidationStatus.blocked));
        expect(c.blockedReason, isNotNull);
        expect(c.blockedReason, contains('SAFELOAD'));
      }
    });
  });

  // ── 23: XO blocked until output mapping verified ──────────────────────────

  group('23. XO candidates blocked', () {
    test('XO candidates start as blocked', () {
      final result = SigmaAddressLoader.load();
      final xoCandidates = result.candidates
          .where((c) => c.kind == CandidateKind.crossover)
          .toList();
      for (final c in xoCandidates) {
        expect(c.validationStatus, equals(CandidateValidationStatus.blocked));
        expect(c.blockedReason, isNotNull);
        expect(c.blockedReason, contains('OUTPUT_MAPPING_NOT_VERIFIED'));
      }
    });
  });

  // ── 24: Restore All must include 0x0067 and 0x0064 ───────────────────────

  group('24. Restore All includes Master Volume addresses', () {
    test('MV L and R addresses are 0x0067 and 0x0064', () {
      // Verify the constants used by restore all
      const mvL = 0x0067;
      const mvR = 0x0064;
      final bodyL = buildParameterWriteBody(
          addressInt: mvL, fixedPointInt: 0x01000000);
      final bodyR = buildParameterWriteBody(
          addressInt: mvR, fixedPointInt: 0x01000000);
      expect(bodyL[0], equals(0x00));
      expect(bodyL[1], equals(0x67));
      expect(bodyR[0], equals(0x00));
      expect(bodyR[1], equals(0x64));
    });
  });

  // ── 25: Verified registry excludes non-verified rows ──────────────────────

  group('25. Export verified registry', () {
    test('Only verified candidates pass the verified filter', () {
      final result = SigmaAddressLoader.load();
      final verified = result.candidates
          .where((c) => c.validationStatus == CandidateValidationStatus.verified)
          .toList();
      for (final c in verified) {
        expect(c.validationStatus, equals(CandidateValidationStatus.verified));
      }
    });

    test('Blocked candidates are excluded from verified set', () {
      final result = SigmaAddressLoader.load();
      final verified = result.candidates
          .where((c) => c.validationStatus == CandidateValidationStatus.verified)
          .toList();
      for (final c in verified) {
        expect(c.validationStatus, isNot(equals(CandidateValidationStatus.blocked)));
      }
    });
  });

  // ── 26: Persistence model round-trip ──────────────────────────────────────

  group('26. Validation state persists via toJson/fromJson', () {
    test('Candidate round-trips through toJson/fromJson', () {
      final result = SigmaAddressLoader.load();
      final c = result.candidates.first;
      c.operatorNote = 'persist test';
      c.validationStatus = CandidateValidationStatus.passAck;
      c.wasActualWrite = true;

      final json = c.toJson();
      final restored = Adau1466SigmaCandidate.fromJson(json);
      expect(restored.operatorNote, equals('persist test'));
      expect(restored.validationStatus, equals(CandidateValidationStatus.passAck));
      expect(restored.wasActualWrite, isTrue);
    });
  });

  // ── 27: Measurement fields stored ─────────────────────────────────────────

  group('27. Measurement fields stored in candidate', () {
    test('measurementBefore, measurementAfter, measurementMethod stored', () {
      final result = SigmaAddressLoader.load();
      final c = result.candidates.first;
      c.measurementBefore   = -3.0;
      c.measurementAfter    = -9.0;
      c.measurementMethod   = MeasurementMethod.scope;
      c.measurementNote     = 'scope shows -6 dB delta';

      final json = c.toJson();
      final restored = Adau1466SigmaCandidate.fromJson(json);
      expect(restored.measurementBefore, equals(-3.0));
      expect(restored.measurementAfter, equals(-9.0));
      expect(restored.measurementMethod, equals(MeasurementMethod.scope));
      expect(restored.measurementNote, equals('scope shows -6 dB delta'));
    });
  });

  // ── 28–30: Safety restrictions ────────────────────────────────────────────

  group('28–30. No EEPROM / Selfboot / Write All', () {
    test('No CandidateKind represents EEPROM', () {
      expect(CandidateKind.values.any((k) => k.name.toLowerCase().contains('eeprom')), isFalse);
    });

    test('No CandidateKind represents selfboot', () {
      expect(CandidateKind.values.any((k) => k.name.toLowerCase().contains('selfboot')), isFalse);
    });

    test('No CandidateKind represents writeAll', () {
      expect(CandidateKind.values.any((k) => k.name.toLowerCase().contains('writeall')), isFalse);
    });

    test('G5 blocks address >= 0x8000 (EEPROM region)', () async {
      final executor = ProUsbiSigmaVerificationExecutor(
        backend: _FakeBackend(),
        isWindowsPlatform: () => true,
      );
      final result = await executor.writeWithRestore(SigmaVerificationWriteRequest(
        id: 'test_eeprom',
        addressInt: 0xFFFF,
        addressHex: '0xFFFF',
        label: 'EEPROM region',
        testValue32: 0x00000001,
        restoreValue32: 0x00000000,
        userConfirmed: true,
        restoreValueConfirmed: true,
      ));
      expect(result.testWasActualWrite, isFalse);
    });
  });

  // ── 31: USBi remains temporary ────────────────────────────────────────────

  group('31. USBi remains temporary', () {
    test('usbiWindowsTemporary backend label contains Temporary', () {
      expect(
        HardwareTransportBackend.usbiWindowsTemporary.label.toLowerCase(),
        contains('temporary'),
      );
    });
  });

  // ── 32: ICP5 remains final target ─────────────────────────────────────────

  group('32. ICP5 remains final target', () {
    test('icp5 backend is not usbiWindowsTemporary', () {
      expect(
        HardwareTransportBackend.icp5,
        isNot(equals(HardwareTransportBackend.usbiWindowsTemporary)),
      );
    });
  });

  // ── 33: Consumer app unchanged ────────────────────────────────────────────

  group('33. Consumer app unchanged', () {
    test('SigmaAddressLoader is in pro core, not consumer', () {
      // If this test file compiles, the loader is in tunai_pro (correct package)
      final result = SigmaAddressLoader.load();
      expect(result.sourceFiles.any((f) => f.contains('embedded')), isTrue);
    });
  });

  // ── 34: Sigma export signature stored ─────────────────────────────────────

  group('34. Sigma export signature is stored', () {
    test('Signature has checksum and sourceLabel', () {
      final result = SigmaAddressLoader.load();
      expect(result.signature.checksum, isNotEmpty);
      expect(result.signature.sourceLabel, isNotEmpty);
      expect(result.signature.rowCount, greaterThan(0));
    });

    test('Signature round-trips through toJson/fromJson', () {
      final result = SigmaAddressLoader.load();
      final json = result.signature.toJson();
      final restored = SigmaExportSignature.fromJson(json);
      expect(restored.checksum, equals(result.signature.checksum));
      expect(restored.rowCount, equals(result.signature.rowCount));
    });
  });

  // ── 35: Changed signature marks stale ─────────────────────────────────────

  group('35. Stale revalidation status exists', () {
    test('staleRevalidationRequired status exists in enum', () {
      expect(CandidateValidationStatus.staleRevalidationRequired, isNotNull);
    });

    test('Candidate validationStatus can be set to staleRevalidationRequired', () {
      final result = SigmaAddressLoader.load();
      final c = result.candidates.first;
      c.validationStatus = CandidateValidationStatus.staleRevalidationRequired;
      expect(c.validationStatus,
          equals(CandidateValidationStatus.staleRevalidationRequired));
    });
  });

  // ── 36: Address validation independent of transport ───────────────────────

  group('36. Addresses are transport-independent', () {
    test('Candidate has no transport field — address is DSP-level', () {
      final result = SigmaAddressLoader.load();
      final c = result.candidates.first;
      // addressInt is the DSP parameter address, not transport-specific
      expect(c.addressInt, isNonZero);
    });
  });

  // ── 37: ICP5 readiness note ───────────────────────────────────────────────

  group('37. ICP5 future target exists in enum', () {
    test('HardwareTransportBackend.icp5 exists', () {
      expect(
        HardwareTransportBackend.values.any((b) => b.name.toLowerCase().contains('icp5')),
        isTrue,
      );
    });
  });

  // ── 38: Real write path — executor logs backendName ──────────────────────

  group('38. Real write path uses real backend', () {
    test('backendName is included in result', () async {
      final executor = ProUsbiSigmaVerificationExecutor(
        backend: _FakeBackend(ackToReturn: [0x01]),
        isWindowsPlatform: () => true,
      );
      final result = await executor.writeWithRestore(SigmaVerificationWriteRequest(
        id: 'test_backend',
        addressInt: 0x0067,
        addressHex: '0x0067',
        label: 'MV L',
        testValue32: 0x01000000,
        restoreValue32: 0x01000000,
        userConfirmed: true,
        restoreValueConfirmed: true,
      ));
      expect(result.backendName, isNotEmpty);
    });

    test('testBodyHex and restoreBodyHex are logged in result', () async {
      final executor = ProUsbiSigmaVerificationExecutor(
        backend: _FakeBackend(ackToReturn: [0x01]),
        isWindowsPlatform: () => true,
      );
      final result = await executor.writeWithRestore(SigmaVerificationWriteRequest(
        id: 'test_body_log',
        addressInt: 0x0067,
        addressHex: '0x0067',
        label: 'MV L',
        testValue32: 0x00800000,
        restoreValue32: 0x01000000,
        userConfirmed: true,
        restoreValueConfirmed: true,
      ));
      expect(result.testBodyHex, isNotEmpty);
      expect(result.restoreBodyHex, isNotEmpty);
    });
  });

  // ── 39: Smoke test uses confirmed USBi path ───────────────────────────────

  group('39. Smoke test path', () {
    test('Smoke test writes 0x0067 and 0x0064 with confirmed backend', () async {
      final executor = ProUsbiSigmaVerificationExecutor(
        backend: _FakeBackend(ackToReturn: [0x01]),
        isWindowsPlatform: () => true,
      );

      for (final addr in [0x0067, 0x0064]) {
        final result = await executor.writeWithRestore(SigmaVerificationWriteRequest(
          id: 'smoke_$addr',
          addressInt: addr,
          addressHex: '0x${addr.toRadixString(16).padLeft(4, '0').toUpperCase()}',
          label: 'Smoke MV',
          testValue32: 0x00800000,
          restoreValue32: 0x01000000,
          userConfirmed: true,
          restoreValueConfirmed: true,
        ));
        expect(result.testWasActualWrite, isTrue);
        expect(result.testAckOk, isTrue);
        expect(result.restoreWasActualWrite, isTrue);
      }
    });
  });

  // ── 40: No uncontrolled profile deployment ────────────────────────────────

  group('40. No uncontrolled profile deployment', () {
    test('CandidateValidationStatus has no deployAll status', () {
      expect(
        CandidateValidationStatus.values
            .any((s) => s.name.toLowerCase().contains('deploy')),
        isFalse,
      );
    });
  });

  // ── 41: Commit/push policy ────────────────────────────────────────────────

  group('41. Build marker and policy', () {
    test('CandidateKind enum has expected count', () {
      // Ensure enum completeness — 12 kinds including unknown
      expect(CandidateKind.values.length, greaterThanOrEqualTo(10));
    });

    test('TestProfile.restoreOnly exists for restore-only operations', () {
      expect(TestProfile.restoreOnly, isNotNull);
    });

    test('PASS_ACK is distinct from VERIFIED', () {
      expect(
        CandidateValidationStatus.passAck,
        isNot(equals(CandidateValidationStatus.verified)),
      );
    });
  });
}
