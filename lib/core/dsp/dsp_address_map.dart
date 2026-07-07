// ADAU1466 v0.8B Export18 주소 상수
// ─── Master Volume (SafeLoad, 5.27 고정소수점) ───────────────────────────────
const kAdau1466MasterVolL = 103; // 0x67
const kAdau1466MasterVolR = 100; // 0x64
// SafeLoad 레지스터 (실측 확정)
const kAdau1466SafeLoadData0   = 0x6000;
const kAdau1466SafeLoadTrigger = 0x6005;

// ─── Phase 2/3 (정의만, write 잠금 — Capture Window 확인 전) ─────────────────
// PEQ, Delay, Crossover, Mute 주소는 Export18 확정 후 채울 것

// ADAU1701 v0.8 Export14 주소 상수
// ─── Master Volume (27-byte UART/BLE 프레임, 5.23 고정소수점) ────────────────
const kAdau1701MasterVolR = 0x0004;
const kAdau1701MasterVolL = 0x0005;

// ─── 절대 금지 ────────────────────────────────────────────────────────────────
// ignore: constant_identifier_names
const kAdau1701EepromI2cAddr = 0xA0; // NEVER WRITE — I2C EEPROM 주소
