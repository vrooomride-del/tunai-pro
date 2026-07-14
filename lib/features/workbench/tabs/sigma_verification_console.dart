// ── TUNAI PRO — ADAU1466 Sigma Export Hardware Verification Console ────────────
// Lists ALL candidates from the embedded CSV and provides a controlled
// test+restore write path via ProUsbiSigmaVerificationExecutor.
//
// ABSOLUTE RESTRICTIONS:
//   - No EEPROM. No Selfboot. No WriteAll.
//   - XO remains hard-blocked (OUTPUT_MAPPING_NOT_VERIFIED).
//   - PEQ remains blocked (SAFELOAD_NOT_VALIDATED).
//   - SafeLoad write blocked (SAFELOAD_NOT_VALIDATED).
//   - VERIFIED = operator manual mark only — not set by ACK alone.
//   - wasActualWrite = true only when executor calls real backend.
//   - USBi is TEMPORARY. ICP5 is the final target.

import 'package:flutter/material.dart';
import '../../../core/pro_usbi_native_backend.dart';
import '../../../core/pro_usbi_packet_builder.dart';
import '../../../core/pro_adau1466_sigma_candidate.dart';
import '../../../core/pro_adau1466_sigma_loader.dart';
import '../../../core/pro_adau1466_sigma_executor.dart';
import '../../../core/pro_adau1466_mute_validation_executor.dart';
import '../../../core/pro_adau1466_gain_safeload_executor.dart';
import '../../../core/pro_adau1466_sigma_persistence.dart';
import '../../../shared/pro_widgets.dart';

// ── Widget ────────────────────────────────────────────────────────────────────

class SigmaVerificationConsole extends StatefulWidget {
  final ProUsbiNativeBackend backend;
  final bool Function() isWindowsPlatform;
  final bool deviceOpen;
  final bool dspWritesDisabled;
  final bool muteDiagnosticUsedThisSession;
  final bool gainDiagnosticUsedThisSession;
  final VoidCallback? onMuteDiagnosticConsumed;
  final VoidCallback? onGainDiagnosticConsumed;
  final void Function(String warning)? onDspWriteStop;

  const SigmaVerificationConsole({
    super.key,
    required this.backend,
    required this.isWindowsPlatform,
    required this.deviceOpen,
    this.dspWritesDisabled = false,
    this.muteDiagnosticUsedThisSession = false,
    this.gainDiagnosticUsedThisSession = false,
    this.onMuteDiagnosticConsumed,
    this.onGainDiagnosticConsumed,
    this.onDspWriteStop,
  });

  @override
  State<SigmaVerificationConsole> createState() =>
      _SigmaVerificationConsoleState();
}

class _SigmaVerificationConsoleState extends State<SigmaVerificationConsole> {
  // ── Loaded data ──────────────────────────────────────────────────────────
  late SigmaLoadResult _loadResult;
  late List<Adau1466SigmaCandidate> _candidates;
  late ProUsbiSigmaVerificationExecutor _executor;
  late ProAdau1466MuteValidationExecutor _muteExecutor;
  late ProAdau1466GainSafeLoadExecutor _gainExecutor;

  // ── Filter / selection ───────────────────────────────────────────────────
  CandidateKind? _filterKind;
  Adau1466SigmaCandidate? _selected;

  // ── Test config ──────────────────────────────────────────────────────────
  TestProfile _testProfile = TestProfile.linear824;
  String _testValueHex   = '0x01000000';
  String _restoreValueHex = '0x01000000';
  bool _userConfirmed = false;
  bool _restoreConfirmed = false;

  // ── Execution ────────────────────────────────────────────────────────────
  bool _executing = false;
  SigmaVerificationWriteResult? _lastResult;
  int? _smokeTestingAddress;
  final Map<int, SigmaVerificationWriteResult> _smokeResults = {};
  bool _muteDiagnosticRunning = false;
  Adau1466MuteValidationResult? _muteDiagnosticResult;
  bool _gainDiagnosticRunning = false;
  Adau1466GainSafeLoadResult? _gainDiagnosticResult;

  // ── Log ──────────────────────────────────────────────────────────────────
  List<SigmaValidationLogEntry> _log = [];

  @override
  void initState() {
    super.initState();
    _loadResult = SigmaAddressLoader.load();
    _candidates = List.from(_loadResult.candidates);
    _executor = ProUsbiSigmaVerificationExecutor(
      backend: widget.backend,
      isWindowsPlatform: widget.isWindowsPlatform,
    );
    _muteExecutor = ProAdau1466MuteValidationExecutor(
      backend: widget.backend,
      isWindowsPlatform: widget.isWindowsPlatform,
    );
    _gainExecutor = ProAdau1466GainSafeLoadExecutor(
      backend: widget.backend,
      isWindowsPlatform: widget.isWindowsPlatform,
    );
    _loadPersisted();
  }

