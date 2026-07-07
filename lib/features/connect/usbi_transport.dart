// win32 패키지 자체의 생성 코드와 동일하게, Win32/WinUSB 원본 API 이름을
// 그대로 유지하기 위해 네이밍 컨벤션 린트를 끈다.
// ignore_for_file: non_constant_identifier_names, camel_case_types

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'usbi_protocol.dart';

/// ADAU1466 USBi 실제 USB 전송 계층 — **Windows 전용, WinUSB 기반.**
///
/// win32 패키지에는 WinUSB 바인딩이 없어(확인함 — setupapi/kernel32만 제공)
/// 이 파일에서 `winusb.dll`을 직접 FFI로 바인딩했다. `WINUSB_SETUP_PACKET`
/// 구조체와 `WinUsb_Initialize`/`WinUsb_ControlTransfer`/`WinUsb_Free` 시그니처는
/// 마이크로소프트 공식 문서 기준(15년 이상 안정된 API — USBi 자체의 미공개
/// 커맨드셋과 달리 이 부분은 공개·표준 문서가 있음)으로 작성했지만, **실제
/// win32 패키지 소스처럼 대조해볼 참조가 없어 지난 SetupAPI 작업보다 검증
/// 수준이 낮다.** 실기기 연결 전 반드시 확인할 것(HANDOFF.md 참고).
///
/// **알려진 미해결 지점**: WinUSB 장치를 `CreateFile`로 열려면 그 장치가 등록한
/// 디바이스 인터페이스 GUID로 심볼릭 링크 경로(`\\?\...`)를 얻어야 하는데,
/// ADI USBi 드라이버가 등록하는 정확한 GUID를 확인할 방법이 없었다(추측해서
/// 넣으면 조용히 "장치 없음"으로 실패할 뿐 위험하진 않지만, 아무 근거 없이
/// 채워 넣는 것 자체가 이번 주 내내 지켜온 "검증 안 된 값은 넣지 않는다"
/// 원칙에 어긋나 비워뒀다). Windows 장치관리자에서 USBi 장치 속성 → 세부정보 →
/// "장치 인스턴스 경로"/"디바이스 인터페이스 클래스" 항목으로 확인 가능.
class UsbiTransport {
  /// ADI USBi WinUSB 디바이스 인터페이스 GUID.
  /// VID=0x0456 PID=0x7031, 드라이버=libwdi(winusb.sys), 장치관리자 Class GUID로 확인.
  static const String kUsbiDeviceInterfaceGuid =
      '{3DA527B1-7E23-4147-88CB-E5F953755CA2}';

  int _fileHandle = -1;
  int _winUsbHandle = 0;

  bool get isOpen => _winUsbHandle != 0;

  /// [devicePath]는 `CreateFile`에 바로 넘길 수 있는 심볼릭 링크 경로
  /// (`\\?\USB#VID_0456&PID_...#...#{GUID}` 형태) — SetupAPI로 얻어야 하며,
  /// 위 GUID가 비어있는 동안은 얻을 방법이 없다.
  bool open(String devicePath) {
    if (!Platform.isWindows) return false;
    final pathPtr = devicePath.toNativeUtf16();
    try {
      _fileHandle = CreateFile(
        pathPtr,
        GENERIC_READ | GENERIC_WRITE,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        nullptr,
        OPEN_EXISTING,
        FILE_FLAG_OVERLAPPED,
        0,
      );
      if (_fileHandle == -1 || _fileHandle == 0) {
        _fileHandle = -1;
        return false;
      }

      final handleOut = calloc<IntPtr>();
      try {
        final ok = WinUsb_Initialize(_fileHandle, handleOut);
        if (ok == 0) {
          CloseHandle(_fileHandle);
          _fileHandle = -1;
          return false;
        }
        _winUsbHandle = handleOut.value;
        return true;
      } finally {
        calloc.free(handleOut);
      }
    } catch (_) {
      close();
      return false;
    } finally {
      calloc.free(pathPtr);
    }
  }

  void close() {
    if (_winUsbHandle != 0) {
      WinUsb_Free(_winUsbHandle);
      _winUsbHandle = 0;
    }
    if (_fileHandle != -1) {
      CloseHandle(_fileHandle);
      _fileHandle = -1;
    }
  }

  /// Setup(8B) + Body를 컨트롤 전송으로 write. 성공 시 전송된 바이트 수 반환,
  /// 실패 시 -1.
  int controlWrite(Uint8List setup, Uint8List body) {
    if (!isOpen) return -1;
    final packetPtr = calloc<WINUSB_SETUP_PACKET>();
    final buf = calloc<Uint8>(body.length);
    final lenOut = calloc<Uint32>();
    try {
      _fillSetupPacket(packetPtr.ref, setup);
      buf.asTypedList(body.length).setAll(0, body);
      final ok = WinUsb_ControlTransfer(
        _winUsbHandle, packetPtr.ref, buf, body.length, lenOut, nullptr,
      );
      return ok == 0 ? -1 : lenOut.value;
    } finally {
      calloc.free(packetPtr);
      calloc.free(buf);
      calloc.free(lenOut);
    }
  }

  /// ACK 조회(컨트롤 IN, 1바이트) — [UsbiProtocol.ackExpectedByte]와 일치하면 true.
  bool readAck() {
    if (!isOpen) return false;
    final packetPtr = calloc<WINUSB_SETUP_PACKET>();
    final buf = calloc<Uint8>(1);
    final lenOut = calloc<Uint32>();
    try {
      _fillSetupPacket(packetPtr.ref, UsbiProtocol.ackSetupPacket);
      final ok = WinUsb_ControlTransfer(_winUsbHandle, packetPtr.ref, buf, 1, lenOut, nullptr);
      if (ok == 0 || lenOut.value < 1) return false;
      return buf[0] == UsbiProtocol.ackExpectedByte;
    } finally {
      calloc.free(packetPtr);
      calloc.free(buf);
      calloc.free(lenOut);
    }
  }

