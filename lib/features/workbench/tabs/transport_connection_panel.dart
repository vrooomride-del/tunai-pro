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
  Icp5MasterMuteResult? _lastMuteCommand;
  int _confirmedMuteState = 0;
  Icp5OutputDac1GainResult? _lastDacGainCommand;
  double _confirmedDacGain = -4.8;
  String _dacGainRollback = 'not required';
  final Map<String, num> _phaseCConfirmed = {
    'gain1': -4.7,
    'gain2': -0.06666946,
    'gain3': -0.06666946,
    for (var channel = 0; channel < 4; channel++) 'delay$channel': 0.04,
    'cutoff0': 2000,
    'cutoff1': 2000,
    'cutoff2': 20,
    'cutoff3': 20,
    'peq0': -1.0,
    'peq1': 4.1,
    'peq2': -2.0,
    'peq3': 2.0,
  };
  final Map<String, Icp5PhaseCResult> _phaseCLast = {};
  final Map<String, String> _phaseCRollback = {};
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
        const SizedBox(height: 12),
        Container(
          key: const Key('icp5_master_mute_panel'),
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            border: Border.all(color: kProBorder),
            borderRadius: BorderRadius.circular(3),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ADAU1701 Master Mute',
                style: proLabel(size: 9, spacing: 0.8)),
            const SizedBox(height: 5),
            _row('Parameter ID', '0x00000012'),
            _row('Captured State 0 payload', '01 00 00'),
            _row('Captured State 1 payload', '01 00 01'),
            _row('Current confirmed state', 'State $_confirmedMuteState'),
            _row('Last ACK', _lastMuteCommand?.message ?? 'not run'),
            const SizedBox(height: 6),
            Wrap(spacing: 7, runSpacing: 7, children: [
              FilledButton(
                key: const Key('icp5_mute_test_state_1_button'),
                onPressed: blocked || !_icp5Usb.handshakeComplete
                    ? null
                    : _testMuteState1,
                child: const Text('TEST State 1'),
              ),
              OutlinedButton(
                key: const Key('icp5_mute_restore_state_0_button'),
                onPressed: blocked || !_icp5Usb.handshakeComplete
                    ? null
                    : _restoreMuteState0,
                child: const Text('RESTORE State 0'),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
                'PASS_ACK only, never VERIFIED · Audible mute polarity pending.',
                style: proSubtitle(size: 9)),
          ]),
        ),
        const SizedBox(height: 12),
        Container(
          key: const Key('icp5_output_dac_1_gain_panel'),
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            border: Border.all(color: kProBorder),
            borderRadius: BorderRadius.circular(3),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Output Gain index 0', style: proLabel(size: 9, spacing: 0.8)),
            const SizedBox(height: 5),
            _row('Parameter ID', '0x00000014'),
            _row('Protocol channel index', '0'),
            _row('Captured baseline', '-4.8'),
            _row('Captured TEST', '-4.9'),
            _row('Current confirmed state',
                _confirmedDacGain.toStringAsFixed(1)),
            _row('Last ACK', _lastDacGainCommand?.message ?? 'not run'),
            _row('Rollback status', _dacGainRollback),
            _row('DSP STOP status', _icp5Usb.stopped ? 'STOPPED' : 'enabled'),
            const SizedBox(height: 6),
            Wrap(spacing: 7, runSpacing: 7, children: [
              FilledButton(
                key: const Key('icp5_dac_gain_test_49_button'),
                onPressed: blocked || !_icp5Usb.handshakeComplete
                    ? null
                    : _testDacGain49,
                child: const Text('TEST -4.9'),
              ),
              OutlinedButton(
                key: const Key('icp5_dac_gain_restore_48_button'),
                onPressed: blocked || !_icp5Usb.handshakeComplete
                    ? null
                    : _restoreDacGain48,
                child: const Text('RESTORE -4.8'),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
                'PASS_ACK only, never VERIFIED · Complete range and audible verification pending.',
                style: proSubtitle(size: 9)),
          ]),
        ),
        const SizedBox(height: 8),
        _phaseCCard(
            blocked: blocked,
            keyName: 'gain1',
            title: 'Output Gain index 1',
            parameter: '0x00000014',
            channelIndex: 1,
            testLabel: 'TEST -4.8',
            restoreLabel: 'RESTORE -4.7',
            onTest: () => _runPhaseCTest(
                'gain1', -4.8, -4.7, () => _icp5Usb.runOutputGainTest(1)),
            onRestore: () => _runPhaseCRestore(
                'gain1', -4.7, () => _icp5Usb.restoreOutputGain(1))),
        for (var channel = 2; channel < 4; channel++)
          _phaseCCard(
              blocked: blocked,
              keyName: 'gain$channel',
              title: 'Output Gain index $channel',
              parameter: '0x00000014',
              channelIndex: channel,
              testLabel: 'TEST -0.16666946',
              restoreLabel: 'RESTORE -0.06666946',
              onTest: () => _runPhaseCTest('gain$channel', -0.16666946,
                  -0.06666946, () => _icp5Usb.runOutputGainTest(channel)),
              onRestore: () => _runPhaseCRestore('gain$channel', -0.06666946,
                  () => _icp5Usb.restoreOutputGain(channel))),
        const SizedBox(height: 12),
        Text('Delay candidate DAC0–DAC3',
            style: proLabel(size: 9, spacing: 0.8)),
        Text(
            'Neutral captured values only; engineering unit and range pending.',
            style: proSubtitle(size: 9)),
        for (var channel = 0; channel < 4; channel++)
          _phaseCCard(
              blocked: blocked,
              keyName: 'delay$channel',
              title: 'Delay candidate DAC$channel',
              parameter: '0x00000017',
              channelIndex: channel,
              testLabel: 'TEST 1.0',
              restoreLabel: 'RESTORE 0.04',
              onTest: () => _runPhaseCTest('delay$channel', 1.0, 0.04,
                  () => _icp5Usb.runDelayCandidateTest(channel)),
              onRestore: () => _runPhaseCRestore('delay$channel', 0.04,
                  () => _icp5Usb.restoreDelayCandidate(channel))),
        const SizedBox(height: 12),
        Text('Filter cutoff diagnostics',
            style: proLabel(size: 9, spacing: 0.8)),
        _phaseCCard(
            blocked: blocked,
            keyName: 'cutoff0',
            title: 'Filter Cutoff Diagnostic index 0 · 2000/2001',
            parameter: '0x00000015',
            channelIndex: 0,
            testLabel: 'TEST 2001',
            restoreLabel: 'RESTORE 2000',
            onTest: () => _runPhaseCTest(
                'cutoff0', 2001, 2000, () => _icp5Usb.runFilterCutoffTest(0)),
            onRestore: () => _runPhaseCRestore(
                'cutoff0', 2000, () => _icp5Usb.restoreFilterCutoff(0))),
        _phaseCCard(
            blocked: blocked,
            keyName: 'cutoff1',
            title: 'Filter Cutoff Diagnostic index 1 · 2000/2001',
            parameter: '0x00000015',
            channelIndex: 1,
            testLabel: 'TEST 2001',
            restoreLabel: 'RESTORE 2000',
            onTest: () => _runPhaseCTest(
                'cutoff1', 2001, 2000, () => _icp5Usb.runFilterCutoffTest(1)),
            onRestore: () => _runPhaseCRestore(
                'cutoff1', 2000, () => _icp5Usb.restoreFilterCutoff(1))),
        _phaseCCard(
            blocked: blocked,
            keyName: 'cutoff2',
            title: 'Filter Cutoff Diagnostic index 2 · 20/21',
            parameter: '0x00000015',
            channelIndex: 2,
            testLabel: 'TEST 21',
            restoreLabel: 'RESTORE 20',
            onTest: () => _runPhaseCTest(
                'cutoff2', 21, 20, () => _icp5Usb.runFilterCutoffTest(2)),
            onRestore: () => _runPhaseCRestore(
                'cutoff2', 20, () => _icp5Usb.restoreFilterCutoff(2))),
        _phaseCCard(
            blocked: blocked,
            keyName: 'cutoff3',
            title: 'Filter Cutoff Diagnostic index 3 · 20/21',
            parameter: '0x00000015',
            channelIndex: 3,
            testLabel: 'TEST 21',
            restoreLabel: 'RESTORE 20',
            onTest: () => _runPhaseCTest(
                'cutoff3', 21, 20, () => _icp5Usb.runFilterCutoffTest(3)),
            onRestore: () => _runPhaseCRestore(
                'cutoff3', 20, () => _icp5Usb.restoreFilterCutoff(3))),
        const SizedBox(height: 12),
        Text('PEQ Band 1 Gain diagnostics',
            style: proLabel(size: 9, spacing: 0.8)),
        _phaseCCard(
            blocked: blocked,
            keyName: 'peq0',
            title: 'PEQ Band 1 Gain index 0 · -1.0/-0.9 dB',
            parameter: '0x00000018',
            channelIndex: 0,
            testLabel: 'TEST -0.9',
            restoreLabel: 'RESTORE -1.0',
            onTest: () => _runPhaseCTest(
                'peq0', -0.9, -1.0, () => _icp5Usb.runPeqBand1GainTest(0)),
            onRestore: () => _runPhaseCRestore(
                'peq0', -1.0, () => _icp5Usb.restorePeqBand1Gain(0))),
        _phaseCCard(
            blocked: blocked,
            keyName: 'peq1',
            title: 'PEQ Band 1 Gain index 1 · 4.1/4.2 dB',
            parameter: '0x00000018',
            channelIndex: 1,
            testLabel: 'TEST 4.2 dB',
            restoreLabel: 'RESTORE 4.1 dB',
            onTest: () => _runPhaseCTest(
                'peq1', 4.2, 4.1, () => _icp5Usb.runPeqBand1GainTest(1)),
            onRestore: () => _runPhaseCRestore(
                'peq1', 4.1, () => _icp5Usb.restorePeqBand1Gain(1))),
        _phaseCCard(
            blocked: blocked,
            keyName: 'peq2',
            title: 'PEQ Band 1 Gain index 2 · -2.0/-1.0 dB',
            parameter: '0x00000018',
            channelIndex: 2,
            testLabel: 'TEST -1.0',
            restoreLabel: 'RESTORE -2.0',
            onTest: () => _runPhaseCTest(
                'peq2', -1.0, -2.0, () => _icp5Usb.runPeqBand1GainTest(2)),
            onRestore: () => _runPhaseCRestore(
                'peq2', -2.0, () => _icp5Usb.restorePeqBand1Gain(2))),
        _phaseCCard(
            blocked: blocked,
            keyName: 'peq3',
            title: 'PEQ Band 1 Gain index 3 · 2.0/2.1 dB',
            parameter: '0x00000018',
            channelIndex: 3,
            testLabel: 'TEST 2.1 dB',
            restoreLabel: 'RESTORE 2.0 dB',
            onTest: () => _runPhaseCTest(
                'peq3', 2.1, 2.0, () => _icp5Usb.runPeqBand1GainTest(3)),
            onRestore: () => _runPhaseCRestore(
                'peq3', 2.0, () => _icp5Usb.restorePeqBand1Gain(3))),
        Text(
            'Exact diagnostics only — not production controls. PASS_ACK only, never VERIFIED · physical speaker/output mapping, full ranges, audible verification, Filter HPF/LPF roles, and PEQ Frequency/Q/Bands 2–10 remain unproven.',
            style: proSubtitle(size: 9)),
      ]),
    );
  }

  Widget _phaseCCard(
      {required bool blocked,
      required String keyName,
      required String title,
      required String parameter,
      required int channelIndex,
      required String testLabel,
      required String restoreLabel,
      required VoidCallback onTest,
      required VoidCallback onRestore}) {
    return Container(
      key: Key('icp5_phase_c_$keyName'),
      margin: const EdgeInsets.only(top: 7),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(3)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: proLabel(size: 9, spacing: 0.5)),
        _row('Parameter ID', parameter),
        _row('Protocol channel index', '$channelIndex'),
        _row('Confirmed', '${_phaseCConfirmed[keyName]}'),
        _row('Last ACK', _phaseCLast[keyName]?.message ?? 'not run'),
        _row('Rollback status', _phaseCRollback[keyName] ?? 'not required'),
        _row('DSP STOP status', _icp5Usb.stopped ? 'STOPPED' : 'enabled'),
        Wrap(spacing: 7, runSpacing: 7, children: [
          FilledButton(
              key: Key('icp5_phase_c_${keyName}_test'),
              onPressed: blocked || !_icp5Usb.handshakeComplete ? null : onTest,
              child: Text(testLabel)),
          OutlinedButton(
              key: Key('icp5_phase_c_${keyName}_restore'),
              onPressed:
                  blocked || !_icp5Usb.handshakeComplete ? null : onRestore,
              child: Text(restoreLabel)),
        ]),
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

  Future<void> _testMuteState1() async {
    setState(() => _working = true);
    final outcome = await _icp5Usb.runMuteTestWithGuardedRestore();
    if (!mounted) return;
    setState(() {
      _working = false;
      _lastMuteCommand = outcome.restore ?? outcome.test;
      if (outcome.test.success) _confirmedMuteState = 1;
      if (!outcome.test.success && outcome.restore?.success == true) {
        _confirmedMuteState = 0;
      }
    });
  }

  Future<void> _restoreMuteState0() async {
    setState(() => _working = true);
    final result = await _icp5Usb.restoreMuteStateZeroWithStop();
    if (!mounted) return;
    setState(() {
      _working = false;
      _lastMuteCommand = result;
      if (result.success) _confirmedMuteState = 0;
    });
  }

  Future<void> _testDacGain49() async {
    setState(() => _working = true);
    final outcome = await _icp5Usb.runOutputDac1GainTestWithGuardedRestore();
    if (!mounted) return;
    setState(() {
      _working = false;
      _lastDacGainCommand = outcome.restore ?? outcome.test;
      _dacGainRollback = outcome.restore == null
          ? 'not required'
          : outcome.restore!.success
              ? 'RESTORE PASS_ACK'
              : 'RESTORE FAILED · STOP';
      if (outcome.test.success) _confirmedDacGain = -4.9;
      if (!outcome.test.success && outcome.restore?.success == true) {
        _confirmedDacGain = -4.8;
      }
    });
  }

  Future<void> _restoreDacGain48() async {
    setState(() => _working = true);
    final result = await _icp5Usb.restoreOutputDac1GainWithStop();
    if (!mounted) return;
    setState(() {
      _working = false;
      _lastDacGainCommand = result;
      _dacGainRollback = result.success
          ? 'explicit RESTORE PASS_ACK'
          : result.writeMayHaveReachedDevice
              ? 'RESTORE FAILED · STOP'
              : 'restore blocked before transmit';
      if (result.success) _confirmedDacGain = -4.8;
    });
  }

  Future<void> _runPhaseCTest(String key, num testValue, num restoreValue,
      Future<Icp5PhaseCOutcome> Function() operation) async {
    setState(() => _working = true);
    final outcome = await operation();
    if (!mounted) return;
    setState(() {
      _working = false;
      _phaseCLast[key] = outcome.restore ?? outcome.test;
      _phaseCRollback[key] = outcome.restore == null
          ? 'not required'
          : outcome.restore!.success
              ? 'RESTORE PASS_ACK'
              : 'RESTORE FAILED · STOP';
      if (outcome.test.success) _phaseCConfirmed[key] = testValue;
      if (!outcome.test.success && outcome.restore?.success == true) {
        _phaseCConfirmed[key] = restoreValue;
      }
    });
  }

  Future<void> _runPhaseCRestore(String key, num restoreValue,
      Future<Icp5PhaseCResult> Function() operation) async {
    setState(() => _working = true);
    final result = await operation();
    if (!mounted) return;
    setState(() {
      _working = false;
      _phaseCLast[key] = result;
      _phaseCRollback[key] = result.success
          ? 'explicit RESTORE PASS_ACK'
          : result.writeMayHaveReachedDevice
              ? 'RESTORE FAILED · STOP'
              : 'restore blocked before transmit';
      if (result.success) _phaseCConfirmed[key] = restoreValue;
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