  @override
  void didUpdateWidget(covariant SigmaVerificationConsole oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.deviceOpen && widget.deviceOpen) {
      _muteDiagnosticResult = null;
      _gainDiagnosticResult = null;
    }
  }

  Future<void> _loadPersisted() async {
    final saved = await SigmaVerificationPersistence.loadCandidates();
    final log   = await SigmaVerificationPersistence.loadLog();
    if (!mounted) return;
    if (saved != null && saved.length == _candidates.length) {
      normalizeAdau1466VerificationStatuses(saved);
      setState(() {
        _candidates = saved;
        _log = log;
      });
    } else {
      setState(() => _log = log);
    }
  }

  Future<void> _persist() async {
    await SigmaVerificationPersistence.saveCandidates(_candidates);
    await SigmaVerificationPersistence.saveLog(_log);
  }

  List<Adau1466SigmaCandidate> get _filtered =>
      _filterKind == null
          ? _candidates
          : _candidates.where((c) => c.kind == _filterKind).toList();

  void _selectCandidate(Adau1466SigmaCandidate c) {
    setState(() {
      _selected = c;
      _userConfirmed = false;
      _restoreConfirmed = false;
      _lastResult = null;
      _testProfile = _defaultProfile(c.kind);
      _updateTestValues();
    });
  }

  TestProfile _defaultProfile(CandidateKind kind) => switch (kind) {
    CandidateKind.masterVolume => TestProfile.linear824,
    CandidateKind.mute         => TestProfile.muteA,
    CandidateKind.gain         => TestProfile.linear824,
    CandidateKind.delay        => TestProfile.delayStep,
    _                          => TestProfile.raw32bit,
  };

  void _updateTestValues() {
    final exportHex = _selected?.exportDefaultHex ?? '0x01000000';
    switch (_testProfile) {
      case TestProfile.muteA:
        _testValueHex    = '0x01000000';
        _restoreValueHex = exportHex.isEmpty ? '0x01000000' : exportHex;
      case TestProfile.muteB:
        _testValueHex    = '0x00000000';
        _restoreValueHex = exportHex.isEmpty ? '0x01000000' : exportHex;
      case TestProfile.linear824:
        _testValueHex    = '0x00800000'; // 0.5 in 8.24
        _restoreValueHex = exportHex.isEmpty ? '0x01000000' : exportHex;
      case TestProfile.delayStep:
        _testValueHex    = '0x00000001';
        _restoreValueHex = exportHex.isEmpty ? '0x00000000' : exportHex;
      case TestProfile.raw32bit:
        _testValueHex    = '0x00000001';
        _restoreValueHex = exportHex.isEmpty ? '0x00000000' : exportHex;
      case TestProfile.restoreOnly:
        _testValueHex    = exportHex.isEmpty ? '0x01000000' : exportHex;
        _restoreValueHex = exportHex.isEmpty ? '0x01000000' : exportHex;
    }
  }

  bool get _canExecute {
    final c = _selected;
    if (c == null) return false;
    if (c.validationStatus == CandidateValidationStatus.blocked) return false;
    if (!_userConfirmed) return false;
    if (!_restoreConfirmed) return false;
    if (_executing) return false;
    if (widget.dspWritesDisabled) return false;
    return true;
  }

  Future<void> _execute() async {
    final c = _selected;
    if (c == null || !_canExecute) return;

    setState(() => _executing = true);

    final testVal    = int.tryParse(_testValueHex.replaceFirst('0x', ''),
        radix: 16) ?? 0;
    final restoreVal = int.tryParse(_restoreValueHex.replaceFirst('0x', ''),
        radix: 16) ?? 0;

    final req = SigmaVerificationWriteRequest(
      id:                   'sigma_${c.addressHex}_${DateTime.now().millisecondsSinceEpoch}',
      addressInt:           c.addressInt,
      addressHex:           c.addressHex,
      label:                c.logicalName.isEmpty ? c.rawName : c.logicalName,
      testValue32:          testVal,
      restoreValue32:       restoreVal,
      userConfirmed:        _userConfirmed,
      restoreValueConfirmed: _restoreConfirmed,
    );

    final result = await _executor.writeWithRestore(req);

    // Mutate candidate state
    c.wasActualWrite        = result.testWasActualWrite;
    c.lastTestValueHex      = _testValueHex;
    c.lastRestoreValueHex   = _restoreValueHex;
    c.lastTestBodyHex       = result.testBodyHex;
    c.lastRestoreBodyHex    = result.restoreBodyHex;
    c.lastAckBytes          = result.testAckBytes;
    c.lastRestoreAckBytes   = result.restoreAckBytes;
    c.timestamp             = result.executedAt;
    if (c.validationStatus != CandidateValidationStatus.blocked &&
        c.validationStatus != CandidateValidationStatus.verified) {
      c.validationStatus = result.resultStatus;
    }

    // Append log entry
    final entry = SigmaValidationLogEntry(
      timestamp:            result.executedAt,
      addressInt:           c.addressInt,
      addressHex:           c.addressHex,
      rawName:              c.rawName,
      kind:                 c.kind.name,
      testProfile:          _testProfile.name,
      testValueHex:         _testValueHex,
      restoreValueHex:      _restoreValueHex,
      testBodyHex:          result.testBodyHex,
      restoreBodyHex:       result.restoreBodyHex,
      testAckBytes:         result.testAckBytes,
      restoreAckBytes:      result.restoreAckBytes,
      testWasActualWrite:   result.testWasActualWrite,
      restoreWasActualWrite: result.restoreWasActualWrite,
      resultStatus:         result.resultStatus.name,
      error:                result.error,
      transport:            result.backendName,
      sigmaSignature:       _loadResult.signature.checksum,
    );

    if (mounted) {
      setState(() {
        _executing  = false;
        _lastResult = result;
        _log = [entry, ..._log.take(49)];
      });
    }

    await _persist();
  }

  Future<void> _runMasterVolumeSmokeTest(int address, String label) async {
    if (_smokeTestingAddress != null ||
        !widget.deviceOpen ||
        widget.dspWritesDisabled) {
      return;
    }
    setState(() => _smokeTestingAddress = address);
    final result = await _executor.writeWithRestore(SigmaVerificationWriteRequest(
      id: 'mv_smoke_${address.toRadixString(16)}_${DateTime.now().millisecondsSinceEpoch}',
      addressInt: address,
      addressHex: '0x${address.toRadixString(16).padLeft(4, '0').toUpperCase()}',
      label: label,
      testValue32: 0x00800000,
      restoreValue32: 0x01000000,
      userConfirmed: true,
      restoreValueConfirmed: true,
    ));
    if (!mounted) return;
    setState(() {
      _smokeTestingAddress = null;
      _smokeResults[address] = result;
    });
  }

  Future<void> _runMuteDiagnostic() async {
    if (_muteDiagnosticRunning ||
        widget.muteDiagnosticUsedThisSession ||
        widget.dspWritesDisabled ||
        !widget.deviceOpen ||
        !_muteExecutor.isRealExecutorAvailable) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm one-shot Mute1_3 diagnostic'),
        content: const Text(
          'This performs one volatile test write to 0x060E with value 0, then '
          'always attempts to restore value 1. It can run only once during '
          'this USBi device-open session. ACK means PASS_ACK only, not VERIFIED.',
        ),
        actions: [
          TextButton(
            key: const Key('cancel-mute-diagnostic'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-mute-diagnostic'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirm and Run Once'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    widget.onMuteDiagnosticConsumed?.call();
    setState(() {
      _muteDiagnosticRunning = true;
      _muteDiagnosticResult = null;
    });
    final result = await _muteExecutor.runSmokeTest(
      addressInt: ProAdau1466MuteValidationExecutor.mute1_3Address,
      deviceOpen: widget.deviceOpen,
    );
    if (!mounted) return;
    setState(() {
      _muteDiagnosticRunning = false;
      _muteDiagnosticResult = result;
    });
    if (!result.restoreReturnedRawAck01) {
      widget.onDspWriteStop?.call(
        'STOP — Mute1_3 restore did not return raw ACK 01. '
        'All further DSP writes are disabled for this device-open session.',
      );
    }
  }

  Future<void> _runGainDiagnostic() async {
    if (_gainDiagnosticRunning ||
        widget.gainDiagnosticUsedThisSession ||
        widget.dspWritesDisabled ||
        !widget.deviceOpen ||
        !_gainExecutor.isRealExecutorAvailable) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm one-shot Gain Single 1 diagnostic'),
        content: const Text(
          'This runs the capture-proven three-stage TEST SafeLoad sequence for '
          'target 0x03B8, then always runs the complete three-stage RESTORE '
          'sequence. It can run only once during this USBi device-open session. '
          'ACK means PASS_ACK only, not VERIFIED.',
        ),
        actions: [
          TextButton(
            key: const Key('cancel-gain-diagnostic'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-gain-diagnostic'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirm and Run Once'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    widget.onGainDiagnosticConsumed?.call();
    setState(() {
      _gainDiagnosticRunning = true;
      _gainDiagnosticResult = null;
    });
    final result = await _gainExecutor.runDiagnostic(
      requestedTargetAddress: ProAdau1466GainSafeLoadExecutor.targetAddress,
      requestedTestValue: ProAdau1466GainSafeLoadExecutor.testGainValue,
      requestedRestoreValue: ProAdau1466GainSafeLoadExecutor.restoreGainValue,
      deviceOpen: widget.deviceOpen,
    );
    if (!mounted) return;
    setState(() {
      _gainDiagnosticRunning = false;
      _gainDiagnosticResult = result;
    });
    if (!result.allRestoreStagesReturnedRawAck01) {
      widget.onDspWriteStop?.call(
        'STOP — Gain Single 1 restore did not return raw ACK 01 for all '
        'three stages. All further DSP writes are disabled for this '
        'device-open session.',
      );
    }
  }

  void _markVerified() {
    final c = _selected;
    if (c == null) return;
    if (!c.wasActualWrite) return;
    setState(() => c.validationStatus = CandidateValidationStatus.verified);
    _persist();
  }

  void _markRejected() {
    final c = _selected;
    if (c == null) return;
    setState(() => c.validationStatus = CandidateValidationStatus.rejected);
    _persist();
  }

  Future<void> _clearAll() async {
    await SigmaVerificationPersistence.clearAll();
    final fresh = SigmaAddressLoader.load();
    if (!mounted) return;
    setState(() {
      _loadResult = fresh;
      _candidates = List.from(fresh.candidates);
      _selected   = null;
      _lastResult = null;
      _log        = [];
    });
  }

  // ── Summary counts ────────────────────────────────────────────────────────
  int get _verifiedCount =>
      _candidates.where((c) => c.validationStatus == CandidateValidationStatus.verified).length;
  int get _passAckCount =>
      _candidates.where((c) => c.validationStatus == CandidateValidationStatus.passAck).length;
  int get _blockedCount =>
      _candidates.where((c) => c.validationStatus == CandidateValidationStatus.blocked).length;
  int get _candidateCount =>
      _candidates.where((c) => c.validationStatus == CandidateValidationStatus.candidate).length;
  int get _failCount =>
      _candidates.where((c) => c.validationStatus == CandidateValidationStatus.fail).length;

  @override
  Widget build(BuildContext context) {
    final isWindows = widget.isWindowsPlatform();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _MasterVolumeVerificationPanel(
        backendAvailable: widget.backend.isAvailable,
        isWindows: isWindows,
        deviceOpen: widget.deviceOpen,
        executingAddress: _smokeTestingAddress,
        dspWritesDisabled: widget.dspWritesDisabled,
        results: _smokeResults,
        onSmokeTest: _runMasterVolumeSmokeTest,
      ),
      const SizedBox(height: 12),
      _MuteValidationPanel(
        executorAvailable: _muteExecutor.isRealExecutorAvailable,
        deviceOpen: widget.deviceOpen,
        running: _muteDiagnosticRunning,
        usedThisSession: widget.muteDiagnosticUsedThisSession,
        dspWritesDisabled: widget.dspWritesDisabled,
        result: _muteDiagnosticResult,
        onRun: _runMuteDiagnostic,
      ),
      const SizedBox(height: 12),
      _GainSafeLoadDiagnosticPanel(
        executorAvailable: _gainExecutor.isRealExecutorAvailable,
        deviceOpen: widget.deviceOpen,
        running: _gainDiagnosticRunning,
        usedThisSession: widget.gainDiagnosticUsedThisSession,
        dspWritesDisabled: widget.dspWritesDisabled,
        result: _gainDiagnosticResult,
        onRun: _runGainDiagnostic,
      ),
      const SizedBox(height: 12),
      // ── S1: Console header ──────────────────────────────────────────────
      _ConsoleHeader(
        loadResult: _loadResult,
        verifiedCount: _verifiedCount,
        passAckCount: _passAckCount,
        blockedCount: _blockedCount,
        candidateCount: _candidateCount,
        failCount: _failCount,
        onClearAll: _clearAll,
      ),
      const SizedBox(height: 12),

      // ── S2: Safety banner ────────────────────────────────────────────────
      _SafetyBanner(isWindows: isWindows, deviceOpen: widget.deviceOpen),
      const SizedBox(height: 12),

      // ── S3: Kind filter ──────────────────────────────────────────────────
      _KindFilterRow(
        selected: _filterKind,
        kindCounts: _loadResult.kindCounts,
        onSelect: (k) => setState(() {
          _filterKind = k;
          _selected   = null;
          _lastResult = null;
        }),
      ),
      const SizedBox(height: 8),

      // ── S4: Candidate list ───────────────────────────────────────────────
      _CandidateList(
        candidates: _filtered,
        selected: _selected,
        onSelect: _selectCandidate,
      ),
      const SizedBox(height: 12),

      // ── S5: Candidate detail + execute panel ─────────────────────────────
      if (_selected != null)
        _CandidateDetailPanel(
          candidate: _selected!,
          testProfile: _testProfile,
          testValueHex: _testValueHex,
          restoreValueHex: _restoreValueHex,
          userConfirmed: _userConfirmed,
          restoreConfirmed: _restoreConfirmed,
          executing: _executing,
          canExecute: _canExecute,
          lastResult: _lastResult,
          isWindows: isWindows,
          deviceOpen: widget.deviceOpen,
          onProfileChanged: (p) => setState(() {
            _testProfile = p;
            _updateTestValues();
          }),
          onTestHexChanged: (v) => setState(() => _testValueHex = v),
          onRestoreHexChanged: (v) => setState(() => _restoreValueHex = v),
          onConfirmChanged: (v) => setState(() {
            _userConfirmed = v;
            _lastResult    = null;
          }),
          onRestoreConfirmChanged: (v) => setState(() {
            _restoreConfirmed = v;
            _lastResult       = null;
          }),
          onExecute: _execute,
          onMarkVerified: _markVerified,
          onMarkRejected: _markRejected,
        ),

      // ── S6: Validation log ───────────────────────────────────────────────
      if (_log.isNotEmpty) ...[
        const SizedBox(height: 12),
        _ValidationLog(log: _log),
      ],

      // ── S7: Export warnings ──────────────────────────────────────────────
      if (_loadResult.warnings.isNotEmpty) ...[
        const SizedBox(height: 12),
        _WarningsPanel(warnings: _loadResult.warnings),
      ],
    ]);
  }
}

class _MuteValidationPanel extends StatelessWidget {
  final bool executorAvailable;
  final bool deviceOpen;
  final bool running;
  final bool usedThisSession;
  final bool dspWritesDisabled;
  final Adau1466MuteValidationResult? result;
  final VoidCallback onRun;

  const _MuteValidationPanel({
    required this.executorAvailable,
    required this.deviceOpen,
    required this.running,
    required this.usedThisSession,
    required this.dspWritesDisabled,
    required this.result,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    final canRun = executorAvailable && deviceOpen && !running &&
        !usedThisSession && !dspWritesDisabled;
    return Container(
      key: const Key('adau1466-mute1-3-validation-ui'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF171525),
        border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Mute1_3',
            style: TextStyle(fontSize: 13, color: Colors.purpleAccent,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const _StatusText('Address 0x060E'),
        const _StatusText('Captured states: unchecked=0, checked=1'),
        const _StatusText('Current assumed baseline: 1'),
        _StatusText('real executor status: ${executorAvailable ? "available" : "unavailable"}'),
        _StatusText('USBi device-open status: ${deviceOpen ? "open" : "closed"}'),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('controlled-mute-smoke-test'),
          onPressed: canRun ? onRun : null,
          child: Text(running
              ? 'Mute Diagnostic Running…'
              : 'Run One-Shot Mute Diagnostic'),
        ),
        const SizedBox(height: 8),
        _StatusText('one-shot session status: ${usedThisSession ? "used" : "available"}'),
        _StatusText('test ACK status: ${result == null ? "not run" : result!.testAckOk ? "PASS_ACK" : "FAIL"}'),
        _StatusText('restore ACK status: ${result == null ? "not run" : result!.restoreReturnedRawAck01 ? "PASS_ACK" : "FAIL"}'),
        _StatusText('wasActualWrite status: ${result?.wasActualWrite ?? false}'),
        const _StatusText('audible verification pending'),
        const SizedBox(height: 8),
        _NativeTransactionDiagnosticsPanel(
          title: 'TEST TRANSACTION DIAGNOSTICS',
          diagnostics: result?.testDiagnostics,
        ),
        const SizedBox(height: 8),
        _NativeTransactionDiagnosticsPanel(
          title: 'RESTORE TRANSACTION DIAGNOSTICS',
          diagnostics: result?.restoreDiagnostics,
        ),
        if (result != null && !result!.restoreReturnedRawAck01) ...[
          const SizedBox(height: 8),
          const Text(
            'STOP — RESTORE DID NOT RETURN RAW ACK 01. ALL FURTHER DSP WRITES '
            'ARE DISABLED FOR THIS DEVICE-OPEN SESSION.',
            key: Key('mute-diagnostic-stop-warning'),
            style: TextStyle(fontSize: 11, color: Colors.redAccent,
                fontWeight: FontWeight.w900, height: 1.35),
          ),
        ],
        const SizedBox(height: 7),
        const Text(
          'One-shot volatile diagnostic only. No automatic retry. '
          'Physical WFL / OUT3 mapping remains pending. ACK means PASS_ACK only, never VERIFIED. '
          'All other Mute addresses, Gain, Delay, XO, PEQ, SafeLoad, unknown addresses, EEPROM, and Selfboot remain blocked.',
          style: TextStyle(fontSize: 8, color: Colors.white38, height: 1.4),
        ),
      ]),
    );
  }
}

class _GainSafeLoadDiagnosticPanel extends StatelessWidget {
  final bool executorAvailable;
  final bool deviceOpen;
  final bool running;
  final bool usedThisSession;
  final bool dspWritesDisabled;
  final Adau1466GainSafeLoadResult? result;
  final VoidCallback onRun;

  const _GainSafeLoadDiagnosticPanel({
    required this.executorAvailable,
    required this.deviceOpen,
    required this.running,
    required this.usedThisSession,
    required this.dspWritesDisabled,
    required this.result,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    final canRun = executorAvailable && deviceOpen && !running &&
        !usedThisSession && !dspWritesDisabled;
    final stages = result == null
        ? const <Adau1466GainSafeLoadStageResult>[]
        : [...result!.testStages, ...result!.restoreStages];
    return Container(
      key: const Key('adau1466-gain-single-1-diagnostic-ui'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B18),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Gain Single 1',
            style: TextStyle(fontSize: 13, color: Colors.greenAccent,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const _StatusText('Target address 0x03B8'),
        const _StatusText('Slew address 0x03B9'),
        const _StatusText('Test value 0x00000840'),
        const _StatusText('Restore value 0x0000068E'),
        _StatusText('real executor status: ${executorAvailable ? "available" : "unavailable"}'),
        _StatusText('USBi device-open status: ${deviceOpen ? "open" : "closed"}'),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('run-one-shot-gain-diagnostic'),
          onPressed: canRun ? onRun : null,
          child: Text(running
              ? 'Gain Diagnostic Running…'
              : 'Run One-Shot Gain Diagnostic'),
        ),
        const SizedBox(height: 8),
        _StatusText('one-shot session status: ${usedThisSession ? "used" : "available"}'),
        _StatusText('wasActualWrite status: ${result?.wasActualWrite ?? false}'),
        const _StatusText('audible verification pending'),
        const _StatusText('physical WFL / OUT3 mapping pending'),
        const SizedBox(height: 8),
        for (var index = 0; index < 6; index++) ...[
          _GainStageDiagnosticsPanel(
            title: index < 3
                ? 'TEST stage ${index + 1}'
                : 'RESTORE stage ${index - 2}',
            result: index < stages.length ? stages[index] : null,
          ),
          if (index != 5) const SizedBox(height: 8),
        ],
        if (result != null && result!.restoreFailed) ...[
          const SizedBox(height: 8),
          const Text(
            'STOP — RESTORE DID NOT RETURN RAW ACK 01 FOR ALL THREE STAGES. '
            'ALL FURTHER DSP WRITES ARE DISABLED FOR THIS DEVICE-OPEN SESSION.',
            key: Key('gain-diagnostic-stop-warning'),
            style: TextStyle(fontSize: 11, color: Colors.redAccent,
                fontWeight: FontWeight.w900, height: 1.35),
          ),
        ],
        const SizedBox(height: 7),
        const Text(
          'Capture-locked one-shot diagnostic only. No automatic retry. '
          'ACK is PASS_ACK only, not VERIFIED. All other Gain and Mute '
          'addresses, XO, PEQ, Delay, unknown addresses, EEPROM, and Selfboot '
          'remain blocked.',
          style: TextStyle(fontSize: 8, color: Colors.white38, height: 1.4),
        ),
      ]),
    );
  }
}

class _GainStageDiagnosticsPanel extends StatelessWidget {
  final String title;
  final Adau1466GainSafeLoadStageResult? result;

  const _GainStageDiagnosticsPanel({required this.title, required this.result});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _StatusText('$title ACK: ${result == null ? "not run" : result!.ackOk ? "PASS_ACK" : "FAIL"}'),
      _NativeTransactionDiagnosticsPanel(
        title: '$title DIAGNOSTICS',
        diagnostics: result?.diagnostics,
      ),
    ],
  );
}

