import 'dart:math';
import 'dart:typed_data';

/// ADAU1466 USBi(VID 0x0456) 프로토콜 — GPT + Wireshark 캡처 역산으로 확정된
/// 패킷 구조. 플랫폼 독립적인 순수 바이트 조립 로직만 여기 둔다(win32/WinUSB
/// 의존성은 usbi_transport.dart로 분리) — 이 파일은 유닛 테스트도 가능하다.
///
/// **주의**: 아래 SafeLoad 3단계의 바이트 구조(주소/데이터 배치)는 실측 캡처
/// 예시와 100% 일치하도록 구현했지만, 각 단계가 "왜" 그 주소를 쓰는지의 의미
/// 해석(예: 1단계가 target+1 슬루 레지스터에 값을 쓰고 3단계 트리거가 target
/// 자체를 참조한다는 것)은 예시 하나에서 재구성한 것이다 — 실기기로 여러
/// 채널/값을 검증하기 전까지는 "구조가 맞다"이지 "의미까지 확정"은 아니다.
/// HANDOFF.md 참고.
class UsbiProtocol {
  /// USBi 컨트롤 전송 Setup 패킷(8바이트, WINUSB_SETUP_PACKET 레이아웃과 동일):
  /// [bmRequestType=0x40][bRequest=0xB2][wValue=0x0000 LE][wIndex=0x0101 LE][wLength LE]
  static Uint8List buildSetupPacket(int bodyLength) => Uint8List.fromList([
        0x40, 0xB2, 0x00, 0x00, 0x01, 0x01,
        bodyLength & 0xFF, (bodyLength >> 8) & 0xFF,
      ]);

  /// ACK 조회용 컨트롤 IN Setup 패킷 — 응답 1바이트가 0x01이어야 성공.
  static final Uint8List ackSetupPacket =
      Uint8List.fromList([0xC0, 0xB5, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00]);
  static const int ackExpectedByte = 0x01;

  /// 단일 워드 write body: [addr 2B BE] + [data 4B BE] = 6바이트.
  static Uint8List buildWriteBody(int addr, int data4B) => Uint8List.fromList([
        (addr >> 8) & 0xFF, addr & 0xFF,
        (data4B >> 24) & 0xFF, (data4B >> 16) & 0xFF,
        (data4B >> 8) & 0xFF, data4B & 0xFF,
      ]);

  /// 다중 워드 write body(트리거용): [addr 2B BE] + [word 4B BE]×N.
  static Uint8List buildMultiWordBody(int addr, List<int> words) {
    final bytes = <int>[(addr >> 8) & 0xFF, addr & 0xFF];
    for (final w in words) {
      bytes.addAll([
        (w >> 24) & 0xFF, (w >> 16) & 0xFF, (w >> 8) & 0xFF, w & 0xFF,
      ]);
    }
    return Uint8List.fromList(bytes);
  }

  // ── SafeLoad 레지스터 (실측 확정) ──────────────────────────────
  static const int safeloadData0Addr = 0x6000;
  static const int safeloadTriggerAddr = 0x6005;
  static const int safeloadUnityValue = 0x00800000; // Q5.23 unity(1.0) — 2단계 리셋용

  /// dB → Q8.24 고정소수점 변환: linear = 10^(dB/20), value = round(linear * 2^24).
  static int dbToFixed824(double dB) {
    final linear = pow(10, dB / 20).toDouble();
    return (linear * (1 << 24)).round();
  }

  /// 실시간 파라미터(볼륨 등) write용 SafeLoad 3단계 시퀀스를 (setup, body) 쌍
  /// 리스트로 만든다. [targetAddr]는 실제 파라미터 주소(예: CH0 Volume=545) —
  /// 1단계는 targetAddr+1(슬루 스테이징 추정 주소)에 값을 쓰고, 3단계 트리거가
  /// targetAddr 자체를 커밋 대상으로 지정한다(위 클래스 docstring의 주의 참고).
  static List<(Uint8List setup, Uint8List body)> buildSafeLoadWriteSequence(
    int targetAddr,
    int fixedPointValue,
  ) {
    final step1Body = buildWriteBody(targetAddr + 1, fixedPointValue);
    final step2Body = buildWriteBody(safeloadData0Addr, safeloadUnityValue);
    final step3Body = buildMultiWordBody(safeloadTriggerAddr, [targetAddr, 1, 0]);

    return [
      (buildSetupPacket(step1Body.length), step1Body),
      (buildSetupPacket(step2Body.length), step2Body),
      (buildSetupPacket(step3Body.length), step3Body),
    ];
  }

  /// 채널 게인(dB)을 SafeLoad 시퀀스로 변환 — [writeVolumeUsbi]가 사용.
  static List<(Uint8List setup, Uint8List body)> buildVolumeWriteSequence(
    int targetAddr,
    double gainDb,
  ) => buildSafeLoadWriteSequence(targetAddr, dbToFixed824(gainDb));
}

/// ADAU1466 Volume 레지스터(target) 주소 — 기존 확정값 그대로 재사용
/// (adau1466_adapter.dart와 동일, 이 파일은 어댑터를 건드리지 않고 참고만 함).
const List<int> kAdau1466VolumeAddresses = [545, 548, 551, 554, 557, 560];
