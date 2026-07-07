import 'package:flutter_riverpod/flutter_riverpod.dart';

final dspWriteLoggerProvider = Provider<DspWriteLogger>((ref) => DspWriteLogger());

class DspWriteEntry {
  final String profile;
  final String param;
  final int addrL;
  final int addrR;
  final List<int> bytes;
  final double dB;
  final bool success;
  final DateTime timestamp;

  const DspWriteEntry({
    required this.profile,
    required this.param,
    required this.addrL,
    required this.addrR,
    required this.bytes,
    required this.dB,
    required this.success,
    required this.timestamp,
  });

  @override
  String toString() =>
      '[$timestamp] $profile.$param dB=$dB addrL=0x${addrL.toRadixString(16)} '
      'addrR=0x${addrR.toRadixString(16)} ok=$success';
}

class DspWriteLogger {
  final _entries = <DspWriteEntry>[];

  void log({
    required String profile,
    required String param,
    required int addrL,
    required int addrR,
    required List<int> bytes,
    required double dB,
    required bool success,
    required DateTime timestamp,
  }) {
    _entries.add(DspWriteEntry(
      profile: profile, param: param,
      addrL: addrL, addrR: addrR,
      bytes: List.unmodifiable(bytes),
      dB: dB, success: success, timestamp: timestamp,
    ));
  }

  List<DspWriteEntry> get entries => List.unmodifiable(_entries);

  void clear() => _entries.clear();
}
