import 'package:flutter/foundation.dart';
import 'dsp_transport.dart';

/// ADAU1701 전송 계층 — UART 또는 BLE ICP5 경유.
/// ConnectController.sendBytes() 콜백을 통해 실제 전송을 위임하므로
/// 현재 연결 모드(UART/BLE)와 무관하게 동일하게 동작한다.
class Adau1701ConnectTransport implements DspTransport {
  final Future<bool> Function(List<int>) _sendBytes;

  Adau1701ConnectTransport(this._sendBytes);

  /// 27바이트 ICP5 프레임: [AA][addr 2B][word0 4B][zeros 16B][XOR][55][zeros 2B]
  @override
  Future<void> writeParameter(int address, List<int> bytes4) async {
    assert(bytes4.length == 4, 'bytes4 must be exactly 4 bytes');
    final frame = _buildFrame(address, bytes4);
    final ok = await _sendBytes(frame.toList());
    if (!ok) {
      debugPrint('[ADAU1701] writeParameter failed'
          ' (addr=0x${address.toRadixString(16)})');
    }
  }

  static List<int> _buildFrame(int addr, List<int> word0bytes) {
    final frame = List<int>.filled(27, 0); // ICP5 MCU가 기대하는 고정 크기
    frame[0] = 0xAA;
    frame[1] = (addr >> 8) & 0xFF;
    frame[2] = addr & 0xFF;
    frame[3] = word0bytes[0];
    frame[4] = word0bytes[1];
    frame[5] = word0bytes[2];
    frame[6] = word0bytes[3];
    // frame[7..22]: word1~4 = 0 (List.filled 초기화값)
    int chk = 0;
    for (int i = 0; i < 23; i++) {
      chk ^= frame[i];
    }
    frame[23] = chk;
    frame[24] = 0x55;
    // frame[25..26]: 패딩 0
    return frame;
  }

  @override
  Future<List<int>?> readParameter(int address) async => null;

  @override
  Future<bool> detectDevice() async => true;

  @override
  void dispose() {}
}
