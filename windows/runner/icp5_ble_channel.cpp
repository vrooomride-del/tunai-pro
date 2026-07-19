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

#include <atomic>
#include <chrono>
#include <cstdio>
#include <map>
#include <memory>
#include <mutex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
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

// Emit to BOTH the Win32 debugger (DebugView / VS Output) AND stdout so the
// lines are visible in the `flutter run -d windows` terminal without a debugger.
void LogLine(const std::string& line) {
  const std::string full = "[ICP5 windows BLE lifecycle] " + line + "\n";
  OutputDebugStringA(full.c_str());
  fputs(full.c_str(), stdout);
  fflush(stdout);
}

void Log(const char* tag) { LogLine(tag); }

void LogMsg(const std::string& message) { LogLine(message); }

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

std::string SessionStatusStr(GattSessionStatus s) {
  return s == GattSessionStatus::Active ? "Active" : "Closed";
}

// BluetoothError enum -> string. GattSessionStatusChangedEventArgs.Error is a
// BluetoothError (Windows 10 1709+), so this is the most specific error info the
// SDK exposes for a session status transition.
std::string BtErrStr(BluetoothError e) {
  switch (e) {
    case BluetoothError::Success: return "Success";
    case BluetoothError::RadioNotAvailable: return "RadioNotAvailable";
    case BluetoothError::ResourceInUse: return "ResourceInUse";
    case BluetoothError::DeviceNotConnected: return "DeviceNotConnected";
    case BluetoothError::OtherError: return "OtherError";
    case BluetoothError::DisabledByPolicy: return "DisabledByPolicy";
    case BluetoothError::NotSupported: return "NotSupported";
    case BluetoothError::DisabledByUser: return "DisabledByUser";
    case BluetoothError::ConsentRequired: return "ConsentRequired";
    case BluetoothError::TransportNotSupported: return "TransportNotSupported";
    default: return "Unknown";
  }
}

// Monotonic milliseconds for correlating lifecycle timing across log lines.
long long NowMs() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}

// Render the ATT protocol error byte from a GATT result's ProtocolError ref.
std::string AttErr(winrt::Windows::Foundation::IReference<uint8_t> const& e) {
  if (e) {
    char buf[16]{};
    sprintf_s(buf, "0x%02X", static_cast<int>(e.Value()));
    return buf;
  }
  return "none";
}

// Event-driven bounded wait for the GattSession to reach Active. WinRT's
// BluetoothLEDevice.ConnectionStatus can read "Connected" while the ATT session
// is not usable yet (Uncached GATT returns Unreachable, only Cached metadata
// succeeds). The real signal that ATT operations will work is
// GattSession.SessionStatus == Active. We subscribe to SessionStatusChanged and
// wait on an OS event (no sleep-poll loop); the timeout exists only to fail
// explicitly, never as an arbitrary delay.
winrt::Windows::Foundation::IAsyncOperation<bool> WaitSessionActive(
    GattSession session, std::chrono::milliseconds timeout) {
  LogMsg(std::string("GATT_SESSION_INITIAL status=") +
         SessionStatusStr(session.SessionStatus()));
  if (session.SessionStatus() == GattSessionStatus::Active) {
    Log("GATT_SESSION_ACTIVE");
    co_return true;
  }
  Log("GATT_SESSION_WAIT_ACTIVE_BEGIN");
  winrt::handle signal{::CreateEventW(nullptr, TRUE, FALSE, nullptr)};
  const HANDLE signalHandle = signal.get();
  auto token = session.SessionStatusChanged(
      [signalHandle](GattSession const& s,
                     GattSessionStatusChangedEventArgs const&) {
        LogMsg(std::string("GATT_SESSION_STATUS_CHANGED status=") +
               SessionStatusStr(s.SessionStatus()));
        if (s.SessionStatus() == GattSessionStatus::Active) {
          ::SetEvent(signalHandle);
        }
      });
  // Guard against the status flipping to Active between the check above and the
  // handler registration.
  if (session.SessionStatus() == GattSessionStatus::Active) {
    ::SetEvent(signalHandle);
  }
  const bool signaled = co_await winrt::resume_on_signal(signalHandle, timeout);
  session.SessionStatusChanged(token);
  const bool active =
      signaled && session.SessionStatus() == GattSessionStatus::Active;
  if (active) {
    Log("GATT_SESSION_ACTIVE");
  } else {
    Log("GATT_SESSION_ACTIVE_TIMEOUT");
  }
  co_return active;
}

