import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

/// Analog Devices USBi 프로그래머 — VID 0x0456.
///
/// **Windows 전용.** win32 패키지는 Windows DLL(setupapi.dll)을 FFI로 호출하므로
/// 다른 플랫폼에서 이 함수를 호출하면 안 된다 — 호출부(connect_controller.dart)가
/// 반드시 `Platform.isWindows`로 감싸야 한다.
///
/// **SPI 프로토콜은 여기서 다루지 않는다.** 이 파일은 SetupAPI로 장치가 꽂혀있는지
/// "감지"만 한다 — ADI USBi가 SigmaStudio와 주고받는 실제 커맨드셋은 공개 문서가
/// 없어(추측으로 구현하면 실기기에 잘못된 데이터를 보낼 위험이 있음) 이번 세션에서
/// 구현하지 않았다. HANDOFF.md 참고.
const int kAnalogDevicesVid = 0x0456;

class UsbiDeviceInfo {
  final String instanceId; // 예: "USB\VID_0456&PID_...\..."
  final String friendlyName;
  const UsbiDeviceInfo({required this.instanceId, required this.friendlyName});
}

/// SetupAPI로 VID 0x0456(Analog Devices) USB 장치를 전부 찾는다.
/// 실패해도 예외를 던지지 않고 빈 리스트를 반환한다(감지 실패가 앱을 죽이면 안 됨).
List<UsbiDeviceInfo> detectUsbiDevices() {
  final results = <UsbiDeviceInfo>[];
  var deviceInfoSet = -1;
  Pointer<Utf16> enumerator = nullptr;
  Pointer<SP_DEVINFO_DATA> devInfo = nullptr;

  try {
    enumerator = 'USB'.toNativeUtf16();
    deviceInfoSet = SetupDiGetClassDevs(
      nullptr,
      enumerator,
      0,
      DIGCF_PRESENT | DIGCF_ALLCLASSES,
    );
    if (deviceInfoSet == -1) return results;

    devInfo = calloc<SP_DEVINFO_DATA>();
    devInfo.ref.cbSize = sizeOf<SP_DEVINFO_DATA>();

    var index = 0;
    while (SetupDiEnumDeviceInfo(deviceInfoSet, index, devInfo) != 0) {
      index++;
      _readDeviceIfAnalogDevices(deviceInfoSet, devInfo, results);
    }
  } catch (_) {
    // Win32 API 실패 시 조용히 빈 리스트 반환
  } finally {
    if (devInfo != nullptr) calloc.free(devInfo);
    if (enumerator != nullptr) calloc.free(enumerator);
    if (deviceInfoSet != -1) SetupDiDestroyDeviceInfoList(deviceInfoSet);
  }
  return results;
}

void _readDeviceIfAnalogDevices(
  int deviceInfoSet,
  Pointer<SP_DEVINFO_DATA> devInfo,
  List<UsbiDeviceInfo> results,
) {
  const idBufChars = 512;
  final idBuf = calloc<Uint16>(idBufChars).cast<Utf16>();
  try {
    final ok = SetupDiGetDeviceInstanceId(
      deviceInfoSet, devInfo, idBuf, idBufChars, nullptr,
    );
    if (ok == 0) return;

    final instanceId = idBuf.toDartString();
    if (!instanceId.toUpperCase().contains('VID_0456')) return;

    results.add(UsbiDeviceInfo(
      instanceId: instanceId,
      friendlyName: _friendlyName(deviceInfoSet, devInfo) ?? instanceId,
    ));
  } finally {
    calloc.free(idBuf);
  }
}

