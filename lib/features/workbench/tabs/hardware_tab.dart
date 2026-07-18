// ── Hardware Guard Tab — Phase T ──────────────────────────────────────────────
// Dry-run hardware planning + controlled master volume write prototype.
// Only ADAU1466 Master Volume L (0x67) and R (0x64) are verified write targets.
// No EEPROM. No Selfboot. No SafeLoad. No Write-All.
// AI suggests. Expert verifies. AOS protects. DSP executes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/pro_project.dart';
import '../../../core/pro_project_store.dart';
import '../../../core/pro_export_data.dart';
import '../../../core/pro_hardware_connection_data.dart';
import '../../../core/pro_hardware_write_plan_engine.dart';
import '../../../core/pro_hardware_write_data.dart';
import '../../../core/pro_controlled_write_engine.dart';
import '../../../core/pro_usbi_transport.dart';
import '../../../core/pro_hardware_transport.dart';
import '../../../shared/pro_widgets.dart';
import '../../../core/pro_dsp_address_registry.dart';
import '../../../core/pro_adau1466_3way_address_map_embedded.dart';
import '../../../core/pro_address_validation_data.dart';
import '../../../core/pro_address_validation_engine.dart';
import '../../../core/pro_transport_command_data.dart';
import '../../../core/pro_transport_command_engine.dart';
import '../../../core/pro_usbi_executor_data.dart';
import '../../../core/pro_usbi_temporary_executor.dart';
import '../../../core/pro_usbi_native_backend.dart';
import '../../../core/pro_usbi_windows_native_backend.dart';
import '../../../core/pro_usbi_packet_builder.dart';
import 'dart:async';
import 'dart:io';
import 'pro_hardware_mvp_status_card.dart';
import 'sigma_verification_console.dart';
import 'operational_master_volume_control.dart';
import 'transport_connection_panel.dart';
import 'adau1701_icp5_tuning_panel.dart';
import '../../../core/transport/icp5_transports.dart';

class HardwareTab extends ConsumerStatefulWidget {
  final String projectId;
  final ProUsbiNativeBackend? usbiBackend;
  final bool Function()? isWindowsPlatform;
  final bool initialUsbiDeviceOpen;
  final ValueChanged<bool>? onUsbiDeviceOpenChanged;
  final ValueChanged<bool>? onDspWritesDisabledChanged;
  const HardwareTab({
    super.key,
    required this.projectId,
    this.usbiBackend,
    this.isWindowsPlatform,
    this.initialUsbiDeviceOpen = false,
    this.onUsbiDeviceOpenChanged,
    this.onDspWritesDisabledChanged,
  });

  @override
  ConsumerState<HardwareTab> createState() => _HardwareTabState();
}

class _HardwareTabState extends ConsumerState<HardwareTab> {
  bool get _isWindows => widget.isWindowsPlatform?.call() ?? Platform.isWindows;

  bool _generating = false;
  bool _generatingQueue = false;
  String? _activeValidationTaskId;

  // ── Phase T: Controlled Master Volume Write state ────────────────────────
  final _transport = ProUsbiTransport();
  double _leftVolume  = 0.8;
  double _rightVolume = 0.8;
  List<HardwareWriteRequest>? _dryRunRequests;
  bool _userConfirmed = false;
  bool _writing = false;
  HardwareWriteLog? _lastWriteLog;

  // ── Phase T3: Transport Command Preview state ────────────────────────────
  String _commandSide = 'L';
  double _commandValue = 1.0;
  TransportCommandEnvelope? _commandEnvelope;

  // ── Phase T4A/T4C: USBi Temporary Executor state ────────────────────────
  late final ProUsbiNativeBackend _usbiNativeBackend;
  late final ProUsbiTemporaryExecutor _usbiExecutor;
  bool _executingUsbi = false;
  bool _usbiUserConfirmed = false;
  UsbiExecutionResult? _lastUsbiResult;
  // T4C: Windows USBi device lifecycle state
  bool _usbiChecking = false;
  bool _usbiDeviceOpen = false;
  String? _usbiOpenError;
  bool _dspWritesDisabledForSession = false;
  String? _dspWriteStopWarning;
  bool _muteDiagnosticUsedForSession = false;
  bool _gainDiagnosticUsedForSession = false;
  // T4C: self-contained panel state (no Transport Command Preview dependency)
  String _t4cSide = 'L';           // 'L' or 'R'
  double _t4cValue = 1.0;          // 1.0 / 0.5 / 0.0

  // ── MVP: Mute/Gain guarded validation panel state ────────────────────────
  VerifiedDspAddress? _muteGainSelected;
  bool _muteGainConfirmed = false;
  bool _executingMuteGain = false;
  UsbiExecutionResult? _lastMuteGainResult;

  // ── ADAU1701 ICP5 tuning transports (USB + BLE shared with connection panel)
  late final Icp5UsbTransport _adau1701UsbTransport;
  late final Icp5BluetoothTransport _adau1701BleTransport;
  Timer? _tuningRefreshTimer;

  // ── Phase T2 Revised: Multi-transport readiness state ───────────────────
  bool _checkingTransport = false;
  HardwareTransportBackend _selectedTransport = HardwareTransportBackend.simulation;
  List<HardwareTransportInfo> _transportInfos =
      HardwareTransportInfo.defaultAvailableTransports;
  String? _transportCheckMessage;
  DateTime? _transportLastChecked;

  ProProject? get _project => ref
      .read(proProjectStoreProvider)
      .projects
      .where((p) => p.id == widget.projectId)
      .firstOrNull;

  Future<void> _setTransport(HardwareTransportType t) async {
    final project = _project;
    if (project == null) return;
    final newConn = project.hardwareState.connectionState.copyWith(
      transportType: t,
      connectionStatus: t == HardwareTransportType.simulationOnly
          ? HardwareConnectionStatus.simulated
          : HardwareConnectionStatus.disconnected,
    );
    final newHw = project.hardwareState.copyWith(
      connectionState: newConn,
      updatedAt: DateTime.now(),
    );
    await ref.read(proProjectStoreProvider.notifier)
        .updateHardwareState(widget.projectId, newHw);
  }

  Future<void> _setTargetDevice(HardwareTargetDevice d) async {
    final project = _project;
    if (project == null) return;
    final newConn = project.hardwareState.connectionState.copyWith(targetDevice: d);
    final newHw = project.hardwareState.copyWith(
      connectionState: newConn,
      updatedAt: DateTime.now(),
    );
    await ref.read(proProjectStoreProvider.notifier)
        .updateHardwareState(widget.projectId, newHw);
  }

  Future<void> _checkConnection() async {
    final project = _project;
    if (project == null) return;
    final current = project.hardwareState.connectionState;
    // Phase Q: only simulated status update. No real hardware scan.
    final newStatus = current.transportType == HardwareTransportType.simulationOnly
        ? HardwareConnectionStatus.simulated
        : HardwareConnectionStatus.disconnected;
    final newConn = current.copyWith(
      connectionStatus: newStatus,
      lastCheckedAt: DateTime.now(),
    );
    final newHw = project.hardwareState.copyWith(
      connectionState: newConn,
      updatedAt: DateTime.now(),
    );
    await ref.read(proProjectStoreProvider.notifier)
        .updateHardwareState(widget.projectId, newHw);
  }

  Future<void> _checkTransportReadiness() async {
    if (_checkingTransport) return;
    setState(() => _checkingTransport = true);
    try {
      // Phase T2: all transports are placeholders — no real I/O occurs.
      // Update the selected transport info's lastCheckedAt timestamp.
      final now = DateTime.now();
      if (mounted) {
        setState(() {
          _transportInfos = _transportInfos.map((t) =>
              t.backend == _selectedTransport
                  ? t.copyWith(lastCheckedAt: now)
                  : t).toList();
          _transportCheckMessage =
              'Checked ${_selectedTransport.label} at '
              '${now.toLocal().toString().substring(0, 19)}. '
              '${_selectedTransport.descriptionNote}';
          _transportLastChecked = now;
        });
      }
    } finally {
      if (mounted) setState(() => _checkingTransport = false);
    }
  }

  void _selectTransportBackend(HardwareTransportBackend backend) =>
      setState(() => _selectedTransport = backend);

  void _generateTransportCommand() {
    final registry = createTunaiAdau1466ThreeWayRegistry();
    final envelope = createMasterVolumeCommand(
      backend:      _selectedTransport,
      side:         _commandSide,
      linearValue:  _commandValue,
      registry:     registry,
    );
    setState(() => _commandEnvelope = envelope);
  }

  void _generateDryRun() {
    setState(() {
      _dryRunRequests = createMasterVolumeWriteRequests(
        leftVolume:  _leftVolume,
        rightVolume: _rightVolume,
      );
      _userConfirmed = false;
      _lastWriteLog  = null;
    });
  }

