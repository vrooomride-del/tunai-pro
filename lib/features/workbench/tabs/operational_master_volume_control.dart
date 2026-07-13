import 'package:flutter/material.dart';
import '../../../core/pro_adau1466_master_volume_executor.dart';
import '../../../core/pro_adau1466_sigma_executor.dart';
import '../../../core/pro_usbi_native_backend.dart';
import '../../../shared/pro_widgets.dart';

class OperationalMasterVolumeControl extends StatefulWidget {
  final ProUsbiNativeBackend backend;
  final bool Function() isWindowsPlatform;
  final bool deviceOpen;

  const OperationalMasterVolumeControl({
    super.key,
    required this.backend,
    required this.isWindowsPlatform,
    required this.deviceOpen,
  });

  @override
  State<OperationalMasterVolumeControl> createState() =>
      _OperationalMasterVolumeControlState();
}

class _OperationalMasterVolumeControlState
    extends State<OperationalMasterVolumeControl> {
  late ProAdau1466MasterVolumeExecutor _executor;
  double _confirmedLinear = 1.0;
  double _draftLinear = 1.0;
  bool _writing = false;
  Adau1466StereoWriteResult? _lastResult;

  @override
  void initState() {
    super.initState();
    _buildExecutor();
  }

  @override
  void didUpdateWidget(covariant OperationalMasterVolumeControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backend != widget.backend ||
        oldWidget.isWindowsPlatform != widget.isWindowsPlatform) {
      _buildExecutor();
    }
  }

  void _buildExecutor() {
    _executor = ProAdau1466MasterVolumeExecutor(
      sigmaExecutor: ProUsbiSigmaVerificationExecutor(
        backend: widget.backend,
        isWindowsPlatform: widget.isWindowsPlatform,
      ),
    );
  }

  bool get _writeEnabled => widget.deviceOpen &&
      _executor.isRealExecutorAvailable &&
      !_writing;

  String _dbLabel(double linear) {
    final db = adau1466LinearToDb(linear);
    return db.isInfinite ? '-∞ dB' : '${db.toStringAsFixed(1)} dB';
  }

  Future<void> _commit(double requested) async {
    if (_writing) return;
    final previous = _confirmedLinear;
    if (!_writeEnabled) {
      setState(() {
        _draftLinear = previous;
        _lastResult = Adau1466StereoWriteResult.blocked(
            'Write blocked: Windows, open USBi, and real executor are required.');
      });
      return;
    }

    setState(() => _writing = true);
    final result = await _executor.writeLinkedStereo(
      previousLinear: previous,
      requestedLinear: requested,
      deviceOpen: widget.deviceOpen,
    );
    if (!mounted) return;
    setState(() {
      _writing = false;
      _lastResult = result;
      if (result.confirmed) {
        _confirmedLinear = requested;
        _draftLinear = requested;
      } else {
        _draftLinear = previous;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _lastResult;
    return Container(
      key: const Key('operational-master-volume-control'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1828),
        border: Border.all(color: kProAccent.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.volume_up_outlined, size: 15, color: kProAccent),
          const SizedBox(width: 8),
          Text('Linked Stereo Master Volume', style: proTitle(size: 12)),
          const Spacer(),
          Text(_writing ? 'WRITING…' : 'PASS_ACK ONLY',
              style: TextStyle(fontSize: 8,
                  color: _writing ? Colors.orange : kProAccent,
                  fontWeight: FontWeight.w700, letterSpacing: 0.6)),
        ]),
        const SizedBox(height: 8),
        const Text(
          'Operational volatile control · MV L 0x0067 then MV R 0x0064 · ADAU1466 8.24',
          style: TextStyle(fontSize: 9, color: Colors.white54),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Text(
            'Current: ${_draftLinear.toStringAsFixed(4)} linear · ${_dbLabel(_draftLinear)}',
            key: const Key('operational-master-volume-current'),
            style: const TextStyle(fontSize: 12, color: Colors.white70,
                fontFamily: 'monospace'),
          )),
          Text('Confirmed: ${_confirmedLinear.toStringAsFixed(4)}',
              key: const Key('operational-master-volume-confirmed'),
              style: const TextStyle(fontSize: 9, color: Colors.white38,
                  fontFamily: 'monospace')),
        ]),
        Slider(
          key: const Key('operational-master-volume-slider'),
          value: _draftLinear,
          min: 0.0,
          max: 1.0,
          divisions: 200,
          label: '${_draftLinear.toStringAsFixed(3)} · ${_dbLabel(_draftLinear)}',
          onChanged: _writeEnabled
              ? (value) => setState(() => _draftLinear = value)
              : null,
          onChangeEnd: _writeEnabled ? _commit : null,
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 18, runSpacing: 5, children: [
          _OperationalStatus('USBi device-open status',
              widget.deviceOpen ? 'open' : 'closed'),
          _OperationalStatus('real executor status',
              _executor.isRealExecutorAvailable ? 'available' : 'unavailable'),
          _OperationalStatus('Last write status',
              result?.status.label ?? 'not run'),
          _OperationalStatus('L ACK status',
              result == null ? 'not run' : result.lAckOk ? 'PASS_ACK' : 'FAIL'),
          _OperationalStatus('R ACK status',
              result == null ? 'not run' : result.rAckOk ? 'PASS_ACK' : 'FAIL'),
          _OperationalStatus('rollback status', result == null
              ? 'not run'
              : !result.rollbackAttempted
                  ? 'not required'
                  : result.rollbackAckOk ? 'PASS_ACK' : 'FAIL'),
        ]),
        if (result?.error != null) ...[
          const SizedBox(height: 8),
          Text(result!.error!,
              style: const TextStyle(fontSize: 9, color: Colors.orange)),
        ],
        const SizedBox(height: 8),
        const Text(
          'ACK does not mark VERIFIED. Audible or measured operator confirmation remains required. '
          'XO, PEQ, SafeLoad, Gain, Mute, Delay, unknown addresses, EEPROM, and Selfboot remain blocked.',
          style: TextStyle(fontSize: 8, color: Colors.white38, height: 1.4),
        ),
      ]),
    );
  }
}

class _OperationalStatus extends StatelessWidget {
  final String label;
  final String value;
  const _OperationalStatus(this.label, this.value);

  @override
  Widget build(BuildContext context) => Text('$label: $value',
      style: const TextStyle(fontSize: 9, color: Colors.white60,
          fontFamily: 'monospace'));
}
