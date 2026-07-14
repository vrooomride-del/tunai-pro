import 'package:flutter/material.dart';
import '../../../core/pro_usbi_native_backend.dart';
import '../../../core/transport/dsp_transport.dart';
import '../../../core/transport/icp5_transports.dart';
import '../../../core/transport/usbi_dsp_transport.dart';
import '../../../shared/pro_widgets.dart';

class TransportConnectionPanel extends StatefulWidget {
  final ProUsbiNativeBackend backend;
  final bool deviceOpen;
  const TransportConnectionPanel({
    super.key,
    required this.backend,
    required this.deviceOpen,
  });

  @override
  State<TransportConnectionPanel> createState() =>
      _TransportConnectionPanelState();
}

class _TransportConnectionPanelState extends State<TransportConnectionPanel> {
  DspTransportIdentity _selected = DspTransportIdentity.usbi;

  List<DspTransport> get _transports => [
        UsbiDspTransport(
            backend: widget.backend, deviceOpen: () => widget.deviceOpen),
        const Icp5UsbTransport(),
        const Icp5BluetoothTransport(),
      ];

  @override
  Widget build(BuildContext context) {
    final transports = _transports;
    final active =
        transports.firstWhere((transport) => transport.identity == _selected);
    final caps = active.capabilities;
    return Container(
      key: const Key('workbench_transport_connection_panel'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('WORKBENCH CONNECTION / TRANSPORT',
            style: proLabel(size: 10, spacing: 1.5)),
        const SizedBox(height: 5),
        Text(
            'USBi is the default temporary Windows engineering transport. Selection never falls back during an active write.',
            style: proSubtitle(size: 9)),
        const SizedBox(height: 10),
        Wrap(spacing: 7, runSpacing: 7, children: [
          for (final transport in transports)
            ChoiceChip(
              label: Text(_selectorLabel(transport.identity)),
              selected: transport.identity == _selected,
              onSelected: (_) => setState(() => _selected = transport.identity),
            ),
        ]),
        const SizedBox(height: 12),
        _row('Selected transport', _selectedLabel(active.identity)),
        _row('Availability', active.isAvailable ? 'available' : 'unavailable'),
        _row('Connection state', active.connectionState.name),
        _row('Current board', 'ADAU1466'),
        _row(
            'Current executor',
            active.identity == DspTransportIdentity.usbi
                ? 'real USBi engineering executor'
                : 'unproven placeholder — writes rejected'),
        _row('Direct parameter write', _yesNo(caps.directParameterWrite)),
        _row('One-word SafeLoad', _yesNo(caps.oneWordSafeLoad)),
        _row('Five-word SafeLoad', _yesNo(caps.fiveWordSafeLoad)),
        _row('ACK support', _yesNo(caps.ackSupport)),
        _row('Readback support', _yesNo(caps.readbackSupport)),
        _row('Reconnect support', _yesNo(caps.reconnectSupport)),
        _row(
            'Maximum payload',
            caps.maximumPayloadSize == null
                ? 'unproven'
                : '${caps.maximumPayloadSize} bytes'),
        _row('Board detection', _yesNo(caps.boardDetectionSupport)),
        if (active.missingEvidence != null) ...[
          const SizedBox(height: 8),
          Text(active.missingEvidence!,
              key: const Key('icp5_protocol_evidence_required'),
              style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(
              'Missing: VID/PID, interface/endpoints, Bluetooth UUIDs, framing, payload limit, ACK, fragmentation, checksum, DSP target selection, direct-write and SafeLoad sequences.',
              style: proSubtitle(size: 9)),
        ],
        const SizedBox(height: 8),
        Text('NO AUTOMATIC FALLBACK DURING ACTIVE WRITES',
            style: proLabel(size: 9, color: Colors.orangeAccent, spacing: 0.6)),
      ]),
    );
  }

  String _yesNo(bool value) => value ? 'proven' : 'unproven';

  String _selectorLabel(DspTransportIdentity identity) => switch (identity) {
        DspTransportIdentity.usbi => 'USBi',
        DspTransportIdentity.icp5Usb => 'ICP5 USB',
        DspTransportIdentity.icp5Bluetooth => 'ICP5 Bluetooth',
      };

  String _selectedLabel(DspTransportIdentity identity) => switch (identity) {
        DspTransportIdentity.usbi => 'USBi · Windows temporary engineering',
        DspTransportIdentity.icp5Usb => 'ICP5 USB',
        DspTransportIdentity.icp5Bluetooth => 'ICP5 Bluetooth',
      };

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 155, child: Text(label, style: proSubtitle(size: 9))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(color: Colors.white70, fontSize: 10))),
        ]),
      );
}