class _NativeTransactionDiagnosticsPanel extends StatelessWidget {
  final String title;
  final UsbiNativeTransactionDiagnostics? diagnostics;

  const _NativeTransactionDiagnosticsPanel({
    required this.title,
    required this.diagnostics,
  });

  String _transferLabel(bool? success) => success == null
      ? 'not captured'
      : success ? 'success' : 'failure';

  String _hex(List<int>? bytes) =>
      bytes == null ? 'not captured' : bytesToHex(bytes);

  @override
  Widget build(BuildContext context) {
    final d = diagnostics;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 9, color: Colors.white54,
          fontWeight: FontWeight.w700)),
      _StatusText('setup packet: ${_hex(d?.setupPacket)}'),
      _StatusText('body packet: ${_hex(d?.bodyPacket)}'),
      _StatusText('setup transfer result: ${_transferLabel(d?.setupTransferSuccess)}'),
      _StatusText('body transfer result: ${_transferLabel(d?.bodyTransferSuccess)} '
          '(included in setup control transfer)'),
      _StatusText('bytes transferred: ${d?.bytesTransferred ?? "not captured"}'),
      _StatusText('ACK request: ${_hex(d?.ackRequestPacket)}'),
      _StatusText('ACK read result: ${_transferLabel(d?.ackReadSuccess)}'),
      _StatusText('ACK bytes transferred: ${d?.ackBytesTransferred ?? "not captured"}'),
      _StatusText('raw ACK bytes: ${_hex(d?.rawAckBytes)}'),
      _StatusText('native exception: ${d?.nativeException ?? "none captured"}'),
      _StatusText('native transfer error: ${d?.transferError ?? "none captured"}'),
      _StatusText('ACK read error/timeout: '
          '${d?.ackReadError ?? d?.timeoutDescription ?? "not captured"}'),
      _StatusText('timing: setup=${d?.setupElapsedMilliseconds ?? "not captured"} ms · '
          'ACK=${d?.ackElapsedMilliseconds ?? "not captured"} ms'),
    ]);
  }
}

