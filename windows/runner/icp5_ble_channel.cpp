#include "icp5_ble_channel.h"

#include <windows.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>
#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>
#include <winrt/Windows.Devices.Radios.h>
#include <winrt/Windows.Storage.Streams.h>

#include <flutter/event_stream_handler_functions.h>

#include <chrono>
#include <map>
#include <mutex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

using namespace winrt;
using namespace winrt::Windows::Foundation;
using namespace winrt::Windows::Devices::Bluetooth;
using namespace winrt::Windows::Devices::Bluetooth::Advertisement;
using namespace winrt::Windows::Devices::Bluetooth::GenericAttributeProfile;
using namespace winrt::Windows::Devices::Radios;
using namespace winrt::Windows::Storage::Streams;

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using MethodResultPtr =
    std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>;

void Log(const char* tag) {
  OutputDebugStringA((std::string("[ICP5 windows BLE lifecycle] ") + tag + "\n")
                         .c_str());
}

void LogMsg(const std::string& message) {
  OutputDebugStringA(
      (std::string("[ICP5 windows BLE lifecycle] ") + message + "\n").c_str());
}

std::string ToUtf8(winrt::hstring const& value) {
  return winrt::to_string(value);
}

std::string CommStatusStr(GattCommunicationStatus s) {
  switch (s) {
    case GattCommunicationStatus::Success:
      return "Success";
    case GattCommunicationStatus::Unreachable:
      return "Unreachable";
    case GattCommunicationStatus::ProtocolError:
      return "ProtocolError";
    case GattCommunicationStatus::AccessDenied:
      return "AccessDenied";
    default:
      return "Unknown";
  }
}

std::string ConnStatusStr(BluetoothConnectionStatus s) {
  return s == BluetoothConnectionStatus::Connected ? "Connected"
                                                   : "Disconnected";
}

std::string AddrTypeStr(BluetoothAddressType t) {
  switch (t) {
    case BluetoothAddressType::Public:
      return "Public";
    case BluetoothAddressType::Random:
      return "Random";
    default:
      return "Unspecified";
  }
}

// Bluetooth address type captured per device during the advertisement scan, so
// connect() uses the SAME type the device advertised (many peripherals — incl.
// the WONDOM ICP5 — use Random; connecting as Public yields zero services).
std::mutex g_addr_mutex;
std::map<std::string, BluetoothAddressType> g_addr_types;

// Builds a 128-bit GATT UUID from a Dart-supplied short ("fff0") or full
// ("0000fff0-0000-1000-8000-00805f9b34fb") uuid string.
winrt::guid ToGuid(const std::string& uuid) {
  if (uuid.size() == 4) {
    const uint16_t shortId =
        static_cast<uint16_t>(std::stoul(uuid, nullptr, 16));
    return BluetoothUuidHelper::FromShortId(shortId);
  }
  return winrt::guid(winrt::to_hstring(uuid));
}

bool HasProp(GattCharacteristicProperties props,
             GattCharacteristicProperties flag) {
  return (props & flag) != GattCharacteristicProperties::None;
}

std::string B(bool v) { return v ? "1" : "0"; }

// Low 16 bits of Data1 = the SIG 16-bit short UUID (e.g. 0xFFF2) for standard
// base-UUID characteristics; rendered as 4 hex chars for logging.
std::string Short16(winrt::guid const& g) {
  wchar_t buf[8]{};
  swprintf_s(buf, L"%04hx", static_cast<uint16_t>(g.Data1 & 0xFFFF));
  return winrt::to_string(buf);
}

std::string GuidToShort(winrt::guid const& g) {
  // Render lower-case canonical 128-bit form; the Dart side matches both short
  // and full, so the full form is always safe.
  wchar_t buffer[64]{};
  swprintf_s(buffer, L"%08lx-%04hx-%04hx-%02hhx%02hhx-%02hhx%02hhx%02hhx%02hhx%02hhx%02hhx",
             g.Data1, g.Data2, g.Data3, g.Data4[0], g.Data4[1], g.Data4[2],
             g.Data4[3], g.Data4[4], g.Data4[5], g.Data4[6], g.Data4[7]);
  return ToUtf8(winrt::hstring(buffer));
}

