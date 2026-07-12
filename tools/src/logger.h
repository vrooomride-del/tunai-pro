#pragma once
#include <string>
#include <vector>
#include <cstdint>

struct WriteLogEntry {
    std::string  timestamp;
    std::string  address;
    std::string  valueFloat;
    std::string  fixedPointHex;
    std::string  setupBytes;
    std::string  bodyBytes;
    std::string  ackRequestBytes;
    std::string  ackResponseBytes;
    bool         success;
    std::string  errorMessage;
};

void logWrite(const WriteLogEntry& entry);
void logInfo(const std::string& message);

// Returns current timestamp as "YYYY-MM-DD HH:MM:SS"
std::string currentTimestamp();