  Future<void> _performWrite() async {
    if (_writing) return;
    setState(() => _writing = true);
    try {
      final log = await performControlledMasterVolumeWrite(
        leftVolume:    _leftVolume,
        rightVolume:   _rightVolume,
        userConfirmed: _userConfirmed,
        transport:     _transport,
      );
      if (mounted) setState(() => _lastWriteLog = log);
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  Future<void> _generateWritePlan() async {
    final project = _project;
    if (project == null) return;
    final pkg = project.exportState.activePackage;
    if (pkg == null) return;

    setState(() => _generating = true);
    try {
      final plan = generateHardwareWritePlan(project: project, package: pkg);
      final existing = project.hardwareState.writePlans;
      // Keep last 5 plans
      final updated = [...existing.take(4), plan];
      final newHw = project.hardwareState.copyWith(
        writePlans: updated,
        activePlanId: plan.id,
        updatedAt: DateTime.now(),
        revision: project.hardwareState.revision + 1,
      );
      await ref.read(proProjectStoreProvider.notifier)
          .updateHardwareState(widget.projectId, newHw);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _generateValidationQueue() async {
    final project = _project;
    if (project == null) return;
    setState(() => _generatingQueue = true);
    try {
      final registry = createTunaiAdau1466ThreeWayRegistry();
      final newState = createValidationTasksFromRegistry(registry: registry);
      await ref.read(proProjectStoreProvider.notifier)
          .updateAddressValidationState(widget.projectId, newState);
      if (mounted) setState(() => _activeValidationTaskId = null);
    } finally {
      if (mounted) setState(() => _generatingQueue = false);
    }
  }

  void _setActiveTask(String? taskId) =>
      setState(() => _activeValidationTaskId = taskId);

  Future<void> _markTaskFailed(String taskId) async {
    final project = _project;
    if (project == null) return;
    final vs = project.addressValidationState;
    final updated = vs.tasks.map((t) => t.id == taskId
        ? t.copyWith(
            currentStatus: AddressValidationStatus.failed,
            updatedAt: DateTime.now(),
          )
        : t).toList();
    await ref.read(proProjectStoreProvider.notifier)
        .updateAddressValidationState(widget.projectId,
          vs.copyWith(tasks: updated, updatedAt: DateTime.now()));
  }

  Future<void> _markTaskBlocked(String taskId) async {
    final project = _project;
    if (project == null) return;
    final vs = project.addressValidationState;
    final updated = vs.tasks.map((t) => t.id == taskId
        ? t.copyWith(
            currentStatus: AddressValidationStatus.blocked,
            updatedAt: DateTime.now(),
          )
        : t).toList();
    await ref.read(proProjectStoreProvider.notifier)
        .updateAddressValidationState(widget.projectId,
          vs.copyWith(tasks: updated, updatedAt: DateTime.now()));
  }

  @override
  void initState() {
    super.initState();
    _usbiDeviceOpen = widget.initialUsbiDeviceOpen;
    _adau1701UsbTransport = Icp5UsbTransport();
    // 3 s timeout gives the DSP firmware margin to respond after back-to-back
    // page reads; the default 1 s is tight for BLE with ATT Write Response.
    _adau1701BleTransport = Icp5BluetoothTransport(
      readTimeout: const Duration(seconds: 3),
      writeTimeout: const Duration(seconds: 3),
    );
    // Periodic rebuild so the tuning panel's key reflects the active transport
    // (USB vs BLE) without needing a callback from TransportConnectionPanel.
    _tuningRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    if (widget.usbiBackend != null) {
      _usbiNativeBackend = widget.usbiBackend!;
      _usbiExecutor = ProUsbiTemporaryExecutor(
        isWindowsPlatform: () => _isWindows,
        backend: _usbiNativeBackend,
      );
    } else if (_isWindows) {
      final backend = ProUsbiWindowsNativeBackend();
      _usbiNativeBackend = backend;
      _usbiExecutor = ProUsbiTemporaryExecutor(
        isWindowsPlatform: () => true,
        backend: backend,
      );
      backend.initialise().then((_) {
        if (mounted) setState(() {});
      });
    } else {
      _usbiNativeBackend = const ProUsbiNativeBackendDisabled();
      _usbiExecutor = ProUsbiTemporaryExecutor.disabled();
    }
  }

  @override
  void dispose() {
    if (_isWindows && _usbiNativeBackend is ProUsbiWindowsNativeBackend) {
      (_usbiNativeBackend as ProUsbiWindowsNativeBackend).closeDevice();
    }
    _tuningRefreshTimer?.cancel();
    _adau1701UsbTransport.close();
    _adau1701BleTransport.close();
    super.dispose();
  }

  /// Returns whichever ADAU1701 ICP5 transport is currently ready.
  /// BLE takes priority when connected; falls back to USB.
  Icp5UsbTransport get _activeTuningTransport {
    if (_adau1701BleTransport.isConnected &&
        _adau1701BleTransport.handshakeComplete) {
      return _adau1701BleTransport;
    }
    return _adau1701UsbTransport;
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(proProjectStoreProvider)
        .projects
        .where((p) => p.id == widget.projectId)
        .firstOrNull;
    final hwState = project?.hardwareState ?? HardwareProjectState.createDefault();
    final conn = hwState.connectionState;
    // The CONNECTION STATE panel is sourced from the persisted project model,
    // which is not updated by the live ICP5 USB/BLE transport. Reflect the
    // actual active transport so a working, handshaked connection (proven by a
    // successful read/write) is not shown as "Disconnected". Display-only: the
    // project model and transport behavior are unchanged, and simulation-only
    // mode is left exactly as-is. Re-evaluated live by the 1 s refresh timer.
    final liveIcp5Connected = (_adau1701BleTransport.isConnected &&
            _adau1701BleTransport.handshakeComplete) ||
        (_adau1701UsbTransport.isConnected &&
            _adau1701UsbTransport.handshakeComplete);
    final displayConn = (liveIcp5Connected &&
            conn.transportType != HardwareTransportType.simulationOnly)
        ? conn.copyWith(connectionStatus: HardwareConnectionStatus.connected)
        : conn;
    final activePlan = hwState.activePlan;
    final activePkg = project?.exportState.activePackage;
    final validationState = project?.addressValidationState
        ?? AddressValidationProjectState.createDefault();

    if (_isWindows &&
        _selectedTransport == HardwareTransportBackend.usbiWindowsTemporary) {
      return _buildUsbiMasterVolumeHardwareTab();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Icon(Icons.security_outlined,
              color: kProAccent.withValues(alpha: 0.6), size: 18),
          const SizedBox(width: 10),
          Text('Hardware Guard', style: proTitle(size: 16)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: kProAmber.withValues(alpha: 0.12),
              border: Border.all(color: kProAmber.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text('DRY RUN ONLY',
                style: TextStyle(fontSize: 9, color: kProAmber,
                    fontWeight: FontWeight.w600, letterSpacing: 0.8)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          Platform.isWindows
              ? 'Dry-run planning + T4C USBi Master Volume executor (Windows). '
                'Select USBi transport below to access the write path.'
              : 'Dry-run hardware planning. No USBi/BLE write is enabled.',
          style: proSubtitle(),
        ),
        const SizedBox(height: 24),

        const _SectionHeader('TRANSPORT ARCHITECTURE — ICP5 PHASE A', Icons.alt_route_outlined),
        const SizedBox(height: 8),
        TransportConnectionPanel(
          backend: _usbiNativeBackend,
          deviceOpen: _usbiDeviceOpen,
          dspWritesStopped: _dspWritesDisabledForSession,
          icp5UsbTransport: _adau1701UsbTransport,
          icp5BluetoothTransport: _adau1701BleTransport,
          onDspWriteStop: (warning) {
            if (!mounted) return;
            setState(() {
              _dspWritesDisabledForSession = true;
              _dspWriteStopWarning = warning;
              widget.onDspWritesDisabledChanged?.call(true);
            });
          },
        ),
        const SizedBox(height: 20),

        const _SectionHeader('ADAU1701 ICP5 TUNING', Icons.tune_outlined),
        const SizedBox(height: 8),
        Adau1701Icp5TuningPanel(
          key: ValueKey(_activeTuningTransport.identity),
          transport: _activeTuningTransport,
        ),
        const SizedBox(height: 20),

        // A: Connection State Panel
        const _SectionHeader('CONNECTION STATE', Icons.usb_outlined),
        const SizedBox(height: 8),
        _ConnectionPanel(
          conn: displayConn,
          onTransport: _setTransport,
          onTarget: _setTargetDevice,
          onCheck: _checkConnection,
        ),
        const SizedBox(height: 20),

        // B: Transport Readiness (Phase T2 Revised)
        const _SectionHeader('TRANSPORT READINESS', Icons.compare_arrows_outlined),
        const SizedBox(height: 8),
        _TransportReadinessPanel(
          selectedBackend:  _selectedTransport,
          transportInfos:   _transportInfos,
          checking:         _checkingTransport,
          checkMessage:     _transportCheckMessage,
          lastChecked:      _transportLastChecked,
          onCheck:          _checkTransportReadiness,
          onSelect:         _selectTransportBackend,
        ),
        const SizedBox(height: 20),

        // C: Active Export Package
        const _SectionHeader('ACTIVE EXPORT PACKAGE', Icons.upload_outlined),
        const SizedBox(height: 8),
        _ExportPackagePanel(pkg: activePkg, protection: project?.protectionState),
        const SizedBox(height: 20),

        // C: Generate button
        GestureDetector(
          onTap: (_generating || activePkg == null) ? null : _generateWritePlan,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: (_generating || activePkg == null)
                  ? kProSurface
                  : kProAccent.withValues(alpha: 0.08),
              border: Border.all(
                  color: (_generating || activePkg == null)
                      ? kProBorder
                      : kProAccent.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                _generating
                    ? Icons.hourglass_empty_outlined
                    : Icons.play_arrow_outlined,
                color: (_generating || activePkg == null)
                    ? Colors.white24
                    : kProAccent,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                activePkg == null
                    ? 'No Export Package — Generate Export First'
                    : _generating
                        ? 'Generating...'
                        : 'Generate Dry-Run Write Plan',
                style: TextStyle(
                    color: (_generating || activePkg == null)
                        ? Colors.white24
                        : kProAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 20),

        // D: Guard checklist
        if (activePlan != null) ...[
          const _SectionHeader('GUARD CHECKLIST', Icons.checklist_outlined),
          const SizedBox(height: 8),
          _GuardChecklistPanel(plan: activePlan),
          const SizedBox(height: 20),

          // E: Write plan preview
          const _SectionHeader('WRITE PLAN PREVIEW', Icons.list_alt_outlined),
          const SizedBox(height: 8),
          _WritePlanPanel(plan: activePlan),
          const SizedBox(height: 20),

          // F: Warnings
          if (activePlan.warnings.isNotEmpty || activePlan.blockedReason != null) ...[
            const _SectionHeader('WARNINGS', Icons.warning_amber_outlined),
            const SizedBox(height: 8),
            _WarningsPanel(plan: activePlan),
            const SizedBox(height: 20),
          ],
        ] else ...[
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: kProSurface,
              border: Border.all(color: kProBorder),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, color: Colors.white24, size: 13),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Generate an export draft first, then click '
                  '"Generate Dry-Run Write Plan" to preview the hardware guard checklist.',
                  style: proSubtitle(),
                ),
              ),
            ]),
          ),
        ],

        // ── G: Address Validation Status (Phase U1) ──────────────────────
        const SizedBox(height: 20),
        const _SectionHeader('ADDRESS VALIDATION STATUS', Icons.checklist_outlined),
        const SizedBox(height: 8),
        const _AddressValidationStatusPanel(),
        const SizedBox(height: 16),

        // ── H: Live Validation Queue (Phase U1) ──────────────────────────
        const _SectionHeader('LIVE VALIDATION QUEUE', Icons.playlist_add_check_outlined),
        const SizedBox(height: 8),
        const _LiveValidationQueuePanel(),
        const SizedBox(height: 16),

        // ── I: Address Live Validation Manager (Phase U2) ────────────────
        const SizedBox(height: 20),
        const _SectionHeader('ADDRESS LIVE VALIDATION MANAGER', Icons.task_alt_outlined),
        const SizedBox(height: 8),
        _ValidationManagerPanel(
          validationState:   validationState,
          generating:        _generatingQueue,
          activeTaskId:      _activeValidationTaskId,
          onGenerate:        _generateValidationQueue,
          onSelectTask:      _setActiveTask,
          onMarkFailed:      _markTaskFailed,
          onMarkBlocked:     _markTaskBlocked,
        ),
        const SizedBox(height: 20),

        // ── J: Controlled Master Volume Write (Phase T) ──────────────────
        const SizedBox(height: 4),
        const _SectionHeader('CONTROLLED MASTER VOLUME WRITE', Icons.volume_up_outlined),
        const SizedBox(height: 8),
        _ControlledWritePanel(
          leftVolume:      _leftVolume,
          rightVolume:     _rightVolume,
          dryRunRequests:  _dryRunRequests,
          userConfirmed:   _userConfirmed,
          writing:         _writing,
          lastLog:         _lastWriteLog,
          onLeftChanged:   (v) => setState(() { _leftVolume = v; _dryRunRequests = null; _userConfirmed = false; }),
          onRightChanged:  (v) => setState(() { _rightVolume = v; _dryRunRequests = null; _userConfirmed = false; }),
          onGenerateDryRun: _generateDryRun,
          onConfirmChanged: (v) => setState(() => _userConfirmed = v),
          onWrite:         _performWrite,
        ),

        // ── K: Transport Command Preview (Phase T3) ──────────────────────
        const SizedBox(height: 20),
        const _SectionHeader('TRANSPORT COMMAND PREVIEW', Icons.terminal_outlined),
        const SizedBox(height: 8),
        _TransportCommandPreviewPanel(
          selectedBackend: _selectedTransport,
          commandSide:     _commandSide,
          commandValue:    _commandValue,
          envelope:        _commandEnvelope,
          onSideChanged:   (s) => setState(() {
            _commandSide     = s;
            _commandEnvelope = null;
          }),
          onValueChanged:  (v) => setState(() {
            _commandValue    = v;
            _commandEnvelope = null;
          }),
          onGenerate:      _generateTransportCommand,
        ),

        // ── L: T4C — USBi Temporary Master Volume Executor ──────────────
        // Visible directly when Windows + USBi transport selected.
        // No Transport Command Preview prerequisite.
        if (Platform.isWindows &&
            _selectedTransport ==
                HardwareTransportBackend.usbiWindowsTemporary) ...[
          const SizedBox(height: 20),
          _T4cMasterVolumePanel(
            side:           _t4cSide,
            value:          _t4cValue,
            deviceOpen:     _usbiDeviceOpen,
            checking:       _usbiChecking,
            openError:      _usbiOpenError,
            executing:      _executingUsbi,
            userConfirmed:  _usbiUserConfirmed,
            lastResult:     _lastUsbiResult,
            onSideChanged:  (s) => setState(() {
              _t4cSide           = s;
              _usbiUserConfirmed = false;
              _lastUsbiResult    = null;
            }),
            onValueChanged: (v) => setState(() {
              _t4cValue          = v;
              _usbiUserConfirmed = false;
              _lastUsbiResult    = null;
            }),
            onOpenDevice: () async {
              setState(() { _usbiChecking = true; _usbiOpenError = null; });
              final backend = _usbiNativeBackend as ProUsbiWindowsNativeBackend;
              final res = await backend.openDevice();
              if (mounted) setState(() {
                _usbiChecking   = false;
                _usbiDeviceOpen = res.success;
                _usbiOpenError  = res.success ? null : res.error;
              });
            },
            onCloseDevice: () async {
              final backend = _usbiNativeBackend as ProUsbiWindowsNativeBackend;
              await backend.closeDevice();
              if (mounted) setState(() {
                _usbiDeviceOpen    = false;
                _usbiUserConfirmed = false;
                _usbiOpenError     = null;
                _lastUsbiResult    = null;
              });
            },
            onConfirmChanged: (v) => setState(() {
              _usbiUserConfirmed = v;
              _lastUsbiResult    = null;
            }),
            onExecute: () async {
              if (!_usbiUserConfirmed || _executingUsbi || !_usbiDeviceOpen) return;
              setState(() => _executingUsbi = true);
              final addrInt = _t4cSide == 'L'
                  ? kMasterVolumeLAddr : kMasterVolumeRAddr;
              final fixedInt = _t4cValue >= 1.0
                  ? 0x01000000
                  : _t4cValue >= 0.5
                      ? 0x00800000
                      : 0x00000000;
              final req = UsbiExecutionRequest(
                id:                't4c_${DateTime.now().millisecondsSinceEpoch}',
                commandEnvelopeId: 't4c_direct',
                transportBackend:  HardwareTransportBackend.usbiWindowsTemporary,
                parameterId:       'master_volume_${_t4cSide.toLowerCase()}',
                logicalName:       'Master Volume ${_t4cSide}',
                addressHex:        '0x${addrInt.toRadixString(16).padLeft(4, '0').toUpperCase()}',
                addressInt:        addrInt,
                fixedPointHex:     '0x${fixedInt.toRadixString(16).padLeft(8, '0').toUpperCase()}',
                fixedPointInt:     fixedInt,
                valueFloat:        _t4cValue,
                userConfirmed:     _usbiUserConfirmed,
              );
              final result = await _usbiExecutor.execute(req);
              if (mounted) setState(() {
                _executingUsbi  = false;
                _lastUsbiResult = result;
              });
            },
            onRestore: () async {
              if (_executingUsbi || !_usbiDeviceOpen) return;
              setState(() => _executingUsbi = true);
              final addrInt = _t4cSide == 'L'
                  ? kMasterVolumeLAddr : kMasterVolumeRAddr;
              final req = UsbiExecutionRequest(
                id:                't4c_restore_${DateTime.now().millisecondsSinceEpoch}',
                commandEnvelopeId: 't4c_restore',
                transportBackend:  HardwareTransportBackend.usbiWindowsTemporary,
                parameterId:       'master_volume_${_t4cSide.toLowerCase()}_restore',
                logicalName:       'Master Volume ${_t4cSide} Restore 1.0',
                addressHex:        '0x${addrInt.toRadixString(16).padLeft(4, '0').toUpperCase()}',
                addressInt:        addrInt,
                fixedPointHex:     '0x01000000',
                fixedPointInt:     0x01000000,
                valueFloat:        1.0,
                userConfirmed:     true,
              );
              final result = await _usbiExecutor.execute(req);
              if (mounted) setState(() {
                _executingUsbi  = false;
                _lastUsbiResult = result;
              });
            },
          ),
        ],

        // ── M: T4C — Mute/Gain Guarded Validation Panel ─────────────────
        if (Platform.isWindows &&
            _selectedTransport ==
                HardwareTransportBackend.usbiWindowsTemporary) ...[
          const SizedBox(height: 20),
          const _SectionHeader(
              'USBi TEMPORARY — MUTE/GAIN VALIDATION', Icons.tune_outlined),
          const SizedBox(height: 8),
          _T4cMuteGainPanel(
            selected:         _muteGainSelected,
            deviceOpen:       _usbiDeviceOpen,
            confirmed:        _muteGainConfirmed,
            executing:        _executingMuteGain,
            lastResult:       _lastMuteGainResult,
            onSelect: (addr) => setState(() {
              _muteGainSelected  = addr;
              _muteGainConfirmed = false;
              _lastMuteGainResult = null;
            }),
            onConfirmChanged: (v) => setState(() {
              _muteGainConfirmed  = v;
              _lastMuteGainResult = null;
            }),
            onExecute: () async {
              final addr = _muteGainSelected;
              if (addr == null || !_muteGainConfirmed ||
                  _executingMuteGain || !_usbiDeviceOpen) return;
              if (!addr.isActualWriteEligible) return;
              if (addr.dataFormat == null) return;
              setState(() => _executingMuteGain = true);
              final req = UsbiExecutionRequest(
                id:                'mvp_mg_${DateTime.now().millisecondsSinceEpoch}',
                commandEnvelopeId: 'mvp_mute_gain',
                transportBackend:  HardwareTransportBackend.usbiWindowsTemporary,
                parameterId:       addr.id,
                logicalName:       addr.logicalName,
                addressHex:        addr.addressHex,
                addressInt:        addr.addressInt,
                fixedPointHex:     '0x00000000',
                fixedPointInt:     0x00000000,
                valueFloat:        0.0,
                userConfirmed:     _muteGainConfirmed,
              );
              final result = await _usbiExecutor.execute(req);
              if (mounted) setState(() {
                _executingMuteGain  = false;
                _lastMuteGainResult = result;
              });
            },
          ),
        ],

        // ── N: T4C — Delay Validation Panel (dry-run only) ──────────────
        if (Platform.isWindows &&
            _selectedTransport ==
                HardwareTransportBackend.usbiWindowsTemporary) ...[
          const SizedBox(height: 20),
          const _SectionHeader(
              'USBi TEMPORARY — DELAY VALIDATION (DRY RUN ONLY)',
              Icons.access_time_outlined),
          const SizedBox(height: 8),
          const _T4cDelayPanel(),
        ],

        // ── O: T4C — PEQ Band 1 Validation Panel (dry-run only) ─────────
        if (Platform.isWindows &&
            _selectedTransport ==
                HardwareTransportBackend.usbiWindowsTemporary) ...[
          const SizedBox(height: 20),
          const _SectionHeader(
              'USBi TEMPORARY — PEQ BAND 1 VALIDATION (DRY RUN ONLY)',
              Icons.graphic_eq_outlined),
          const SizedBox(height: 8),
          const _T4cPeqBand1Panel(),
        ],

        // ── P: T4C — XO Validation Panel (hard-blocked) ─────────────────
        if (Platform.isWindows &&
            _selectedTransport ==
                HardwareTransportBackend.usbiWindowsTemporary) ...[
          const SizedBox(height: 20),
          const _SectionHeader(
              'USBi TEMPORARY — XO VALIDATION (BLOCKED)',
              Icons.device_hub_outlined),
          const SizedBox(height: 8),
          const _T4cXoPanel(),
        ],

        // ── Q: SafeLoad Validation Panel (dry-run only) ──────────────────
        if (Platform.isWindows &&
            _selectedTransport ==
                HardwareTransportBackend.usbiWindowsTemporary) ...[
          const SizedBox(height: 20),
          const _SectionHeader(
              'SAFELOAD VALIDATION (DRY RUN ONLY)', Icons.save_outlined),
          const SizedBox(height: 8),
          const _T4cSafeloadPanel(),
        ],

        // ── S: Sigma Export Hardware Verification Console ────────────────
        if (Platform.isWindows &&
            _selectedTransport ==
                HardwareTransportBackend.usbiWindowsTemporary) ...[
          const SizedBox(height: 20),
          const _SectionHeader(
              'ADAU1466 SIGMA EXPORT VERIFICATION CONSOLE',
              Icons.science_outlined),
          const SizedBox(height: 8),
          SigmaVerificationConsole(
            backend:           _usbiNativeBackend,
            isWindowsPlatform: () => Platform.isWindows,
            deviceOpen:        _usbiDeviceOpen,
          ),
        ],

        // ── R: Hardware MVP Status Card (always visible) ─────────────────
        const SizedBox(height: 20),
        const _SectionHeader('HARDWARE MVP STATUS', Icons.info_outline),
        const SizedBox(height: 8),
        const HardwareMvpStatusCard(),

        // ── Scoped safety notice ──────────────────────────────────────────
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: kProAmber.withValues(alpha: 0.06),
            border: Border.all(color: kProAmber.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.block_outlined, color: kProAmber, size: 13),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                Platform.isWindows &&
                    _selectedTransport ==
                        HardwareTransportBackend.usbiWindowsTemporary
                    ? 'Only verified Master Volume L/R can use the temporary '
                      'USBi executor. All other writes remain blocked. '
                      'No PEQ/XO/Gain/Mute/Delay/SafeLoad/EEPROM/Selfboot. '
                      'USBi is temporary — ICP5 is the final target.'
                    : 'Hardware write remains disabled for the selected transport. '
                      'No USB, BLE, or ICP5 packets are sent. No SafeLoad is executed. '
                      'No EEPROM/Selfboot write is performed.',
                style: proSubtitle(size: 9),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildUsbiMasterVolumeHardwareTab() {
    final backendAvailable = _usbiNativeBackend.isAvailable;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.security_outlined,
              color: kProAccent.withValues(alpha: 0.6), size: 18),
          const SizedBox(width: 10),
          Text('Hardware Guard', style: proTitle(size: 16)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: kProAccent.withValues(alpha: 0.10),
              border: Border.all(color: kProAccent.withValues(alpha: 0.45)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text('MV WRITE ACTIVE',
                style: TextStyle(fontSize: 9, color: kProAccent,
                    fontWeight: FontWeight.w700, letterSpacing: 0.7)),
          ),
        ]),
        const SizedBox(height: 16),
        const _SectionHeader('TRANSPORT READINESS', Icons.compare_arrows_outlined),
        const SizedBox(height: 8),
        _TransportReadinessPanel(
          selectedBackend: _selectedTransport,
          transportInfos: _transportInfos,
          checking: _checkingTransport,
          checkMessage: _transportCheckMessage,
          lastChecked: _transportLastChecked,
          onCheck: _checkTransportReadiness,
          onSelect: _selectTransportBackend,
          realUsbiExecutorAvailable: backendAvailable,
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 30,
          child: OutlinedButton.icon(
            key: const Key('usbi-open-device'),
            onPressed: (!_usbiDeviceOpen && !_usbiChecking &&
                    _usbiNativeBackend is ProUsbiWindowsNativeBackend)
                ? () async {
                    setState(() { _usbiChecking = true; _usbiOpenError = null; });
                    final result = await (_usbiNativeBackend as ProUsbiWindowsNativeBackend).openDevice();
                    if (mounted) {
                      setState(() {
                        _usbiChecking = false;
                        _usbiDeviceOpen = result.success;
                        _usbiOpenError = result.error;
                        if (result.success) {
                          _dspWritesDisabledForSession = false;
                          _dspWriteStopWarning = null;
                          _muteDiagnosticUsedForSession = false;
                          _gainDiagnosticUsedForSession = false;
                          widget.onUsbiDeviceOpenChanged?.call(true);
                          widget.onDspWritesDisabledChanged?.call(false);
                        }
                      });
                    }
                  }
                : null,
            icon: const Icon(Icons.usb_outlined, size: 13),
            label: Text(_usbiDeviceOpen ? 'USBi Device Open' : 'Open USBi Device'),
          ),
        ),
        if (_usbiOpenError != null) ...[
          const SizedBox(height: 8),
          Text(_usbiOpenError!, style: const TextStyle(fontSize: 9, color: Colors.redAccent)),
        ],
        if (_dspWriteStopWarning != null) ...[
          const SizedBox(height: 8),
          Container(
            key: const Key('session-dsp-write-stop-warning'),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.12),
              border: Border.all(color: Colors.redAccent),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(_dspWriteStopWarning!,
                style: const TextStyle(fontSize: 10, color: Colors.redAccent,
                    fontWeight: FontWeight.w800)),
          ),
        ],
        const SizedBox(height: 16),
        const _SectionHeader('ADAU1466 SIGMA VERIFICATION CONSOLE', Icons.science_outlined),
        const SizedBox(height: 8),
        SigmaVerificationConsole(
          backend: _usbiNativeBackend,
          isWindowsPlatform: () => _isWindows,
          deviceOpen: _usbiDeviceOpen,
          dspWritesDisabled: _dspWritesDisabledForSession,
          muteDiagnosticUsedThisSession: _muteDiagnosticUsedForSession,
          gainDiagnosticUsedThisSession: _gainDiagnosticUsedForSession,
          onMuteDiagnosticConsumed: () {
            if (!mounted) return;
            setState(() => _muteDiagnosticUsedForSession = true);
          },
          onGainDiagnosticConsumed: () {
            if (!mounted) return;
            setState(() => _gainDiagnosticUsedForSession = true);
          },
          onDspWriteStop: (warning) {
            if (!mounted) return;
            setState(() {
              _dspWritesDisabledForSession = true;
              _dspWriteStopWarning = warning;
              widget.onDspWritesDisabledChanged?.call(true);
            });
          },
        ),
        const SizedBox(height: 20),
        const _SectionHeader('OPERATIONAL MASTER VOLUME', Icons.volume_up_outlined),
        const SizedBox(height: 8),
        OperationalMasterVolumeControl(
          backend: _usbiNativeBackend,
          isWindowsPlatform: () => _isWindows,
          deviceOpen: _usbiDeviceOpen,
          dspWritesDisabled: _dspWritesDisabledForSession,
        ),
      ]),
    );
  }
}