// ── Session state ─────────────────────────────────────────────────────────────

struct BleSession {
  BluetoothLEDevice device{nullptr};
  GattSession gattSession{nullptr};    // keeps the link alive (MaintainConnection)
  GattDeviceService service{nullptr};
  GattCharacteristic tx{nullptr};      // FFF2 write
  GattCharacteristic rx{nullptr};      // FFF1 notify
  winrt::event_token rxToken{};
  bool rxSubscribed{false};
};

std::mutex g_mutex;
std::map<std::string, BleSession> g_sessions;  // keyed by deviceId (BT address)
std::mutex g_sink_mutex;
std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> g_notify_sink;

void EmitNotify(const std::string& deviceId, const std::vector<uint8_t>& data) {
  std::lock_guard<std::mutex> lock(g_sink_mutex);
  if (!g_notify_sink) return;
  EncodableList bytes;
  bytes.reserve(data.size());
  for (uint8_t b : data) bytes.push_back(EncodableValue(static_cast<int>(b)));
  g_notify_sink->Success(EncodableValue(bytes));
}

// ── Helpers to read call args ────────────────────────────────────────────────

const EncodableMap* Args(
    const flutter::MethodCall<flutter::EncodableValue>& call) {
  return std::get_if<EncodableMap>(call.arguments());
}

std::string GetString(const EncodableMap& m, const char* key,
                      const std::string& fallback = "") {
  auto it = m.find(EncodableValue(std::string(key)));
  if (it == m.end()) return fallback;
  if (auto s = std::get_if<std::string>(&it->second)) return *s;
  return fallback;
}

int GetInt(const EncodableMap& m, const char* key, int fallback) {
  auto it = m.find(EncodableValue(std::string(key)));
  if (it == m.end()) return fallback;
  if (auto v = std::get_if<int>(&it->second)) return *v;
  if (auto v = std::get_if<int64_t>(&it->second))
    return static_cast<int>(*v);
  return fallback;
}

std::vector<uint8_t> GetBytes(const EncodableMap& m, const char* key) {
  std::vector<uint8_t> out;
  auto it = m.find(EncodableValue(std::string(key)));
  if (it == m.end()) return out;
  if (auto list = std::get_if<EncodableList>(&it->second)) {
    for (const auto& e : *list) {
      if (auto v = std::get_if<int>(&e)) out.push_back(static_cast<uint8_t>(*v));
    }
  } else if (auto bytes = std::get_if<std::vector<uint8_t>>(&it->second)) {
    out = *bytes;
  }
  return out;
}

// ── WinRT async operations (fire-and-forget, reply on the captured apartment) ──

// NOTE on coroutine exception handling: C++20 forbids `co_await` inside a catch
// block (C2304). Every handler below captures success/error state inside the
// try/catch, then performs the single `co_await ui;` (apartment dispatch) and
// the result reply AFTER the try/catch. Error conditions inside the try throw
// so they land in the same catch — no `co_await` ever sits in a catch.

winrt::fire_and_forget AdapterOn(MethodResultPtr result) {
  apartment_context ui;
  bool on = false;
  bool has_error = false;
  std::string err_msg;
  try {
    auto radio = co_await BluetoothAdapter::GetDefaultAsync();
    if (radio) {
      auto r = co_await radio.GetRadioAsync();
      on = r && r.State() == RadioState::On;
    }
  } catch (const winrt::hresult_error& e) {
    has_error = true;
    err_msg = ToUtf8(e.message());
  } catch (const std::exception& e) {
    has_error = true;
    err_msg = e.what();
  }
  co_await ui;
  if (has_error) {
    result->Error("adapter", err_msg);
  } else {
    result->Success(EncodableValue(on));
  }
}