String? findUsbiDevicePath(String instanceId, {String? interfaceGuid}) {
  if (interfaceGuid == null) return null;

  debugPrint('[USBi] findUsbiDevicePath() instanceId=$instanceId guid=$interfaceGuid');

  final guidPtr = GUIDFromString(interfaceGuid);
  var deviceInfoSet = -1;
  Pointer<SP_DEVICE_INTERFACE_DATA> ifaceData = nullptr;
  Pointer<SP_DEVICE_INTERFACE_DETAIL_DATA_> detailData = nullptr;

  try {
    debugPrint('[USBi] SetupDiGetClassDevs 호출...');
    deviceInfoSet = SetupDiGetClassDevs(
      guidPtr, nullptr, 0, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE,
    );
    debugPrint('[USBi] SetupDiGetClassDevs 결과: $deviceInfoSet  lastError=${GetLastError()}');
    if (deviceInfoSet == -1) {
      debugPrint('[USBi] deviceInfoSet == -1 → null 반환');
      return null;
    }

    ifaceData = calloc<SP_DEVICE_INTERFACE_DATA>();
    ifaceData.ref.cbSize = sizeOf<SP_DEVICE_INTERFACE_DATA>();

    var index = 0;
    debugPrint('[USBi] SetupDiEnumDeviceInterfaces 루프 시작...');
    while (SetupDiEnumDeviceInterfaces(deviceInfoSet, nullptr, guidPtr, index, ifaceData) != 0) {
      debugPrint('[USBi]   index=$index 인터페이스 발견');
      index++;

      final requiredSize = calloc<Uint32>();
      try {
        SetupDiGetDeviceInterfaceDetail(deviceInfoSet, ifaceData, nullptr, 0, requiredSize, nullptr);
        debugPrint('[USBi]   requiredSize=${requiredSize.value}  lastError=${GetLastError()}');
        if (requiredSize.value == 0) continue;

        detailData = calloc<Uint8>(requiredSize.value).cast<SP_DEVICE_INTERFACE_DETAIL_DATA_>();
        // SP_DEVICE_INTERFACE_DETAIL_DATA_W: DWORD(4) + WCHAR[1](2), 4-byte alignment → 8
        // sizeOf<IntPtr>() 를 쓰면 12 가 되어 error 1784 (ERROR_INVALID_USER_BUFFER) 발생
        detailData.ref.cbSize = 8;

        final devInfo = calloc<SP_DEVINFO_DATA>();
        devInfo.ref.cbSize = sizeOf<SP_DEVINFO_DATA>();
        try {
          final ok = SetupDiGetDeviceInterfaceDetail(
            deviceInfoSet, ifaceData, detailData, requiredSize.value, nullptr, devInfo,
          );
          debugPrint('[USBi]   GetDeviceInterfaceDetail ok=$ok  lastError=${GetLastError()}');
          if (ok == 0) continue;

          final idBuf = calloc<Uint16>(512).cast<Utf16>();
          try {
            final gotId = SetupDiGetDeviceInstanceId(deviceInfoSet, devInfo, idBuf, 512, nullptr);
            final foundId = gotId != 0 ? idBuf.toDartString() : '(실패)';
            debugPrint('[USBi]   foundInstanceId=$foundId  target=$instanceId  match=${foundId == instanceId}');
            if (gotId != 0 && foundId == instanceId) {
              final path = detailData.ref.DevicePath;
              debugPrint('[USBi]   devicePath=$path');
              return path;
            }
          } finally {
            calloc.free(idBuf);
          }
        } finally {
          calloc.free(devInfo);
        }
      } finally {
        calloc.free(requiredSize);
        if (detailData != nullptr) {
          calloc.free(detailData);
          detailData = nullptr;
        }
      }
    }
    debugPrint('[USBi] 루프 종료 — 총 $index개 인터페이스 열거, 일치 없음. lastError=${GetLastError()}');
  } catch (e, st) {
    debugPrint('[USBi] findUsbiDevicePath 예외: $e\n$st');
  } finally {
    if (ifaceData != nullptr) calloc.free(ifaceData);
    calloc.free(guidPtr);
    if (deviceInfoSet != -1) SetupDiDestroyDeviceInfoList(deviceInfoSet);
  }
  return null;
}

String? _friendlyName(int deviceInfoSet, Pointer<SP_DEVINFO_DATA> devInfo) {
  const bufBytes = 512;
  final buf = calloc<Uint8>(bufBytes);
  final regType = calloc<Uint32>();
  final required = calloc<Uint32>();
  try {
    var got = SetupDiGetDeviceRegistryProperty(
      deviceInfoSet, devInfo, SPDRP_FRIENDLYNAME, regType, buf, bufBytes, required,
    );
    if (got == 0) {
      // FRIENDLYNAME이 없는 장치도 있음 — DEVICEDESC로 재시도
      got = SetupDiGetDeviceRegistryProperty(
        deviceInfoSet, devInfo, SPDRP_DEVICEDESC, regType, buf, bufBytes, required,
      );
    }
    if (got == 0) return null;
    return buf.cast<Utf16>().toDartString();
  } finally {
    calloc.free(buf);
    calloc.free(regType);
    calloc.free(required);
  }
}