// ── Phase U1: Address Validation Status ──────────────────────────────────────

class _AddressValidationStatusPanel extends StatelessWidget {
  const _AddressValidationStatusPanel();

  @override
  Widget build(BuildContext context) {
    final registry = createTunaiAdau1466ThreeWayRegistry();
    final muteCount    = registry.countByKind(DspParameterKind.mute);
    final gainCount    = registry.countByKind(DspParameterKind.gain);
    final delayCount   = registry.countByKind(DspParameterKind.delay);
    final xoCount      = registry.countByKind(DspParameterKind.crossover);
    final safeloadCount = registry.countByKind(DspParameterKind.safeload);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _HwStatusRow(
          label: 'Master Volume L/R',
          status: 'PASS_ACK',
          eligible: true,
          detail: '0x0067 / 0x0064 — audible verification pending',
        ),
        const SizedBox(height: 6),
        _HwStatusRow(
          label: 'SafeLoad ($safeloadCount registers)',
          status: 'Export Confirmed',
          eligible: false,
          detail: '0x6000–0x6007 — needs live validation',
        ),
        const SizedBox(height: 6),
        _HwStatusRow(
          label: 'Mute ($muteCount channels)',
          status: 'Export Confirmed',
          eligible: false,
          detail: 'Blocked for actual write until capture',
        ),
        const SizedBox(height: 6),
        _HwStatusRow(
          label: 'Gain / Driver ($gainCount)',
          status: 'Export Confirmed',
          eligible: false,
          detail: 'Blocked for actual write until capture',
        ),
        const SizedBox(height: 6),
        _HwStatusRow(
          label: 'Delay ($delayCount channels)',
          status: 'Export Confirmed',
          eligible: false,
          detail: 'Blocked for actual write until capture',
        ),
        const SizedBox(height: 6),
        _HwStatusRow(
          label: 'XO — HPF + LPF ($xoCount coefficients)',
          status: 'Export Confirmed',
          eligible: false,
          detail: 'Safeload candidate — needs validation',
        ),
        const SizedBox(height: 6),
        _HwStatusRow(
          label: 'PEQ Coefficients (${registry.peqRowCount} rows)',
          status: 'Export Confirmed',
          eligible: false,
          detail: 'Safeload candidate — blocked until XO validated',
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.07),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            'Export-confirmed address requires live validation before hardware write. '
            'Only Verified addresses pass actual write guard.',
            style: proSubtitle(size: 9),
          ),
        ),
      ]),
    );
  }
}

class _HwStatusRow extends StatelessWidget {
  final String label;
  final String status;
  final bool eligible;
  final String detail;
  const _HwStatusRow({
    required this.label,
    required this.status,
    required this.eligible,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final color = eligible ? Colors.greenAccent : Colors.orange;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(eligible ? Icons.check_circle_outline : Icons.info_outline,
          size: 12, color: color),
      const SizedBox(width: 6),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label, style: proSubtitle(size: 10))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(status, style: TextStyle(fontSize: 8, color: color)),
            ),
          ]),
          Text(detail, style: proSubtitle(size: 9)),
        ]),
      ),
    ]);
  }
}

// ── Phase U1: Live Validation Queue ──────────────────────────────────────────

class _LiveValidationQueuePanel extends StatelessWidget {
  const _LiveValidationQueuePanel();

  static const _steps = [
    (order: '1', label: 'Master Volume L/R', note: 'PASS_ACK — audible verification pending', done: false),
    (order: '2', label: 'SafeLoad Protocol', note: '0x6000–0x6007 — data + trigger', done: false),
    (order: '3', label: 'Mute — 1 channel', note: 'Confirm mute state effect', done: false),
    (order: '4', label: 'Gain — 1 channel', note: 'Confirm level change effect', done: false),
    (order: '5', label: 'Delay — 1 channel', note: 'Confirm timing offset effect', done: false),
    (order: '6', label: 'PEQ Band 1 — 1 channel', note: 'Verify coefficient write via SafeLoad', done: false),
    (order: '7', label: 'XO HPF + LPF — last', note: 'Requires SafeLoad + routing verify', done: false),
  ];

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        'Recommended order for one-parameter-at-a-time live capture.',
        style: proSubtitle(size: 9),
      ),
      const SizedBox(height: 8),
      for (final step in _steps) ...[
        _ValidationStep(
          order: step.order,
          label: step.label,
          note: step.note,
          done: step.done,
        ),
        const SizedBox(height: 5),
      ],
      const SizedBox(height: 6),
      Text(
        'Do not add actual write buttons for unvalidated groups. '
        'Each step requires expert confirmation before advancing.',
        style: proSubtitle(size: 9),
      ),
    ]),
  );
}

class _ValidationStep extends StatelessWidget {
  final String order;
  final String label;
  final String note;
  final bool done;
  const _ValidationStep({
    required this.order,
    required this.label,
    required this.note,
    required this.done,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: done
            ? Colors.greenAccent.withValues(alpha: 0.15)
            : kProBorder.withValues(alpha: 0.3),
        border: Border.all(
            color: done ? Colors.greenAccent.withValues(alpha: 0.4) : kProBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(order,
          style: TextStyle(
              fontSize: 9,
              color: done ? Colors.greenAccent : Colors.white38,
              fontWeight: FontWeight.w600)),
    ),
    const SizedBox(width: 8),
    Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                fontSize: 10,
                color: done ? Colors.greenAccent : Colors.white70)),
        Text(note, style: proSubtitle(size: 9)),
      ]),
    ),
    if (done)
      const Icon(Icons.check_circle_outline, size: 12, color: Colors.greenAccent),
  ]);
}

// ── Section Header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SectionHeader(this.label, this.icon);

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: Colors.white38, size: 13),
    const SizedBox(width: 6),
    Text(label, style: proLabel(size: 9, spacing: 2)),
  ]);
}

// ── Connection Panel ──────────────────────────────────────────────────────────

class _ConnectionPanel extends StatelessWidget {
  final HardwareConnectionState conn;
  final ValueChanged<HardwareTransportType> onTransport;
  final ValueChanged<HardwareTargetDevice> onTarget;
  final VoidCallback onCheck;

  const _ConnectionPanel({
    required this.conn,
    required this.onTransport,
    required this.onTarget,
    required this.onCheck,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Transport selector
        Text('TRANSPORT', style: proLabel(size: 9, color: Colors.white38, spacing: 1.5)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final t in [
            HardwareTransportType.simulationOnly,
            HardwareTransportType.usbi,
            HardwareTransportType.ble,
            HardwareTransportType.usbAudio,
          ])
            _SelectChip(
              label: t.label,
              selected: conn.transportType == t,
              onTap: () => onTransport(t),
            ),
        ]),
        const SizedBox(height: 12),