winrt::fire_and_forget Scan(int timeoutMs, MethodResultPtr result) {
  apartment_context ui;
  EncodableList devices;
  bool has_error = false;
  std::string err_msg;
  Log("SCAN_START");
  try {
    struct Seen {
      std::string name;
      int rssi{0};
      bool connectable{false};
    };
    auto found = std::make_shared<std::map<std::string, Seen>>();
    auto foundMutex = std::make_shared<std::mutex>();

    BluetoothLEAdvertisementWatcher watcher;
    watcher.ScanningMode(BluetoothLEScanningMode::Active);
    auto receivedToken = watcher.Received([found, foundMutex](
                         BluetoothLEAdvertisementWatcher const&,
                         BluetoothLEAdvertisementReceivedEventArgs const& args) {
      const uint64_t address = args.BluetoothAddress();
      const std::string id = std::to_string(address);
      const auto type = args.AdvertisementType();
      const bool connectable =
          type == BluetoothLEAdvertisementType::ConnectableUndirected ||
          type == BluetoothLEAdvertisementType::ConnectableDirected;
      // Remember the advertised address type so connect() uses the right one.
      {
        std::lock_guard<std::mutex> alock(g_addr_mutex);
        g_addr_types[id] = args.BluetoothAddressType();
      }
      std::string name = ToUtf8(args.Advertisement().LocalName());
      std::lock_guard<std::mutex> lock(*foundMutex);
      auto& seen = (*found)[id];
      seen.rssi = args.RawSignalStrengthInDBm();
      if (!name.empty()) seen.name = name;
      if (connectable) seen.connectable = true;
    });

    watcher.Start();
    co_await winrt::resume_after(std::chrono::milliseconds(timeoutMs));
    // Always stop the watcher and drop the Received handler so the scan ends
    // deterministically within timeoutMs.
    watcher.Stop();
    watcher.Received(receivedToken);
    Log("SCAN_STOP");

    {
      std::lock_guard<std::mutex> lock(*foundMutex);
      for (const auto& [id, seen] : *found) {
        // Stable device map schema consumed by the Dart parser:
        //   deviceId:string, id:string (alias), name:string, advertisedName:string,
        //   rssi:int, connectable:bool
        EncodableMap d;
        d[EncodableValue("deviceId")] = EncodableValue(id);
        d[EncodableValue("id")] = EncodableValue(id);  // back-compat alias
        d[EncodableValue("name")] = EncodableValue(seen.name);
        d[EncodableValue("advertisedName")] = EncodableValue(seen.name);
        d[EncodableValue("rssi")] = EncodableValue(seen.rssi);
        d[EncodableValue("connectable")] = EncodableValue(seen.connectable);
        devices.push_back(EncodableValue(d));
        LogMsg("DEVICE_FOUND deviceId=" + id + " name=" + seen.name +
               " advertisedName=" + seen.name +
               " rssi=" + std::to_string(seen.rssi) +
               " connectable=" + (seen.connectable ? "true" : "false"));
      }
    }
    LogMsg("SCAN_RESULT count=" + std::to_string(devices.size()));
  } catch (const winrt::hresult_error& e) {
    has_error = true;
    err_msg = ToUtf8(e.message());
  } catch (const std::exception& e) {
    has_error = true;
    err_msg = e.what();
  }
  co_await ui;
  // Reply exactly once — success (possibly empty) or a precise error.
  if (has_error) {
    LogMsg("SCAN_ERROR " + err_msg);
    result->Error("scan", err_msg);
  } else {
    result->Success(EncodableValue(devices));
  }
}

