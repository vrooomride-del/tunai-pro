#pragma once

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <memory>

class Icp5SerialChannel {
 public:
  static void Register(flutter::BinaryMessenger* messenger);

 private:
  explicit Icp5SerialChannel(flutter::BinaryMessenger* messenger);
  void HandleMethod(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void ListPorts(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
