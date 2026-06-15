import 'dsp_adapter.dart';

/// ADAU1452/1466 어댑터 — SigmaStudio 주소 맵 확정 후 구현 예정
///
/// 5.27 고정소수점 (ADAU1701의 5.23과 다름)
/// CS42448 코덱, 14in/18out
// ignore: unused_field
class Adau1452Adapter implements DspAdapter {
  // ignore: unused_field
  final RawWriteFn _send;

  Adau1452Adapter({required RawWriteFn send}) : _send = send;

  @override
  Future<void> writeBiquad(int channelIndex, int bandIndex, BiquadCoeffs coeffs) {
    // TODO: SigmaStudio PRAM 주소 맵 확정 후 구현
    throw UnimplementedError('ADAU1452 writeBiquad: address map TBD');
  }

  @override
  Future<void> writeCrossover(int channelIndex, CrossoverConfig config) {
    // TODO: SigmaStudio 크로스오버 셀 주소 확정 후 구현
    throw UnimplementedError('ADAU1452 writeCrossover: address map TBD');
  }

  @override
  Future<void> writeDelay(int channelIndex, double delayMs) {
    // TODO: SigmaStudio 딜레이 셀 주소 확정 후 구현
    throw UnimplementedError('ADAU1452 writeDelay: address map TBD');
  }

  @override
  Future<void> writeGain(int channelIndex, double gainDb) {
    // TODO: SigmaStudio 게인 셀 주소 확정 후 구현
    throw UnimplementedError('ADAU1452 writeGain: address map TBD');
  }

  @override
  Future<void> writeSubsonicFilter(int channelIndex, double freqHz) {
    // TODO: SigmaStudio 서브소닉 필터 셀 주소 확정 후 구현
    throw UnimplementedError('ADAU1452 writeSubsonicFilter: address map TBD');
  }
}