class _MasterVolumeVerificationPanel extends StatelessWidget {
  final bool backendAvailable;
  final bool isWindows;
  final bool deviceOpen;
  final int? executingAddress;
  final bool dspWritesDisabled;
  final Map<int, SigmaVerificationWriteResult> results;
  final Future<void> Function(int address, String label) onSmokeTest;

  const _MasterVolumeVerificationPanel({
    required this.backendAvailable,
    required this.isWindows,
    required this.deviceOpen,
    required this.executingAddress,
    required this.dspWritesDisabled,
    required this.results,
    required this.onSmokeTest,
  });

  String get _executorLabel {
    if (!isWindows || !backendAvailable) return 'unavailable';
    return 'real';
  }

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('adau1466-mv-verification-ui'),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF0E1A2E),
      border: Border.all(color: kProAccent.withValues(alpha: 0.45)),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('MV WRITE ACTIVE',
          style: TextStyle(fontSize: 13, color: kProAccent, fontWeight: FontWeight.w700)),
      const SizedBox(height: 3),
      const Text('MV WRITE ACTIVE · XO/PEQ BLOCKED',
          style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      _StatusText('Backend available: ${backendAvailable ? "yes" : "no"}'),
      _StatusText('Platform: ${isWindows ? "Windows" : "not Windows"}'),
      _StatusText('Executor: $_executorLabel'),
      const SizedBox(height: 8),
      const Text('Write enabled addresses:',
          style: TextStyle(fontSize: 9, color: Colors.white54, fontWeight: FontWeight.w600)),
      const _StatusText('MV L 0x0067'),
      const _StatusText('MV R 0x0064'),
      const SizedBox(height: 10),
      _MvCandidateSmokeRow(
        label: 'MV L 0x0067 candidate row',
        address: 0x0067,
        deviceOpen: deviceOpen && !dspWritesDisabled,
        executing: executingAddress == 0x0067,
        result: results[0x0067],
        onSmokeTest: () => onSmokeTest(0x0067, 'MV L'),
      ),
      const SizedBox(height: 8),
      _MvCandidateSmokeRow(
        label: 'MV R 0x0064 candidate row',
        address: 0x0064,
        deviceOpen: deviceOpen && !dspWritesDisabled,
        executing: executingAddress == 0x0064,
        result: results[0x0064],
        onSmokeTest: () => onSmokeTest(0x0064, 'MV R'),
      ),
      const SizedBox(height: 10),
      const Wrap(spacing: 12, runSpacing: 4, children: [
        _StatusText('XO blocked'),
        _StatusText('PEQ blocked'),
        _StatusText('SafeLoad blocked'),
        _StatusText('Gain blocked'),
        _StatusText('Mute blocked'),
        _StatusText('Delay blocked'),
      ]),
      const SizedBox(height: 7),
      const Text(
        'ACK means PASS_ACK only. VERIFIED requires manual audible or measured confirmation. No EEPROM or Selfboot.',
        style: TextStyle(fontSize: 8, color: Colors.white38, height: 1.4),
      ),
    ]),
  );
}

