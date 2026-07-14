import 'package:flutter/material.dart';

import '../../../core/pro_adau1466_peq_audit_registry.dart';
import '../../../core/pro_usbi_native_backend.dart';
import '../../../shared/pro_widgets.dart';

class Adau1466PeqHardwareMappingPanel extends StatefulWidget {
  final ProUsbiNativeBackend backend;
  final bool Function() isWindowsPlatform;
  final bool deviceOpen;
  final bool dspWritesDisabled;
  final String? sourceOverride;

  const Adau1466PeqHardwareMappingPanel({
    super.key,
    required this.backend,
    required this.isWindowsPlatform,
    required this.deviceOpen,
    required this.dspWritesDisabled,
    this.sourceOverride,
  });

  @override
  State<Adau1466PeqHardwareMappingPanel> createState() =>
      _Adau1466PeqHardwareMappingPanelState();
}

class _Adau1466PeqHardwareMappingPanelState
    extends State<Adau1466PeqHardwareMappingPanel> {
  Future<String>? _source;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _source ??= widget.sourceOverride != null
        ? Future.value(widget.sourceOverride)
        : DefaultAssetBundle.of(context)
            .loadString(ProAdau1466PeqAuditRegistry.sourceAsset);
  }

  @override
  Widget build(BuildContext context) {
    final realExecutor =
        widget.isWindowsPlatform() && widget.backend.isAvailable &&
        !widget.backend.isFake;
    return FutureBuilder<String>(
      future: _source,
      builder: (context, snapshot) {
        final rows = snapshot.hasData
            ? ProAdau1466PeqAuditRegistry.parse(snapshot.data!)
            : const <Adau1466PeqCoefficientRow>[];
        final bands = ProAdau1466PeqAuditRegistry.bands(rows);
        return _buildPanel(realExecutor, rows, bands,
            loading: snapshot.connectionState != ConnectionState.done,
            error: snapshot.error);
      },
    );
  }

  Widget _buildPanel(bool realExecutor,
      List<Adau1466PeqCoefficientRow> rows,
      List<Adau1466PeqBandAudit> bands,
      {required bool loading, Object? error}) {
    final representative = bands.where((band) =>
        band.output.channel == 'WFL' && band.bandNumber == 1).firstOrNull;
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
          'USBi device: ${widget.deviceOpen ? "open" : "closed"} · '
          'real executor: ${realExecutor ? "available" : "unavailable"} · '
          'DSP writes: ${widget.dspWritesDisabled ? "STOPPED" : "enabled"}',
          style: proSubtitle(size: 9),
        ),
        const Text(
          'PEQ TEST WRITE BLOCKED — baseline Frequency/Gain/Q are not explicit; strict write allowlist remains empty.',
          style: TextStyle(fontSize: 9, color: Colors.amber),
        ),
        const SizedBox(height: 8),
        Text(
          loading ? 'Loading complete v0.9 Final PEQ export…'
              : error != null ? 'PEQ export load failed: $error'
              : 'v0.9 Final export: ${rows.length} individual coefficient rows · ${bands.length} five-word bands · no truncation.',
          style: const TextStyle(fontSize: 8, color: Colors.white54),
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
              Text(
                '${output.cellName} · ${bands.where((band) => band.output.cellName == output.cellName).length} bands · '
                '${_outputRanges(output, bands)}',
                style: const TextStyle(fontSize: 8, color: Colors.white54),
              ),
              Text('Source: ${ProAdau1466PeqAuditRegistry.sourceAsset}',
                  style: proSubtitle(size: 8)),
              const Text('WRITE BLOCKED — no arbitrary PEQ transaction; Frequency/Gain/Q metadata absent.',
                style: TextStyle(fontSize: 8, color: Colors.amber)),
            ]),
          ),
        const SizedBox(height: 4),
        Text('WFL · L_WOOFER_PEQ 20-band · Band 1',
            style: proTitle(size: 10)),
        Text(
          representative == null ? 'Representative row loading/unavailable.'
              : 'Target ${_hex(representative.targetStartAddress, 4)} · addresses ${representative.addressRange} · '
                'order b2, b1, b0, a2, a1 · words ${representative.coefficients.map((row) => row.wordHex).join(" · ")}',
          key: const Key('peq-representative-blocked'),
          style: const TextStyle(fontSize: 8, color: Colors.amber),
        ),
        const SizedBox(height: 6),
        const Text(
          'Slew parameter: not exported for this IdxSelectable Independent Bands cell. Frequency/Gain/Q: not explicit. Baseline coefficients are preserved; TEST generation remains blocked and no reverse-engineering is performed.',
          key: Key('peq-missing-design-metadata'),
          style: TextStyle(fontSize: 8, color: Colors.white54),
        ),
        const Text(
          'No TEST/RESTORE action is exposed. No arbitrary address or coefficient input. PASS_ACK only, never VERIFIED. Audible/measurement verification pending. EEPROM, Selfboot, legacy transport, and ADAU1701 remain blocked.',
          style: TextStyle(fontSize: 8, color: Colors.white38),
        ),
      ]),
    );
  }

  static String _hex(int value, int width) =>
      '0x${value.toRadixString(16).padLeft(width, '0').toUpperCase()}';

  static String _outputRanges(Adau1466PeqOutputAudit output,
      List<Adau1466PeqBandAudit> bands) {
    final selected = bands.where((band) =>
        band.output.cellName == output.cellName).toList();
    if (selected.isEmpty) return 'address ranges loading';
    return 'Band 1 ${selected.first.addressRange} · Band 20 ${selected.last.addressRange}';
  }
}