        // Device target
        Text('DEVICE TARGET', style: proLabel(size: 9, color: Colors.white38, spacing: 1.5)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final d in [
            HardwareTargetDevice.simulation,
            HardwareTargetDevice.adau1466,
            HardwareTargetDevice.adau1701,
            HardwareTargetDevice.aosBox,
          ])
            _SelectChip(
              label: d.label,
              selected: conn.targetDevice == d,
              onTap: () => onTarget(d),
            ),
        ]),
        const SizedBox(height: 12),

        // Status row
        Row(children: [
          _StatusDot(status: conn.connectionStatus),
          const SizedBox(width: 8),
          Text(conn.connectionStatus.label,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const Spacer(),
          if (conn.lastCheckedAt != null)
            Text(
              'Last checked: ${_timeLabel(conn.lastCheckedAt!)}',
              style: proSubtitle(size: 9),
            ),
        ]),
        const SizedBox(height: 10),

        // Check connection button
        GestureDetector(
          onTap: onCheck,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: kProSurface,
              border: Border.all(color: kProBorder),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.refresh_outlined, size: 13, color: Colors.white38),
              const SizedBox(width: 6),
              Text('Check Connection Placeholder',
                  style: proLabel(size: 10, color: Colors.white38, spacing: 0)),
            ]),
          ),
        ),
        const SizedBox(height: 4),
        Text('Simulated status only. No real hardware scan.',
            style: proSubtitle(size: 9)),
      ]),
    );
  }

  String _timeLabel(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    return '${diff.inMinutes}m ago';
  }
}

class _StatusDot extends StatelessWidget {
  final HardwareConnectionStatus status;
  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      HardwareConnectionStatus.connected  => kProGreen,
      HardwareConnectionStatus.simulated  => const Color(0xFF4A9EFF),
      HardwareConnectionStatus.detected   => const Color(0xFF4A9EFF),
      HardwareConnectionStatus.error      => const Color(0xFFEF4444),
      HardwareConnectionStatus.unauthorized => kProAmber,
      HardwareConnectionStatus.driverMissing => kProAmber,
      _                                   => Colors.white24,
    };
    return Container(
      width: 8, height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _SelectChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SelectChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? kProAccent.withValues(alpha: 0.12) : kProSurface,
        border: Border.all(
            color: selected
                ? kProAccent.withValues(alpha: 0.5)
                : kProBorder),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              color: selected ? kProAccent : Colors.white38)),
    ),
  );
}

// ── Export Package Panel ──────────────────────────────────────────────────────

class _ExportPackagePanel extends StatelessWidget {
  final DspExportPackage? pkg;
  final dynamic protection; // ProtectionProjectState
  const _ExportPackagePanel({this.pkg, this.protection});

  @override
  Widget build(BuildContext context) {
    if (pkg == null) {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: kProSurface,
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline, color: Colors.white24, size: 13),
          const SizedBox(width: 8),
          Text('No export package. Generate an export draft first.',
              style: proSubtitle()),
        ]),
      );
    }

    final hasMapping = pkg!.sigmaMappingReferenceJson != null;
    final hasFP = pkg!.fixedPointDraftJson != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _InfoRow('Target', pkg!.targetPlatform.label),
        const SizedBox(height: 4),
        _InfoRow('Format', pkg!.format.label),
        const SizedBox(height: 4),
        _InfoRow('Status', pkg!.status.label),
        const SizedBox(height: 4),
        _InfoRow('Sigma Mapping', hasMapping ? 'Present' : 'Not generated'),
        const SizedBox(height: 4),
        _InfoRow('Fixed-point Draft', hasFP ? 'Present' : 'Not generated'),
        const SizedBox(height: 4),
        _InfoRow('Warnings', '${pkg!.warningCount}'),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Row(children: [
    Text('$label:', style: proLabel(size: 9, color: Colors.white38, spacing: 0)),
    const SizedBox(width: 8),
    Text(value, style: const TextStyle(color: Colors.white70, fontSize: 10)),
  ]);
}

// ── Guard Checklist Panel ─────────────────────────────────────────────────────

class _GuardChecklistPanel extends StatelessWidget {
  final HardwareWritePlan plan;
  const _GuardChecklistPanel({required this.plan});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const _GuardPill(HardwareGuardStatus.pass),
          const SizedBox(width: 6),
          Text('${plan.guardChecks.where((c) => c.status == HardwareGuardStatus.pass).length}',
              style: const TextStyle(fontSize: 10, color: Colors.white54)),
          const SizedBox(width: 12),
          const _GuardPill(HardwareGuardStatus.warning),
          const SizedBox(width: 6),
          Text('${plan.warningCheckCount}',
              style: const TextStyle(fontSize: 10, color: Colors.white54)),
          const SizedBox(width: 12),
          const _GuardPill(HardwareGuardStatus.blocked),
          const SizedBox(width: 6),
          Text('${plan.blockedCheckCount}',
              style: const TextStyle(fontSize: 10, color: Colors.white54)),
        ]),
        const SizedBox(height: 10),
        ...plan.guardChecks.map((c) => _GuardCheckRow(check: c)),
      ]),
    );
  }
}

class _GuardCheckRow extends StatelessWidget {
  final HardwareGuardCheck check;
  const _GuardCheckRow({required this.check});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _GuardPill(check.status),
        const SizedBox(width: 8),
        Expanded(
          child: Text(check.title,
              style: const TextStyle(color: Colors.white70, fontSize: 10,
                  fontWeight: FontWeight.w500)),
        ),
      ]),
      Padding(
        padding: const EdgeInsets.only(left: 52, top: 2),
        child: Text(check.description, style: proSubtitle(size: 9)),
      ),
      if (check.recommendation != null)
        Padding(
          padding: const EdgeInsets.only(left: 52, top: 1),
          child: Text('→ ${check.recommendation}',
              style: proSubtitle(size: 9, color: kProAmber.withValues(alpha: 0.7))),
        ),
    ]),
  );
}

class _GuardPill extends StatelessWidget {
  final HardwareGuardStatus status;
  const _GuardPill(this.status);

  @override
  Widget build(BuildContext context) {
    final (color, bg) = switch (status) {
      HardwareGuardStatus.pass  => (kProGreen, kProGreen.withValues(alpha: 0.12)),
      HardwareGuardStatus.warning => (kProAmber, kProAmber.withValues(alpha: 0.12)),
      HardwareGuardStatus.blocked => (const Color(0xFFEF4444), const Color(0xFFEF4444).withValues(alpha: 0.12)),
      HardwareGuardStatus.notApplicable => (Colors.white24, Colors.white.withValues(alpha: 0.04)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(status.label, style: TextStyle(fontSize: 8, color: color)),
    );
  }
}

// ── Write Plan Panel ──────────────────────────────────────────────────────────

class _WritePlanPanel extends StatelessWidget {
  final HardwareWritePlan plan;
  const _WritePlanPanel({required this.plan});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: kProAmber.withValues(alpha: 0.12),
              border: Border.all(color: kProAmber.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text('DRY RUN ONLY',
                style: TextStyle(fontSize: 8, color: kProAmber,
                    fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          ),
          const SizedBox(width: 10),
          Text(plan.summary, style: proSubtitle(size: 9)),
        ]),
        const SizedBox(height: 10),
        if (plan.steps.isEmpty)
          Text('No write steps generated.', style: proSubtitle())
        else ...[
          // Column headers
          Row(children: [
            SizedBox(width: 24, child: Text('#', style: proLabel(size: 8, spacing: 0, color: Colors.white24))),
            Expanded(flex: 3, child: Text('LOGICAL NAME', style: proLabel(size: 8, spacing: 0, color: Colors.white24))),
            SizedBox(width: 60, child: Text('ADDRESS', style: proLabel(size: 8, spacing: 0, color: Colors.white24))),
            SizedBox(width: 50, child: Text('VERIFIED', style: proLabel(size: 8, spacing: 0, color: Colors.white24))),
            SizedBox(width: 55, child: Text('STATUS', style: proLabel(size: 8, spacing: 0, color: Colors.white24))),
          ]),
          const SizedBox(height: 6),
          const Divider(color: kProBorder, height: 1),
          const SizedBox(height: 4),
          ...plan.steps.map((s) => _StepRow(step: s)),
        ],
      ]),
    );
  }
}

class _StepRow extends StatelessWidget {
  final HardwareWritePlanStep step;
  const _StepRow({required this.step});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        SizedBox(
          width: 24,
          child: Text('${step.order + 1}',
              style: proSubtitle(size: 9)),
        ),
        Expanded(
          flex: 3,
          child: Text(step.logicalName,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
              overflow: TextOverflow.ellipsis),
        ),
        SizedBox(
          width: 60,
          child: Text(step.addressHex ?? '—',
              style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: step.addressHex != null
                      ? const Color(0xFF4A9EFF)
                      : Colors.white24)),
        ),
        SizedBox(
          width: 50,
          child: Text(step.addressVerified ? 'Yes' : 'No',
              style: TextStyle(
                  fontSize: 9,
                  color: step.addressVerified ? kProGreen : Colors.white38)),
        ),
        SizedBox(width: 55, child: _GuardPill(step.status)),
      ]),
      if (step.warning != null)
        Padding(
          padding: const EdgeInsets.only(left: 24, top: 1),
          child: Text(step.warning!,
              style: proSubtitle(size: 9, color: kProAmber.withValues(alpha: 0.7))),
        ),
    ]),
  );
}

// ── Controlled Master Volume Write Panel (Phase T) ────────────────────────────

class _ControlledWritePanel extends StatelessWidget {
  final double leftVolume;
  final double rightVolume;
  final List<HardwareWriteRequest>? dryRunRequests;
  final bool userConfirmed;
  final bool writing;
  final HardwareWriteLog? lastLog;
  final ValueChanged<double> onLeftChanged;
  final ValueChanged<double> onRightChanged;
  final VoidCallback onGenerateDryRun;
  final ValueChanged<bool> onConfirmChanged;
  final VoidCallback onWrite;

  const _ControlledWritePanel({
    required this.leftVolume,
    required this.rightVolume,
    required this.dryRunRequests,
    required this.userConfirmed,
    required this.writing,
    required this.lastLog,
    required this.onLeftChanged,
    required this.onRightChanged,
    required this.onGenerateDryRun,
    required this.onConfirmChanged,
    required this.onWrite,
  });

  bool get _canWrite =>
      dryRunRequests != null &&
      userConfirmed &&
      !writing &&
      !ProUsbiTransport.isPlaceholder;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Safety banner
      Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withValues(alpha: 0.07),
          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.warning_amber_outlined, color: Color(0xFFEF4444), size: 13),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Experimental volatile write. ADAU1466 Master Volume only.\n'
              'Only addresses 0x67 (L) and 0x64 (R) are allowed. '
              'No EEPROM. No Selfboot. No SafeLoad. No Write-All.\n'
              'USBi write backend is not enabled in Phase T2. '
              'Detection does not imply write permission. '
              'Actual write remains disabled.',
              style: TextStyle(fontSize: 9, color: Color(0xFFEF4444), height: 1.5),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 14),

      // Volume sliders
      Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: kProSurface,
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('VOLUME TARGET (0.0 – 1.0)', style: proLabel(size: 9, spacing: 1.8)),
          const SizedBox(height: 12),
          _VolumeRow(
            label: 'Master Volume L  (0x67)',
            value: leftVolume,
            onChanged: onLeftChanged,
          ),
          const SizedBox(height: 8),
          _VolumeRow(
            label: 'Master Volume R  (0x64)',
            value: rightVolume,
            onChanged: onRightChanged,
          ),
        ]),
      ),
      const SizedBox(height: 10),

      // Generate Dry Run button
      GestureDetector(
        onTap: onGenerateDryRun,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: kProAccent.withValues(alpha: 0.08),
            border: Border.all(color: kProAccent.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.preview_outlined, size: 14, color: kProAccent),
            SizedBox(width: 8),
            Text('Generate Dry Run',
                style: TextStyle(fontSize: 12, color: kProAccent,
                    fontWeight: FontWeight.w500)),
          ]),
        ),
      ),
      const SizedBox(height: 10),

      // Dry-run request preview
      if (dryRunRequests != null) ...[
        _DryRunPreviewPanel(requests: dryRunRequests!),
        const SizedBox(height: 12),

        // Confirmation checkbox
        GestureDetector(
          onTap: () => onConfirmChanged(!userConfirmed),
          child: Row(children: [
            Container(
              width: 16, height: 16,
              decoration: BoxDecoration(
                color: userConfirmed
                    ? kProAccent.withValues(alpha: 0.2)
                    : kProSurface,
                border: Border.all(
                    color: userConfirmed ? kProAccent : kProBorder),
                borderRadius: BorderRadius.circular(3),
              ),
              child: userConfirmed
                  ? const Icon(Icons.check, size: 11, color: kProAccent)
                  : null,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'I understand this is a volatile ADAU1466 Master Volume write only. '
                'No EEPROM. No Selfboot. No SafeLoad. No other registers.',
                style: TextStyle(fontSize: 10, color: Colors.white60, height: 1.4),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),

        // Write button
        _WriteButton(
          canWrite:  _canWrite,
          writing:   writing,
          onWrite:   onWrite,
        ),
        const SizedBox(height: 6),
        const Text(
          'Write disabled — USBi write backend is not enabled in Phase T2. '
          'Detection does not imply write permission. '
          'Actual write remains disabled.',
          style: TextStyle(fontSize: 9, color: Colors.white38, height: 1.4),
        ),
        const SizedBox(height: 12),
      ],

      // Write log
      if (lastLog != null) ...[
        _WriteLogPanel(log: lastLog!),
      ],
    ]);
  }
}

class _VolumeRow extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  const _VolumeRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
    SizedBox(
      width: 190,
      child: Text(label,
          style: const TextStyle(fontSize: 10, color: Colors.white60,
              fontFamily: 'monospace')),
    ),
    Expanded(
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: kProAccent.withValues(alpha: 0.7),
          inactiveTrackColor: kProBorder,
          thumbColor: kProAccent,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          trackHeight: 2,
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        ),
        child: Slider(
          value: value,
          min: 0.0, max: 1.0,
          divisions: 100,
          onChanged: onChanged,
        ),
      ),
    ),
    SizedBox(
      width: 42,
      child: Text(value.toStringAsFixed(2),
          style: const TextStyle(fontSize: 10, color: Colors.white70,
              fontFamily: 'monospace'),
          textAlign: TextAlign.right),
    ),
  ]);
}

