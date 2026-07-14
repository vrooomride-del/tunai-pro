import 'package:flutter/material.dart';

import '../../../core/pro_adau1466_peq_audit_registry.dart';
import '../../../core/pro_usbi_native_backend.dart';
import '../../../shared/pro_widgets.dart';

class Adau1466PeqHardwareMappingPanel extends StatelessWidget {
  final ProUsbiNativeBackend backend;
  final bool Function() isWindowsPlatform;
  final bool deviceOpen;
  final bool dspWritesDisabled;

  const Adau1466PeqHardwareMappingPanel({
    super.key,
    required this.backend,
    required this.isWindowsPlatform,
    required this.deviceOpen,
    required this.dspWritesDisabled,
  });

  @override
  Widget build(BuildContext context) {
    final realExecutor =
        isWindowsPlatform() && backend.isAvailable && !backend.isFake;
    return Container(
      key: const Key('adau1466-peq-hardware-mapping'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: Colors.amber.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('ADAU1466 PEQ Hardware Mapping', style: proTitle(size: 13)),
        Text(
          'USBi device: ${deviceOpen ? "open" : "closed"} · '
          'real executor: ${realExecutor ? "available" : "unavailable"} · '
          'DSP writes: ${dspWritesDisabled ? "STOPPED" : "enabled"}',
          style: proSubtitle(size: 9),
        ),
        const Text(
          'PEQ WRITE BLOCKED — strict allowlist is empty.',
          style: TextStyle(fontSize: 9, color: Colors.amber),
        ),
        const SizedBox(height: 8),
        const Text(
          'Embedded export audit: source declares 875 PEQ rows; 0 individual PEQ rows are embedded. The embedded CSV explicitly contains non-PEQ rows only.',
          style: TextStyle(fontSize: 8, color: Colors.white54),
        ),
        const Text(
          'Known transport architecture: atomic five-word SafeLoad · b2, b1, b0, a2, a1 · signed ADAU1466 8.24 · lower count 5 · upper count 0.',
          style: TextStyle(fontSize: 8, color: Colors.white54),
        ),
        const SizedBox(height: 8),
        for (final output in ProAdau1466PeqAuditRegistry.outputs)
          Container(
            key: Key('peq-map-${output.channel}'),
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kProPanel,
              border: Border.all(color: kProBorder),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '${output.channel} · ${output.sigmaOutput} / ${output.physicalOutput}',
                style: proTitle(size: 9),
              ),
              const Text(
                'Sigma cell: unavailable · bands: unavailable · slew/address ranges: unavailable · exported words: unavailable',
                style: TextStyle(fontSize: 8, color: Colors.white54),
              ),
              Text(output.status,
                  style: const TextStyle(fontSize: 8, color: Colors.amber)),
            ]),
          ),
        const SizedBox(height: 4),
        Text(ProAdau1466PeqAuditRegistry.selectedRepresentative,
            style: proTitle(size: 10)),
        const Text(
          'Representative diagnostic: WRITE BLOCKED. WFL Band 1 cannot be attributed unambiguously because its exact slew address, five coefficient addresses/symbols, exported baseline words, sample rate, Frequency, Gain, and Q are absent from the embedded repository evidence.',
          key: Key('peq-representative-blocked'),
          style: TextStyle(fontSize: 8, color: Colors.amber),
        ),
        const SizedBox(height: 6),
        const Text(
          'Required original export file: TUNAI_ADAU1466_v0_8B_GLOBAL_DRIVER_160BAND_PEQ.params',
          key: Key('peq-required-export-file'),
          style: TextStyle(fontSize: 8, color: Colors.white54),
        ),
        const Text(
          'Required SigmaStudio operation: open the matching project, compile/link it, run Export System Files, and retain the complete generated .params parameter export without filtering PEQ rows. USBPcap is not requested.',
          key: Key('peq-required-export-operation'),
          style: TextStyle(fontSize: 8, color: Colors.white54),
        ),
        const Text(
          'No TEST/RESTORE action is exposed. No arbitrary address or coefficient input. PASS_ACK only, never VERIFIED. Audible/measurement verification pending. EEPROM, Selfboot, legacy transport, and ADAU1701 remain blocked.',
          style: TextStyle(fontSize: 8, color: Colors.white38),
        ),
      ]),
    );
  }
}