winrt::fire_and_forget Connect(std::string deviceId, int /*timeoutMs*/,
                               MethodResultPtr result) {
  apartment_context ui;
  EncodableValue payload;
  bool has_error = false;
  std::string err_msg;
  Log("CONNECT_START");
  try {
    const uint64_t address = std::stoull(deviceId);
    LogMsg("CONNECT deviceId=" + deviceId + " address=" +
           std::to_string(address));

    // Use the advertised address type first (Random for most peripherals incl.
    // WONDOM ICP5); fall back to the other type if creation/discovery fails.
    std::vector<BluetoothAddressType> typesToTry;
    {
      std::lock_guard<std::mutex> alock(g_addr_mutex);
      auto it = g_addr_types.find(deviceId);
      if (it != g_addr_types.end()) typesToTry.push_back(it->second);
    }
    typesToTry.push_back(BluetoothAddressType::Random);
    typesToTry.push_back(BluetoothAddressType::Public);

    BluetoothLEDevice device{nullptr};
    for (auto t : typesToTry) {
      device =
          co_await BluetoothLEDevice::FromBluetoothAddressAsync(address, t);
      if (device) {
        LogMsg("DEVICE_CREATED addrType=" + AddrTypeStr(t));
        break;
      }
      LogMsg("DEVICE_CREATE_FAILED addrType=" + AddrTypeStr(t));
    }
    if (!device) {
      throw std::runtime_error("BluetoothLEDevice creation failed for " +
                               deviceId + " (address unreachable/unknown type)");
    }
    LogMsg("DEVICE Name=" + ToUtf8(device.Name()) +
           " Id=" + ToUtf8(device.DeviceId()));
    LogMsg("CONN_STATUS " + ConnStatusStr(device.ConnectionStatus()));

    // Keep the link up so service discovery has a live connection.
    GattSession gattSession{nullptr};
    try {
      gattSession =
          co_await GattSession::FromDeviceIdAsync(device.BluetoothDeviceId());
      gattSession.MaintainConnection(true);
      LogMsg(std::string("GATT_SESSION canMaintain=") +
             (gattSession.CanMaintainConnection() ? "true" : "false"));
    } catch (...) {
      LogMsg("GATT_SESSION creation failed (continuing without it)");
    }

    // Wait briefly for readiness, then discover (Uncached, a few attempts).
    GattDeviceServicesResult servicesResult{nullptr};
    for (int attempt = 0; attempt < 5; ++attempt) {
      co_await winrt::resume_after(std::chrono::milliseconds(300));
      servicesResult =
          co_await device.GetGattServicesAsync(BluetoothCacheMode::Uncached);
      const uint32_t count =
          servicesResult.Status() == GattCommunicationStatus::Success
              ? servicesResult.Services().Size()
              : 0;
      LogMsg("GET_SERVICES attempt=" + std::to_string(attempt) + " status=" +
             CommStatusStr(servicesResult.Status()) +
             " count=" + std::to_string(count));
      if (servicesResult.Status() == GattCommunicationStatus::Success &&
          count > 0) {
        break;
      }
    }
    // Cached fallback if uncached never succeeded.
    if (servicesResult.Status() != GattCommunicationStatus::Success) {
      auto cached =
          co_await device.GetGattServicesAsync(BluetoothCacheMode::Cached);
      LogMsg("GET_SERVICES cached status=" + CommStatusStr(cached.Status()));
      if (cached.Status() == GattCommunicationStatus::Success) {
        servicesResult = cached;
      }
    }
    if (servicesResult.Status() != GattCommunicationStatus::Success) {
      // Distinguish the failure mode for the caller/logs.
      throw std::runtime_error("GATT service discovery failed: " +
                               CommStatusStr(servicesResult.Status()));
    }

    BleSession session;
    session.device = device;
    session.gattSession = gattSession;

    EncodableList serviceUuids;
    EncodableList characteristics;
    const winrt::guid fff0 = ToGuid("fff0");
    const winrt::guid fff2 = ToGuid("fff2");
    const winrt::guid fff1 = ToGuid("fff1");
    for (auto const& service : servicesResult.Services()) {
      const std::string svcUuid = GuidToShort(service.Uuid());
      const bool isFff0 = service.Uuid() == fff0;
      serviceUuids.push_back(EncodableValue(svcUuid));
      LogMsg(std::string("SERVICE uuid=") + svcUuid + (isFff0 ? " (FFF0)" : ""));

      // Uncached first, then Cached fallback if it failed or came back empty.
      auto charsResult =
          co_await service.GetCharacteristicsAsync(BluetoothCacheMode::Uncached);
      uint32_t charCount =
          charsResult.Status() == GattCommunicationStatus::Success
              ? charsResult.Characteristics().Size()
              : 0;
      LogMsg("  chars uncached status=" + CommStatusStr(charsResult.Status()) +
             " count=" + std::to_string(charCount));
      if (charsResult.Status() != GattCommunicationStatus::Success ||
          charCount == 0) {
        auto cached =
            co_await service.GetCharacteristicsAsync(BluetoothCacheMode::Cached);
        const uint32_t cachedCount =
            cached.Status() == GattCommunicationStatus::Success
                ? cached.Characteristics().Size()
                : 0;
        LogMsg("  chars cached status=" + CommStatusStr(cached.Status()) +
               " count=" + std::to_string(cachedCount));
        if (cached.Status() == GattCommunicationStatus::Success &&
            cachedCount > 0) {
          charsResult = cached;
        }
      }
      if (charsResult.Status() != GattCommunicationStatus::Success) {
        if (isFff0) LogMsg("  FFF0 characteristic list empty/unreadable");
        continue;
      }

      bool sawFff2 = false;
      bool sawFff1 = false;
      for (auto const& ch : charsResult.Characteristics()) {
        const std::string chUuid = GuidToShort(ch.Uuid());
        const auto props = ch.CharacteristicProperties();
        const bool hasRead = HasProp(props, GattCharacteristicProperties::Read);
        const bool hasWrite = HasProp(props, GattCharacteristicProperties::Write);
        const bool hasWwr =
            HasProp(props, GattCharacteristicProperties::WriteWithoutResponse);
        const bool hasNotify =
            HasProp(props, GattCharacteristicProperties::Notify);
        const bool hasIndicate =
            HasProp(props, GattCharacteristicProperties::Indicate);
        // Accept FFF2 on Write OR WriteWithoutResponse; FFF1 on Notify OR Indicate.
        const bool canWrite = hasWrite || hasWwr;
        const bool canNotify = hasNotify || hasIndicate;

        EncodableMap c;
        c[EncodableValue("service")] = EncodableValue(svcUuid);
        c[EncodableValue("uuid")] = EncodableValue(chUuid);
        c[EncodableValue("canWrite")] = EncodableValue(canWrite);
        c[EncodableValue("canNotify")] = EncodableValue(canNotify);
        characteristics.push_back(EncodableValue(c));

        if (isFff0) {
          LogMsg("  CHAR full=" + chUuid + " short=" + Short16(ch.Uuid()) +
                 " props=" + std::to_string(static_cast<int>(props)) +
                 " R=" + B(hasRead) + " W=" + B(hasWrite) + " WWR=" + B(hasWwr) +
                 " N=" + B(hasNotify) + " I=" + B(hasIndicate));
          session.service = service;
          if (ch.Uuid() == fff2) {
            sawFff2 = true;
            if (canWrite) {
              session.tx = ch;
            } else {
              LogMsg("  FFF2 present but has neither Write nor WriteWithoutResponse");
            }
          }
          if (ch.Uuid() == fff1) {
            sawFff1 = true;
            if (canNotify) {
              session.rx = ch;
            } else {
              LogMsg("  FFF1 present but has neither Notify nor Indicate");
            }
          }
        }
      }
      if (isFff0) {
        LogMsg(std::string("  FFF2 match=") +
               (session.tx ? "accepted"
                           : (sawFff2 ? "rejected(no-write)" : "not-found")));
        LogMsg(std::string("  FFF1 match=") +
               (session.rx ? "accepted"
                           : (sawFff1 ? "rejected(no-notify)" : "not-found")));
        Log("SERVICE_FOUND FFF0");
      }
    }
    LogMsg("SERVICE_TOTAL count=" + std::to_string(serviceUuids.size()));

    {
      std::lock_guard<std::mutex> lock(g_mutex);
      g_sessions[deviceId] = session;
    }

    EncodableMap profile;
    profile[EncodableValue("services")] = EncodableValue(serviceUuids);
    profile[EncodableValue("characteristics")] =
        EncodableValue(characteristics);
    payload = EncodableValue(profile);
  } catch (const winrt::hresult_error& e) {
    has_error = true;
    err_msg = ToUtf8(e.message());
  } catch (const std::exception& e) {
    has_error = true;
    err_msg = e.what();
  }
  co_await ui;
  if (has_error) {
    result->Error("connect", err_msg);
  } else {
    result->Success(payload);
  }
}