class _MvCandidateSmokeRow extends StatelessWidget {
  final String label;
  final int address;
  final bool deviceOpen;
  final bool executing;
  final SigmaVerificationWriteResult? result;
  final VoidCallback onSmokeTest;

  const _MvCandidateSmokeRow({
    required this.label,
    required this.address,
    required this.deviceOpen,
    required this.executing,
    required this.result,
    required this.onSmokeTest,
  });

  String get _addressStatus {
    final addressLabel =
        '0x${address.toRadixString(16).padLeft(4, '0').toUpperCase()}';
    if (result == null || (result!.testAckOk && result!.restoreAckOk)) {
      return '$addressLabel: PASS_ACK · audible verification pending';
    }
    return '$addressLabel: FAIL · audible verification pending';
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(label,
            style: const TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.w600))),
        OutlinedButton(
          key: Key('smoke-test-${address.toRadixString(16).padLeft(4, '0')}'),
          onPressed: deviceOpen && !executing ? onSmokeTest : null,
          child: Text(executing ? 'Smoke Test running…' : 'Smoke Test'),
        ),
      ]),
      _StatusText('ACK status: ${result == null ? "not run" : result!.testAckOk ? "PASS_ACK" : "FAIL"}'),
      _StatusText('restore status: ${result == null ? "not run" : result!.restoreAckOk ? "PASS_ACK" : "FAIL"}'),
      _StatusText('wasActualWrite status: ${result?.testWasActualWrite ?? false}'),
      _StatusText(_addressStatus),
    ]),
  );
}

class _StatusText extends StatelessWidget {
  final String text;
  const _StatusText(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Text(text, style: const TextStyle(
        fontSize: 9, color: Colors.white60, fontFamily: 'monospace')),
  );
}

// ── S1: Console Header ────────────────────────────────────────────────────────

class _ConsoleHeader extends StatelessWidget {
  final SigmaLoadResult loadResult;
  final int verifiedCount;
  final int passAckCount;
  final int blockedCount;
  final int candidateCount;
  final int failCount;
  final VoidCallback onClearAll;

  const _ConsoleHeader({
    required this.loadResult,
    required this.verifiedCount,
    required this.passAckCount,
    required this.blockedCount,
    required this.candidateCount,
    required this.failCount,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    final sig = loadResult.signature;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.science_outlined, color: kProAccent, size: 13),
          const SizedBox(width: 8),
          Text('ADAU1466 Sigma Export Verification Console',
              style: proTitle(size: 12)),
          const Spacer(),
          GestureDetector(
            onTap: onClearAll,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text('Clear All',
                  style: TextStyle(fontSize: 9, color: Colors.redAccent)),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        // Signature row
        Text(
          'Source: ${sig.sourceLabel}  ·  Rows: ${sig.rowCount}  ·  '
          'Checksum: ${sig.checksum}',
          style: proSubtitle(size: 9),
        ),
        const SizedBox(height: 6),
        // Status chips
        Wrap(spacing: 6, runSpacing: 4, children: [
          _SummaryChip('Total', loadResult.totalLoaded, Colors.white54),
          _SummaryChip('Verified', verifiedCount, Colors.greenAccent),
          _SummaryChip('PASS_ACK', passAckCount, kProAccent),
          _SummaryChip('Candidate', candidateCount, kProAmber),
          _SummaryChip('Blocked', blockedCount, Colors.orange),
          _SummaryChip('FAIL', failCount, Colors.redAccent),
          _SummaryChip('Unknown', loadResult.unknownCount, Colors.white24),
        ]),
      ]),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _SummaryChip(this.label, this.count, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      border: Border.all(color: color.withValues(alpha: 0.3)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text('$label  $count',
        style: TextStyle(fontSize: 8, color: color, fontWeight: FontWeight.w600)),
  );
}

// ── S2: Safety Banner ─────────────────────────────────────────────────────────

class _SafetyBanner extends StatelessWidget {
  final bool isWindows;
  final bool deviceOpen;
  const _SafetyBanner({required this.isWindows, required this.deviceOpen});

  @override
  Widget build(BuildContext context) {
    final ready = isWindows && deviceOpen;
    final color = ready ? kProAmber : Colors.white24;
    final msg = ready
        ? 'USBi device open. Controlled test+restore write enabled for unblocked candidates. '
          'VERIFIED = operator mark only. ACK alone ≠ VERIFIED. '
          'No EEPROM/Selfboot/WriteAll. USBi is TEMPORARY — ICP5 is final target.'
        : 'Write path inactive. ${isWindows ? "Open USBi device above." : "Windows only."} '
          'All writes remain dry-run until device is open.';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(
          ready ? Icons.warning_amber_outlined : Icons.info_outline,
          color: color,
          size: 12,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(msg, style: TextStyle(fontSize: 9, color: color, height: 1.4)),
        ),
      ]),
    );
  }
}

// ── S3: Kind Filter Row ───────────────────────────────────────────────────────

class _KindFilterRow extends StatelessWidget {
  final CandidateKind? selected;
  final Map<CandidateKind, int> kindCounts;
  final void Function(CandidateKind?) onSelect;

