// ── TUNAI PRO — ADAU1466 Sigma Verification Persistence ──────────────────────
// SharedPreferences-based persistence for candidate state and validation log.
//
// ABSOLUTE RESTRICTIONS:
//   - No EEPROM. No Selfboot. No WriteAll.
//   - Persists validation metadata only; does not affect DSP state.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'pro_adau1466_sigma_candidate.dart';

// ── SigmaValidationLogEntry ───────────────────────────────────────────────────

class SigmaValidationLogEntry {
  final DateTime timestamp;
  final int addressInt;
  final String addressHex;
  final String rawName;
  final String kind;
  final String testProfile;
  final String testValueHex;
  final String restoreValueHex;
  final String testBodyHex;
  final String restoreBodyHex;
  final String? testAckBytes;
  final String? restoreAckBytes;
  final bool testWasActualWrite;
  final bool restoreWasActualWrite;
  final String resultStatus;
  final String? error;
  final String? measurementNote;
  final String? operatorNote;
  final String transport;
  final String sigmaSignature;

  const SigmaValidationLogEntry({
    required this.timestamp,
    required this.addressInt,
    required this.addressHex,
    required this.rawName,
    required this.kind,
    required this.testProfile,
    required this.testValueHex,
    required this.restoreValueHex,
    required this.testBodyHex,
    required this.restoreBodyHex,
    this.testAckBytes,
    this.restoreAckBytes,
    required this.testWasActualWrite,
    required this.restoreWasActualWrite,
    required this.resultStatus,
    this.error,
    this.measurementNote,
    this.operatorNote,
    required this.transport,
    required this.sigmaSignature,
  });

  Map<String, dynamic> toJson() => {
    'timestamp':            timestamp.toIso8601String(),
    'addressInt':           addressInt,
    'addressHex':           addressHex,
    'rawName':              rawName,
    'kind':                 kind,
    'testProfile':          testProfile,
    'testValueHex':         testValueHex,
    'restoreValueHex':      restoreValueHex,
    'testBodyHex':          testBodyHex,
    'restoreBodyHex':       restoreBodyHex,
    if (testAckBytes != null)    'testAckBytes':    testAckBytes,
    if (restoreAckBytes != null) 'restoreAckBytes': restoreAckBytes,
    'testWasActualWrite':    testWasActualWrite,
    'restoreWasActualWrite': restoreWasActualWrite,
    'resultStatus':          resultStatus,
    if (error != null)           'error':           error,
    if (measurementNote != null) 'measurementNote': measurementNote,
    if (operatorNote != null)    'operatorNote':    operatorNote,
    'transport':             transport,
    'sigmaSignature':        sigmaSignature,
  };

  factory SigmaValidationLogEntry.fromJson(Map<String, dynamic> j) =>
      SigmaValidationLogEntry(
        timestamp:            DateTime.parse(j['timestamp'] as String),
        addressInt:           j['addressInt']    as int,
        addressHex:           j['addressHex']    as String,
        rawName:              j['rawName']        as String? ?? '',
        kind:                 j['kind']           as String? ?? '',
        testProfile:          j['testProfile']    as String? ?? '',
        testValueHex:         j['testValueHex']   as String? ?? '',
        restoreValueHex:      j['restoreValueHex']as String? ?? '',
        testBodyHex:          j['testBodyHex']    as String? ?? '',
        restoreBodyHex:       j['restoreBodyHex'] as String? ?? '',
        testAckBytes:         j['testAckBytes']   as String?,
        restoreAckBytes:      j['restoreAckBytes']as String?,
        testWasActualWrite:   j['testWasActualWrite']    as bool? ?? false,
        restoreWasActualWrite:j['restoreWasActualWrite'] as bool? ?? false,
        resultStatus:         j['resultStatus']   as String? ?? 'unknown',
        error:                j['error']          as String?,
        measurementNote:      j['measurementNote']as String?,
        operatorNote:         j['operatorNote']   as String?,
        transport:            j['transport']      as String? ?? '',
        sigmaSignature:       j['sigmaSignature'] as String? ?? '',
      );
}

// ── SigmaVerificationPersistence ─────────────────────────────────────────────

class SigmaVerificationPersistence {
  static const _kCandidatesKey = 'tunai_sigma_candidates_v1';
  static const _kLogKey        = 'tunai_sigma_log_v1';

  static Future<void> saveCandidates(
      List<Adau1466SigmaCandidate> candidates) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = candidates.map((c) => c.toJson()).toList();
    await prefs.setString(_kCandidatesKey, jsonEncode(jsonList));
  }

  static Future<List<Adau1466SigmaCandidate>?> loadCandidates() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCandidatesKey);
    if (raw == null) return null;
    try {
      final jsonList = jsonDecode(raw) as List<dynamic>;
      return jsonList
          .map((e) => Adau1466SigmaCandidate.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveLog(List<SigmaValidationLogEntry> log) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = log.map((e) => e.toJson()).toList();
    await prefs.setString(_kLogKey, jsonEncode(jsonList));
  }

  static Future<List<SigmaValidationLogEntry>> loadLog() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLogKey);
    if (raw == null) return [];
    try {
      final jsonList = jsonDecode(raw) as List<dynamic>;
      return jsonList
          .map((e) => SigmaValidationLogEntry.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCandidatesKey);
    await prefs.remove(_kLogKey);
  }
}
