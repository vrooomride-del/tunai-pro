import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/dsp/dsp_address_map.dart';
import '../../core/dsp/transport/dsp_transport_provider.dart';
import '../../core/dsp/transport/dsp_write_logger.dart';
import '../../core/profiles/system_profile.dart';
import '../connect/connect_controller.dart';

final masterVolumeProvider =
    StateNotifierProvider<MasterVolumeController, double>(
  (ref) => MasterVolumeController(ref),
);

class MasterVolumeController extends StateNotifier<double> {
  MasterVolumeController(this._ref) : super(-60.0) {
    // 연결 성공 시 자동 -60dB write
    _sub = _ref.listen<ConnectState>(connectProvider, (prev, next) {
      if (next.connected && !(prev?.connected ?? false)) {
        writeConnectDefault();
      }
    });
  }

  final Ref _ref;
  late final ProviderSubscription<ConnectState> _sub;

  Future<void> setVolume(double dB) async {
    final clamped = dB.clamp(-70.0, 0.0);
    state = clamped;

    final transport = _ref.read(dspTransportProvider);
    if (transport == null) return;

    final profile = _ref.read(systemProfileProvider);
    final linear = pow(10.0, clamped / 20.0).toDouble();

    final List<int> bytes4;
    final int addrL;
    final int addrR;
    final String profileName;

    if (profile.isAdau1466) {
      // ADAU1466 5.27 고정소수점 — dbToFixed824() 사용 금지 (Q8.24 ≠ 5.27)
      final fixed = (linear * (1 << 27)).round();
      bytes4 = _toBytes4(fixed);
      addrL = kAdau1466MasterVolL;
      addrR = kAdau1466MasterVolR;
      profileName = 'adau1466';
    } else {
      // ADAU1701 5.23 고정소수점
      final fixed = (linear * (1 << 23)).round();
      bytes4 = _toBytes4(fixed);
      addrL = kAdau1701MasterVolL;
      addrR = kAdau1701MasterVolR;
      profileName = 'adau1701';
    }

    await transport.writeParameter(addrL, bytes4);
    await transport.writeParameter(addrR, bytes4);

    _ref.read(dspWriteLoggerProvider).log(
      profile: profileName, param: 'masterVol',
      addrL: addrL, addrR: addrR,
      bytes: bytes4, dB: clamped,
      success: true, timestamp: DateTime.now(),
    );
    debugPrint('[MasterVol] ${profile.chipLabel} dB=$clamped '
        'addrL=0x${addrL.toRadixString(16)} addrR=0x${addrR.toRadixString(16)}');
  }

  Future<void> writeConnectDefault() => setVolume(-60.0);

  /// 슬라이더 드래그 중 UI만 업데이트 (DSP write 없음) — onChangeEnd에서 setVolume 호출.
  void updateUiOnly(double dB) => state = dB.clamp(-70.0, 0.0);

  static List<int> _toBytes4(int v) => [
        (v >> 24) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 8) & 0xFF,
        v & 0xFF,
      ];

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}
