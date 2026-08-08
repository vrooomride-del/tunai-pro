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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/calibration/microphone_profile_edit_rules.dart';
import '../../core/measurement/live_level_check.dart';
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

  // ── Live Level Check ──────────────────────────────────────────────────
  // See MicMeasurementController.startLiveLevelCheck's doc comment for the
  // exclusivity/lifecycle contract this dialog relies on. This dialog owns
  // ONLY the UX-facing state (current reading, stability tracking, the
  // auto-triggered verification) — the controller owns the actual
  // recorder/player session.
  StreamSubscription<LiveLevelReading>? _liveSub;
  LiveLevelReading? _liveReading;
  bool _liveCheckActive = false;
  // True while _confirmLiveLevelPass() (the SINGLE evidence-commit path —
  // see that method's doc comment) is running, whether triggered by the
  // auto-confirm or the explicit "이 레벨로 확인" button. Guards against
  // double-commit and against starting a new live session mid-confirmation.
  bool _confirmingLivePass = false;
  LiveLevelStabilityTracker? _stabilityTracker;
  String? _liveCheckError;

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

  @override
  void dispose() {
    // Live Level Check item 5: dialog close/dispose gets the exact same
    // cleanup as an explicit Stop. Cancel our own subscription synchronously
    // and fire-and-forget the controller-side stop (dispose() cannot await);
    // the controller's own dispose() (a separate lifetime — this dialog does
    // not own the controller) provides a second, independent safety net.
    _liveSub?.cancel();
    if (_liveCheckActive) {
      unawaited(ref.read(mic.micMeasurementProvider.notifier).stopLiveLevelCheck());
    }
    super.dispose();
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
    // A stale live session bound to the OLD device must never keep running
    // once the selection changes.
    if (_liveCheckActive) await _stopLiveLevelCheckSession();
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
    if (_liveCheckActive) await _stopLiveLevelCheckSession();
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

  // ── Live Level Check ──────────────────────────────────────────────────
  //
  // Contract:
  //   1. "Live GOOD" (a single tick) is a UX-only signal — never itself the
  //      PASS evidence. Sustained GOOD (LiveLevelStabilityTracker) is what
  //      unlocks confirmation.
  //   2. Exactly ONE function commits PASS evidence: _confirmLiveLevelPass().
  //      Both the auto-trigger (once sustained GOOD is reached) and the
  //      explicit "이 레벨로 확인" button call this SAME helper — no two
  //      divergent save paths. A re-entry guard (_confirmingLivePass)
  //      ensures evidence is committed at most once per session.
  //   3. No live "clipping" state — see live_level_check.dart's header
  //      comment for why. Real clipping detection stays with the WAV-based
  //      analyzer inside the manual/Expert legacy check.
  //   4. [중지] always means CANCEL — it never itself counts as a PASS.

  Future<void> _startLiveLevelCheck() async {
    final selection = _project?.selectedInputDevice;
    if (selection == null || _liveCheckActive || _confirmingLivePass) return;

    setState(() {
      _liveCheckError = null;
      _liveReading = null;
      _liveCheckActive = true;
    });
    _stabilityTracker = LiveLevelStabilityTracker();

    final ctrl = ref.read(mic.micMeasurementProvider.notifier);
    try {
      final stream = await ctrl.startLiveLevelCheck(
        inputSelection: selection,
        policy: _policy,
        signal: _selectedSignal,
      );
      _liveSub = stream.listen(
        (reading) {
          if (!mounted) return;
          setState(() => _liveReading = reading);
          final tracker = _stabilityTracker;
          tracker?.addTick(reading);
          final stable = tracker?.isStableGood ?? false;
          if (stable && !_confirmingLivePass) {
            unawaited(_confirmLiveLevelPass());
          }
        },
        onError: (Object e, StackTrace _) {
          if (!mounted) return;
          setState(() {
            _liveCheckError = e.toString();
            _liveCheckActive = false;
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _liveCheckError = e.toString();
        _liveCheckActive = false;
      });
    }
  }

  /// Cancels the live session WITHOUT committing anything — [중지]. Never
  /// treated as a PASS.
  Future<void> _cancelLiveLevelCheck() async {
    await _stopLiveLevelCheckSession();
  }

  Future<void> _stopLiveLevelCheckSession() async {
    await _liveSub?.cancel();
    _liveSub = null;
    _stabilityTracker = null;
    final ctrl = ref.read(mic.micMeasurementProvider.notifier);
    await ctrl.stopLiveLevelCheck();
    if (!mounted) return;
    setState(() {
      _liveCheckActive = false;
      _liveReading = null;
    });
  }

  /// THE single evidence-commit path — called by BOTH the auto-trigger
  /// (once sustained GOOD is first reached) and the explicit "이 레벨로
  /// 확인" button. Never two divergent save paths.
  ///
  /// FIX (double-verification bug, prior pass): this used to stop the live
  /// session and then automatically re-run the legacy WAV-based
  /// runInputLevelCheck() as a second, independent truth source that could
  /// silently overwrite the live PASS. The sustained-GOOD window itself IS
  /// the verification: this builds Input Level PASS evidence directly from
  /// the live tracker's own data (buildLiveLevelPassEvidence, reusing the
  /// exact existing MeasurementQualityEvaluation shape) and persists it via
  /// the SAME _maybePersistReadiness() path the legacy check has always
  /// used — no second capture, no parallel truth source.
  ///
  /// Re-entry guarded by [_confirmingLivePass] — a duplicate call (auto-fire
  /// racing an explicit button tap, or two ticks arriving before the first
  /// call's `await` yields) commits evidence at most once.
  Future<void> _confirmLiveLevelPass() async {
    if (_confirmingLivePass) {
      return;
    }
    final tracker = _stabilityTracker;
    if (tracker == null || !tracker.isStableGood) {
      return;
    }

    setState(() => _confirmingLivePass = true);

    // Snapshot the tracker's data BEFORE stopping the session (stopping
    // tears down the tracker).
    final selection = _project?.selectedInputDevice;
    final representativeDbFs = tracker.latestDbFs;
    final peakDbFs = tracker.peakDbFsInWindow;
    final stableDuration = tracker.trackedDuration;

    await _stopLiveLevelCheckSession();
    if (!mounted) return;

    if (selection == null || representativeDbFs == null || peakDbFs == null) {
      // Shouldn't happen (isStableGood already guarantees tracked data
      // exists), but fail closed rather than persist bogus evidence.
      // (stableDuration is non-nullable — LiveLevelStabilityTracker.
      // trackedDuration always returns a real Duration, Duration.zero when
      // empty — so it's never the cause of this branch.)
      setState(() => _confirmingLivePass = false);
      return;
    }

    final ctrl = ref.read(mic.micMeasurementProvider.notifier);
    final result = ctrl.buildLiveLevelPassEvidence(
      inputSelection: selection,
      representativeDbFs: representativeDbFs,
      peakDbFs: peakDbFs,
      stableDuration: stableDuration,
    );
    setState(() {
      _levelCheckResult = result;
      _confirmingLivePass = false;
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
      // The REAL current value, always — never nulled out. Persistence
      // (_maybePersistReadiness) must see the actual state. Hiding a STALE
      // Input Level blocker while a live session is active is a
      // presentation-layer concern only — see _displayBlockers(), used by
      // _resultSection — not something this preview object itself should
      // fake by dropping real evaluation data.
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
    if (preview == null || !preview.isReady) {
      return;
    }
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
                  _liveLevelCheckSection(),
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
        // Final QA closure #3 §4 — permission-denied, enumeration-failed,
        // and device-temporarily-absent are three DIFFERENT facts and must
        // never collapse into one message. A permission denial does not
        // mean devices weren't found (macOS still enumerates them; using
        // one just fails), and a transient enumeration exception is not a
        // permission problem at all — see _refreshDevices()'s two
        // independently-tracked fields (_permissionGranted,
        // _enumerationError).
        if (_permissionGranted == false)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              const Expanded(
                  child: Text('마이크 접근 권한이 필요합니다.',
                      style: TextStyle(color: kProRed, fontSize: 11))),
              TextButton(
                  onPressed: _requestPermission, child: const Text('Allow')),
            ]),
          ),
        if (_enumerationError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('장치 목록을 가져오지 못했습니다: $_enumerationError',
                style: const TextStyle(color: kProRed, fontSize: 11)),
          ),
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

  /// Beginner-facing primary entry point: a continuous live meter that
  /// guides the user to the right speaker volume. Three states —
  /// TOO LOW / GOOD-but-not-yet-stable / STABLE GOOD — with an explicit
  /// [이 레벨로 확인] confirm button that unlocks only once stable, PLUS the
  /// existing auto-confirm (both call the SAME _confirmLiveLevelPass()).
  /// [중지] always means cancel — never a PASS. No raw numbers here; Expert
  /// Details shows the actual dBFS.
  Widget _liveLevelCheckSection() {
    final isStableNow = _stabilityTracker?.isStableGood == true;
    final (statusLabel, statusColor, guidance) = switch (_liveReading?.status) {
      null => ('', Colors.transparent, ''),
      LiveLevelStatus.tooLow => ('너무 낮음', kProAmber, '스피커 볼륨을 조금 높여 주세요.'),
      LiveLevelStatus.good => isStableNow
          ? ('측정 레벨 확인됨', kProGreen, '측정 레벨이 확인되었습니다.')
          : ('적정 범위', kProGreen, '적정 범위입니다. 잠시 유지해 주세요.'),
      LiveLevelStatus.tooHigh => ('너무 높음', kProRed, '스피커 볼륨을 조금 낮춰 주세요.'),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('4. INPUT LEVEL', style: proLabel(size: 10)),
        const SizedBox(height: 4),
        // Same beginner-facing speaker guidance the manual check has always
        // shown — deliberately no "mono" wording here either.
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
        Text('버튼을 누르면 테스트 신호가 계속 재생됩니다. 미터가 "적정 범위"에서 '
            '잠시 유지되면 [이 레벨로 확인]을 눌러 확정하세요.', style: proSubtitle(size: 11)),
        const SizedBox(height: 8),
        Row(children: [
          OutlinedButton(
            onPressed: (_liveCheckActive || _confirmingLivePass)
                ? null
                : _startLiveLevelCheck,
            child: Text(_confirmingLivePass ? '확인 중…' : '측정 레벨 맞추기'),
          ),
          if (_liveCheckActive) ...[
            const SizedBox(width: 8),
            // [이 레벨로 확인] — commit. Enabled ONLY once sustained GOOD is
            // actually reached; never treated as available on a single tick.
            OutlinedButton(
              onPressed: (isStableNow && !_confirmingLivePass)
                  ? () => unawaited(_confirmLiveLevelPass())
                  : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: kProGreen,
                side: BorderSide(
                    color: isStableNow ? kProGreen : kProBorder),
              ),
              child: const Text('이 레벨로 확인'),
            ),
            const SizedBox(width: 8),
            // [중지] — cancel. Never itself a PASS, regardless of the
            // current reading.
            OutlinedButton(
              onPressed: () => unawaited(_cancelLiveLevelCheck()),
              child: const Text('중지'),
            ),
          ],
        ]),
        if (_liveCheckActive) ...[
          const SizedBox(height: 10),
          Text('테스트 신호 재생 중', style: proSubtitle(size: 11, color: kProAccent)),
          const SizedBox(height: 6),
          // Simple bar meter — no raw dB required to read it. Clamped to the
          // policy's own min/max RMS window so the bar position visually
          // matches the same thresholds driving the tooLow/good/tooHigh
          // classification (no separate, invented visual scale).
          _LiveLevelMeterBar(
            reading: _liveReading,
            minDbFs: _policy.minimumSignalRmsDbFs,
            maxDbFs: _policy.maximumSignalRmsDbFs,
          ),
          const SizedBox(height: 6),
          if (_liveReading != null) ...[
            Text(statusLabel,
                style: proValue(size: 13, color: statusColor)),
            Text(guidance, style: proSubtitle(size: 11)),
          ],
        ],
        if (_liveCheckError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_liveCheckError!,
                style: const TextStyle(color: kProRed, fontSize: 11)),
          ),
        // Fresh live-sourced PASS evidence, session already stopped —
        // "입력 레벨 확인 완료". Only for THIS dialog session's own live
        // confirmation (metrics.source == 'liveMeter'), not a stale/manual
        // legacy result, so this never mislabels an old check as live.
        if (!_liveCheckActive &&
            !_confirmingLivePass &&
            _levelCheckResult?.isSuccess == true &&
            _levelCheckResult?.evaluation?.metrics.source == 'liveMeter')
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              const Icon(Icons.check_circle, size: 14, color: kProGreen),
              const SizedBox(width: 6),
              Text('입력 레벨 확인 완료', style: proValue(size: 12, color: kProGreen)),
            ]),
          ),
      ],
    );
  }

  /// The original fixed-3s manual level check — kept for expert/manual/
  /// compatibility use (see Closure #3 item 9). No longer the beginner
  /// primary path; also the method the live check's auto-trigger calls
  /// internally once sustained GOOD is confirmed, so this is never dead
  /// code even though the button itself is now expert-only.
  Widget _levelCheckSection() {
    final eval = _levelCheckResult?.evaluation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('MANUAL LEVEL CHECK (fixed 3s)', style: proLabel(size: 10)),
        const SizedBox(height: 8),
        // Speaker-side guidance is shown once, in the live level check
        // section above (the primary beginner path) — not duplicated here
        // to avoid two copies of the same sentence being visible at once
        // when Expert Details is expanded.
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

  // Presentation-layer only (item 4 of the P0 fix): the exact set of
  // MeasurementSetupReadinessBuilder blocker strings that are specifically
  // about the Input Level check (never the persisted evaluation/blockers
  // themselves — _buildPreview() always carries the REAL, unfiltered
  // values, which is what _maybePersistReadiness actually persists). While
  // a live session is active, these are hidden from DISPLAY only — a stale
  // prior failure (or the "has not been run yet" default) must never sit
  // next to a live meter that's currently showing 적정/안정.
  static const Set<String> _inputLevelBlockerStrings = {
    'Input signal is too low.',
    'Input signal is too loud, causing distortion.',
    'Input level capture was too short.',
    'Input level signal is clipping.',
    'Input-level check has not been run yet.',
    'Signal-to-noise ratio is too low.',
  };

  List<String> _displayBlockers(MeasurementSetupReadinessSnapshot preview) {
    if (!_liveCheckActive) return preview.blockers;
    return preview.blockers
        .where((b) => !_inputLevelBlockerStrings.contains(b))
        .toList();
  }

  Widget _resultSection(MeasurementSetupReadinessSnapshot preview) {
    final displayBlockers = _displayBlockers(preview);
    // isReady itself is NEVER faked here — only which blocker STRINGS are
    // shown. If live-active happens to be the only remaining blocker
    // category, the card still correctly shows "not ready" (an active live
    // session is, correctly, not yet a completed setup) — it just does so
    // without the confusing stale-failure text.
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
          for (final b in displayBlockers)
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
        // The original finite (fixed 3s) manual level check — kept, not
        // deleted, for expert/manual/compatibility use. The beginner-facing
        // primary path is now the live level check above.
        if (_expertExpanded) _levelCheckSection(),
        if (_expertExpanded && _liveReading != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 6),
            child: Text(
              'Live: current=${_liveReading!.currentDbFs.toStringAsFixed(1)} dBFS '
              'status=${_liveReading!.status.name}',
              style: proSubtitle(size: 10),
            ),
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

/// A simple bar meter for the live level check — deliberately not a raw dB
/// readout. Position/fill reflects [reading]'s currentDbFs clamped into
/// [minDbFs, maxDbFs] (the SAME thresholds driving the tooLow/good/tooHigh
/// classification, never a separately-invented visual scale), colored by
/// [reading]'s own status.
class _LiveLevelMeterBar extends StatelessWidget {
  final LiveLevelReading? reading;
  final double minDbFs;
  final double maxDbFs;

  const _LiveLevelMeterBar({
    required this.reading,
    required this.minDbFs,
    required this.maxDbFs,
  });

  @override
  Widget build(BuildContext context) {
    final r = reading;
    final color = switch (r?.status) {
      null => Colors.white24,
      LiveLevelStatus.tooLow => kProAmber,
      LiveLevelStatus.good => kProGreen,
      LiveLevelStatus.tooHigh => kProRed,
    };
    final fraction = r == null
        ? 0.0
        : ((r.currentDbFs - minDbFs) / (maxDbFs - minDbFs)).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Container(
        height: 14,
        color: kProSurface,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: fraction,
          child: Container(color: color.withValues(alpha: 0.85)),
        ),
      ),
    );
  }
}
