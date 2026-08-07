// ── TUNAI PRO Phase 3-D2 — Guided Measurement Setup dialog ─────────────────
//
// One scrollable dialog covering microphone / input device / background
// noise / input level / result — not a forced multi-page wizard (per the
// Phase 3-D2 spec: "필요한 만큼 세분화해도 되지만 불필요한 10개의 복잡한
// 페이지를 강제하지 않는다"). Reuses the real MicMeasurementController
// instance (same one Factory/Room capture uses) for
// measureNoiseFloor()/runInputLevelCheck() — never a second recorder.
//
// Persistence policy (see the Phase 3-D2 completion report for the full
// rationale): only a SUCCESSFUL check (isReady true) is ever persisted via
// ProProjectStoreNotifier.updateSetupReadiness. A failed check is shown
// locally but never overwrites a still-valid prior Ready snapshot — closing
// this dialog never deletes an existing valid readiness, and a stale
// (identity-changed) prior readiness is simply never treated as usable by
// isUsableNow, with no explicit "clear" step needed.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/calibration/microphone_profile_edit_rules.dart';
import '../../core/measurement/measurement_input_device.dart';
import '../../core/measurement/measurement_quality_policy.dart';
import '../../core/measurement/measurement_setup_capture_result.dart';
import '../../core/measurement/measurement_setup_readiness.dart';
import '../../core/measurement/measurement_setup_readiness_builder.dart';
import '../../core/measurement/measurement_setup_readiness_project_identity.dart';
import '../../core/pro_project.dart';
import '../../core/pro_project_store.dart';
import '../../shared/pro_widgets.dart';
import 'mic_measurement_controller.dart' as mic;

Future<void> showGuidedMeasurementSetupDialog(
  BuildContext context, {
  required String projectId,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => GuidedMeasurementSetupDialog(projectId: projectId),
  );
}

class GuidedMeasurementSetupDialog extends ConsumerStatefulWidget {
  final String projectId;
  const GuidedMeasurementSetupDialog({super.key, required this.projectId});

  @override
  ConsumerState<GuidedMeasurementSetupDialog> createState() =>
      _GuidedMeasurementSetupDialogState();
}

