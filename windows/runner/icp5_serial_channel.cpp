#include "icp5_serial_channel.h"

#include <windows.h>
#include <initguid.h>
#include <setupapi.h>
#include <devpkey.h>
#include <cfgmgr32.h>
#include <algorithm>
#include <iterator>
#include <string>
#include <vector>

// Official Ports device setup-class GUID. Keep this local definition instead
// of importing devguid.h, which declares every Windows device-class GUID and
// is sensitive to GUID header ordering in some Windows SDK versions.
#ifndef TUNAI_GUID_DEVCLASS_PORTS_DEFINED
#define TUNAI_GUID_DEVCLASS_PORTS_DEFINED
DEFINE_GUID(GUID_DEVCLASS_PORTS,
            0x4d36e978, 0xe325, 0x11ce,
            0xbf, 0xc1, 0x08, 0x00, 0x2b, 0xe1, 0x03, 0x18);
#endif

namespace {
std::string WideToUtf8(const wchar_t* value) {
  if (!value || !*value) return "";
  const int length = WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0,
                                         nullptr, nullptr);
  if (length <= 1) return "";
  std::string result(static_cast<size_t>(length), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value, -1, result.data(), length, nullptr,
                      nullptr);
  result.pop_back();
  return result;
}

std::wstring DeviceProperty(HDEVINFO devices, SP_DEVINFO_DATA* device,
                            DWORD property) {
  wchar_t buffer[1024]{};
  if (!SetupDiGetDeviceRegistryPropertyW(
          devices, device, property, nullptr,
          reinterpret_cast<PBYTE>(buffer), sizeof(buffer), nullptr)) {
    return L"";
  }
  return buffer;
}

std::wstring PortName(HDEVINFO devices, SP_DEVINFO_DATA* device) {
  HKEY key = SetupDiOpenDevRegKey(devices, device, DICS_FLAG_GLOBAL, 0,
                                 DIREG_DEV, KEY_READ);
  if (key == INVALID_HANDLE_VALUE) return L"";
  wchar_t buffer[256]{};
  DWORD type = 0;
  DWORD bytes = sizeof(buffer);
  const LONG status = RegQueryValueExW(
      key, L"PortName", nullptr, &type, reinterpret_cast<LPBYTE>(buffer),
      &bytes);
  RegCloseKey(key);
  return status == ERROR_SUCCESS && type == REG_SZ ? buffer : L"";
}
}  // namespace

void Icp5SerialChannel::Register(flutter::BinaryMessenger* messenger) {
  new Icp5SerialChannel(messenger);  // MethodChannel handler owns lifetime.
}

Icp5SerialChannel::Icp5SerialChannel(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "tunai/icp5_serial",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethod(call, std::move(result));
      });
}

void Icp5SerialChannel::HandleMethod(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "list_ports") {
    ListPorts(std::move(result));
    return;
  }
  result->NotImplemented();
}

void Icp5SerialChannel::ListPorts(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  HDEVINFO devices = SetupDiGetClassDevsW(
      &GUID_DEVCLASS_PORTS, nullptr, nullptr, DIGCF_PRESENT);
  if (devices == INVALID_HANDLE_VALUE) {
    result->Error("setupapi_ports_failed",
                  "SetupAPI could not enumerate the Ports device class.");
    return;
  }

  flutter::EncodableList ports;
  SP_DEVINFO_DATA device{};
  device.cbSize = sizeof(device);
  for (DWORD index = 0; SetupDiEnumDeviceInfo(devices, index, &device);
       ++index) {
    wchar_t instance_buffer[1024]{};
    SetupDiGetDeviceInstanceIdW(devices, &device, instance_buffer,
                                static_cast<DWORD>(std::size(instance_buffer)),
                                nullptr);
    const std::wstring friendly =
        DeviceProperty(devices, &device, SPDRP_FRIENDLYNAME);
    const std::wstring description =
        DeviceProperty(devices, &device, SPDRP_DEVICEDESC);
    const std::wstring port_name = PortName(devices, &device);

    flutter::EncodableMap entry;
    entry[flutter::EncodableValue("portName")] =
        flutter::EncodableValue(WideToUtf8(port_name.c_str()));
    entry[flutter::EncodableValue("friendlyName")] =
        flutter::EncodableValue(WideToUtf8(friendly.c_str()));
    entry[flutter::EncodableValue("instanceId")] =
        flutter::EncodableValue(WideToUtf8(instance_buffer));
    entry[flutter::EncodableValue("description")] =
        flutter::EncodableValue(WideToUtf8(description.c_str()));
    entry[flutter::EncodableValue("source")] =
        flutter::EncodableValue("Windows SetupAPI Ports class");
    ports.push_back(flutter::EncodableValue(entry));
  }
  SetupDiDestroyDeviceInfoList(devices);

  flutter::EncodableMap response;
  response[flutter::EncodableValue("source")] =
      flutter::EncodableValue("Windows SetupAPI Ports class");
  response[flutter::EncodableValue("candidateCount")] =
      flutter::EncodableValue(static_cast<int>(ports.size()));
  response[flutter::EncodableValue("ports")] = flutter::EncodableValue(ports);
  result->Success(flutter::EncodableValue(response));
}