class _DryRunPreviewPanel extends StatelessWidget {
  final List<HardwareWriteRequest> requests;
  const _DryRunPreviewPanel({required this.requests});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: kProAccent.withValues(alpha: 0.10),
            border: Border.all(color: kProAccent.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: const Text('DRY RUN',
              style: TextStyle(fontSize: 8, color: kProAccent,
                  fontWeight: FontWeight.w600, letterSpacing: 0.6)),
        ),
        const SizedBox(width: 8),
        Text('${requests.length} write requests',
            style: proSubtitle(size: 9)),
      ]),
      const SizedBox(height: 10),
      // Header row
      Row(children: [
        Expanded(flex: 3, child: Text('TARGET', style: proLabel(size: 8, spacing: 0, color: Colors.white24))),
        SizedBox(width: 56, child: Text('ADDRESS', style: proLabel(size: 8, spacing: 0, color: Colors.white24))),
        SizedBox(width: 36, child: Text('VALUE', style: proLabel(size: 8, spacing: 0, color: Colors.white24))),
        SizedBox(width: 88, child: Text('FIXED-POINT HEX', style: proLabel(size: 8, spacing: 0, color: Colors.white24))),
      ]),
      const SizedBox(height: 6),
      const Divider(color: kProBorder, height: 1),
      const SizedBox(height: 4),
      ...requests.map((r) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(
            flex: 3,
            child: Text(r.target.label,
                style: const TextStyle(fontSize: 10, color: Colors.white70),
                overflow: TextOverflow.ellipsis),
          ),
          SizedBox(
            width: 56,
            child: Text(r.addressHex,
                style: const TextStyle(fontSize: 10, color: Color(0xFF4A9EFF),
                    fontFamily: 'monospace')),
          ),
          SizedBox(
            width: 36,
            child: Text(r.valueDouble.toStringAsFixed(2),
                style: const TextStyle(fontSize: 10, color: Colors.white54,
                    fontFamily: 'monospace')),
          ),
          SizedBox(
            width: 88,
            child: Text(r.fixedPointHex,
                style: const TextStyle(fontSize: 10, color: Colors.white38,
                    fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis),
          ),
        ]),
      )),
    ]),
  );
}

class _WriteButton extends StatelessWidget {
  final bool canWrite;
  final bool writing;
  final VoidCallback onWrite;
  const _WriteButton({
    required this.canWrite,
    required this.writing,
    required this.onWrite,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: canWrite ? onWrite : null,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: canWrite
            ? const Color(0xFFEF4444).withValues(alpha: 0.12)
            : kProSurface,
        border: Border.all(
          color: canWrite
              ? const Color(0xFFEF4444).withValues(alpha: 0.5)
              : kProBorder,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          writing
              ? Icons.hourglass_empty_outlined
              : Icons.send_outlined,
          size: 14,
          color: canWrite
              ? const Color(0xFFEF4444)
              : Colors.white24,
        ),
        const SizedBox(width: 8),
        Text(
          writing
              ? 'Writing…'
              : 'Write Master Volume',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: canWrite
                ? const Color(0xFFEF4444)
                : Colors.white24,
          ),
        ),
      ]),
    ),
  );
}

class _WriteLogPanel extends StatelessWidget {
  final HardwareWriteLog log;
  const _WriteLogPanel({required this.log});

  @override
  Widget build(BuildContext context) {
    final result = log.result;
    final status = result?.status ?? HardwareWriteStatus.notStarted;
    final statusColor = switch (status) {
      HardwareWriteStatus.success  => kProGreen,
      HardwareWriteStatus.failed   => const Color(0xFFEF4444),
      HardwareWriteStatus.blocked  => kProAmber,
      _                            => Colors.white38,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('WRITE LOG', style: proLabel(size: 9, spacing: 1.8)),
        const SizedBox(height: 10),
        _InfoRow('Log ID', log.id),
        _InfoRow('Status', status.label),
        _InfoRow('Timestamp',
            log.createdAt.toIso8601String().substring(0, 19)),
        _InfoRow('User Confirmed', log.userConfirmed ? 'Yes' : 'No'),
        _InfoRow('Actual Write', result?.wasActualWrite == true ? 'Yes' : 'No'),
        if (result?.errorMessage != null)
          _InfoRow('Error', result!.errorMessage!),
        const SizedBox(height: 8),
        Row(children: [
          const Text('STATUS  ',
              style: TextStyle(fontSize: 9, color: Colors.white38,
                  letterSpacing: 1)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              border: Border.all(color: statusColor.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(status.label,
                style: TextStyle(fontSize: 9, color: statusColor,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          result?.safetyNote ?? 'No write occurred.',
          style: proSubtitle(size: 9, color: Colors.white24),
        ),
        if (log.sessionNote.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(log.sessionNote, style: proSubtitle(size: 9)),
        ],
      ]),
    );
  }
}

// ── Warnings Panel ────────────────────────────────────────────────────────────

class _WarningsPanel extends StatelessWidget {
  final HardwareWritePlan plan;
  const _WarningsPanel({required this.plan});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kProAmber.withValues(alpha: 0.04),
        border: Border.all(color: kProAmber.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (plan.blockedReason != null) ...[
          Row(children: [
            const Icon(Icons.block_outlined, size: 12, color: kProAmber),
            const SizedBox(width: 6),
            Expanded(
              child: Text(plan.blockedReason!,
                  style: const TextStyle(fontSize: 10, color: kProAmber,
                      fontWeight: FontWeight.w500)),
            ),
          ]),
          const SizedBox(height: 6),
        ],
        ...plan.warnings.map((w) => Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('• ', style: TextStyle(fontSize: 9, color: Colors.white38)),
            Expanded(child: Text(w, style: proSubtitle(size: 9))),
          ]),
        )),
      ]),
    );
  }
}

// ── Phase U2: Address Live Validation Manager ─────────────────────────────────

class _ValidationManagerPanel extends StatelessWidget {
  final AddressValidationProjectState validationState;
  final bool generating;
  final String? activeTaskId;
  final VoidCallback onGenerate;
  final void Function(String?) onSelectTask;
  final Future<void> Function(String) onMarkFailed;
  final Future<void> Function(String) onMarkBlocked;

  const _ValidationManagerPanel({
    required this.validationState,
    required this.generating,
    required this.activeTaskId,
    required this.onGenerate,
    required this.onSelectTask,
    required this.onMarkFailed,
    required this.onMarkBlocked,
  });

  @override
  Widget build(BuildContext context) {
    final tasks = validationState.tasks;
    final hasQueue = tasks.isNotEmpty;
    final activeTask = activeTaskId != null
        ? tasks.where((t) => t.id == activeTaskId).firstOrNull
        : null;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Summary chips
      if (hasQueue) ...[
        Wrap(spacing: 8, runSpacing: 6, children: [
          _ValChip('Queued', validationState.queuedCount, Colors.blue),
          _ValChip('Verified', validationState.verifiedCount, Colors.greenAccent),
          _ValChip('Failed', validationState.failedCount, Colors.redAccent),
          _ValChip('Blocked', validationState.blockedCount, Colors.orange),
          _ValChip('High Risk', validationState.highRiskCount, Colors.purpleAccent),
        ]),
        const SizedBox(height: 12),
      ],

      // Generate queue button
      GestureDetector(
        onTap: generating ? null : onGenerate,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: generating ? kProSurface : kProAccent.withValues(alpha: 0.08),
            border: Border.all(
                color: generating ? kProBorder : kProAccent.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              generating ? Icons.hourglass_empty_outlined : Icons.playlist_add_outlined,
              size: 14,
              color: generating ? Colors.white24 : kProAccent,
            ),
            const SizedBox(width: 7),
            Text(
              generating
                  ? 'Generating queue...'
                  : hasQueue
                      ? 'Regenerate Validation Queue'
                      : 'Generate Validation Queue',
              style: TextStyle(
                fontSize: 11,
                color: generating ? Colors.white24 : kProAccent,
                fontWeight: FontWeight.w500,
              ),
            ),
          ]),
        ),
      ),

      // Safety note
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: kProSurface,
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline, size: 11, color: Colors.white38),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'Validation manager does not write hardware. '
              'It records readiness and observed results for expert review.',
              style: proSubtitle(size: 9),
            ),
          ),
        ]),
      ),

      // Task list
      if (hasQueue) ...[
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: kProSurface,
            border: Border.all(color: kProBorder),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(children: [
            for (int i = 0; i < tasks.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: kProBorder),
              _ValidationTaskRow(
                task: tasks[i],
                isActive: tasks[i].id == activeTaskId,
                onTap: () => onSelectTask(
                    tasks[i].id == activeTaskId ? null : tasks[i].id),
              ),
            ],
          ]),
        ),
      ],

      // Active task detail
      if (activeTask != null) ...[
        const SizedBox(height: 12),
        _ActiveTaskDetail(
          task: activeTask,
          onMarkFailed: () => onMarkFailed(activeTask.id),
          onMarkBlocked: () => onMarkBlocked(activeTask.id),
        ),
      ],
    ]);
  }
}

class _ValChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _ValChip(this.label, this.count, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      border: Border.all(color: color.withValues(alpha: 0.35)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text('$label  $count',
        style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w600)),
  );
}

class _ValidationTaskRow extends StatelessWidget {
  final AddressValidationTask task;
  final bool isActive;
  final VoidCallback onTap;
  const _ValidationTaskRow({
    required this.task,
    required this.isActive,
    required this.onTap,
  });

  Color get _riskColor => switch (task.risk) {
    AddressValidationRisk.low      => Colors.greenAccent,
    AddressValidationRisk.medium   => kProAmber,
    AddressValidationRisk.high     => Colors.orange,
    AddressValidationRisk.critical => Colors.redAccent,
  };

  Color get _statusColor => switch (task.currentStatus) {
    AddressValidationStatus.liveWriteVerified => Colors.greenAccent,
    AddressValidationStatus.failed            => Colors.redAccent,
    AddressValidationStatus.blocked           => Colors.orange,
    AddressValidationStatus.queued            => Colors.blue,
    _                                         => Colors.white38,
  };

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Container(
      color: isActive ? kProAccent.withValues(alpha: 0.05) : Colors.transparent,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(children: [
        // Group badge
        Container(
          width: 60,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(task.group.label,
              style: const TextStyle(fontSize: 8, color: Colors.white54),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        // Name + address
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(task.logicalName,
                style: const TextStyle(fontSize: 10, color: Colors.white70),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(task.addressHex,
                style: const TextStyle(fontSize: 9, color: Colors.white38,
                    fontFamily: 'monospace')),
          ]),
        ),
        const SizedBox(width: 8),
        // Risk
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: _riskColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(task.risk.label,
              style: TextStyle(fontSize: 8, color: _riskColor)),
        ),
        const SizedBox(width: 6),
        // Status
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: _statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(task.currentStatus.label,
              style: TextStyle(fontSize: 8, color: _statusColor)),
        ),
        if (isActive) ...[
          const SizedBox(width: 6),
          const Icon(Icons.keyboard_arrow_up, size: 12, color: kProAccent),
        ],
      ]),
    ),
  );
}

class _ActiveTaskDetail extends StatelessWidget {
  final AddressValidationTask task;
  final VoidCallback onMarkFailed;
  final VoidCallback onMarkBlocked;
  const _ActiveTaskDetail({
    required this.task,
    required this.onMarkFailed,
    required this.onMarkBlocked,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProAccent.withValues(alpha: 0.25)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(task.logicalName,
            style: proLabel(size: 11)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: const Text('DRY-RUN ONLY',
              style: TextStyle(fontSize: 8, color: Colors.orange,
                  fontWeight: FontWeight.w600, letterSpacing: 0.6)),
        ),
      ]),
      const SizedBox(height: 8),
      _DetailRow('Address', task.addressHex),
      _DetailRow('Group', task.group.label),
      _DetailRow('Risk', task.risk.label),
      _DetailRow('Status', task.currentStatus.label),
      if (task.channel != null) _DetailRow('Channel', task.channel!),
      if (task.outputIndex != null) _DetailRow('Output', task.outputIndex!),
      if (task.coefficient != null) _DetailRow('Coefficient', task.coefficient!),
      if (task.expectedEffect != null) ...[
        const SizedBox(height: 6),
        Text('Expected Effect', style: proSubtitle(size: 9, color: Colors.white38)),
        const SizedBox(height: 3),
        Text(task.expectedEffect!,
            style: const TextStyle(fontSize: 10, color: Colors.white60)),
      ],
      if (task.actualObservedEffect != null) ...[
        const SizedBox(height: 6),
        Text('Observed', style: proSubtitle(size: 9, color: Colors.white38)),
        const SizedBox(height: 3),
        Text(task.actualObservedEffect!,
            style: const TextStyle(fontSize: 10, color: Colors.white60)),
      ],
      const SizedBox(height: 10),
      // Buttons
      Row(children: [
        // Mark Verified — disabled until wasActualWrite in future phases
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: kProSurface,
            border: Border.all(color: kProBorder),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text('Mark Verified (disabled — Phase U2)',
              style: TextStyle(fontSize: 9, color: Colors.white24)),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onMarkFailed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.08),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('Mark Failed',
                style: TextStyle(fontSize: 9, color: Colors.redAccent)),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onMarkBlocked,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('Block',
                style: TextStyle(fontSize: 9, color: Colors.orange)),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Text(
        'Validation manager does not write hardware. '
        '"Mark Verified" requires wasActualWrite = true, '
        'which is only enabled in future write phases.',
        style: proSubtitle(size: 9),
      ),
    ]),
  );
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(children: [
      SizedBox(
        width: 72,
        child: Text(label,
            style: const TextStyle(fontSize: 9, color: Colors.white38)),
      ),
      Expanded(
        child: Text(value,
            style: const TextStyle(fontSize: 9, color: Colors.white60)),
      ),
    ]),
  );
}


// ── Phase T2 Revised: Transport Readiness Panel ───────────────────────────────

class _TransportReadinessPanel extends StatelessWidget {
  final HardwareTransportBackend selectedBackend;
  final List<HardwareTransportInfo> transportInfos;
  final bool checking;
  final String? checkMessage;
  final DateTime? lastChecked;
  final VoidCallback onCheck;
  final void Function(HardwareTransportBackend) onSelect;
  final bool realUsbiExecutorAvailable;

  const _TransportReadinessPanel({
    required this.selectedBackend,
    required this.transportInfos,
    required this.checking,
    required this.checkMessage,
    required this.lastChecked,
    required this.onCheck,
    required this.onSelect,
    this.realUsbiExecutorAvailable = false,
  });