class _GuidedMeasurementSetupDialogState
    extends ConsumerState<GuidedMeasurementSetupDialog> {
  final _policy = MeasurementQualityPolicy.proProvisional();

  List<MeasurementInputDeviceDescriptor>? _availableDevices;
  bool _enumerating = false;
  String? _enumerationError;
  bool? _permissionGranted;

  MeasurementSetupCaptureResult? _noiseFloorResult;
  MeasurementSetupCaptureResult? _levelCheckResult;
  bool _noiseFloorRunning = false;
  bool _levelCheckRunning = false;

  bool _explicitAck = false;
  // Guided Setup default is an explicit stereo LEFT-ONLY signal, never mono:
  // a mono WAV can be duplicated to both channels by the output device, so it
  // cannot guarantee that only one speaker played. Setup Level Check needs a
  // reproducible, single-speaker signal for input-level verification.
  // mono remains in the enum for API compatibility / diagnostics only and is
  // never the Guided default. L+R are never played simultaneously, and no DSP
  // mute / gain / channel-routing write is used for isolation — the stereo WAV
  // itself carries the isolation (inactive channel is exact-zero PCM).
  MeasurementLevelCheckSignal _selectedSignal =
      MeasurementLevelCheckSignal.leftOnly;
  bool _expertExpanded = false;

  ProProject? get _project => ref
      .watch(proProjectStoreProvider)
      .projects
      .where((p) => p.id == widget.projectId)
      .firstOrNull;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshDevices());
  }

  Future<void> _refreshDevices() async {
    if (_enumerating) return;
    setState(() {
      _enumerating = true;
      _enumerationError = null;
    });
    final ctrl = ref.read(mic.micMeasurementProvider.notifier);
    try {
      final granted =
          await ctrl.inputDeviceService.hasPermission(request: false);
      final devices = await ctrl.inputDeviceService.listAvailableDevices();
      if (!mounted) return;
      setState(() {
        _permissionGranted = granted;
        _availableDevices = devices;
        _enumerating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enumerationError = e.toString();
        _enumerating = false;
      });
    }
  }

  Future<void> _requestPermission() async {
    final ctrl = ref.read(mic.micMeasurementProvider.notifier);
    final granted = await ctrl.inputDeviceService.hasPermission(request: true);
    if (!mounted) return;
    setState(() => _permissionGranted = granted);
    if (granted) await _refreshDevices();
  }

  Future<void> _selectSystemDefault() async {
    await ref.read(proProjectStoreProvider.notifier).updateSelectedInputDevice(
          widget.projectId,
          MeasurementInputDeviceSelection.systemDefault(
              selectedAt: DateTime.now()),
        );
    setState(() {
      _noiseFloorResult = null;
      _levelCheckResult = null;
    });
  }

  Future<void> _selectDevice(MeasurementInputDeviceDescriptor device) async {
    await ref.read(proProjectStoreProvider.notifier).updateSelectedInputDevice(
          widget.projectId,
          MeasurementInputDeviceSelection.specificDevice(
            deviceId: device.id,
            labelSnapshot: device.label,
            selectedAt: DateTime.now(),
          ),
        );
    setState(() {
      _noiseFloorResult = null;
      _levelCheckResult = null;
    });
  }

  bool get _deviceCurrentlyAvailable {
    final selection = _project?.selectedInputDevice;
    if (selection == null) return false;
    if (selection.useSystemDefault) return true;
    final devices = _availableDevices;
    if (devices == null) return false;
    return devices.any((d) => d.id == selection.deviceId);
  }

  Future<void> _runNoiseFloor() async {
    final selection = _project?.selectedInputDevice;
    if (selection == null || _noiseFloorRunning) return;
    setState(() => _noiseFloorRunning = true);
    final ctrl = ref.read(mic.micMeasurementProvider.notifier);
    final result = await ctrl.measureNoiseFloor(
        inputSelection: selection, policy: _policy);
    if (!mounted) return;
    setState(() {
      _noiseFloorResult = result;
      _noiseFloorRunning = false;
    });
  }

  Future<void> _runLevelCheck() async {
    final selection = _project?.selectedInputDevice;
    if (selection == null || _levelCheckRunning) return;
    setState(() => _levelCheckRunning = true);
    final ctrl = ref.read(mic.micMeasurementProvider.notifier);
    final priorNoise = _noiseFloorResult?.evaluation?.metrics.noiseFloorDbFs;
    final result = await ctrl.runInputLevelCheck(
      inputSelection: selection,
      policy: _policy,
      signal: _selectedSignal,
      priorNoiseFloorDbFs: priorNoise,
    );
    if (!mounted) return;
    setState(() {
      _levelCheckResult = result;
      _levelCheckRunning = false;
    });
    await _maybePersistReadiness();
  }

  MeasurementSetupReadinessIdentity? _currentIdentity() {
    final project = _project;
    if (project == null) return null;
    return MeasurementSetupReadinessProjectIdentity.forProject(project,
        policy: _policy);
  }

  MeasurementSetupReadinessSnapshot? _buildPreview() {
    final identity = _currentIdentity();
    final project = _project;
    if (identity == null || project == null) return null;
    return MeasurementSetupReadinessBuilder.build(
      identity: identity,
      microphoneState:
          deriveMicrophoneDisplayState(project.selectedMicrophoneProfile),
      inputDeviceSelected: project.selectedInputDevice != null,
      inputDeviceAvailable: _deviceCurrentlyAvailable,
      permissionGranted: _permissionGranted ?? false,
      noiseFloorEvaluation: _noiseFloorResult?.evaluation,
      levelCheckEvaluation: _levelCheckResult?.evaluation,
      deviceSnapshot:
          _levelCheckResult?.evaluation?.metrics.inputDeviceSnapshot ??
              _noiseFloorResult?.evaluation?.metrics.inputDeviceSnapshot,
      explicitWarningAcknowledgement: _explicitAck,
      selectedSetupSignalSide: switch (_selectedSignal) {
        MeasurementLevelCheckSignal.mono => MeasurementSetupSignalSide.mono,
        MeasurementLevelCheckSignal.leftOnly => MeasurementSetupSignalSide.left,
        MeasurementLevelCheckSignal.rightOnly =>
          MeasurementSetupSignalSide.right,
      },
      validity: _policy.setupCheckValidity,
    );
  }

  Future<void> _maybePersistReadiness() async {
    final preview = _buildPreview();
    if (preview == null || !preview.isReady) return;
    await ref
        .read(proProjectStoreProvider.notifier)
        .updateSetupReadiness(widget.projectId, preview);
  }

  @override
  Widget build(BuildContext context) {
    final project = _project;
    return Dialog(
      backgroundColor: kProPanel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: kProBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 700),
        child: project == null
            ? const Padding(
                padding: EdgeInsets.all(24), child: Text('Project not found.'))
            : _buildBody(project),
      ),
    );
  }

  Widget _buildBody(ProProject project) {
    final preview = _buildPreview();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Text('CHECK MEASUREMENT SETUP', style: proTitle(size: 14)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: Colors.white38),
              onPressed: () => Navigator.pop(context),
            ),
          ]),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _microphoneSection(project),
                  const Divider(height: 24, color: kProBorder),
                  _inputDeviceSection(project),
                  const Divider(height: 24, color: kProBorder),
                  _noiseFloorSection(),
                  const Divider(height: 24, color: kProBorder),
                  _levelCheckSection(),
                  const Divider(height: 24, color: kProBorder),
                  if (preview != null) _resultSection(preview),
                  const SizedBox(height: 8),
                  _expertDetailsSection(preview),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _microphoneSection(ProProject project) {
    final profile = project.selectedMicrophoneProfile;
    final state = deriveMicrophoneDisplayState(profile);
    final (label, color) = switch (state) {
      MicrophoneDisplayState.notSelected => ('측정 마이크를 선택하세요.', Colors.white38),
      MicrophoneDisplayState.calibrationReady => (
          'Calibrated — ${profile!.manufacturer} ${profile.model}',
          kProGreen
        ),
      MicrophoneDisplayState.explicitlyUncalibrated => (
          'Explicitly uncalibrated',
          kProAmber
        ),
      MicrophoneDisplayState.invalid => (
          'Calibration profile is invalid.',
          kProRed
        ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('1. MEASUREMENT MICROPHONE', style: proLabel(size: 10)),
        const SizedBox(height: 6),
        Text(label, style: proValue(size: 12, color: color)),
        if (profile?.calibrationCurve != null)
          Text('Orientation: ${profile!.calibrationCurve!.angle.label}',
              style: proSubtitle(size: 10)),
        if (state == MicrophoneDisplayState.explicitlyUncalibrated)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Checkbox(
                value: _explicitAck,
                onChanged: (v) => setState(() => _explicitAck = v ?? false),
              ),
              Expanded(
                child: Text('보정 없이 진행하면 정확도가 낮아질 수 있습니다.',
                    style: proSubtitle(size: 11)),
              ),
            ]),
          ),
      ],
    );
  }

  Widget _inputDeviceSection(ProProject project) {
    final selection = project.selectedInputDevice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('2. INPUT DEVICE', style: proLabel(size: 10)),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.refresh,
                size: 16, color: _enumerating ? Colors.white24 : kProAccent),
            onPressed: _enumerating ? null : _refreshDevices,
            tooltip: 'Refresh',
          ),
        ]),
        if (_permissionGranted == false)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              const Expanded(
                  child: Text('입력 장치를 찾을 수 없습니다: 마이크 접근 권한이 필요합니다.',
                      style: TextStyle(color: kProRed, fontSize: 11))),
              TextButton(
                  onPressed: _requestPermission, child: const Text('Allow')),
            ]),
          ),
        if (_enumerationError != null)
          Text('Enumeration failed: $_enumerationError',
              style: const TextStyle(color: kProRed, fontSize: 11)),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ChoiceChip(
            label: const Text('System Default'),
            selected: selection?.useSystemDefault ?? false,
            onSelected: (_) => _selectSystemDefault(),
          ),
          for (final d in _availableDevices ??
              const <MeasurementInputDeviceDescriptor>[])
            ChoiceChip(
              label: Text(d.label),
              selected: !(selection?.useSystemDefault ?? true) &&
                  selection?.deviceId == d.id,
              onSelected: (_) => _selectDevice(d),
            ),
        ]),
        if (selection != null && !_deviceCurrentlyAvailable)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('선택한 입력 장치를 찾을 수 없습니다.',
                style: TextStyle(color: kProRed, fontSize: 11)),
          ),
      ],
    );
  }

  Widget _noiseFloorSection() {
    final eval = _noiseFloorResult?.evaluation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('3. BACKGROUND NOISE', style: proLabel(size: 10)),
        const SizedBox(height: 4),
        Text('잠시 조용히 해주세요. 방의 배경 소음을 확인합니다.', style: proSubtitle(size: 11)),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _noiseFloorRunning ? null : _runNoiseFloor,
          child: Text(
              _noiseFloorRunning ? 'Measuring…' : 'Measure Background Noise'),
        ),
        if (_noiseFloorResult != null && !_noiseFloorResult!.isSuccess)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_noiseFloorResult!.error ?? 'Failed',
                style: const TextStyle(color: kProRed, fontSize: 11)),
          ),
        if (eval != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Noise floor: ${eval.metrics.noiseFloorDbFs?.toStringAsFixed(1)} dBFS',
              style: proSubtitle(size: 11),
            ),
          ),
      ],
    );
  }

  Widget _levelCheckSection() {
    final eval = _levelCheckResult?.evaluation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('4. INPUT LEVEL', style: proLabel(size: 10)),
        const SizedBox(height: 8),
        // Beginner-facing guidance: name the speaker that plays and the one
        // that is excluded. Deliberately no "mono" wording here — that term
        // stays in Expert Details only.
        if (_selectedSignal != MeasurementLevelCheckSignal.mono) ...[
          Text(
            _selectedSignal == MeasurementLevelCheckSignal.leftOnly
                ? '왼쪽 스피커에서 테스트 신호를 재생합니다.'
                : '오른쪽 스피커에서 테스트 신호를 재생합니다.',
            style: proSubtitle(size: 11),
          ),
          Text(
            _selectedSignal == MeasurementLevelCheckSignal.leftOnly
                ? '오른쪽 스피커는 테스트 신호에서 자동으로 제외됩니다.'
                : '왼쪽 스피커는 테스트 신호에서 자동으로 제외됩니다.',
            style: proSubtitle(size: 11),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton(
          onPressed: _levelCheckRunning ? null : _runLevelCheck,
          child: Text(
              _levelCheckRunning ? 'Measuring…' : 'Play Test Signal & Measure'),
        ),
        if (_levelCheckResult != null && !_levelCheckResult!.isSuccess)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_levelCheckResult!.error ?? 'Failed',
                style: const TextStyle(color: kProRed, fontSize: 11)),
          ),
        if (eval != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(spacing: 12, children: [
              Text('Peak: ${eval.metrics.peakDbFs.toStringAsFixed(1)} dBFS',
                  style: proSubtitle(size: 11)),
              Text('RMS: ${eval.metrics.rmsDbFs.toStringAsFixed(1)} dBFS',
                  style: proSubtitle(size: 11)),
              if (eval.metrics.signalToNoiseDb != null)
                Text(
                    'SNR: ${eval.metrics.signalToNoiseDb!.toStringAsFixed(1)} dB',
                    style: proSubtitle(size: 11)),
            ]),
          ),
      ],
    );
  }

  Widget _resultSection(MeasurementSetupReadinessSnapshot preview) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: (preview.isReady ? kProGreen : kProRed).withValues(alpha: 0.08),
        border: Border.all(
            color: (preview.isReady ? kProGreen : kProRed)
                .withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            preview.isReady ? '측정 준비가 완료되었습니다.' : '측정 준비가 완료되지 않았습니다.',
            style: TextStyle(
                color: preview.isReady ? kProGreen : kProRed,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
          for (final b in preview.blockers)
            Text('• $b', style: proSubtitle(size: 11)),
          for (final w in preview.warnings)
            Text('⚠ $w',
                style: const TextStyle(color: kProAmber, fontSize: 11)),
        ],
      ),
    );
  }

  static String _signalChipLabel(MeasurementLevelCheckSignal s) => switch (s) {
        MeasurementLevelCheckSignal.leftOnly => 'Test Left',
        MeasurementLevelCheckSignal.rightOnly => 'Test Right',
        // Kept for API compatibility / diagnostics only — never the Guided
        // default, and this label only ever appears under Expert Details.
        MeasurementLevelCheckSignal.mono => 'Mono (diagnostic)',
      };

  /// Switching the setup signal side invalidates the previous side's level
  /// check: its result must not be shown as if it belonged to the newly
  /// selected side, and a still-Ready snapshot from the old side must not be
  /// silently reused. Clearing [_levelCheckResult] forces an explicit re-run,
  /// which then produces a fresh snapshot (new generationId) carrying the
  /// side actually measured. Nothing already persisted is deleted — a prior
  /// valid Ready snapshot stays until a new successful check replaces it.
  void _selectSetupSignal(MeasurementLevelCheckSignal s) {
    if (_selectedSignal == s) return;
    setState(() {
      _selectedSignal = s;
      _levelCheckResult = null;
    });
  }

  Widget _expertDetailsSection(MeasurementSetupReadinessSnapshot? preview) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton(
          onPressed: () => setState(() => _expertExpanded = !_expertExpanded),
          child:
              Text(_expertExpanded ? 'Hide Expert Details' : 'Expert Details'),
        ),
        if (_expertExpanded && preview != null)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: kProSurface,
              border: Border.all(color: kProBorder),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'device: ${preview.deviceSnapshot?.deviceId ?? "system default"}',
                    style: proSubtitle(size: 10)),
                Text('label: ${preview.deviceSnapshot?.label ?? "-"}',
                    style: proSubtitle(size: 10)),
                Text(
                    'actual sample rate/channel: '
                    '${preview.deviceSnapshot?.actualSampleRate ?? "-"} Hz / '
                    '${preview.deviceSnapshot?.actualChannelCount ?? "-"} ch',
                    style: proSubtitle(size: 10)),
                Text('generationId: ${preview.generationId}',
                    style: proSubtitle(size: 10)),
                Text('checkedAt: ${preview.checkedAt}',
                    style: proSubtitle(size: 10)),
                Text('expiresAt: ${preview.expiresAt}',
                    style: proSubtitle(size: 10)),
                Text('policy version: ${_policy.version} (provisional)',
                    style: proSubtitle(size: 10)),
                const SizedBox(height: 6),
                Text('Setup signal side', style: proLabel(size: 9)),
                Wrap(spacing: 6, children: [
                  for (final s in MeasurementLevelCheckSignal.values)
                    ChoiceChip(
                      label: Text(_signalChipLabel(s)),
                      selected: _selectedSignal == s,
                      onSelected: (_) => _selectSetupSignal(s),
                    ),
                ]),
              ],
            ),
          ),
      ],
    );
  }
}