winrt::fire_and_forget EnableNotify(std::string deviceId, MethodResultPtr result) {
  apartment_context ui;
  bool has_error = false;
  std::string err_msg;
  try {
    GattCharacteristic rx{nullptr};
    {
      std::lock_guard<std::mutex> lock(g_mutex);
      auto it = g_sessions.find(deviceId);
      if (it == g_sessions.end() || !it->second.rx) {
        throw std::runtime_error("No RX (FFF1) characteristic for " + deviceId);
      }
      rx = it->second.rx;
    }

    // Use Notify when supported, otherwise Indicate (req 7).
    const auto rxProps = rx.CharacteristicProperties();
    const auto cccd =
        HasProp(rxProps, GattCharacteristicProperties::Notify)
            ? GattClientCharacteristicConfigurationDescriptorValue::Notify
            : GattClientCharacteristicConfigurationDescriptorValue::Indicate;
    auto status =
        co_await rx.WriteClientCharacteristicConfigurationDescriptorAsync(cccd);
    if (status != GattCommunicationStatus::Success) {
      throw std::runtime_error("Failed to enable notifications on FFF1.");
    }

    auto token = rx.ValueChanged(
        [deviceId](GattCharacteristic const&,
                   GattValueChangedEventArgs const& args) {
          auto reader = DataReader::FromBuffer(args.CharacteristicValue());
          std::vector<uint8_t> data(reader.UnconsumedBufferLength());
          reader.ReadBytes(data);
          Log("RX_BYTES");
          EmitNotify(deviceId, data);
        });
    {
      std::lock_guard<std::mutex> lock(g_mutex);
      auto it = g_sessions.find(deviceId);
      if (it != g_sessions.end()) {
        it->second.rxToken = token;
        it->second.rxSubscribed = true;
      }
    }
    Log("RX_NOTIFY_ENABLED");
  } catch (const winrt::hresult_error& e) {
    has_error = true;
    err_msg = ToUtf8(e.message());
  } catch (const std::exception& e) {
    has_error = true;
    err_msg = e.what();
  }
  co_await ui;
  if (has_error) {
    result->Error("notify", err_msg);
  } else {
    result->Success();
  }
}

