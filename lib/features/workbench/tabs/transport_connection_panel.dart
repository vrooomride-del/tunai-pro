import 'package:flutter/material.dart';
import '../../../core/pro_usbi_native_backend.dart';
import '../../../core/transport/dsp_transport.dart';
import '../../../core/transport/icp5_transports.dart';
import '../../../core/transport/usbi_dsp_transport.dart';
import '../../../shared/pro_widgets.dart';

class TransportConnectionPanel extends StatefulWidget {
  final ProUsbiNativeBackend backend;
  final bool deviceOpen;
  final bool dspWritesStopped;
  final ValueChanged<String>? onDspWriteStop;
  final Icp5UsbTransport? icp5UsbTransport;
  const TransportConnectionPanel({
    super.key,
    required this.backend,
    required this.deviceOpen,
    this.dspWritesStopped = false,
    this.onDspWriteStop,
    this.icp5UsbTransport,
  });

  @override
  State<TransportConnectionPanel> createState() =>
      _TransportConnectionPanelState();
}

class _TransportConnectionPanelState extends State<TransportConnectionPanel> {
  DspTransportIdentity _selected = DspTransportIdentity.usbi;
  late final Icp5UsbTransport _icp5Usb;
  bool _working = false;
  Icp5MasterVolumeResult? _lastCommand;
  double _confirmedValue = 6.0;
  String? _discoveryError;

  @override
  void initState() {
    super.initState();
    _icp5Usb = widget.icp5UsbTransport ??
        Icp5UsbTransport(onDspWriteStop: widget.onDspWriteStop);
  }

  @override
  void dispose() {
    _icp5Usb.close();
    super.dispose();
  }

