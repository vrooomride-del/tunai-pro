cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "usbi_channel.cpp"
  "icp5_serial_channel.cpp"
  "icp5_ble_channel.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# The ADAU1701 ICP5 BLE native channel (icp5_ble_channel.cpp) uses C++/WinRT
# coroutines (co_await). Standard coroutines require C++20; under the default
# C++17 MSVC reports C3773/C3312 ("co_await is a non-conforming extension").
# Override the standard to C++20 AFTER apply_standard_settings so it wins.
# No /await flag is needed with /std:c++20 (that flag is for the pre-C++20
# experimental coroutines).
set_property(TARGET ${BINARY_NAME} PROPERTY CXX_STANDARD 20)
set_property(TARGET ${BINARY_NAME} PROPERTY CXX_STANDARD_REQUIRED ON)
target_compile_features(${BINARY_NAME} PRIVATE cxx_std_20)
if(MSVC)
  target_compile_options(${BINARY_NAME} PRIVATE "/std:c++20")
endif()

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
# USBi WinUSB native channel
target_link_libraries(${BINARY_NAME} PRIVATE "winusb.lib" "setupapi.lib" "cfgmgr32.lib")
# ADAU1701 ICP5 BLE native channel (C++/WinRT: Windows.Devices.Bluetooth)
target_link_libraries(${BINARY_NAME} PRIVATE "windowsapp.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
