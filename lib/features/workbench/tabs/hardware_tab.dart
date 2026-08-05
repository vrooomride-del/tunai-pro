// ── Hardware Guard Tab — Phase T ──────────────────────────────────────────────
// Dry-run hardware planning + controlled master volume write prototype.
// Only ADAU1466 Master Volume L (0x67) and R (0x64) are verified write targets.
// No EEPROM. No Selfboot. No SafeLoad. No Write-All.
// AI suggests. Expert verifies. AOS protects. DSP executes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/pro_project.dart';
import '../../../core/pro_project_store.dart';
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
import 'dart:async';
import 'dart:io';
import 'pro_hardware_mvp_status_card.dart';
import '../widgets/hardware_t4c_mute_gain_card.dart';
import '../widgets/hardware_t4c_delay_card.dart';
import '../widgets/hardware_t4c_peq_band1_card.dart';
import '../widgets/hardware_t4c_xo_card.dart';
import '../widgets/hardware_t4c_safeload_card.dart';
import '../widgets/hardware_t4c_master_volume_card.dart';
import '../widgets/hardware_export_package_card.dart';
import '../widgets/hardware_live_validation_queue_card.dart';
import '../widgets/hardware_address_validation_status_card.dart';
import '../widgets/hardware_connection_card.dart';
import '../widgets/hardware_write_plan_card.dart';
import '../widgets/hardware_controlled_write_card.dart';
import '../widgets/hardware_validation_manager_card.dart';
import '../widgets/hardware_transport_readiness_card.dart';
import '../widgets/hardware_transport_command_preview_card.dart';
import '../widgets/hardware_device_status_card.dart';
import 'sigma_verification_console.dart';
import 'operational_master_volume_control.dart';
import 'transport_connection_panel.dart';
import 'adau1701_icp5_tuning_panel.dart';
import '../../../core/transport/icp5_transports.dart';
import '../../../core/deploy/pro_hardware_context_provider.dart';
import '../../../core/deploy/pro_adau1701_hardware_context.dart';
import '../../../shared/components/section_header.dart';
import '../widgets/hardware_warnings_card.dart';
import '../widgets/hardware_guard_checklist_card.dart';