  List<DspTransport> get _transports => [
        UsbiDspTransport(
            backend: widget.backend, deviceOpen: () => widget.deviceOpen),
        _icp5Usb,
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
        _row(
            'Current board',
            active.identity == DspTransportIdentity.usbi
                ? 'ADAU1466'
                : active.identity == DspTransportIdentity.icp5Usb
                    ? (_icp5Usb.handshakeComplete
                        ? 'ADAU1701'
                        : 'pending identity handshake')
                    : 'unproven'),
        _row(
            'Current executor',
            active.identity == DspTransportIdentity.usbi
                ? 'real USBi engineering executor'
                : active.identity == DspTransportIdentity.icp5Usb
                    ? 'guarded ICP5 Windows serial executor'
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
              active.identity == DspTransportIdentity.icp5Usb
                  ? 'Still missing: arbitrary parameters/range, dB conversion, SafeLoad, ADAU1466 commands, and Bluetooth protocol.'
                  : 'Missing: Bluetooth UUIDs, framing, payload limit, ACK, fragmentation, checksum, DSP target selection, direct-write and SafeLoad sequences.',
              style: proSubtitle(size: 9)),
        ],
        if (active.identity == DspTransportIdentity.icp5Usb) ...[
          const SizedBox(height: 10),
          _icp5Controls(),
        ],
        const SizedBox(height: 8),
        Text('NO AUTOMATIC FALLBACK DURING ACTIVE WRITES',
            style: proLabel(size: 9, color: Colors.orangeAccent, spacing: 0.6)),
      ]),
    );
  }

  String _yesNo(bool value) => value ? 'proven' : 'unproven';

  Widget _icp5Controls() {
    final device = _icp5Usb.enumeratedPorts
        .where((candidate) => candidate.portName == _icp5Usb.selectedPort)
        .firstOrNull;
    final blocked = _working || widget.dspWritesStopped || _icp5Usb.stopped;
    return Container(
      key: const Key('icp5_usb_operational_panel'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black12,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('ICP5 USB · CAPTURE-PROVEN ADAU1701 MASTER VOLUME',
            style: proLabel(size: 9, spacing: 0.8)),
        const SizedBox(height: 6),
        _row('Discovered port', _icp5Usb.selectedPort ?? 'none'),
        _row(
            'Availability', _icp5Usb.isAvailable ? 'available' : 'unavailable'),
        _row(
            'Device identity',
            device?.isCaptureProvenIcp5 == true
                ? 'VID 1A86 / PID 55D6'
                : 'VID 1A86 / PID 55D6 required'),
        _row('Friendly name', device?.friendlyName ?? 'none'),
        _row('InstanceId', device?.instanceId ?? 'none'),
        _row('Enumeration source', _icp5Usb.discoverySource),
        _row('Serial', '115200 · 8-N-1'),
        _row('Port state', _icp5Usb.connectionState.name),
        _row('Handshake', _icp5Usb.handshakeComplete ? 'PASS' : 'required'),
        _row('Profile',
            _icp5Usb.detectedProfile ?? 'DSP1701.100.00.01 required'),
        _row('Board',
            _icp5Usb.handshakeComplete ? 'ADAU1701' : 'unproven this session'),
        _row('Confirmed internal value', _confirmedValue.toStringAsFixed(1)),
        _row('Last ACK', _lastCommand?.message ?? 'not run'),
        if (_discoveryError != null) ...[
          const SizedBox(height: 5),
          Text(_discoveryError!,
              key: const Key('icp5_discovery_error'),
              style: const TextStyle(color: Colors.redAccent, fontSize: 10)),
        ],
        if (_icp5Usb.enumeratedPorts.isNotEmpty) ...[
          const SizedBox(height: 7),
          DropdownButton<String>(
            key: const Key('icp5_manual_port_selector'),
            value: _icp5Usb.enumeratedPorts
                    .any((entry) => entry.portName == _icp5Usb.selectedPort)
                ? _icp5Usb.selectedPort
                : null,
            hint: const Text('Select enumerated COM port'),
            items: [
              for (final entry in _icp5Usb.enumeratedPorts)
                DropdownMenuItem(
                    value: entry.portName, child: Text(entry.portName)),
            ],
            onChanged: blocked
                ? null
                : (port) {
                    if (port != null) {
                      setState(() => _icp5Usb.selectEnumeratedPort(port));
                    }
                  },
          ),
        ],
        const SizedBox(height: 7),
        Wrap(spacing: 7, runSpacing: 7, children: [
          OutlinedButton(
            key: const Key('icp5_discover_button'),
            onPressed: _working ? null : _discoverIcp5,
            child:
                Text(_working ? 'Discovering ICP5 USB…' : 'Discover ICP5 USB'),
          ),
          OutlinedButton(
            key: const Key('icp5_open_button'),
            onPressed: _working ? null : _openIcp5,
            child: Text(
                _icp5Usb.handshakeComplete ? 'Connected' : 'Open + Handshake'),
          ),
          OutlinedButton(
            onPressed: _working ? null : _closeIcp5,
            child: const Text('Close'),
          ),
          FilledButton(
            key: const Key('icp5_test_59_button'),
            onPressed: blocked || !_icp5Usb.handshakeComplete ? null : _test59,
            child: const Text('TEST internal value 5.9'),
          ),
          OutlinedButton(
            key: const Key('icp5_restore_60_button'),
            onPressed:
                blocked || !_icp5Usb.handshakeComplete ? null : _restore60,
            child: const Text('RESTORE internal value 6.0'),
          ),
        ]),
        const SizedBox(height: 7),
        Text(
            'PASS_ACK only, never VERIFIED · Range, dB mapping, and audible effect pending.',
            style: proSubtitle(size: 9)),
      ]),
    );
  }

  Future<void> _openIcp5() async {
    setState(() {
      _working = true;
      _discoveryError = null;
    });
    final result = await _icp5Usb.open();
    if (mounted) {
      setState(() {
        _working = false;
        if (!result.success) _discoveryError = result.message;
      });
    }
  }

  Future<void> _discoverIcp5() async {
    setState(() {
      _working = true;
      _discoveryError = null;
    });
    final result = await _icp5Usb.discover();
    if (!mounted) return;
    setState(() {
      _working = false;
      _discoveryError = result.error;
    });
  }

  Future<void> _closeIcp5() async {
    setState(() => _working = true);
    await _icp5Usb.close();
    if (mounted) setState(() => _working = false);
  }

  Future<void> _test59() async {
    setState(() => _working = true);
    final outcome = await _icp5Usb.runTestWithGuardedRestore();
    if (!mounted) return;
    setState(() {
      _working = false;
      _lastCommand = outcome.restore ?? outcome.test;
      if (outcome.test.success) _confirmedValue = 5.9;
      if (!outcome.test.success && outcome.restore?.success == true) {
        _confirmedValue = 6.0;
      }
    });
  }

  Future<void> _restore60() async {
    setState(() => _working = true);
    final result = await _icp5Usb.restoreBaselineWithStop();
    if (!mounted) return;
    setState(() {
      _working = false;
      _lastCommand = result;
      if (result.success) _confirmedValue = 6.0;
    });
  }

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
