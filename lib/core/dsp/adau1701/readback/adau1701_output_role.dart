// MiUMAX ADAU1701 output-to-speaker-role mapping.
// DAC0 = Output 1 = Tweeter L, DAC1 = Output 2 = Tweeter R,
// DAC2 = Output 3 = Woofer L,  DAC3 = Output 4 = Woofer R.
// Read-only — no write, BLE, or deploy logic.

enum Adau1701OutputRole {
  tweeterLeft,
  tweeterRight,
  wooferLeft,
  wooferRight;

  String get shortLabel => switch (this) {
        Adau1701OutputRole.tweeterLeft => 'Tweeter L',
        Adau1701OutputRole.tweeterRight => 'Tweeter R',
        Adau1701OutputRole.wooferLeft => 'Woofer L',
        Adau1701OutputRole.wooferRight => 'Woofer R',
      };
}

// MiUMAX output index → speaker role. Index 0-3 = Output 1-4 = DAC0-3.
const List<Adau1701OutputRole> miuMaxOutputRoles = [
  Adau1701OutputRole.tweeterLeft,
  Adau1701OutputRole.tweeterRight,
  Adau1701OutputRole.wooferLeft,
  Adau1701OutputRole.wooferRight,
];

// Full output tab label: "Output N · Role".
String miuMaxOutputTabLabel(int outputIndex) =>
    'Output ${outputIndex + 1} · ${miuMaxOutputRoles[outputIndex].shortLabel}';