  @override
  Widget build(BuildContext context) {
    final selectedInfo = transportInfos
        .where((t) => t.backend == selectedBackend)
        .firstOrNull;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Transport selector chips
      Wrap(spacing: 8, runSpacing: 6, children: [
        for (final t in transportInfos)
          _TransportChip(
            info: t,
            isSelected: t.backend == selectedBackend,
            onTap: () => onSelect(t.backend),
          ),
      ]),
      const SizedBox(height: 12),

      // Selected transport detail card
      if (selectedInfo != null)
        _TransportDetailCard(
          info: selectedInfo,
          realUsbiExecutorAvailable: realUsbiExecutorAvailable,
        ),
      const SizedBox(height: 10),

      // Action row
      Row(children: [
        GestureDetector(
          onTap: checking ? null : onCheck,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: checking
                  ? kProSurface
                  : kProAccent.withValues(alpha: 0.08),
              border: Border.all(
                  color: checking
                      ? kProBorder
                      : kProAccent.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                checking
                    ? Icons.hourglass_empty_outlined
                    : Icons.radar_outlined,
                size: 13,
                color: checking ? Colors.white24 : kProAccent,
              ),
              const SizedBox(width: 7),
              Text(
                checking ? 'Checking...' : 'Check Transport Readiness',
                style: TextStyle(
                  fontSize: 11,
                  color: checking ? Colors.white24 : kProAccent,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () => onSelect(HardwareTransportBackend.simulation),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: kProSurface,
              border: Border.all(color: kProBorder),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('Clear Selection',
                style: TextStyle(fontSize: 10, color: Colors.white38)),
          ),
        ),
      ]),

      // Check result message
      if (checkMessage != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            border: Border.all(color: kProBorder),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(checkMessage!, style: proSubtitle(size: 9)),
        ),
      ],

      // Global safety note
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: kProSurface,
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline, size: 11, color: Colors.white38),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              selectedBackend == HardwareTransportBackend.usbiWindowsTemporary
                  ? 'USBi Temporary executor available. '
                    'Master Volume L/R only. '
                    'All other writes remain blocked.'
                  : 'No transport backend is enabled for hardware write in this build. '
                    'Transport selection does not enable write. '
                    'Write capability remains: Dry-Run Only.',
              style: proSubtitle(size: 9),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _TransportChip extends StatelessWidget {
  final HardwareTransportInfo info;
  final bool isSelected;
  final VoidCallback onTap;
  const _TransportChip({
    required this.info,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isSelected ? kProAccent : Colors.white38;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? kProAccent.withValues(alpha: 0.08)
              : kProSurface,
          border: Border.all(
              color: isSelected
                  ? kProAccent.withValues(alpha: 0.4)
                  : kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(info.displayName,
              style: TextStyle(
                  fontSize: 10, color: accent, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(info.platformHint,
              style: const TextStyle(fontSize: 8, color: Colors.white24)),
          if (info.backend.isTemporary)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('TEMPORARY',
                  style: TextStyle(
                      fontSize: 7,
                      color: Colors.orange.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)),
            ),
          if (info.backend.isFinalTarget)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('FINAL TARGET',
                  style: TextStyle(
                      fontSize: 7,
                      color: Colors.greenAccent.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)),
            ),
        ]),
      ),
    );
  }
}

class _TransportDetailCard extends StatelessWidget {
  final HardwareTransportInfo info;
  final bool realUsbiExecutorAvailable;
  const _TransportDetailCard({
    required this.info,
    this.realUsbiExecutorAvailable = false,
  });

  Color get _readinessColor => switch (info.readinessStatus) {
    TransportReadinessStatus.detected  => Colors.greenAccent,
    TransportReadinessStatus.connected => Colors.greenAccent,
    TransportReadinessStatus.detectionOnly => kProAccent,
    TransportReadinessStatus.placeholder   => Colors.white38,
    _ => info.readinessStatus.isWarning ? Colors.orange : Colors.white38,
  };

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(color: kProAccent.withValues(alpha: 0.2)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(info.displayName,
            style: const TextStyle(fontSize: 11, color: Colors.white70,
                fontWeight: FontWeight.w500)),
        const Spacer(),
        // Write enabled: always false
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
              realUsbiExecutorAvailable ? 'MV WRITE ACTIVE' : 'WRITE DISABLED',
              style: TextStyle(fontSize: 7,
                  color: realUsbiExecutorAvailable ? kProAccent : Colors.orange,
                  fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        ),
      ]),
      const SizedBox(height: 8),
      _TrRow('Backend',    info.backend.label),
      _TrRow('Platform', realUsbiExecutorAvailable ? 'Windows' : info.platformHint),
      _TrRow('Readiness', realUsbiExecutorAvailable
              ? 'Real executor available'
              : info.readinessStatus.label,
          color: _readinessColor),
      if (!realUsbiExecutorAvailable)
        _TrRow('Write Capability', info.writeCapability.label),
      _TrRow('Write Enabled',
          realUsbiExecutorAvailable
              ? 'MV L 0x0067 · MV R 0x0064'
              : info.backend == HardwareTransportBackend.usbiWindowsTemporary
              ? 'Temporary executor unavailable'
              : 'false — Write disabled'),
      if (realUsbiExecutorAvailable) ...[
        const _TrRow('Backend available', 'yes'),
        const _TrRow('Executor', 'real'),
      ] else ...[
        _TrRow('Placeholder', info.isPlaceholder ? 'Yes' : 'No'),
        _TrRow('Detection Only', info.isDetectionOnly ? 'Yes' : 'No'),
      ],
      if (info.backend == HardwareTransportBackend.usbiWindowsTemporary)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.07),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text(
              'USBi temporary engineering transport. '
              'Use only for controlled validation. '
              'Not the primary or final transport path.',
              style: TextStyle(fontSize: 9, color: Colors.orange),
            ),
          ),
        ),
      if (info.backend == HardwareTransportBackend.icp5)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.greenAccent.withValues(alpha: 0.05),
              border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.2)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text(
              'ICP5 is the final intended transport/programmer path. '
              'Packet format and protocol are TBD by hardware team.',
              style: TextStyle(fontSize: 9, color: Colors.greenAccent),
            ),
          ),
        ),
      if (info.backend == HardwareTransportBackend.bleMacos)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.05),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text(
              'macOS BLE transport planned. '
              'Detection/write backend not enabled in this build.',
              style: TextStyle(fontSize: 9, color: Colors.blueAccent),
            ),
          ),
        ),
      if (info.lastCheckedAt != null) ...[
        const SizedBox(height: 4),
        Text(
          'Last checked: '
          '${info.lastCheckedAt!.toLocal().toString().substring(0, 19)}',
          style: const TextStyle(fontSize: 8, color: Colors.white24),
        ),
      ],
    ]),
  );
}

class _TrRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _TrRow(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(children: [
      SizedBox(
        width: 110,
        child: Text(label,
            style: const TextStyle(fontSize: 9, color: Colors.white38)),
      ),
      Expanded(
        child: Text(value,
            style: TextStyle(
                fontSize: 9,
                color: color ?? Colors.white60,
                fontWeight:
                    color != null ? FontWeight.w500 : FontWeight.normal)),
      ),
    ]),
  );
}

// ── Phase T3: Transport Command Preview Panel ─────────────────────────────────

class _TransportCommandPreviewPanel extends StatelessWidget {
  final HardwareTransportBackend selectedBackend;
  final String commandSide;
  final double commandValue;
  final TransportCommandEnvelope? envelope;
  final void Function(String) onSideChanged;
  final void Function(double) onValueChanged;
  final VoidCallback onGenerate;

  const _TransportCommandPreviewPanel({
    required this.selectedBackend,
    required this.commandSide,
    required this.commandValue,
    required this.envelope,
    required this.onSideChanged,
    required this.onValueChanged,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Transport context pill
      Row(children: [
        const Icon(Icons.compare_arrows_outlined, size: 11, color: Colors.white38),
        const SizedBox(width: 5),
        Text('Transport: ', style: proSubtitle(size: 9)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: kProAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(selectedBackend.label,
              style: const TextStyle(fontSize: 9, color: kProAccent,
                  fontWeight: FontWeight.w500)),
        ),
      ]),
      const SizedBox(height: 12),

      // L / R selector
      Row(children: [
        Text('Channel: ', style: proSubtitle(size: 9)),
        const SizedBox(width: 8),
        for (final side in ['L', 'R']) ...[
          GestureDetector(
            onTap: () => onSideChanged(side),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: commandSide == side
                    ? kProAccent.withValues(alpha: 0.12)
                    : kProSurface,
                border: Border.all(
                    color: commandSide == side
                        ? kProAccent.withValues(alpha: 0.5)
                        : kProBorder),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                side == 'L' ? 'L  0x0067' : 'R  0x0064',
                style: TextStyle(
                    fontSize: 10,
                    color: commandSide == side ? kProAccent : Colors.white38,
                    fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 12),

      // Value presets
      Row(children: [
        Text('Preset: ', style: proSubtitle(size: 9)),
        const SizedBox(width: 8),
        for (final preset in [
          (label: '1.0  Unity', value: 1.0),
          (label: '0.5  −6 dB', value: 0.5),
          (label: '0.0  Mute', value: 0.0),
        ]) ...[
          GestureDetector(
            onTap: () => onValueChanged(preset.value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: (commandValue - preset.value).abs() < 0.001
                    ? kProAccent.withValues(alpha: 0.1)
                    : kProSurface,
                border: Border.all(
                    color: (commandValue - preset.value).abs() < 0.001
                        ? kProAccent.withValues(alpha: 0.4)
                        : kProBorder),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(preset.label,
                  style: TextStyle(
                      fontSize: 9,
                      color: (commandValue - preset.value).abs() < 0.001
                          ? kProAccent
                          : Colors.white38,
                      fontFamily: 'monospace')),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 6),
      Text('Value: ${commandValue.toStringAsFixed(3)}',
          style: proSubtitle(size: 9)),
      const SizedBox(height: 12),

      // Generate button — NO send/execute button
      GestureDetector(
        onTap: onGenerate,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: kProAccent.withValues(alpha: 0.08),
            border: Border.all(color: kProAccent.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.preview_outlined, size: 13, color: kProAccent),
            const SizedBox(width: 7),
            const Text('Generate Dry-Run Command',
                style: TextStyle(fontSize: 11, color: kProAccent,
                    fontWeight: FontWeight.w500)),
          ]),
        ),
      ),
      const SizedBox(height: 4),
      Text('No Send button. No Execute button. No hardware write.',
          style: proSubtitle(size: 8)),

      // Envelope preview card
      if (envelope != null) ...[
        const SizedBox(height: 12),
        _CommandEnvelopeCard(envelope: envelope!),
      ],
    ]);
  }
}

class _CommandEnvelopeCard extends StatelessWidget {
  final TransportCommandEnvelope envelope;
  const _CommandEnvelopeCard({required this.envelope});

  Color get _statusColor => switch (envelope.status) {
    TransportCommandStatus.dryRunReady    => kProAccent,
    TransportCommandStatus.blocked        => Colors.redAccent,
    TransportCommandStatus.failed         => Colors.redAccent,
    TransportCommandStatus.transportDisabled => Colors.orange,
    _ => Colors.white38,
  };

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: kProSurface,
      border: Border.all(
          color: envelope.status == TransportCommandStatus.blocked
              ? Colors.redAccent.withValues(alpha: 0.3)
              : kProAccent.withValues(alpha: 0.2)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('COMMAND ENVELOPE', style: proLabel(size: 9, spacing: 1.5)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: _statusColor.withValues(alpha: 0.1),
            border: Border.all(color: _statusColor.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(envelope.status.label,
              style: TextStyle(fontSize: 8, color: _statusColor,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
      const SizedBox(height: 8),
      _CmdRow('Parameter',    envelope.logicalName),
      _CmdRow('Address',      envelope.addressHex),
      _CmdRow('Platform',     envelope.targetPlatform.label),
      _CmdRow('Transport',    envelope.transportBackend.label),
      if (envelope.valueFloat != null)
        _CmdRow('Float Value',  envelope.valueFloat!.toStringAsFixed(4)),
      if (envelope.fixedPointHex != null)
        _CmdRow('Fixed 8.24',  envelope.fixedPointHex!),
      if (envelope.fixedPointInt != null)
        _CmdRow('Fixed Int',   '${envelope.fixedPointInt}'),
      _CmdRow('Byte Order',   envelope.byteOrder),
      _CmdRow('Write Mode',   envelope.writeMode.label),
      _CmdRow('actualWriteAllowed', '${envelope.actualWriteAllowed}',
          color: Colors.orange),
      _CmdRow('isExecutableNow', '${envelope.isExecutableNow}',
          color: Colors.orange),
      _CmdRow('isDryRunOnly', '${envelope.isDryRunOnly}',
          color: Colors.greenAccent),
      _CmdRow('isMasterVolume', '${envelope.isMasterVolumeCommand}',
          color: envelope.isMasterVolumeCommand ? Colors.greenAccent : Colors.redAccent),
      if (envelope.blockedReason != null) ...[
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.07),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text('BLOCKED: ${envelope.blockedReason}',
              style: const TextStyle(fontSize: 9, color: Colors.redAccent)),
        ),
      ] else if (envelope.notes != null) ...[
        const SizedBox(height: 6),
        Text(envelope.notes!, style: proSubtitle(size: 8)),
      ],
    ]),
  );
}

// ── Phase T4A: USBi Temporary Executor Panel (superseded by T4C panel) ────────
// ignore: unused_element
class _UsbiTemporaryExecutorPanel extends StatelessWidget {
  final TransportCommandEnvelope envelope;
  final ProUsbiTemporaryExecutor executor;
  final bool userConfirmed;
  final bool executing;
  final UsbiExecutionResult? lastResult;
  final bool usbiDeviceOpen;
  final bool usbiChecking;
  final String? usbiOpenError;
  final VoidCallback? onOpenDevice;
  final VoidCallback? onCloseDevice;
  final ValueChanged<bool> onConfirmChanged;
  final VoidCallback onExecute;

  const _UsbiTemporaryExecutorPanel({
    required this.envelope,
    required this.executor,
    required this.userConfirmed,
    required this.executing,
    required this.lastResult,
    required this.usbiDeviceOpen,
    required this.usbiChecking,
    required this.usbiOpenError,
    required this.onOpenDevice,
    required this.onCloseDevice,
    required this.onConfirmChanged,
    required this.onExecute,
  });

  @override
  Widget build(BuildContext context) {
    final backendAvailable = executor.backend.isAvailable;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        border: Border.all(color: const Color(0xFF3A3A5C)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Warning banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.08),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.30)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.warning_amber_outlined, color: Colors.orange, size: 12),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                'PHASE T4A — USBi Temporary Engineering Path. '
                'ADAU1466 Master Volume L/R ONLY. '
                'Volatile write — no EEPROM, no Selfboot, no SafeLoad. '
                'USBi is temporary. ICP5 is the final transport target.',
                style: TextStyle(fontSize: 8, color: Colors.orange),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),

        // Envelope summary
        _CmdRow('Parameter',   envelope.logicalName),
        _CmdRow('Address',     envelope.addressHex),
        if (envelope.valueFloat != null)
          _CmdRow('Float Value', envelope.valueFloat!.toStringAsFixed(4)),
        if (envelope.fixedPointHex != null)
          _CmdRow('Fixed 8.24',  envelope.fixedPointHex!),
        _CmdRow('Write Mode',  envelope.writeMode.label),
        const SizedBox(height: 8),

        // Backend status row
        Row(children: [
          Text('Native Backend', style: const TextStyle(fontSize: 9, color: Colors.white38)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: (backendAvailable ? Colors.greenAccent : Colors.orange)
                  .withValues(alpha: 0.1),
              border: Border.all(
                color: (backendAvailable ? Colors.greenAccent : Colors.orange)
                    .withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              backendAvailable
                  ? (usbiDeviceOpen ? 'Connected' : 'Available — device not open')
                  : 'Pending — not implemented',
              style: TextStyle(
                fontSize: 8,
                color: backendAvailable ? Colors.greenAccent : Colors.orange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 8),

        // T4C: Open / Close USBi Device buttons (Windows only)
        if (onOpenDevice != null || onCloseDevice != null) ...[
          Row(children: [
            SizedBox(
              height: 26,
              child: OutlinedButton.icon(
                onPressed: (!usbiDeviceOpen && !usbiChecking) ? onOpenDevice : null,
                icon: usbiChecking && !usbiDeviceOpen
                    ? const SizedBox(width: 10, height: 10,
                        child: CircularProgressIndicator(strokeWidth: 1.2, color: Colors.white54))
                    : const Icon(Icons.usb_outlined, size: 11),
                label: const Text('Open USBi Device', style: TextStyle(fontSize: 9)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: usbiDeviceOpen ? Colors.white24 : Colors.white70,
                  side: BorderSide(
                    color: usbiDeviceOpen ? Colors.white12 : Colors.white30),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 26,
              child: OutlinedButton.icon(
                onPressed: usbiDeviceOpen ? onCloseDevice : null,
                icon: const Icon(Icons.usb_off_outlined, size: 11),
                label: const Text('Close', style: TextStyle(fontSize: 9)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: usbiDeviceOpen ? Colors.redAccent : Colors.white24,
                  side: BorderSide(
                    color: usbiDeviceOpen ? Colors.redAccent.withValues(alpha: 0.5) : Colors.white12),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                ),
              ),
            ),
          ]),
          if (usbiOpenError != null) ...[
            const SizedBox(height: 4),
            Text(usbiOpenError!, style: const TextStyle(fontSize: 8, color: Colors.redAccent)),
          ],
          const SizedBox(height: 8),
        ],

        // Confirm checkbox
        Row(children: [
          SizedBox(
            width: 18,
            height: 18,
            child: Checkbox(
              value:         userConfirmed,
              onChanged:     (backendAvailable && usbiDeviceOpen) ? (v) => onConfirmChanged(v ?? false) : null,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              activeColor:   Colors.orange,
              side: const BorderSide(color: Colors.white30),
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'I confirm this is a controlled volatile Master Volume write. '
              'No EEPROM. No Selfboot. Address is PASS_ACK; audible or measured verification is pending.',
              style: TextStyle(fontSize: 9, color: Colors.white60),
            ),
          ),
        ]),
        const SizedBox(height: 10),

        // Execute button
        SizedBox(
          width: double.infinity,
          height: 32,
          child: ElevatedButton.icon(
            onPressed: (backendAvailable && usbiDeviceOpen && userConfirmed && !executing)
                ? onExecute
                : null,
            icon: executing
                ? const SizedBox(
                    width: 12, height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white))
                : const Icon(Icons.send_outlined, size: 13),
            label: Text(
              executing
                  ? 'Sending...'
                  : !backendAvailable
                      ? 'USBi native write backend pending'
                      : !usbiDeviceOpen
                          ? 'Open USBi device first'
                          : 'Send USBi Packet',
              style: const TextStyle(fontSize: 10),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: (backendAvailable && usbiDeviceOpen && userConfirmed && !executing)
                  ? Colors.orange.withValues(alpha: 0.75)
                  : Colors.white10,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4)),
            ),
          ),
        ),

        // Last result
        if (lastResult != null) ...[
          const SizedBox(height: 10),
          _UsbiResultCard(result: lastResult!),
        ],
      ]),
    );
  }
}

class _UsbiResultCard extends StatelessWidget {
  final UsbiExecutionResult result;
  const _UsbiResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final isSuccess = result.status.isSuccess;
    final borderColor = isSuccess ? Colors.greenAccent : Colors.redAccent;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: borderColor.withValues(alpha: 0.05),
        border: Border.all(color: borderColor.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
            isSuccess ? Icons.check_circle_outline : Icons.error_outline,
            size: 12,
            color: borderColor,
          ),
          const SizedBox(width: 6),
          Text(
            'USBi Result: ${result.status.label}',
            style: TextStyle(fontSize: 9, color: borderColor,
                fontWeight: FontWeight.w600),
          ),
        ]),
        const SizedBox(height: 6),
        _CmdRow('wasActualWrite', '${result.wasActualWrite}',
            color: result.wasActualWrite ? Colors.orange : Colors.white38),
        _CmdRow('ackReceived', '${result.ackReceived}',
            color: result.ackReceived ? Colors.greenAccent : Colors.white38),
        if (result.ackByteHex != null)
          _CmdRow('ACK Bytes', result.ackByteHex!),
        if (result.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(result.error!,
                style: const TextStyle(fontSize: 8, color: Colors.redAccent)),
          ),
        if (result.notes != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(result.notes!,
                style: const TextStyle(fontSize: 8, color: Colors.white38)),
          ),
      ]),
    );
  }
}