// Stable object-identity (ABI pointer) for correlating the same service /
// characteristic across log lines. Diagnostic only.
std::string PtrId(winrt::Windows::Foundation::IUnknown const& obj) {
  if (!obj) return "null";
  char buf[24]{};
  sprintf_s(buf, "0x%llX",
            static_cast<unsigned long long>(
                reinterpret_cast<uintptr_t>(winrt::get_abi(obj))));
  return buf;
}

// Renders a GattWriteResult: communication status + the exact ATT protocol
// error byte when present (e.g. 0x05 InsufficientAuthentication, 0x0F
// InsufficientEncryption → device requires pairing/encryption).
std::string WriteResultStr(GattWriteResult const& r) {
  std::string s = CommStatusStr(r.Status());
  auto perr = r.ProtocolError();
  if (perr != nullptr) {
    char buf[8]{};
    sprintf_s(buf, "0x%02X", static_cast<int>(perr.Value()));
    s += std::string(" attError=") + buf;
  } else {
    s += " attError=none";
  }
  return s;
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
std::atomic<int> g_rx_event_count{0};  // RX ValueChanged events since launch

void EmitNotify(const std::string& deviceId, const std::vector<uint8_t>& data) {
  // Called from the WinRT ValueChanged thread-pool thread. The Flutter Windows
  // EventSink forwards through the BinaryMessenger, which posts to the platform
  // task runner, so delivery is marshalled to the platform thread by the
  // embedder. The g_sink_mutex guards against a concurrent OnCancel.
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

// Subscribes to FFF1 notifications on an already-live connection. An active
// notification subscription is what keeps an unpaired WinRT BLE connection
// alive (BluetoothLEDevice + GattSession.MaintainConnection alone do not hold
// it). Registers ValueChanged then writes the CCCD (Notify, or Indicate only if
// Notify is absent). Returns true on Success. Revokes on failure.
winrt::Windows::Foundation::IAsyncOperation<bool> SubscribeFff1(
    std::string deviceId, GattCharacteristic rx) {
  const auto props = rx.CharacteristicProperties();
  const bool hasNotify = HasProp(props, GattCharacteristicProperties::Notify);
  const bool hasIndicate =
      HasProp(props, GattCharacteristicProperties::Indicate);
  LogMsg("FFF1_PROPS raw=" + std::to_string(static_cast<int>(props)) +
         " notify=" + B(hasNotify) + " indicate=" + B(hasIndicate));
  if (!hasNotify && !hasIndicate) {
    LogMsg("NOTIFY_ERROR stage=props status=NoNotifyNoIndicate");
    co_return false;
  }
  const bool useIndicate = !hasNotify;
  const std::string modeLabel = useIndicate ? "Indicate" : "Notify";

  // Identity + live connection status right before we subscribe.
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_sessions.find(deviceId);
    const std::string conn =
        (it != g_sessions.end() && it->second.device)
            ? ConnStatusStr(it->second.device.ConnectionStatus())
            : "no-device";
    LogMsg("CONNECT_SUBSCRIBE_FFF1_BEGIN key=" + deviceId + " rx=" + PtrId(rx) +
           " conn=" + conn + " mode=" + modeLabel);
  }

  Log("FFF1_NOTIFY_BEGIN");
  winrt::event_token token{};
  try {
    token = rx.ValueChanged(
        [deviceId](GattCharacteristic const&,
                   GattValueChangedEventArgs const& args) {
          auto reader = DataReader::FromBuffer(args.CharacteristicValue());
          std::vector<uint8_t> data(reader.UnconsumedBufferLength());
          reader.ReadBytes(data);
          const int n = ++g_rx_event_count;
          LogMsg("RX_EVENT_RECEIVED count=" + std::to_string(n) +
                 " bytes=" + std::to_string(data.size()));
          EmitNotify(deviceId, data);
        });
  } catch (const winrt::hresult_error& e) {
    LogMsg(std::string("CONNECT_SUBSCRIBE_FFF1_FAILED reason=handler ") +
           ToUtf8(e.message()));
    co_return false;
  } catch (...) {
    Log("CONNECT_SUBSCRIBE_FFF1_FAILED reason=handler");
    co_return false;
  }
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_sessions.find(deviceId);
    if (it != g_sessions.end()) {
      it->second.rx = rx;
      it->second.rxToken = token;
      it->second.rxSubscribed = true;
    }
  }
  Log("CONNECT_SUBSCRIBE_FFF1_VALUE_HANDLER_ATTACHED");

  const auto mode =
      useIndicate
          ? GattClientCharacteristicConfigurationDescriptorValue::Indicate
          : GattClientCharacteristicConfigurationDescriptorValue::Notify;
  LogMsg("CCCD_WRITE_BEGIN mode=" + modeLabel);
  auto wr = co_await
      rx.WriteClientCharacteristicConfigurationDescriptorWithResultAsync(mode);
  LogMsg("CONNECT_SUBSCRIBE_FFF1_CCCD_RESULT status=" + WriteResultStr(wr));
  if (wr.Status() != GattCommunicationStatus::Success) {
    LogMsg("CONNECT_SUBSCRIBE_FFF1_FAILED reason=cccd " + WriteResultStr(wr));
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_sessions.find(deviceId);
    if (it != g_sessions.end() && it->second.rxSubscribed && it->second.rx) {
      try {
        it->second.rx.ValueChanged(it->second.rxToken);
      } catch (...) {
      }
      it->second.rxSubscribed = false;
      Log("RX_HANDLER_REVOKED");
    }
    co_return false;
  }
  Log(useIndicate ? "RX_INDICATE_ENABLED" : "RX_NOTIFY_ENABLED");
  Log("CONNECT_SUBSCRIBE_FFF1_SUCCESS");
  co_return true;
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
    LogMsg("CONNECT_BEGIN key=" + deviceId + " address=" +
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
    LogMsg("CONNECT_DEVICE_READY conn=" +
           ConnStatusStr(device.ConnectionStatus()));

    // Open a GattSession and request the OS to establish/maintain the link.
    // This is required before any Uncached ATT operation will succeed.
    GattSession gattSession{nullptr};
    try {
      gattSession =
          co_await GattSession::FromDeviceIdAsync(device.BluetoothDeviceId());
      gattSession.MaintainConnection(true);
      LogMsg(std::string("GATT_SESSION canMaintain=") +
             (gattSession.CanMaintainConnection() ? "true" : "false"));
    } catch (...) {
      throw std::runtime_error("GattSession creation failed for " + deviceId);
    }

    // Wait (event-driven, bounded) for the session to actually become Active.
    // ConnectionStatus=Connected is NOT sufficient: the observed failure was
    // Uncached GATT returning Unreachable while only Cached metadata succeeded,
    // which then produced a stale FFF1 whose CCCD write failed with Unreachable.
    // We refuse to proceed on Cached metadata; ATT operations only run once the
    // GattSession reports Active.
    const bool sessionActive =
        co_await WaitSessionActive(gattSession, std::chrono::seconds(15));
    if (!sessionActive) {
      throw std::runtime_error(
          "GATT_SESSION_ACTIVE_TIMEOUT: session never became Active for " +
          deviceId);
    }
    const long long activeMs = NowMs();

    // (req 1) Full state snapshot at the moment the session reports Active.
    LogMsg("GATT_SESSION_ACTIVE_DETAIL t=" + std::to_string(activeMs) +
           " session=" + SessionStatusStr(gattSession.SessionStatus()) +
           " conn=" + ConnStatusStr(device.ConnectionStatus()) +
           " canMaintain=" + B(gattSession.CanMaintainConnection()) +
           " maintain=" + B(gattSession.MaintainConnection()) +
           " device=" + PtrId(device) + " sessionPtr=" + PtrId(gattSession));

    // (req 1/4) Keep logging SessionStatus transitions AFTER Active with the
    // full error info the SDK exposes (diagnostic; token intentionally not
    // revoked — the source object lives in g_sessions). Also records the last
    // BluetoothError so CONNECT_FINAL_STATE can report it.
    auto prevStatus = std::make_shared<std::atomic<int>>(
        static_cast<int>(gattSession.SessionStatus()));
    auto lastSessionError = std::make_shared<std::atomic<int>>(
        static_cast<int>(BluetoothError::Success));
    const std::string devPtr = PtrId(device);
    const std::string sesPtr = PtrId(gattSession);
    {
      auto dev = device;
      gattSession.SessionStatusChanged(
          [prevStatus, lastSessionError, dev, devPtr, sesPtr](
              GattSession const& s,
              GattSessionStatusChangedEventArgs const& args) {
            const int now = static_cast<int>(s.SessionStatus());
            const int was = prevStatus->exchange(now);
            const BluetoothError err = args.Error();
            lastSessionError->store(static_cast<int>(err));
            std::string maxPdu = "n/a";
            try {
              maxPdu = std::to_string(s.MaxPduSize());
            } catch (...) {
            }
            LogMsg(
                "GATT_SESSION_STATUS_CHANGED prev=" +
                SessionStatusStr(static_cast<GattSessionStatus>(was)) +
                " new=" + SessionStatusStr(static_cast<GattSessionStatus>(now)) +
                " error=" + BtErrStr(err) +
                " errorRaw=" + std::to_string(static_cast<int>(err)) +
                " conn=" + ConnStatusStr(dev.ConnectionStatus()) +
                " maxPdu=" + maxPdu + " t=" + std::to_string(NowMs()) +
                " device=" + devPtr + " sessionPtr=" + sesPtr);
          });
    }
    // (req 5) Temporary diagnostic: BluetoothLEDevice ConnectionStatus changes.
    {
      auto prev = std::make_shared<std::atomic<int>>(
          static_cast<int>(device.ConnectionStatus()));
      device.ConnectionStatusChanged(
          [prev](BluetoothLEDevice const& d, IInspectable const&) {
            const int now = static_cast<int>(d.ConnectionStatus());
            const int was = prev->exchange(now);
            LogMsg(
                "DEVICE_CONNECTION_STATUS_CHANGED prev=" +
                ConnStatusStr(static_cast<BluetoothConnectionStatus>(was)) +
                " new=" +
                ConnStatusStr(static_cast<BluetoothConnectionStatus>(now)) +
                " t=" + std::to_string(NowMs()));
          });
    }

    // Discover FFF0 / FFF1 / FFF2 FRESH and Uncached, now that the ATT session
    // is Active. No Cached fallback: the notify target must be an object backed
    // by the live session, never Cached metadata (that is the root cause).
    const winrt::guid fff0 = ToGuid("fff0");
    const winrt::guid fff2 = ToGuid("fff2");
    const winrt::guid fff1 = ToGuid("fff1");

    // (req 2) State at the start of the Uncached discovery.
    const long long beginMs = NowMs();
    LogMsg("UNCACHED_DISCOVERY_AFTER_ACTIVE_BEGIN t=" +
           std::to_string(beginMs) +
           " sinceActiveMs=" + std::to_string(beginMs - activeMs) +
           " session=" + SessionStatusStr(gattSession.SessionStatus()) +
           " conn=" + ConnStatusStr(device.ConnectionStatus()));
    auto servicesResult = co_await device.GetGattServicesForUuidAsync(
        fff0, BluetoothCacheMode::Uncached);
    const long long doneMs = NowMs();
    const uint32_t svcCount =
        servicesResult.Status() == GattCommunicationStatus::Success
            ? servicesResult.Services().Size()
            : 0;
    // (req 3) Full result snapshot with ATT error and timing.
    LogMsg("UNCACHED_DISCOVERY_AFTER_ACTIVE_RESULT status=" +
           CommStatusStr(servicesResult.Status()) +
           " attError=" + AttErr(servicesResult.ProtocolError()) +
           " count=" + std::to_string(svcCount) +
           " session=" + SessionStatusStr(gattSession.SessionStatus()) +
           " conn=" + ConnStatusStr(device.ConnectionStatus()) +
           " callMs=" + std::to_string(doneMs - beginMs));
    if (servicesResult.Status() != GattCommunicationStatus::Success ||
        svcCount == 0) {
      // (req 6) Failure-point snapshot including MaxPduSize and object identity.
      std::string maxPdu = "n/a";
      try {
        maxPdu = std::to_string(gattSession.MaxPduSize());
      } catch (...) {
      }
      LogMsg("CONNECT_ERROR stage=fff0_uncached_after_active status=" +
             CommStatusStr(servicesResult.Status()) +
             " attError=" + AttErr(servicesResult.ProtocolError()) +
             " session=" + SessionStatusStr(gattSession.SessionStatus()) +
             " conn=" + ConnStatusStr(device.ConnectionStatus()) +
             " maxPdu=" + maxPdu + " device=" + PtrId(device) +
             " sessionPtr=" + PtrId(gattSession));
      // (req 4) Final state snapshot at Connect exit, incl. last session error.
      LogMsg("CONNECT_FINAL_STATE session=" +
             SessionStatusStr(gattSession.SessionStatus()) +
             " conn=" + ConnStatusStr(device.ConnectionStatus()) +
             " maxPdu=" + maxPdu + " lastSessionError=" +
             BtErrStr(static_cast<BluetoothError>(lastSessionError->load())));
      throw std::runtime_error(
          "FFF0 Uncached discovery failed after Active: " +
          CommStatusStr(servicesResult.Status()));
    }
    GattDeviceService service = servicesResult.Services().GetAt(0);

    auto charsResult =
        co_await service.GetCharacteristicsAsync(BluetoothCacheMode::Uncached);
    LogMsg("UNCACHED_DISCOVERY_AFTER_ACTIVE_RESULT chars status=" +
           CommStatusStr(charsResult.Status()) + " count=" +
           std::to_string(
               charsResult.Status() == GattCommunicationStatus::Success
                   ? charsResult.Characteristics().Size()
                   : 0));
    if (charsResult.Status() != GattCommunicationStatus::Success) {
      throw std::runtime_error(
          "FFF0 characteristics Uncached failed after Active: " +
          CommStatusStr(charsResult.Status()));
    }

    BleSession session;
    session.device = device;
    session.gattSession = gattSession;
    session.service = service;

    EncodableList serviceUuids;
    EncodableList characteristics;
    serviceUuids.push_back(EncodableValue(GuidToShort(service.Uuid())));

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
      const bool canWrite = hasWrite || hasWwr;
      const bool canNotify = hasNotify || hasIndicate;

      EncodableMap c;
      c[EncodableValue("service")] = EncodableValue(GuidToShort(service.Uuid()));
      c[EncodableValue("uuid")] = EncodableValue(chUuid);
      c[EncodableValue("canWrite")] = EncodableValue(canWrite);
      c[EncodableValue("canNotify")] = EncodableValue(canNotify);
      characteristics.push_back(EncodableValue(c));

      LogMsg("  CHAR full=" + chUuid + " short=" + Short16(ch.Uuid()) +
             " props=" + std::to_string(static_cast<int>(props)) +
             " R=" + B(hasRead) + " W=" + B(hasWrite) + " WWR=" + B(hasWwr) +
             " N=" + B(hasNotify) + " I=" + B(hasIndicate));
      if (ch.Uuid() == fff2) {
        sawFff2 = true;
        if (canWrite) session.tx = ch;
      }
      if (ch.Uuid() == fff1) {
        sawFff1 = true;
        if (canNotify) session.rx = ch;
      }
    }
    LogMsg(std::string("  FFF2 match=") +
           (session.tx ? "accepted"
                       : (sawFff2 ? "rejected(no-write)" : "not-found")));
    LogMsg(std::string("  FFF1 match=") +
           (session.rx ? "accepted"
                       : (sawFff1 ? "rejected(no-notify)" : "not-found")));
    Log("SERVICE_FOUND FFF0");
    LogMsg("CONNECT_DISCOVERY_OK services=" +
           std::to_string(serviceUuids.size()) +
           " conn=" + ConnStatusStr(device.ConnectionStatus()) +
           " fff1=" + PtrId(session.rx));
    LogMsg("SERVICE_TOTAL count=" + std::to_string(serviceUuids.size()));

    {
      std::lock_guard<std::mutex> lock(g_mutex);
      g_sessions[deviceId] = session;
    }

    // Subscribe to FFF1 NOW, on the Active session with the freshly-discovered
    // Uncached characteristic. If this fails we return a hard error so Dart does
    // NOT proceed to EnableNotify and re-acquire on a dead session.
    if (session.rx == nullptr) {
      Log("CONNECT_SUBSCRIBE_FFF1_FAILED reason=no-fff1-characteristic");
      throw std::runtime_error("FFF1 notify characteristic not found on FFF0");
    }
    const bool subscribedNow = co_await SubscribeFff1(deviceId, session.rx);
    LogMsg(std::string("CONNECT_RETURN subscribed=") + B(subscribedNow));
    if (!subscribedNow) {
      throw std::runtime_error(
          "FFF1 notify subscription failed during connect (see "
          "CONNECT_SUBSCRIBE_FFF1_CCCD_RESULT)");
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
  LogMsg("ENABLE_NOTIFY_BEGIN key=" + deviceId);
  try {
    // Fast path: Connect already subscribed FFF1 on the live discovery
    // connection (which keeps the link alive), so nothing to redo here.
    {
      std::lock_guard<std::mutex> lock(g_mutex);
      auto it = g_sessions.find(deviceId);
      const bool found = it != g_sessions.end();
      LogMsg(std::string("ENABLE_NOTIFY_SESSION_FOUND found=") + B(found) +
             " subscribed=" +
             B(found ? it->second.rxSubscribed : false) + " conn=" +
             ((found && it->second.device)
                  ? ConnStatusStr(it->second.device.ConnectionStatus())
                  : "no-device"));
      if (found && it->second.rxSubscribed) {
        Log("ENABLE_NOTIFY_ALREADY_SUBSCRIBED");
        co_await ui;
        LogMsg("ENABLE_NOTIFY_RETURN result=success-cached");
        result->Success();
        co_return;
      }
    }
    // No re-acquire fallback. Connect performs discovery + subscription only on
    // an Active GattSession and returns a hard error otherwise, so reaching here
    // without rxSubscribed means the live session is gone. Re-acquiring FFF1 on a
    // dead session is exactly what produced the "service=Unreachable" loop, so we
    // fail clearly instead and let Dart re-run Connect from a clean state.
    Log("ENABLE_NOTIFY_NO_ACTIVE_SUBSCRIPTION");
    throw std::runtime_error(
        "FFF1 notify was not established on an Active session during connect; "
        "reconnect required (no re-acquire on a dead session)");
  } catch (const winrt::hresult_error& e) {
    has_error = true;
    char hr[16]{};
    sprintf_s(hr, "0x%08X", static_cast<uint32_t>(e.code().value));
    err_msg = ToUtf8(e.message());
    LogMsg(std::string("NOTIFY_ERROR stage=hresult hresult=") + hr +
           " message=" + err_msg);
  } catch (const std::exception& e) {
    has_error = true;
    err_msg = e.what();
    LogMsg(std::string("NOTIFY_ERROR stage=exception status=") + e.what());
  }
  co_await ui;
  LogMsg(std::string("ENABLE_NOTIFY_RETURN result=") +
         (has_error ? ("error:" + err_msg) : "success-fallback"));
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
      s.rx.ValueChanged(s.rxToken);  // revoke exactly once
      Log("RX_HANDLER_REVOKED");
    } catch (...) {
    }
    s.rxSubscribed = false;
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