winrt::fire_and_forget Write(std::string deviceId, std::vector<uint8_t> data,
                             MethodResultPtr result) {
  apartment_context ui;
  bool has_error = false;
  std::string err_msg;
  try {
    GattCharacteristic tx{nullptr};
    {
      std::lock_guard<std::mutex> lock(g_mutex);
      auto it = g_sessions.find(deviceId);
      if (it == g_sessions.end() || !it->second.tx) {
        throw std::runtime_error("No TX (FFF2) characteristic for " + deviceId);
      }
      tx = it->second.tx;
    }

    DataWriter writer;
    writer.WriteBytes(array_view<const uint8_t>(data.data(),
                                                data.data() + data.size()));
    const auto props = tx.CharacteristicProperties();
    const auto option =
        (props & GattCharacteristicProperties::Write) !=
                GattCharacteristicProperties::None
            ? GattWriteOption::WriteWithResponse
            : GattWriteOption::WriteWithoutResponse;
    Log("TX_WRITE");
    auto status =
        co_await tx.WriteValueAsync(writer.DetachBuffer(), option);
    if (status != GattCommunicationStatus::Success) {
      throw std::runtime_error("GATT write did not succeed.");
    }
  } catch (const winrt::hresult_error& e) {
    has_error = true;
    err_msg = ToUtf8(e.message());
  } catch (const std::exception& e) {
    has_error = true;
    err_msg = e.what();
  }
  co_await ui;
  if (has_error) {
    result->Error("write", err_msg);
  } else {
    result->Success(EncodableValue(static_cast<int>(data.size())));
  }
}