class _CmdRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _CmdRow(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(children: [
      SizedBox(
        width: 140,
        child: Text(label,
            style: const TextStyle(fontSize: 9, color: Colors.white38)),
      ),
      Expanded(
        child: Text(value,
            style: TextStyle(
                fontSize: 9,
                color: color ?? Colors.white60,
                fontFamily: 'monospace',
                fontWeight: color != null ? FontWeight.w500 : FontWeight.normal)),
      ),
    ]),
  );
}

// ── T4C: Self-contained Master Volume Executor Panel ─────────────────────────
// Shown directly in Hardware tab when Windows + USBi transport selected.
// No Transport Command Preview prerequisite.
// Only ADAU1466 Master Volume L (0x0067) / R (0x0064). Volatile only.

class _T4cMasterVolumePanel extends StatelessWidget {
  final String side;
  final double value;
  final bool deviceOpen;
  final bool checking;
  final String? openError;
  final bool executing;
  final bool userConfirmed;
  final UsbiExecutionResult? lastResult;
  final ValueChanged<String> onSideChanged;
  final ValueChanged<double> onValueChanged;
  final VoidCallback onOpenDevice;
  final VoidCallback onCloseDevice;
  final ValueChanged<bool> onConfirmChanged;
  final VoidCallback onExecute;
  final VoidCallback onRestore;

  const _T4cMasterVolumePanel({
    required this.side,
    required this.value,
    required this.deviceOpen,
    required this.checking,
    required this.openError,
    required this.executing,
    required this.userConfirmed,
    required this.lastResult,
    required this.onSideChanged,
    required this.onValueChanged,
    required this.onOpenDevice,
    required this.onCloseDevice,
    required this.onConfirmChanged,
    required this.onExecute,
    required this.onRestore,
  });

  int get _addrInt => side == 'L' ? kMasterVolumeLAddr : kMasterVolumeRAddr;
  String get _addrHex => side == 'L' ? '0x0067' : '0x0064';
  int get _fixedInt => value >= 1.0
      ? 0x01000000
      : value >= 0.5
          ? 0x00800000
          : 0x00000000;
  String get _fixedHex =>
      '0x${_fixedInt.toRadixString(16).padLeft(8, '0').toUpperCase()}';
  String get _bodyHex {
    final b = buildParameterWriteBody(
        addressInt: _addrInt, fixedPointInt: _fixedInt);
    return bytesToHex(b);
  }