  const _KindFilterRow({
    required this.selected,
    required this.kindCounts,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final kinds = CandidateKind.values
        .where((k) => (kindCounts[k] ?? 0) > 0)
        .toList();
    return Wrap(spacing: 6, runSpacing: 4, children: [
      _FilterChip(
        label: 'All (${kindCounts.values.fold(0, (a, b) => a + b)})',
        selected: selected == null,
        onTap: () => onSelect(null),
      ),
      for (final k in kinds)
        _FilterChip(
          label: '${k.label} (${kindCounts[k]})',
          selected: selected == k,
          blocked: k == CandidateKind.crossover || k == CandidateKind.peq || k == CandidateKind.safeload,
          onTap: () => onSelect(selected == k ? null : k),
        ),
    ]);
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool blocked;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    this.blocked = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = blocked
        ? Colors.redAccent
        : selected
            ? kProAccent
            : Colors.white38;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : kProSurface,
          border: Border.all(
              color: selected ? color.withValues(alpha: 0.5) : kProBorder),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 9,
                color: selected ? color : Colors.white38,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }
}

// ── S4: Candidate List ────────────────────────────────────────────────────────

class _CandidateList extends StatelessWidget {
  final List<Adau1466SigmaCandidate> candidates;
  final Adau1466SigmaCandidate? selected;
  final void Function(Adau1466SigmaCandidate) onSelect;

  const _CandidateList({
    required this.candidates,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (candidates.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kProSurface,
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text('No candidates match filter.', style: proSubtitle()),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: kProBorder, width: 0.5)),
          ),
          child: Row(children: [
            SizedBox(width: 70, child: Text('ADDRESS', style: _hdr)),
            SizedBox(width: 80, child: Text('KIND', style: _hdr)),
            const Expanded(child: Text('NAME', style: _hdr)),
            SizedBox(width: 70, child: Text('STATUS', style: _hdr)),
            SizedBox(width: 36, child: Text('RISK', style: _hdr)),
          ]),
        ),
        for (int i = 0; i < candidates.length; i++) ...[
          if (i > 0) const Divider(height: 0.5, color: kProBorder),
          _CandidateRow(
            candidate: candidates[i],
            isSelected: candidates[i].id == selected?.id,
            onTap: () => onSelect(candidates[i]),
          ),
        ],
      ]),
    );
  }

  static const _hdr = TextStyle(fontSize: 8, color: Colors.white24, letterSpacing: 0.5);
}

class _CandidateRow extends StatelessWidget {
  final Adau1466SigmaCandidate candidate;
  final bool isSelected;
  final VoidCallback onTap;

  const _CandidateRow({
    required this.candidate,
    required this.isSelected,
    required this.onTap,
  });

  Color get _statusColor => switch (candidate.validationStatus) {
    CandidateValidationStatus.verified    => Colors.greenAccent,
    CandidateValidationStatus.passAck     => kProAccent,
    CandidateValidationStatus.candidate   => Colors.white54,
    CandidateValidationStatus.fail        => Colors.redAccent,
    CandidateValidationStatus.blocked     => Colors.orange,
    CandidateValidationStatus.rejected    => Colors.redAccent,
    _                                     => Colors.white24,
  };

  Color get _riskColor => switch (candidate.riskLevel) {
    CandidateRisk.low       => Colors.greenAccent,
    CandidateRisk.medium    => kProAmber,
    CandidateRisk.high      => Colors.orange,
    CandidateRisk.forbidden => Colors.redAccent,
  };

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Container(
      color: isSelected ? kProAccent.withValues(alpha: 0.07) : Colors.transparent,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(children: [
        SizedBox(
          width: 70,
          child: Text(
            candidate.addressHex,
            style: const TextStyle(
                fontSize: 9, fontFamily: 'monospace', color: Color(0xFF4A9EFF)),
          ),
        ),
        SizedBox(
          width: 80,
          child: Text(candidate.kind.label,
              style: const TextStyle(fontSize: 9, color: Colors.white54),
              overflow: TextOverflow.ellipsis),
        ),
        Expanded(
          child: Text(
            candidate.logicalName.isEmpty ? candidate.rawName : candidate.logicalName,
            style: TextStyle(
                fontSize: 9,
                color: isSelected ? Colors.white : Colors.white70),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(
          width: 70,
          child: Text(
            candidate.validationStatus.label,
            style: TextStyle(fontSize: 8, color: _statusColor),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            candidate.riskLevel.label,
            style: TextStyle(fontSize: 8, color: _riskColor),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    ),
  );
}

// ── S5: Candidate Detail + Execute Panel ──────────────────────────────────────

class _CandidateDetailPanel extends StatelessWidget {
  final Adau1466SigmaCandidate candidate;
  final TestProfile testProfile;
  final String testValueHex;
  final String restoreValueHex;
  final bool userConfirmed;
  final bool restoreConfirmed;
  final bool executing;
  final bool canExecute;
  final SigmaVerificationWriteResult? lastResult;
  final bool isWindows;
  final bool deviceOpen;
  final void Function(TestProfile) onProfileChanged;
  final void Function(String) onTestHexChanged;
  final void Function(String) onRestoreHexChanged;
  final void Function(bool) onConfirmChanged;
  final void Function(bool) onRestoreConfirmChanged;
  final VoidCallback onExecute;
  final VoidCallback onMarkVerified;
  final VoidCallback onMarkRejected;

  const _CandidateDetailPanel({
    required this.candidate,
    required this.testProfile,
    required this.testValueHex,
    required this.restoreValueHex,
    required this.userConfirmed,
    required this.restoreConfirmed,
    required this.executing,
    required this.canExecute,
    required this.lastResult,
    required this.isWindows,
    required this.deviceOpen,
    required this.onProfileChanged,
    required this.onTestHexChanged,
    required this.onRestoreHexChanged,
    required this.onConfirmChanged,
    required this.onRestoreConfirmChanged,
    required this.onExecute,
    required this.onMarkVerified,
    required this.onMarkRejected,
  });

  bool get _isBlocked =>
      candidate.validationStatus == CandidateValidationStatus.blocked;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(
          color: _isBlocked
              ? Colors.orange.withValues(alpha: 0.4)
              : kProAccent.withValues(alpha: 0.25)),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Detail header
      Row(children: [
        Expanded(
          child: Text(
            candidate.logicalName.isEmpty ? candidate.rawName : candidate.logicalName,
            style: proTitle(size: 11),
          ),
        ),
        _StatusBadge(candidate.validationStatus),
      ]),
      const SizedBox(height: 8),

      // Metadata grid
      _MetaGrid(candidate: candidate),
      const SizedBox(height: 10),

      // Blocked notice
      if (_isBlocked) ...[
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.06),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.block_outlined, color: Colors.orange, size: 12),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                candidate.blockedReason ?? 'This candidate is blocked.',
                style: const TextStyle(fontSize: 9, color: Colors.orange, height: 1.4),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        const Text(
          'Actual write is disabled for this candidate. '
          'Dry-run packet preview is available below.',
          style: TextStyle(fontSize: 9, color: Colors.white38),
        ),
        const SizedBox(height: 8),
      ],

      // Test profile selector
      Text('TEST PROFILE', style: proLabel(size: 8, color: Colors.white38, spacing: 1)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 4, children: [
        for (final p in TestProfile.values)
          _ProfileChip(
            profile: p,
            selected: testProfile == p,
            onTap: () => onProfileChanged(p),
          ),
      ]),
      const SizedBox(height: 10),

      // Value inputs
      _ValueRow(
        label: 'Test Value (32-bit hex)',
        value: testValueHex,
        onChanged: onTestHexChanged,
      ),
      const SizedBox(height: 6),
      _ValueRow(
        label: 'Restore Value (32-bit hex)',
        value: restoreValueHex,
        onChanged: onRestoreHexChanged,
      ),
      const SizedBox(height: 10),

      // Export default hint
      if (candidate.exportDefaultHex.isNotEmpty)
        Text(
          'Export default: ${candidate.exportDefaultHex}',
          style: const TextStyle(fontSize: 9, color: Colors.white38, fontFamily: 'monospace'),
        ),
      const SizedBox(height: 10),

      // Confirm checkboxes
      if (!_isBlocked) ...[
        _ConfirmRow(
          checked: userConfirmed,
          label: 'I confirm this is a volatile test write only. '
              'No EEPROM/Selfboot/WriteAll.',
          onChanged: onConfirmChanged,
        ),
        const SizedBox(height: 6),
        _ConfirmRow(
          checked: restoreConfirmed,
          label: 'I confirm the restore value is correct.',
          onChanged: onRestoreConfirmChanged,
        ),
        const SizedBox(height: 10),

        // Execute button
        _ExecuteButton(
          canExecute: canExecute,
          executing: executing,
          blocked: _isBlocked,
          isWindows: isWindows,
          deviceOpen: deviceOpen,
          onExecute: onExecute,
        ),
        const SizedBox(height: 10),
      ],

      // Result panel
      if (lastResult != null) ...[
        const Divider(color: kProBorder, height: 1),
        const SizedBox(height: 10),
        _ResultPanel(result: lastResult!),
        const SizedBox(height: 10),
      ],

      // Operator actions
      const Divider(color: kProBorder, height: 1),
      const SizedBox(height: 10),
      _OperatorActions(
        candidate: candidate,
        onMarkVerified: onMarkVerified,
        onMarkRejected: onMarkRejected,
      ),

      // Previous run info
      if (candidate.wasActualWrite && candidate.lastTestBodyHex != null) ...[
        const SizedBox(height: 10),
        _PreviousRunPanel(candidate: candidate),
      ],
    ]),
  );
}

