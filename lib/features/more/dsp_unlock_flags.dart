/// DSP 파라미터별 write 잠금 플래그.
/// true = 즉시 write 가능, false = UI만 표시 (Capture Window 확인 필요).
class DspUnlockFlags {
  /// Driver Gain — Capture Window 불필요, 즉시 write 가능.
  static const bool gainWriteUnlocked = true;

  /// Driver Mute — Capture Window 확인 필요.
  static const bool muteWriteUnlocked = false;

  /// Driver Delay — Capture Window 확인 필요.
  static const bool delayWriteUnlocked = false;

  /// Global / Per-driver PEQ — SafeLoad 구현 완료 후 unlock.
  static const bool peqWriteUnlocked = false;
}
