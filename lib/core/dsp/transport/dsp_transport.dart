abstract class DspTransport {
  /// DSP 레지스터에 4바이트(1워드) 값을 write. [bytes4]는 big-endian 4바이트.
  /// EEPROM 주소(0xA0)는 절대 허용되지 않음 — 호출부가 보장해야 한다.
  Future<void> writeParameter(int address, List<int> bytes4);

  Future<List<int>?> readParameter(int address);

  Future<bool> detectDevice();

  void dispose();
}
