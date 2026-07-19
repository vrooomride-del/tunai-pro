#pragma once

#include <flutter/binary_messenger.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

// Native WinRT Bluetooth LE backend for the ADAU1701 ICP5 BLE path.
//
// Wires to the Dart WindowsIcp5BluetoothDriver seam:
//   MethodChannel  "tunai/icp5_ble"        — adapterOn/scan/connect/enableNotify/write/disconnect
//   EventChannel   "tunai/icp5_ble/notify" — raw RX bytes from FFF1
//
// This channel only moves bytes over GATT (write FFF2 / notify FFF1 under
// service FFF0). ICP5 framing, the identity handshake, and DSP writes remain in
// the existing Dart transport/codec — unchanged.
class Icp5BleChannel {
 public:
  static void Register(flutter::BinaryMessenger* messenger);

 private:
  explicit Icp5BleChannel(flutter::BinaryMessenger* messenger);

  void HandleMethod(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> event_channel_;
};
