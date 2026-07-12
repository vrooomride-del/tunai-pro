cmake_minimum_required(VERSION 3.16)
project(tunai_dsp_address_tester LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT WIN32)
    message(FATAL_ERROR "This tool is Windows-only (WinUSB required).")
endif()

add_executable(tunai_dsp_address_tester
    src/main.cpp
    src/packet_builder.cpp
    src/usbi_device.cpp
    src/logger.cpp
)

target_include_directories(tunai_dsp_address_tester PRIVATE src)

# WinUSB and SetupAPI are linked via #pragma comment in usbi_device.cpp,
# but also list them here for CMake generators that need explicit linking.
target_link_libraries(tunai_dsp_address_tester
    PRIVATE
    winusb
    setupapi
)

# Put the .exe next to the source for easy access
set_target_properties(tunai_dsp_address_tester PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/bin"
)
