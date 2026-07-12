#include "logger.h"
#include <fstream>
#include <iostream>
#include <chrono>
#include <ctime>
#include <sstream>
#include <iomanip>

static const char* kLogFile = "tunai_dsp_address_test_log.txt";

std::string currentTimestamp() {
    auto now = std::chrono::system_clock::now();
    std::time_t t = std::chrono::system_clock::to_time_t(now);
    std::tm tm_buf{};
#ifdef _WIN32
    localtime_s(&tm_buf, &t);
#else
    localtime_r(&t, &tm_buf);
#endif
    std::ostringstream ss;
    ss << std::put_time(&tm_buf, "%Y-%m-%d %H:%M:%S");
    return ss.str();
}

void logWrite(const WriteLogEntry& entry) {
    std::ofstream f(kLogFile, std::ios::app);
    if (!f) return;

    f << "=== WRITE " << entry.timestamp << " ===\n"
      << "  address      : " << entry.address       << "\n"
      << "  valueFloat   : " << entry.valueFloat     << "\n"
      << "  fixedPoint   : " << entry.fixedPointHex  << "\n"
      << "  setup        : " << entry.setupBytes     << "\n"
      << "  body         : " << entry.bodyBytes      << "\n"
      << "  ackRequest   : " << entry.ackRequestBytes << "\n"
      << "  ackResponse  : " << entry.ackResponseBytes << "\n"
      << "  result       : " << (entry.success ? "SUCCESS" : "FAILURE") << "\n";
    if (!entry.errorMessage.empty())
        f << "  error        : " << entry.errorMessage << "\n";
    f << "\n";

    // Mirror to stdout
    std::cout << "[LOG] " << (entry.success ? "OK" : "FAIL")
              << "  addr=" << entry.address
              << "  val=" << entry.valueFloat
              << "\n";
}

void logInfo(const std::string& message) {
    std::ofstream f(kLogFile, std::ios::app);
    if (f)
        f << "[INFO] " << currentTimestamp() << "  " << message << "\n";
    std::cout << "[INFO] " << message << "\n";
}