  /// (setup, body) 시퀀스를 순서대로 write하고 매번 ACK을 확인한다 — 하나라도
  /// 실패하면 즉시 중단하고 false 반환.
  bool sendSequence(List<(Uint8List setup, Uint8List body)> steps) {
    for (final (setup, body) in steps) {
      if (controlWrite(setup, body) < 0) return false;
      if (!readAck()) return false;
    }
    return true;
  }

  void _fillSetupPacket(WINUSB_SETUP_PACKET packet, Uint8List b) {
    packet.RequestType = b[0];
    packet.Request = b[1];
    packet.Value = b[2] | (b[3] << 8);
    packet.Index = b[4] | (b[5] << 8);
    packet.Length = b[6] | (b[7] << 8);
  }
}

/// 채널 Volume을 USBi SafeLoad 시퀀스로 write. 실기기 연결(open) 전까지는
/// 항상 false — 코드 구조만 준비된 상태(HANDOFF.md 참고).
bool writeVolumeUsbi(UsbiTransport transport, int targetAddr, double gainDb) {
  final steps = UsbiProtocol.buildVolumeWriteSequence(targetAddr, gainDb);
  return transport.sendSequence(steps);
}

/// 6채널(kAdau1466VolumeAddresses) 전체에 동일 게인을 적용해보는 테스트
/// 유틸리티 — 실기기 연결 전까지는 각 항목이 false로 채워진다. 채널별
/// 결과를 그대로 반환하므로 호출부(디버그 화면/콘솔)에서 성공/실패를
/// 채널 단위로 확인할 수 있다.
Map<int, bool> testWriteAllVolumeChannelsUsbi(UsbiTransport transport, double gainDb) {
  final results = <int, bool>{};
  for (final addr in kAdau1466VolumeAddresses) {
    results[addr] = writeVolumeUsbi(transport, addr, gainDb);
  }
  return results;
}

/// SafeLoad 경유 실시간 파라미터 write의 범용 진입점 — Volume 전용이 아니라
/// PEQ/Delay 등 다른 SafeLoad 대상 파라미터도 이 함수 하나로 확장 가능하도록
/// [targetAddr]/[fixedPointValue]를 직접 받는다. Volume은 dB→Q8.24 변환이
/// 필요해 [writeVolumeUsbi]를 별도로 두지만, 내부적으로는 이 함수와 동일한
/// [UsbiProtocol.buildSafeLoadWriteSequence] 경로를 탄다. PEQ(15밴드 biquad)나
/// Delay를 USBi로 옮길 때는 각 계수/샘플값을 해당 파라미터의 고정소수점
/// 포맷으로 변환한 뒤 이 함수를 호출하면 된다 — SafeLoad 3단계 시퀀스 자체는
/// 파라미터 종류와 무관하게 동일하다(실기기로 다른 값 종류를 검증하기 전까지는
/// usbi_protocol.dart 상단 주의사항대로 "구조는 같다"는 가정 수준).
bool writeSafeLoadParamUsbi(UsbiTransport transport, int targetAddr, int fixedPointValue) {
  final steps = UsbiProtocol.buildSafeLoadWriteSequence(targetAddr, fixedPointValue);
  return transport.sendSequence(steps);
}

// ── WinUSB FFI 바인딩 (win32 패키지에 없어 직접 작성) ──────────────────────

final class WINUSB_SETUP_PACKET extends Struct {
  @Uint8()
  external int RequestType;
  @Uint8()
  external int Request;
  @Uint16()
  external int Value;
  @Uint16()
  external int Index;
  @Uint16()
  external int Length;
}

final DynamicLibrary _winusb = DynamicLibrary.open('winusb.dll');

final int Function(int deviceHandle, Pointer<IntPtr> interfaceHandle) WinUsb_Initialize =
    _winusb
        .lookupFunction<
          Int32 Function(IntPtr deviceHandle, Pointer<IntPtr> interfaceHandle),
          int Function(int deviceHandle, Pointer<IntPtr> interfaceHandle)
        >('WinUsb_Initialize');

final int Function(int interfaceHandle) WinUsb_Free = _winusb
    .lookupFunction<
      Int32 Function(IntPtr interfaceHandle),
      int Function(int interfaceHandle)
    >('WinUsb_Free');

final int Function(
  int interfaceHandle,
  WINUSB_SETUP_PACKET setupPacket,
  Pointer<Uint8> buffer,
  int bufferLength,
  Pointer<Uint32> lengthTransferred,
  Pointer<Void> overlapped,
)
WinUsb_ControlTransfer = _winusb
    .lookupFunction<
      Int32 Function(
        IntPtr interfaceHandle,
        WINUSB_SETUP_PACKET setupPacket,
        Pointer<Uint8> buffer,
        Uint32 bufferLength,
        Pointer<Uint32> lengthTransferred,
        Pointer<Void> overlapped,
      ),
      int Function(
        int interfaceHandle,
        WINUSB_SETUP_PACKET setupPacket,
        Pointer<Uint8> buffer,
        int bufferLength,
        Pointer<Uint32> lengthTransferred,
        Pointer<Void> overlapped,
      )
    >('WinUsb_ControlTransfer');