void Disconnect(const std::string& deviceId) {
  Log("DISCONNECT");
  std::lock_guard<std::mutex> lock(g_mutex);
  auto it = g_sessions.find(deviceId);
  if (it == g_sessions.end()) return;
  BleSession& s = it->second;
  if (s.rxSubscribed && s.rx) {
    try {
      s.rx.ValueChanged(s.rxToken);
    } catch (...) {
    }
  }
  if (s.service) s.service.Close();
  if (s.gattSession) {
    try {
      s.gattSession.MaintainConnection(false);
      s.gattSession.Close();
    } catch (...) {
    }
  }
  if (s.device) s.device.Close();
  g_sessions.erase(it);
}

}  // namespace

// ── Channel wiring ────────────────────────────────────────────────────────────

void Icp5BleChannel::Register(flutter::BinaryMessenger* messenger) {
  new Icp5BleChannel(messenger);  // Handler owns its own lifetime.
}

Icp5BleChannel::Icp5BleChannel(flutter::BinaryMessenger* messenger) {
  method_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "tunai/icp5_ble",
          &flutter::StandardMethodCodec::GetInstance());
  method_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethod(call, std::move(result));
      });

  event_channel_ =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          messenger, "tunai/icp5_ble/notify",
          &flutter::StandardMethodCodec::GetInstance());
  event_channel_->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [](const flutter::EncodableValue*,
             std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& sink)
              -> std::unique_ptr<
                  flutter::StreamHandlerError<flutter::EncodableValue>> {
            std::lock_guard<std::mutex> lock(g_sink_mutex);
            g_notify_sink = std::move(sink);
            return nullptr;
          },
          [](const flutter::EncodableValue*)
              -> std::unique_ptr<
                  flutter::StreamHandlerError<flutter::EncodableValue>> {
            std::lock_guard<std::mutex> lock(g_sink_mutex);
            g_notify_sink.reset();
            return nullptr;
          }));
}

void Icp5BleChannel::HandleMethod(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  MethodResultPtr shared = std::move(result);
  const std::string& method = call.method_name();
  const EncodableMap* args = Args(call);

  if (method == "adapterOn") {
    AdapterOn(shared);
  } else if (method == "scan") {
    const int timeoutMs = args ? GetInt(*args, "timeoutMs", 10000) : 10000;
    Scan(timeoutMs, shared);
  } else if (method == "connect") {
    if (!args) {
      shared->Error("connect", "Missing arguments.");
      return;
    }
    Connect(GetString(*args, "deviceId"), GetInt(*args, "timeoutMs", 10000),
            shared);
  } else if (method == "enableNotify") {
    if (!args) {
      shared->Error("enableNotify", "Missing arguments.");
      return;
    }
    EnableNotify(GetString(*args, "deviceId"), shared);
  } else if (method == "write") {
    if (!args) {
      shared->Error("write", "Missing arguments.");
      return;
    }
    Write(GetString(*args, "deviceId"), GetBytes(*args, "data"), shared);
  } else if (method == "disconnect") {
    if (args) Disconnect(GetString(*args, "deviceId"));
    shared->Success();
  } else {
    shared->NotImplemented();
  }
}