class HardwareTab extends ConsumerStatefulWidget {
  final String projectId;
  final ProUsbiNativeBackend? usbiBackend;
  final bool Function()? isWindowsPlatform;
  final bool initialUsbiDeviceOpen;
  final ValueChanged<bool>? onUsbiDeviceOpenChanged;
  final ValueChanged<bool>? onDspWritesDisabledChanged;
  final Icp5BluetoothTransport? icp5BluetoothTransport;
  const HardwareTab({
    super.key,
    required this.projectId,
    this.usbiBackend,
    this.isWindowsPlatform,
    this.initialUsbiDeviceOpen = false,
    this.onUsbiDeviceOpenChanged,
    this.onDspWritesDisabledChanged,
    this.icp5BluetoothTransport,
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
  // Hardware context wrapping the BLE transport — exposed via
  // activeAdau1701ContextProvider only after PASS_HANDSHAKE.
  late final Adau1701HardwareContext _adau1701BleContext;
  // True only for a tab-created (macOS local) BLE transport; the Windows BLE
  // transport is owned by adau1701Icp5BleWindowsContextProvider.
  bool _ownsBleTransport = true;
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
    // Shared ADAU1701 ICP5 USB transport — the same instance the Deploy Apply
    // flow uses, so connecting here makes the Deploy context ready. The provider
    // owns its lifecycle (closed on provider dispose), so this tab must not
    // close it. (ADAU1466 USBi + BLE ICP5 paths are unaffected.)
    _adau1701UsbTransport =
        ref.read(adau1701Icp5UsbContextProvider).transport as Icp5UsbTransport;
    // ADAU1701 ICP5 BLE transport. On Windows it is the shared WinRT-backed BLE
    // context (provider-owned; not closed here) so Hardware and future Deploy
    // consumers share one BLE connection. On macOS it stays the local
    // flutter_blue_plus transport, owned and closed by this tab (unchanged).
    // 3 s timeout gives the DSP firmware margin after back-to-back page reads.
    if (widget.icp5BluetoothTransport != null) {
      _adau1701BleTransport = widget.icp5BluetoothTransport!;
      _ownsBleTransport = false;
      _adau1701BleContext =
          Adau1701HardwareContext.fromTransport(_adau1701BleTransport);
    } else if (Platform.isWindows) {
      _adau1701BleTransport =
          ref.read(adau1701Icp5BleWindowsContextProvider).transport
              as Icp5BluetoothTransport;
      _ownsBleTransport = false;
      // Reuse the provider-owned context — do not create a second wrapper.
      _adau1701BleContext = ref.read(adau1701Icp5BleWindowsContextProvider);
      // The Windows BLE transport is global and survives WorkbenchShell
      // navigation — it is never closed on back-press. When a new project is
      // opened while BLE is already connected, onBlePassHandshake never fires
      // again (no new BLE connection event). Sync the new project's connection
      // state immediately so the status bar Connected badge and Deploy button
      // activate without waiting for the next explicit BLE connect.
      if (_adau1701BleTransport.isConnected &&
          _adau1701BleTransport.handshakeComplete) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _onBlePassHandshake(widget.projectId);
        });
      }
    } else {
      _adau1701BleTransport = Icp5BluetoothTransport(
        readTimeout: const Duration(seconds: 3),
        writeTimeout: const Duration(seconds: 3),
      );
      _ownsBleTransport = true;
      // Wrap the tab-owned macOS BLE transport so the deploy dialog can use it
      // via activeAdau1701ContextProvider when BLE is the active connection.
      // Default transportType (icp5) is used — no import of pro_hardware_capability
      // needed, which avoids a HardwareTransportType name conflict with the one
      // already imported from pro_hardware_connection_data.dart.
      _adau1701BleContext =
          Adau1701HardwareContext.fromTransport(_adau1701BleTransport);
    }
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
    // _adau1701UsbTransport is owned by adau1701Icp5UsbContextProvider — do not
    // close it here; the Deploy Apply flow shares the same instance.
    // On Windows the BLE transport is likewise provider-owned (shared); only
    // close the macOS local BLE transport this tab created.
    if (_ownsBleTransport) _adau1701BleTransport.close();
    super.dispose();
  }

  void _onBlePassHandshake(String callbackProjectId) {
    _syncBleConnection(
      callbackProjectId,
      HardwareConnection.connected,
      _adau1701BleContext,
    );
  }

  void _onBleDisconnected(String callbackProjectId) {
    _syncBleConnection(
      callbackProjectId,
      HardwareConnection.disconnected,
      null,
    );
  }

  void _syncBleConnection(
    String callbackProjectId,
    HardwareConnection connection,
    Adau1701HardwareContext? activeContext,
  ) {
    if (callbackProjectId != widget.projectId) {
      throw StateError(
        'Stale BLE callback projectId=$callbackProjectId; '
        'open Workbench projectId=${widget.projectId}.',
      );
    }
    final notifier = ref.read(proProjectStoreProvider.notifier);
    notifier.updateHardwareConnection(callbackProjectId, connection);
    ref.read(activeAdau1701ContextProvider.notifier).state = activeContext;
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

        // V3-5A: single read-only summary separating transport / DSP
        // identity / parameter readback / physical output — does not
        // replace or remove any control below; purely additive.
        HardwareDeviceStatusCard(projectId: widget.projectId),
        const SizedBox(height: 20),

        const ProSectionHeader(title: 'TRANSPORT ARCHITECTURE — ICP5 PHASE A', icon: Icons.alt_route_outlined),
        const SizedBox(height: 8),
        TransportConnectionPanel(
          projectId: widget.projectId,
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
          onBlePassHandshake: _onBlePassHandshake,
          onBleDisconnected: _onBleDisconnected,
        ),
        const SizedBox(height: 20),

        const ProSectionHeader(title: 'ADAU1701 ICP5 TUNING', icon: Icons.tune_outlined),
        const SizedBox(height: 8),
        Adau1701Icp5TuningPanel(
          key: ValueKey(_activeTuningTransport.identity),
          transport: _activeTuningTransport,
        ),
        const SizedBox(height: 20),

        // A: Connection State Panel
        const ProSectionHeader(title: 'CONNECTION STATE', icon: Icons.usb_outlined),
        const SizedBox(height: 8),
        HardwareConnectionCard(
          conn: displayConn,
          onTransport: _setTransport,
          onTarget: _setTargetDevice,
          onCheck: _checkConnection,
        ),
        const SizedBox(height: 20),

        // B: Transport Readiness (Phase T2 Revised)
        const ProSectionHeader(title: 'TRANSPORT READINESS', icon: Icons.compare_arrows_outlined),
        const SizedBox(height: 8),
        HardwareTransportReadinessCard(
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
        const ProSectionHeader(title: 'ACTIVE EXPORT PACKAGE', icon: Icons.upload_outlined),
        const SizedBox(height: 8),
        HardwareExportPackageCard(pkg: activePkg, protection: project?.protectionState),
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
          const ProSectionHeader(title: 'GUARD CHECKLIST', icon: Icons.checklist_outlined),
          const SizedBox(height: 8),
          HardwareGuardChecklistCard(plan: activePlan),
          const SizedBox(height: 20),

          // E: Write plan preview
          const ProSectionHeader(title: 'WRITE PLAN PREVIEW', icon: Icons.list_alt_outlined),
          const SizedBox(height: 8),
          HardwareWritePlanCard(plan: activePlan),
          const SizedBox(height: 20),

          // F: Warnings
          if (activePlan.warnings.isNotEmpty || activePlan.blockedReason != null) ...[
            const ProSectionHeader(title: 'WARNINGS', icon: Icons.warning_amber_outlined),
            const SizedBox(height: 8),
            HardwareWarningsCard(plan: activePlan),
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
        const ProSectionHeader(title: 'ADDRESS VALIDATION STATUS', icon: Icons.checklist_outlined),
        const SizedBox(height: 8),
        const HardwareAddressValidationStatusCard(),
        const SizedBox(height: 16),

        // ── H: Live Validation Queue (Phase U1) ──────────────────────────
        const ProSectionHeader(title: 'LIVE VALIDATION QUEUE', icon: Icons.playlist_add_check_outlined),
        const SizedBox(height: 8),
        const HardwareLiveValidationQueueCard(),
        const SizedBox(height: 16),

        // ── I: Address Live Validation Manager (Phase U2) ────────────────
        const SizedBox(height: 20),
        const ProSectionHeader(title: 'ADDRESS LIVE VALIDATION MANAGER', icon: Icons.task_alt_outlined),
        const SizedBox(height: 8),
        HardwareValidationManagerCard(
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
        const ProSectionHeader(title: 'CONTROLLED MASTER VOLUME WRITE', icon: Icons.volume_up_outlined),
        const SizedBox(height: 8),
        HardwareControlledWriteCard(
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
        const ProSectionHeader(title: 'TRANSPORT COMMAND PREVIEW', icon: Icons.terminal_outlined),
        const SizedBox(height: 8),
        HardwareTransportCommandPreviewCard(
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
          HardwareT4cMasterVolumeCard(
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
          const ProSectionHeader(
              title: 'USBi TEMPORARY — MUTE/GAIN VALIDATION',
              icon: Icons.tune_outlined),
          const SizedBox(height: 8),
          HardwareT4cMuteGainCard(
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
          const ProSectionHeader(
              title: 'USBi TEMPORARY — DELAY VALIDATION (DRY RUN ONLY)',
              icon: Icons.access_time_outlined),
          const SizedBox(height: 8),
          const HardwareT4cDelayCard(),
        ],

        // ── O: T4C — PEQ Band 1 Validation Panel (dry-run only) ─────────
        if (Platform.isWindows &&
            _selectedTransport ==
                HardwareTransportBackend.usbiWindowsTemporary) ...[
          const SizedBox(height: 20),
          const ProSectionHeader(
              title: 'USBi TEMPORARY — PEQ BAND 1 VALIDATION (DRY RUN ONLY)',
              icon: Icons.graphic_eq_outlined),
          const SizedBox(height: 8),
          const HardwareT4cPeqBand1Card(),
        ],

        // ── P: T4C — XO Validation Panel (hard-blocked) ─────────────────
        if (Platform.isWindows &&
            _selectedTransport ==
                HardwareTransportBackend.usbiWindowsTemporary) ...[
          const SizedBox(height: 20),
          const ProSectionHeader(
              title: 'USBi TEMPORARY — XO VALIDATION (BLOCKED)',
              icon: Icons.device_hub_outlined),
          const SizedBox(height: 8),
          const HardwareT4cXoCard(),
        ],

        // ── Q: SafeLoad Validation Panel (dry-run only) ──────────────────
        if (Platform.isWindows &&
            _selectedTransport ==
                HardwareTransportBackend.usbiWindowsTemporary) ...[
          const SizedBox(height: 20),
          const ProSectionHeader(
              title: 'SAFELOAD VALIDATION (DRY RUN ONLY)',
              icon: Icons.save_outlined),
          const SizedBox(height: 8),
          const HardwareT4cSafeloadCard(),
        ],

        // ── S: Sigma Export Hardware Verification Console ────────────────
        if (Platform.isWindows &&
            _selectedTransport ==
                HardwareTransportBackend.usbiWindowsTemporary) ...[
          const SizedBox(height: 20),
          const ProSectionHeader(
              title: 'ADAU1466 SIGMA EXPORT VERIFICATION CONSOLE',
              icon: Icons.science_outlined),
          const SizedBox(height: 8),
          SigmaVerificationConsole(
            backend:           _usbiNativeBackend,
            isWindowsPlatform: () => Platform.isWindows,
            deviceOpen:        _usbiDeviceOpen,
          ),
        ],

        // ── R: Hardware MVP Status Card (always visible) ─────────────────
        const SizedBox(height: 20),
        const ProSectionHeader(title: 'HARDWARE MVP STATUS', icon: Icons.info_outline),
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
        const ProSectionHeader(title: 'TRANSPORT READINESS', icon: Icons.compare_arrows_outlined),
        const SizedBox(height: 8),
        HardwareTransportReadinessCard(
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
        const ProSectionHeader(title: 'ADAU1466 SIGMA VERIFICATION CONSOLE', icon: Icons.science_outlined),
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
        const ProSectionHeader(title: 'OPERATIONAL MASTER VOLUME', icon: Icons.volume_up_outlined),
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

// ── Phase U1: Live Validation Queue ──────────────────────────────────────────

// ── Connection Panel ──────────────────────────────────────────────────────────

// ── Export Package Panel ──────────────────────────────────────────────────────

// ── Write Plan Panel ──────────────────────────────────────────────────────────

// ── Controlled Master Volume Write Panel (Phase T) ────────────────────────────

// ── Phase U2: Address Live Validation Manager ─────────────────────────────────

// ── Phase T2 Revised: Transport Readiness Panel ───────────────────────────────