class _StatusBadge extends StatelessWidget {
  final CandidateValidationStatus status;
  const _StatusBadge(this.status);

  Color get _color => switch (status) {
    CandidateValidationStatus.verified    => Colors.greenAccent,
    CandidateValidationStatus.passAck     => kProAccent,
    CandidateValidationStatus.candidate   => Colors.white54,
    CandidateValidationStatus.fail        => Colors.redAccent,
    CandidateValidationStatus.blocked     => Colors.orange,
    CandidateValidationStatus.rejected    => Colors.redAccent,
    _                                     => Colors.white24,
  };

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: _color.withValues(alpha: 0.12),
      border: Border.all(color: _color.withValues(alpha: 0.4)),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(status.label,
        style: TextStyle(fontSize: 8, color: _color, fontWeight: FontWeight.w600)),
  );
}

class _MetaGrid extends StatelessWidget {
  final Adau1466SigmaCandidate candidate;
  const _MetaGrid({required this.candidate});

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 20,
    runSpacing: 4,
    children: [
      _Meta('Address', candidate.addressHex),
      _Meta('Kind', candidate.kind.label),
      _Meta('Risk', candidate.riskLevel.label),
      _Meta('Region', candidate.addressRegion.label),
      _Meta('Channel', candidate.guessedChannel),
      if (candidate.bandOrStage.isNotEmpty)
        _Meta('Band/Stage', candidate.bandOrStage),
      if (candidate.coefficient.isNotEmpty)
        _Meta('Coefficient', candidate.coefficient),
      _Meta('Format', candidate.dataFormatHint),
      _Meta('SafeLoad Req', candidate.safeloadRequired ? 'Yes' : 'No'),
      if (candidate.isDuplicate)
        const _Meta('DUPLICATE', 'Yes'),
    ],
  );
}

class _Meta extends StatelessWidget {
  final String label;
  final String value;
  const _Meta(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 8, color: Colors.white24, letterSpacing: 0.3)),
      Text(value,
          style: const TextStyle(fontSize: 9, color: Colors.white70, fontFamily: 'monospace')),
    ],
  );
}

class _ProfileChip extends StatelessWidget {
  final TestProfile profile;
  final bool selected;
  final VoidCallback onTap;
  const _ProfileChip({required this.profile, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: selected ? kProAccent.withValues(alpha: 0.12) : kProSurface,
        border: Border.all(
            color: selected ? kProAccent.withValues(alpha: 0.5) : kProBorder),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(profile.label,
          style: TextStyle(
              fontSize: 9,
              color: selected ? kProAccent : Colors.white38)),
    ),
  );
}

class _ValueRow extends StatelessWidget {
  final String label;
  final String value;
  final void Function(String) onChanged;

  const _ValueRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(children: [
    SizedBox(
      width: 170,
      child: Text(label, style: const TextStyle(fontSize: 9, color: Colors.white54)),
    ),
    Expanded(
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: kProBg,
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(3),
        ),
        child: TextField(
          controller: TextEditingController(text: value)
            ..selection = TextSelection.collapsed(offset: value.length),
          style: const TextStyle(
              fontSize: 10, color: Colors.white70, fontFamily: 'monospace'),
          decoration: const InputDecoration(border: InputBorder.none, isDense: true),
          onChanged: onChanged,
        ),
      ),
    ),
  ]);
}

class _ConfirmRow extends StatelessWidget {
  final bool checked;
  final String label;
  final void Function(bool) onChanged;

  const _ConfirmRow({required this.checked, required this.label, required this.onChanged});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => onChanged(!checked),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 14,
        height: 14,
        margin: const EdgeInsets.only(top: 1),
        decoration: BoxDecoration(
          color: checked ? kProAccent.withValues(alpha: 0.2) : kProSurface,
          border: Border.all(color: checked ? kProAccent : kProBorder),
          borderRadius: BorderRadius.circular(2),
        ),
        child: checked
            ? const Icon(Icons.check, size: 10, color: kProAccent)
            : null,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(label,
            style: const TextStyle(fontSize: 9, color: Colors.white60, height: 1.4)),
      ),
    ]),
  );
}

class _ExecuteButton extends StatelessWidget {
  final bool canExecute;
  final bool executing;
  final bool blocked;
  final bool isWindows;
  final bool deviceOpen;
  final VoidCallback onExecute;

  const _ExecuteButton({
    required this.canExecute,
    required this.executing,
    required this.blocked,
    required this.isWindows,
    required this.deviceOpen,
    required this.onExecute,
  });

  String get _label {
    if (executing) return 'Executing…';
    if (blocked) return 'BLOCKED — write disabled';
    if (!isWindows) return 'Windows only';
    if (!deviceOpen) return 'Open USBi device first';
    if (!canExecute) return 'Confirm above to enable';
    return 'Execute Test + Restore Write';
  }