  bool get _canExecute =>
      deviceOpen && userConfirmed && !executing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1A2E),
        border: Border.all(color: const Color(0xFF1E4080)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Build marker
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.blueAccent.withValues(alpha: 0.1),
            border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: const Text(
            'TUNAI PRO · T4C USBi MV Test Build · USBi MV executor present',
            style: TextStyle(fontSize: 8, color: Colors.blueAccent,
                fontWeight: FontWeight.w600, letterSpacing: 0.5),
          ),
        ),
        const SizedBox(height: 10),

        // Section header
        Row(children: [
          const Icon(Icons.usb_outlined, size: 13, color: Colors.orange),
          const SizedBox(width: 6),
          const Text('USBi Temporary Master Volume Executor',
              style: TextStyle(fontSize: 11, color: Colors.white,
                  fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),

        // Warning
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.07),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: const Text(
            'PHASE T4C — Temporary USBi engineering path. '
            'ADAU1466 Master Volume L/R ONLY (0x0067 / 0x0064). '
            'Volatile write — no EEPROM, no Selfboot, no SafeLoad. '
            'ICP5 is the final transport target.',
            style: TextStyle(fontSize: 8, color: Colors.orange),
          ),
        ),
        const SizedBox(height: 12),

        // Backend status + open/close
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: (deviceOpen ? Colors.greenAccent : Colors.orange)
                  .withValues(alpha: 0.1),
              border: Border.all(
                  color: (deviceOpen ? Colors.greenAccent : Colors.orange)
                      .withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              deviceOpen ? 'USBi CONNECTED' : 'USBi NOT OPEN',
              style: TextStyle(
                  fontSize: 8,
                  color: deviceOpen ? Colors.greenAccent : Colors.orange,
                  fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 24,
            child: OutlinedButton.icon(
              onPressed: (!deviceOpen && !checking) ? onOpenDevice : null,
              icon: checking
                  ? const SizedBox(width: 10, height: 10,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.2, color: Colors.white54))
                  : const Icon(Icons.usb_outlined, size: 11),
              label: const Text('Open USBi Device',
                  style: TextStyle(fontSize: 9)),
              style: OutlinedButton.styleFrom(
                foregroundColor: deviceOpen ? Colors.white24 : Colors.white70,
                side: BorderSide(
                    color: deviceOpen ? Colors.white12 : Colors.white38),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(3)),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 24,
            child: OutlinedButton.icon(
              onPressed: deviceOpen ? onCloseDevice : null,
              icon: const Icon(Icons.usb_off_outlined, size: 11),
              label: const Text('Close', style: TextStyle(fontSize: 9)),
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    deviceOpen ? Colors.redAccent : Colors.white24,
                side: BorderSide(
                    color: deviceOpen
                        ? Colors.redAccent.withValues(alpha: 0.5)
                        : Colors.white12),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(3)),
              ),
            ),
          ),
        ]),
        if (openError != null) ...[
          const SizedBox(height: 4),
          Text(openError!,
              style: const TextStyle(fontSize: 8, color: Colors.redAccent)),
        ],
        const SizedBox(height: 12),

        // Side selector: L / R
        Row(children: [
          const Text('Channel:',
              style: TextStyle(fontSize: 9, color: Colors.white38)),
          const SizedBox(width: 8),
          for (final s in ['L', 'R']) ...[
            GestureDetector(
              onTap: () => onSideChanged(s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: side == s
                      ? Colors.orange.withValues(alpha: 0.2)
                      : Colors.white10,
                  border: Border.all(
                      color: side == s ? Colors.orange : Colors.white24),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(s,
                    style: TextStyle(
                        fontSize: 9,
                        color: side == s ? Colors.orange : Colors.white60,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 8),

        // Value preset: 1.0 / 0.5 / 0.0
        Row(children: [
          const Text('Value:',
              style: TextStyle(fontSize: 9, color: Colors.white38)),
          const SizedBox(width: 8),
          for (final v in [1.0, 0.5, 0.0]) ...[
            GestureDetector(
              onTap: () => onValueChanged(v),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: value == v
                      ? Colors.orange.withValues(alpha: 0.2)
                      : Colors.white10,
                  border: Border.all(
                      color: value == v ? Colors.orange : Colors.white24),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(v.toStringAsFixed(1),
                    style: TextStyle(
                        fontSize: 9,
                        color: value == v ? Colors.orange : Colors.white60,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 10),

        // Address / packet preview
        _CmdRow('Address', '$_addrHex  (Master Volume $side)'),
        _CmdRow('Fixed 8.24', _fixedHex),
        _CmdRow('Body hex', _bodyHex),
        const SizedBox(height: 12),

        // Confirm checkbox
        Row(children: [
          SizedBox(
            width: 18, height: 18,
            child: Checkbox(
              value: userConfirmed,
              onChanged: deviceOpen
                  ? (v) => onConfirmChanged(v ?? false)
                  : null,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              activeColor: Colors.orange,
              side: const BorderSide(color: Colors.white30),
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'I understand this is a volatile Master Volume write only. '
              'No EEPROM. No Selfboot. Address is PASS_ACK; audible or measured verification is pending.',
              style: TextStyle(fontSize: 9, color: Colors.white60),
            ),
          ),
        ]),
        const SizedBox(height: 10),

        // Execute + Restore buttons
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 32,
              child: ElevatedButton.icon(
                onPressed: _canExecute ? onExecute : null,
                icon: executing
                    ? const SizedBox(width: 12, height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: Colors.white))
                    : const Icon(Icons.send_outlined, size: 13),
                label: Text(
                  executing
                      ? 'Sending...'
                      : !deviceOpen
                          ? 'Open USBi device first'
                          : !userConfirmed
                              ? 'Check confirmation above'
                              : 'Execute via USBi Temporary',
                  style: const TextStyle(fontSize: 10),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _canExecute
                      ? Colors.orange.withValues(alpha: 0.8)
                      : Colors.white10,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 32,
            child: OutlinedButton.icon(
              onPressed: (deviceOpen && !executing) ? onRestore : null,
              icon: const Icon(Icons.restore_outlined, size: 13),
              label: const Text('Restore L/R to 1.0',
                  style: TextStyle(fontSize: 10)),
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    deviceOpen ? Colors.white70 : Colors.white24,
                side: BorderSide(
                    color: deviceOpen ? Colors.white38 : Colors.white12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
              ),
            ),
          ),
        ]),

        // Result log
        if (lastResult != null) ...[
          const SizedBox(height: 12),
          _T4cResultLog(result: lastResult!),
        ],

        // Footer
        const SizedBox(height: 10),
        const Text(
          'ICP5 remains final target. '
          'No PEQ/XO/Gain/Mute/Delay/SafeLoad/EEPROM/Selfboot.',
          style: TextStyle(fontSize: 8, color: Colors.white24),
        ),
      ]),
    );
  }
}

// ── MVP: Shared address row helper ────────────────────────────────────────────

class _MvpAddressRow extends StatelessWidget {
  final VerifiedDspAddress addr;
  final bool dryRunOnly;
  final bool blocked;

  const _MvpAddressRow({
    required this.addr,
    this.dryRunOnly = false,
    this.blocked    = false,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: kProPanel,
          border: Border.all(color: kProBorder),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(addr.logicalName, style: proTitle(size: 10)),
              Text(
                '${addr.addressHex} · ${addr.verificationStatus.label}',
                style: proLabel(size: 8, color: Colors.white38),
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: blocked
                  ? Colors.red.withValues(alpha: 0.1)
                  : kProAmber.withValues(alpha: 0.08),
              border: Border.all(
                  color: blocked
                      ? Colors.red.withValues(alpha: 0.3)
                      : kProAmber.withValues(alpha: 0.2)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              blocked ? 'BLOCKED' : 'DRY RUN',
              style: TextStyle(
                  fontSize: 7,
                  color: blocked ? Colors.redAccent : kProAmber,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      );
}

// ── MVP Panel shared container helper ────────────────────────────────────────

class _MvpPanelContainer extends StatelessWidget {
  final IconData icon;
  final String title;
  final String badgeLabel;
  final Color badgeColor;
  final Widget body;
  final Color? borderColor;

  const _MvpPanelContainer({
    required this.icon,
    required this.title,
    required this.badgeLabel,
    required this.badgeColor,
    required this.body,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: kProSurface,
          border: Border.all(color: borderColor ?? kProBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color: (borderColor ?? kProBorder).withValues(alpha: 0.5),
                      width: 0.5)),
            ),
            child: Row(children: [
              Icon(icon, color: badgeColor, size: 13),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: proTitle(size: 12))),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.1),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(badgeLabel,
                    style: TextStyle(
                        fontSize: 8,
                        color: badgeColor,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          Padding(padding: const EdgeInsets.all(14), child: body),
        ]),
      );
}

// ── MVP: Mute/Gain Guarded Validation Panel ───────────────────────────────────
// Actual execution only when: address in registry, value format confirmed,
// device open, user confirmed. No automatic write. No liveWriteVerified promotion.

class _T4cMuteGainPanel extends StatelessWidget {
  final VerifiedDspAddress? selected;
  final bool deviceOpen;
  final bool confirmed;
  final bool executing;
  final UsbiExecutionResult? lastResult;
  final ValueChanged<VerifiedDspAddress?> onSelect;
  final ValueChanged<bool> onConfirmChanged;
  final VoidCallback onExecute;

  const _T4cMuteGainPanel({
    required this.selected,
    required this.deviceOpen,
    required this.confirmed,
    required this.executing,
    required this.lastResult,
    required this.onSelect,
    required this.onConfirmChanged,
    required this.onExecute,
  });

  @override
  Widget build(BuildContext context) {
    final registry = DspAddressRegistry.createDefault();
    final entries = [
      ...registry.addressesForKind(DspParameterKind.mute),
      ...registry.addressesForKind(DspParameterKind.gain),
    ];

    final bool hasValueFormat  = selected?.dataFormat != null;
    final bool isEligible      = selected?.isActualWriteEligible ?? false;
    final bool canExecute      = deviceOpen && confirmed && !executing &&
        selected != null && isEligible && hasValueFormat;

    return _MvpPanelContainer(
      icon:       Icons.tune_outlined,
      title:      'USBi Temporary Mute/Gain Validation',
      badgeLabel: 'GUARDED',
      badgeColor: kProAmber,
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (entries.isEmpty) ...[
          Row(children: [
            const Icon(Icons.info_outline, color: Colors.white24, size: 12),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No Mute/Gain addresses in registry. '
                'Address confirmation required before validation.',
                style: proSubtitle(size: 10),
              ),
            ),
          ]),
        ] else ...[
          Text('Select parameter:', style: proLabel(size: 9)),
          const SizedBox(height: 6),
          ...entries.map((addr) {
            final valueKnown = addr.dataFormat != null;
            final isSel      = selected?.id == addr.id;
            return GestureDetector(
              onTap: () => onSelect(addr),
              child: Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isSel
                      ? kProAccent.withValues(alpha: 0.1)
                      : kProPanel,
                  border: Border.all(
                      color: isSel
                          ? kProAccent.withValues(alpha: 0.4)
                          : kProBorder),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(addr.logicalName, style: proTitle(size: 11)),
                  Text(
                    '${addr.addressHex} · ${addr.verificationStatus.label}',
                    style: proLabel(size: 9, color: Colors.white38),
                  ),
                  if (!valueKnown)
                    const Text(
                      'blocked: value format requires confirmation',
                      style: TextStyle(fontSize: 9, color: kProAmber),
                    ),
                  if (valueKnown)
                    Text('format: ${addr.dataFormat}',
                        style: const TextStyle(
                            fontSize: 9, color: Colors.greenAccent)),
                ]),
              ),
            );
          }),

          if (selected != null) ...[
            const SizedBox(height: 10),
            if (!hasValueFormat)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kProAmber.withValues(alpha: 0.06),
                  border: Border.all(color: kProAmber.withValues(alpha: 0.25)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Execution blocked: value format not confirmed for '
                  '${selected!.logicalName}.',
                  style: const TextStyle(fontSize: 9, color: kProAmber),
                ),
              )
            else if (!isEligible)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kProAmber.withValues(alpha: 0.06),
                  border: Border.all(color: kProAmber.withValues(alpha: 0.25)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Execution blocked: ${selected!.logicalName} is not '
                  'live-write eligible (${selected!.verificationStatus.label}).',
                  style: const TextStyle(fontSize: 9, color: kProAmber),
                ),
              )
            else ...[
              Row(children: [
                Checkbox(
                  value: confirmed,
                  onChanged: deviceOpen
                      ? (v) => onConfirmChanged(v ?? false)
                      : null,
                  side: const BorderSide(color: Colors.white38),
                  activeColor: kProAccent,
                ),
                Expanded(
                  child: Text(
                    'I confirm this is a single-parameter Mute/Gain write. '
                    'No EEPROM. No Selfboot. No PEQ/XO/Delay/SafeLoad.',
                    style: proSubtitle(size: 9),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: canExecute ? onExecute : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: canExecute
                        ? kProAccent.withValues(alpha: 0.1)
                        : kProPanel,
                    border: Border.all(
                        color: canExecute
                            ? kProAccent.withValues(alpha: 0.4)
                            : kProBorder),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    executing
                        ? 'Executing...'
                        : !deviceOpen
                            ? 'Device not open — connect USBi first'
                            : !confirmed
                                ? 'Check confirmation above'
                                : 'Execute Mute/Gain Write',
                    style: TextStyle(
                        fontSize: 11,
                        color: canExecute ? kProAccent : Colors.white24,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ],
          ],

          if (lastResult != null) ...[
            const SizedBox(height: 10),
            _T4cResultLog(result: lastResult!),
          ],
        ],
      ]),
    );
  }
}

// ── MVP: Delay Validation Panel (dry-run only) ────────────────────────────────

class _T4cDelayPanel extends StatelessWidget {
  const _T4cDelayPanel();

  @override
  Widget build(BuildContext context) {
    final entries = DspAddressRegistry.createDefault()
        .addressesForKind(DspParameterKind.delay);

    return _MvpPanelContainer(
      icon:       Icons.access_time_outlined,
      title:      'USBi Temporary Delay Validation — Dry Run Only',
      badgeLabel: 'DRY RUN ONLY',
      badgeColor: Colors.blueAccent,
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: kProAmber.withValues(alpha: 0.06),
            border: Border.all(color: kProAmber.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.warning_amber_outlined, color: kProAmber, size: 12),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Delay requires oscilloscope or interface timing measurement. '
                'Actual write disabled today.',
                style: TextStyle(fontSize: 9, color: kProAmber),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        if (entries.isEmpty)
          Text(
            'No Delay addresses in registry. '
            'Address confirmation required before validation.',
            style: proSubtitle(size: 10),
          )
        else
          ...entries.map((a) => _MvpAddressRow(addr: a, dryRunOnly: true)),
      ]),
    );
  }
}

// ── MVP: PEQ Band 1 Validation Panel (dry-run only) ──────────────────────────

class _T4cPeqBand1Panel extends StatelessWidget {
  const _T4cPeqBand1Panel();

  static const _coeffLabels = ['b0', 'b1', 'b2', 'a1', 'a2'];

  @override
  Widget build(BuildContext context) {
    final allPeq = DspAddressRegistry.createDefault()
        .addressesForKind(DspParameterKind.peq);
    final band1 = allPeq
        .where((a) =>
            a.bandOrStage == '1' ||
            a.id.contains('band1') ||
            a.id.contains('peq_1'))
        .toList();

    return _MvpPanelContainer(
      icon:       Icons.graphic_eq_outlined,
      title:      'USBi Temporary PEQ Band 1 Validation — Dry Run Only',
      badgeLabel: 'DRY RUN ONLY',
      badgeColor: Colors.blueAccent,
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.05),
            border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.block_outlined, color: Colors.redAccent, size: 12),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'PEQ coefficient write requires SafeLoad validation first. '
                'No PEQ write today.',
                style: TextStyle(fontSize: 9, color: Colors.redAccent),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        Text('PEQ Band 1 coefficient group (preview only):',
            style: proLabel(size: 9)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: _coeffLabels
              .map((c) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: kProPanel,
                      border: Border.all(color: kProBorder),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(c,
                        style: const TextStyle(
                            fontSize: 9,
                            color: Colors.white38,
                            fontFamily: 'monospace')),
                  ))
              .toList(),
        ),
        const SizedBox(height: 8),
        if (band1.isEmpty)
          Text(
            'No PEQ Band 1 addresses in registry. '
            'Address confirmation required.',
            style: proSubtitle(size: 10),
          )
        else
          ...band1.map((a) => _MvpAddressRow(addr: a, dryRunOnly: true)),
      ]),
    );
  }
}

// ── MVP: XO Validation Panel (hard-blocked) ───────────────────────────────────

class _T4cXoPanel extends StatelessWidget {
  const _T4cXoPanel();

  @override
  Widget build(BuildContext context) {
    final entries = DspAddressRegistry.createDefault()
        .addressesForKind(DspParameterKind.crossover);

    return _MvpPanelContainer(
      icon:        Icons.device_hub_outlined,
      title:       'USBi Temporary XO Validation — BLOCKED',
      badgeLabel:  'BLOCKED',
      badgeColor:  Colors.redAccent,
      borderColor: Colors.red.withValues(alpha: 0.35),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.06),
            border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.block_outlined, color: Colors.redAccent, size: 12),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'XO write is hard-blocked. No XO execution. No SafeLoad. '
                  'No speaker-connected testing. No tweeter-risk path.',
                  style: TextStyle(fontSize: 9, color: Colors.redAccent),
                ),
              ),
            ]),
            SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.warning_amber_outlined, color: kProAmber, size: 12),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'OUT1/2/3/4/7/8 output mapping must be verified without speakers first.',
                  style: TextStyle(fontSize: 9, color: kProAmber),
                ),
              ),
            ]),
            SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.warning_amber_outlined, color: kProAmber, size: 12),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'BLOCKED UNTIL: SafeLoad validated + output mapping verified.',
                  style: TextStyle(fontSize: 9, color: kProAmber),
                ),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 10),
        if (entries.isEmpty)
          Text(
            'No XO addresses in registry.',
            style: proSubtitle(size: 10),
          )
        else
          ...entries.map(
              (a) => _MvpAddressRow(addr: a, dryRunOnly: true, blocked: true)),
      ]),
    );
  }
}

// ── MVP: SafeLoad Validation Panel (dry-run only) ─────────────────────────────

class _T4cSafeloadPanel extends StatelessWidget {
  const _T4cSafeloadPanel();

  static const _plannedAddresses = [
    '0x6000', '0x6001', '0x6002', '0x6003',
    '0x6004', '0x6005', '0x6006', '0x6007',
  ];

  @override
  Widget build(BuildContext context) {
    final entries = DspAddressRegistry.createDefault()
        .addressesForKind(DspParameterKind.safeload);

    return _MvpPanelContainer(
      icon:       Icons.save_outlined,
      title:      'SafeLoad Validation — Dry Run Only',
      badgeLabel: 'DRY RUN ONLY',
      badgeColor: Colors.blueAccent,
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: kProAmber.withValues(alpha: 0.06),
            border: Border.all(color: kProAmber.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.warning_amber_outlined, color: kProAmber, size: 12),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'SafeLoad must be validated before PEQ/XO live coefficient write. '
                'No SafeLoad execution today.',
                style: TextStyle(fontSize: 9, color: kProAmber),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        Text('Planned SafeLoad address sequence (preview only):',
            style: proLabel(size: 9)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: _plannedAddresses
              .map((hex) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: kProPanel,
                      border: Border.all(color: kProBorder),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(hex,
                        style: const TextStyle(
                            fontSize: 9,
                            color: Colors.white38,
                            fontFamily: 'monospace')),
                  ))
              .toList(),
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          Text(
            'No SafeLoad addresses in registry. '
            'Address confirmation required before live SafeLoad.',
            style: proSubtitle(size: 10),
          )
        else
          ...entries.map((a) => _MvpAddressRow(addr: a, dryRunOnly: true)),
      ]),
    );
  }
}

// ── T4C: Result log ───────────────────────────────────────────────────────────

class _T4cResultLog extends StatelessWidget {
  final UsbiExecutionResult result;
  const _T4cResultLog({required this.result});

  @override
  Widget build(BuildContext context) {
    final ok = result.status == UsbiExecutionStatus.ackReceived;
    final color = ok
        ? Colors.greenAccent
        : result.status == UsbiExecutionStatus.ackFailed
            ? Colors.orange
            : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Result: ${result.status.label}',
            style: TextStyle(
                fontSize: 9, color: color, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        _CmdRow('wasActualWrite', result.wasActualWrite.toString(),
            color: result.wasActualWrite ? Colors.greenAccent : null),
        _CmdRow('ackReceived', result.ackReceived.toString()),
        if (result.ackByteHex != null)
          _CmdRow('ACK bytes', result.ackByteHex!),
        if (result.error != null)
          _CmdRow('Error', result.error!, color: Colors.redAccent),
      ]),
    );
  }
}