  @override
  Widget build(BuildContext context) {
    final active = canExecute && !blocked;
    final color = active ? Colors.redAccent : Colors.white24;
    return GestureDetector(
      onTap: active ? onExecute : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: active ? Colors.redAccent.withValues(alpha: 0.1) : kProSurface,
          border: Border.all(
              color: active
                  ? Colors.redAccent.withValues(alpha: 0.5)
                  : kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            executing
                ? Icons.hourglass_empty_outlined
                : Icons.send_outlined,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 8),
          Text(_label,
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  final SigmaVerificationWriteResult result;
  const _ResultPanel({required this.result});

  Color get _color => switch (result.resultStatus) {
    CandidateValidationStatus.passAck  => kProAccent,
    CandidateValidationStatus.verified => Colors.greenAccent,
    CandidateValidationStatus.fail     => Colors.redAccent,
    CandidateValidationStatus.blocked  => Colors.orange,
    _                                  => Colors.white38,
  };

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        Text('RESULT', style: proLabel(size: 9, spacing: 1.5, color: Colors.white38)),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: _color.withValues(alpha: 0.12),
            border: Border.all(color: _color.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(result.resultStatus.label,
              style: TextStyle(fontSize: 9, color: _color, fontWeight: FontWeight.w600)),
        ),
      ]),
      const SizedBox(height: 8),
      _RRow('Test write', result.testWasActualWrite ? 'ACTUAL' : 'blocked',
          result.testWasActualWrite ? kProAccent : Colors.white38),
      _RRow('Test ACK', result.testAckOk ? 'OK [${result.testAckBytes ?? "?"}]' : 'no / N/A',
          result.testAckOk ? Colors.greenAccent : Colors.white38),
      _RRow('Restore write', result.restoreWasActualWrite ? 'ACTUAL' : 'blocked',
          result.restoreWasActualWrite ? kProAccent : Colors.white38),
      _RRow('Restore ACK', result.restoreAckOk ? 'OK [${result.restoreAckBytes ?? "?"}]' : 'no / N/A',
          result.restoreAckOk ? Colors.greenAccent : Colors.white38),
      _RRow('Test body', result.testBodyHex, Colors.white38),
      _RRow('Restore body', result.restoreBodyHex, Colors.white38),
      if (result.error != null)
        _RRow('Error', result.error!, Colors.redAccent),
      const SizedBox(height: 4),
      Text(
        'ACK = PASS_ACK, not VERIFIED. Use "Mark Verified" below after expert confirmation.',
        style: const TextStyle(fontSize: 8, color: Colors.white24, height: 1.4),
      ),
    ],
  );
}

class _RRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _RRow(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 90,
        child: Text(label, style: const TextStyle(fontSize: 8, color: Colors.white38)),
      ),
      Expanded(
        child: Text(value,
            style: TextStyle(fontSize: 9, color: color, fontFamily: 'monospace'),
            overflow: TextOverflow.ellipsis),
      ),
    ]),
  );
}

class _OperatorActions extends StatelessWidget {
  final Adau1466SigmaCandidate candidate;
  final VoidCallback onMarkVerified;
  final VoidCallback onMarkRejected;

  const _OperatorActions({
    required this.candidate,
    required this.onMarkVerified,
    required this.onMarkRejected,
  });

  @override
  Widget build(BuildContext context) {
    final canVerify = candidate.wasActualWrite &&
        candidate.validationStatus != CandidateValidationStatus.verified;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('OPERATOR MARK', style: proLabel(size: 8, color: Colors.white38, spacing: 1)),
      const SizedBox(height: 6),
      Row(children: [
        GestureDetector(
          onTap: canVerify ? onMarkVerified : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: canVerify
                  ? Colors.greenAccent.withValues(alpha: 0.08)
                  : kProSurface,
              border: Border.all(
                  color: canVerify
                      ? Colors.greenAccent.withValues(alpha: 0.3)
                      : kProBorder),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Mark VERIFIED',
              style: TextStyle(
                  fontSize: 9,
                  color: canVerify ? Colors.greenAccent : Colors.white24),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onMarkRejected,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.08),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('Mark Rejected',
                style: TextStyle(fontSize: 9, color: Colors.redAccent)),
          ),
        ),
      ]),
      const SizedBox(height: 4),
      Text(
        canVerify
            ? 'wasActualWrite = true. Expert confirmation required before marking VERIFIED.'
            : 'Mark Verified requires wasActualWrite = true (real USBi write must have run).',
        style: const TextStyle(fontSize: 8, color: Colors.white24, height: 1.3),
      ),
    ]);
  }
}

class _PreviousRunPanel extends StatelessWidget {
  final Adau1466SigmaCandidate candidate;
  const _PreviousRunPanel({required this.candidate});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: kProBg,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Previous Run', style: proLabel(size: 8, color: Colors.white38, spacing: 0.5)),
      const SizedBox(height: 6),
      if (candidate.timestamp != null)
        _RRow('At', candidate.timestamp!.toLocal().toIso8601String().substring(0, 19),
            Colors.white38),
      if (candidate.lastTestBodyHex != null)
        _RRow('Test body', candidate.lastTestBodyHex!, Colors.white38),
      if (candidate.lastRestoreBodyHex != null)
        _RRow('Restore body', candidate.lastRestoreBodyHex!, Colors.white38),
      if (candidate.lastAckBytes != null)
        _RRow('ACK bytes', candidate.lastAckBytes!, Colors.white38),
    ]),
  );
}

// ── S6: Validation Log ────────────────────────────────────────────────────────

class _ValidationLog extends StatelessWidget {
  final List<SigmaValidationLogEntry> log;
  const _ValidationLog({required this.log});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: kProBorder, width: 0.5)),
        ),
        child: Row(children: [
          const Icon(Icons.history_outlined, size: 11, color: Colors.white38),
          const SizedBox(width: 6),
          Text('Validation Log (${log.length})',
              style: proLabel(size: 9, color: Colors.white54, spacing: 0)),
        ]),
      ),
      for (final entry in log.take(20)) ...[
        _LogRow(entry: entry),
        const Divider(height: 0.5, color: kProBorder),
      ],
      if (log.length > 20)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text('… ${log.length - 20} more entries (latest 20 shown)',
              style: proSubtitle(size: 9)),
        ),
    ]),
  );
}

class _LogRow extends StatelessWidget {
  final SigmaValidationLogEntry entry;
  const _LogRow({required this.entry});

  Color get _color => switch (entry.resultStatus) {
    'passAck'  => kProAccent,
    'verified' => Colors.greenAccent,
    'fail'     => Colors.redAccent,
    'blocked'  => Colors.orange,
    _          => Colors.white38,
  };

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
    child: Row(children: [
      SizedBox(
        width: 60,
        child: Text(
          entry.timestamp.toLocal().toIso8601String().substring(11, 19),
          style: const TextStyle(fontSize: 8, color: Colors.white24,
              fontFamily: 'monospace'),
        ),
      ),
      SizedBox(
        width: 65,
        child: Text(entry.addressHex,
            style: const TextStyle(fontSize: 8, color: Color(0xFF4A9EFF),
                fontFamily: 'monospace')),
      ),
      SizedBox(
        width: 60,
        child: Text(entry.kind,
            style: const TextStyle(fontSize: 8, color: Colors.white38)),
      ),
      Expanded(
        child: Text(
          entry.rawName,
          style: const TextStyle(fontSize: 8, color: Colors.white54),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: _color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(entry.resultStatus,
            style: TextStyle(fontSize: 7, color: _color, fontWeight: FontWeight.w600)),
      ),
    ]),
  );
}

// ── S7: Warnings Panel ────────────────────────────────────────────────────────

class _WarningsPanel extends StatelessWidget {
  final List<String> warnings;
  const _WarningsPanel({required this.warnings});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: kProAmber.withValues(alpha: 0.04),
      border: Border.all(color: kProAmber.withValues(alpha: 0.2)),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Loader Warnings (${warnings.length})',
          style: proLabel(size: 9, color: kProAmber, spacing: 0)),
      const SizedBox(height: 6),
      for (final w in warnings.take(10))
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('• ', style: TextStyle(fontSize: 9, color: Colors.white38)),
            Expanded(child: Text(w, style: proSubtitle(size: 9))),
          ]),
        ),
    ]),
  );
}
