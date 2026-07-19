import 'dart:async';
import 'package:flutter/foundation.dart';
import 'adau1701_ch0_band0_read_service.dart';
import 'adau1701_tuning_transport.dart';
import 'dsp_command.dart';
import 'dsp_transport.dart';
import 'icp5_frame_codec.dart';
import 'icp5_raw_state_read.dart';
import 'icp5_bluetooth_driver.dart';
import 'icp5_serial_driver.dart';

/// Platform-specific tag for the ICP5 connect lifecycle logs. macOS keeps its
/// proven `[ICP5 mac lifecycle]` tag unchanged; Windows gets its own.
String _icp5LifecycleTag() => switch (defaultTargetPlatform) {
      TargetPlatform.windows => 'ICP5 windows lifecycle',
      TargetPlatform.macOS => 'ICP5 mac lifecycle',
      _ => 'ICP5 lifecycle',
    };

class Icp5MasterVolumeResult {
  final bool success;
  final bool wasActualWrite;
  final bool writeMayHaveReachedDevice;
  final List<int>? rawAck;
  final String message;
  const Icp5MasterVolumeResult(
      {required this.success,
      required this.wasActualWrite,
      required this.writeMayHaveReachedDevice,
      required this.message,
      this.rawAck});
}

class Icp5DiagnosticOutcome {
  final Icp5MasterVolumeResult test;
  final Icp5MasterVolumeResult? restore;
  final bool stopActivated;
  const Icp5DiagnosticOutcome(
      {required this.test, this.restore, required this.stopActivated});
}

class Icp5MasterMuteResult {
  final bool success;
  final bool wasActualWrite;
  final bool writeMayHaveReachedDevice;
  final List<int>? rawAck;
  final String message;
  const Icp5MasterMuteResult(
      {required this.success,
      required this.wasActualWrite,
      required this.writeMayHaveReachedDevice,
      required this.message,
      this.rawAck});
}

class Icp5MuteDiagnosticOutcome {
  final Icp5MasterMuteResult test;
  final Icp5MasterMuteResult? restore;
  final bool stopActivated;
  const Icp5MuteDiagnosticOutcome(
      {required this.test, this.restore, required this.stopActivated});
}

class Icp5OutputDac1GainResult {
  final bool success;
  final bool wasActualWrite;
  final bool writeMayHaveReachedDevice;
  final List<int>? rawAck;
  final String message;
  const Icp5OutputDac1GainResult(
      {required this.success,
      required this.wasActualWrite,
      required this.writeMayHaveReachedDevice,
      required this.message,
      this.rawAck});
}

class Icp5OutputDac1GainDiagnosticOutcome {
  final Icp5OutputDac1GainResult test;
  final Icp5OutputDac1GainResult? restore;
  final bool stopActivated;
  const Icp5OutputDac1GainDiagnosticOutcome(
      {required this.test, this.restore, required this.stopActivated});
}

class Icp5PhaseCResult {
  final bool success;
  final bool wasActualWrite;
  final bool writeMayHaveReachedDevice;
  final List<int>? rawAck;
  final String message;
  const Icp5PhaseCResult(
      {required this.success,
      required this.wasActualWrite,
      required this.writeMayHaveReachedDevice,
      required this.message,
      this.rawAck});
}

class Icp5PhaseCOutcome {
  final Icp5PhaseCResult test;
  final Icp5PhaseCResult? restore;
  final bool stopActivated;
  const Icp5PhaseCOutcome(
      {required this.test, this.restore, required this.stopActivated});
}

class Icp5UsbTransport
    implements DspTransport, Adau1701RawReadTransport, Adau1701TuningTransport {
  final Icp5SerialDriver driver;
  final Duration readTimeout;
  final Duration writeTimeout;
  final void Function(String warning)? onDspWriteStop;
  Icp5SerialConnection? _connection;
  StreamSubscription<List<int>>? _subscription;
  final Icp5FrameBuffer _buffer = Icp5FrameBuffer();

  // ── Consumer-proven request/response transaction engine ────────────────────
  // Ported structurally from ConsumerBleService (tunai_codex). A dedicated
  // handshake completer takes routing priority; application exchanges own a
  // single generation-guarded completer + matcher that are always set BEFORE
  // the write, so a BLE notify arriving during the GATT write is never missed.
  Completer<List<int>>? _handshakeResponse;
  Completer<List<int>>? _pendingResponse;
  bool Function(List<int>)? _pendingAccepts;
  // Monotonically increasing request generation. A frame is only routed to
  // _pendingResponse when _activeGeneration matches the request's generation.
  // Set to -1 when no request is active or during the stale-ACK quarantine.
  int _applicationGeneration = 0;
  int _activeGeneration = -1;

  /// How long to discard incoming notifications after a command timeout before
  /// the next request is allowed. The ICP5 protocol carries no per-command
  /// sequence identifier, so this bounded fail-closed quarantine (proven in the
  /// Consumer transport) prevents a delayed frame from satisfying a later
  /// command. Must exceed the maximum expected BLE round-trip (~30 ms).
  final Duration staleAckQuarantine;
  List<Icp5SerialDevice> _devices = const [];
  List<Icp5SerialDevice> _enumeratedPorts = const [];
  String _discoverySource = 'Windows SetupAPI Ports class';
  String? _discoveryError;
  DspConnectionState _state = DspConnectionState.disconnected;
  bool _handshakeComplete = false;
  bool _busy = false;
  bool _stopped = false;
  String? _profile;
  String? _selectedPort;

  Icp5UsbTransport(
      {Icp5SerialDriver? driver,
      this.readTimeout = const Duration(seconds: 1),
      this.writeTimeout = const Duration(seconds: 1),
      this.staleAckQuarantine = const Duration(milliseconds: 50),
      this.onDspWriteStop})
      : driver = driver ?? WindowsIcp5SerialDriver();

  Future<Icp5DiscoveryResult> discover() async {
    _discoveryError = null;
    final result = await driver.discover();
    _devices = result.matches;
    _enumeratedPorts = result.allPorts;
    _discoverySource = result.source;
    _discoveryError = result.error;
    if (!_enumeratedPorts.any((device) => device.portName == _selectedPort)) {
      _selectedPort = _devices.firstOrNull?.portName;
    }
    debugPrint(
        '[ICP5 Discovery] final selected port=${_selectedPort ?? 'none'}');
    return result;
  }

  List<Icp5SerialDevice> get discoveredDevices => List.unmodifiable(_devices);
  List<Icp5SerialDevice> get enumeratedPorts =>
      List.unmodifiable(_enumeratedPorts);
  String get discoverySource => _discoverySource;
  String? get discoveryError => _discoveryError;
  String? get selectedPort => _selectedPort;
  @override
  bool get isConnected => _state == DspConnectionState.connected;
  @override
  bool get handshakeComplete => _handshakeComplete;
  @override
  String? get detectedProfile => _profile;
  bool get stopped => _stopped;
  bool get busy => _busy;

  bool selectEnumeratedPort(String portName) {
    if (_busy ||
        !_enumeratedPorts.any((device) => device.portName == portName)) {
      return false;
    }
    _selectedPort = portName;
    debugPrint('[ICP5 Discovery] manual enumerated-port selection=$portName');
    return true;
  }

  @override
  DspTransportIdentity get identity => DspTransportIdentity.icp5Usb;
  @override
  String get displayName => 'ICP5 USB';
  @override
  bool get isAvailable => driver.platformSupported && _devices.isNotEmpty;
  @override
  DspConnectionState get connectionState => _state;
  @override
  DspTransportCapabilities get capabilities => const DspTransportCapabilities(
      directParameterWrite: true,
      oneWordSafeLoad: false,
      fiveWordSafeLoad: false,
      ackSupport: true,
      readbackSupport: true,
      reconnectSupport: true,
      maximumPayloadSize: 12,
      boardDetectionSupport: true);
  @override
  String? get missingEvidence =>
      'Raw 0x2202 state read is proven; PEQ offsets, SafeLoad, arbitrary parameters/range, dB mapping, ADAU1466, and Bluetooth remain unproven.';

  @override
  Future<DspTransportResult> open() => _open(discoverFirst: true);

  Future<DspTransportResult> _open({required bool discoverFirst}) async {
    if (_connection != null || _state == DspConnectionState.connected) {
      return _fail(DspTransportFailure.unavailable,
          'ICP5 port is already exclusively owned by this session.');
    }
    if (_busy) {
      return _fail(
          DspTransportFailure.unavailable, 'Transaction already active.');
    }
    Icp5DiscoveryResult? discovery;
    if (discoverFirst) discovery = await discover();
    if (_selectedPort == null ||
        (discoverFirst && discovery!.allPorts.isEmpty)) {
      return _fail(DspTransportFailure.unavailable,
          discovery?.error ?? 'No selected ICP5 device is available.');
    }
    _state = DspConnectionState.connecting;
    try {
      _connection = await driver.open(_selectedPort!);
      // Mirror ConsumerBleService._connectAndValidate: reset the receive buffer
      // and arm the handshake completer BEFORE subscribing and writing.
      _buffer.reset();
      _handshakeResponse = Completer<List<int>>();
      _subscription = _connection!.bytes.listen(
        _onBytes,
        onError: _onConnectionError,
        onDone: _onConnectionClosed,
      );
      // Attach the handshake awaiter BEFORE the write. .timeout() eagerly
      // subscribes to the completer's future, so a disconnect error delivered
      // synchronously during the GATT write is always handled here rather than
      // surfacing as an unhandled async error.
      final handshakeFuture = _handshakeResponse!.future.timeout(readTimeout);
      final written = await _connection!
          .write(Icp5FrameCodec.identificationRequest, writeTimeout)
          .timeout(writeTimeout);
      if (written != Icp5FrameCodec.identificationRequest.length) {
        await close();
        return _fail(DspTransportFailure.ackFailed,
            'ICP5 identity handshake write was incomplete.');
      }
      debugPrint('[${_icp5LifecycleTag()}] HANDSHAKE_START');
      final identity = await handshakeFuture;
      _handshakeResponse = null;
      final profile = Icp5FrameCodec.parseIdentity(identity);
      if (profile == null) {
        await close();
        return _fail(
            DspTransportFailure.ackFailed, 'ICP5 identity handshake failed.');
      }
      _handshakeComplete = true;
      _profile = profile;
      _state = DspConnectionState.connected;
      debugPrint('[${_icp5LifecycleTag()}] HANDSHAKE_PASS');
      return const DspTransportResult(
          success: true,
          failure: DspTransportFailure.none,
          message: 'ICP5 connected · ADAU1701 profile proven.');
    } on TimeoutException {
      debugPrint('[${_icp5LifecycleTag()}] TIMEOUT');
      await close();
      return _fail(
          DspTransportFailure.ackFailed, 'ICP5 identity handshake timed out.');
    } catch (error) {
      await close();
      _state = DspConnectionState.error;
      return _fail(DspTransportFailure.exception, '$error');
    }
  }

  @override
  Future<void> close() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    final connection = _connection;
    _connection = null;
    // Mirror ConsumerBleService._closeConnection: invalidate the active
    // generation and complete both pending operations with an error immediately
    // so callers do not stall until their individual timeouts fire.
    _activeGeneration = -1;
    final handshake = _handshakeResponse;
    _handshakeResponse = null;
    if (handshake != null && !handshake.isCompleted) {
      handshake.completeError(StateError('ICP5 transport disconnected.'));
    }
    final application = _pendingResponse;
    _pendingResponse = null;
    _pendingAccepts = null;
    if (application != null && !application.isCompleted) {
      application.completeError(StateError('ICP5 transport disconnected.'));
    }
    _buffer.reset();
    await connection?.close();
    _handshakeComplete = false;
    _profile = null;
    _selectedPort = null;
    _state = DspConnectionState.disconnected;
  }

  /// Generic commands remain blocked: Phase B exposes only the dedicated,
  /// capture-proven parameter and two values below.
  @override
  Future<DspTransportResult> execute(DspCommand command) async => _fail(
      DspTransportFailure.unsupportedCapability,
      'Arbitrary ICP5 commands are blocked; use the guarded diagnostic.');

  /// Reads the capture-proven raw 0x2202 state block without decoding fields.
  /// This transaction sends only 0x1A read requests and has no write fallback.
  @override
  Future<RawDspStateSnapshot> readRawDspState() async {
    if (!_handshakeComplete ||
        _state != DspConnectionState.connected ||
        _profile != Icp5FrameCodec.expectedProfile ||
        _selectedPort == null) {
      throw StateError('Successful ADAU1701 identity handshake is required.');
    }
    if (_busy) throw StateError('Another ICP5 transaction is active.');
    _busy = true;
    try {
      // Flush partial bytes from any prior cycle.
      _buffer.reset();
      final reader = Icp5RawStateReader(exchange: (request) async {
        final response = await _exchange(
          request,
          (frame) => frame.length >= 3 && frame[0] == 0x55 && frame[2] == 0xE0,
        );
        if (response == null) throw StateError('No ICP5 read response.');
        return response;
      });
      // Use validated firmware identity, not the COM/BLE transport identifier.
      return await reader.read(deviceId: _profile!);
    } finally {
      _busy = false;
    }
  }

  Future<Icp5MasterVolumeResult> writeCapturedMasterVolume(double value) async {
    if (_stopped) return _volumeFailure('Shared DSP STOP is active.');
    if (!_handshakeComplete || _state != DspConnectionState.connected) {
      return _volumeFailure(
          'Successful ADAU1701 identity handshake is required.');
    }
    if (_busy) return _volumeFailure('Another ICP5 transaction is active.');
    _busy = true;
    try {
      final frame = Icp5FrameCodec.buildMasterVolumeWrite(value);
      final ack = await _exchange(frame, Icp5FrameCodec.parseMasterVolumeAck);
      if (ack == null) {
        return _volumeFailure('Malformed or mismatched ACK.',
            actual: true, mayHaveReached: true);
      }
      return Icp5MasterVolumeResult(
          success: true,
          wasActualWrite: true,
          writeMayHaveReachedDevice: true,
          rawAck: ack,
          message: 'PASS_ACK');
    } on TimeoutException {
      return _volumeFailure('ACK timeout.', actual: true, mayHaveReached: true);
    } catch (error) {
      return _volumeFailure('$error', actual: true, mayHaveReached: true);
    } finally {
      _busy = false;
    }
  }

  Future<Icp5DiagnosticOutcome> runTestWithGuardedRestore() async {
    final test = await writeCapturedMasterVolume(5.9);
    if (test.success || !test.writeMayHaveReachedDevice) {
      return Icp5DiagnosticOutcome(test: test, stopActivated: false);
    }
    final restore = await writeCapturedMasterVolume(6.0);
    if (!restore.success) {
      _activateStop(
          'ICP5 Master Volume restore failed; shared DSP STOP activated.');
    }
    return Icp5DiagnosticOutcome(
        test: test, restore: restore, stopActivated: !restore.success);
  }

  Future<Icp5MasterVolumeResult> restoreBaselineWithStop() async {
    final restore = await writeCapturedMasterVolume(6.0);
    if (!restore.success && restore.writeMayHaveReachedDevice) {
      _activateStop(
          'ICP5 Master Volume restore failed; shared DSP STOP activated.');
    }
    return restore;
  }

  Future<Icp5MasterMuteResult> writeCapturedMasterMuteState(int state) async {
    if (_stopped) return _muteFailure('Shared DSP STOP is active.');
    if (!_handshakeComplete ||
        _state != DspConnectionState.connected ||
        _profile != Icp5FrameCodec.expectedProfile) {
      return _muteFailure(
          'Successful ADAU1701 identity handshake is required.');
    }
    if (_busy) return _muteFailure('Another ICP5 transaction is active.');
    _busy = true;
    try {
      final frame = Icp5FrameCodec.buildMasterMuteWrite(state);
      final ack = await _exchange(frame, Icp5FrameCodec.parseMasterMuteAck);
      if (ack == null) {
        return _muteFailure('Malformed or mismatched ACK.',
            actual: true, mayHaveReached: true);
      }
      return Icp5MasterMuteResult(
          success: true,
          wasActualWrite: true,
          writeMayHaveReachedDevice: true,
          rawAck: ack,
          message: 'PASS_ACK');
    } on TimeoutException {
      return _muteFailure('ACK timeout.', actual: true, mayHaveReached: true);
    } catch (error) {
      return _muteFailure('$error', actual: true, mayHaveReached: true);
    } finally {
      _busy = false;
    }
  }

  Future<Icp5MuteDiagnosticOutcome> runMuteTestWithGuardedRestore() async {
    final test = await writeCapturedMasterMuteState(1);
    if (test.success || !test.writeMayHaveReachedDevice) {
      return Icp5MuteDiagnosticOutcome(test: test, stopActivated: false);
    }
    final restore = await writeCapturedMasterMuteState(0);
    if (!restore.success) {
      _activateStop(
          'ICP5 Master Mute restore failed; shared DSP STOP activated.');
    }
    return Icp5MuteDiagnosticOutcome(
        test: test, restore: restore, stopActivated: !restore.success);
  }

  Future<Icp5MasterMuteResult> restoreMuteStateZeroWithStop() async {
    final restore = await writeCapturedMasterMuteState(0);
    if (!restore.success && restore.writeMayHaveReachedDevice) {
      _activateStop(
          'ICP5 Master Mute restore failed; shared DSP STOP activated.');
    }
    return restore;
  }

  Future<Icp5OutputDac1GainResult> writeCapturedOutputDac1Gain(
      double value) async {
    if (_stopped) return _dacGainFailure('Shared DSP STOP is active.');
    if (!_handshakeComplete ||
        _state != DspConnectionState.connected ||
        _profile != Icp5FrameCodec.expectedProfile) {
      return _dacGainFailure(
          'Successful ADAU1701 identity handshake is required.');
    }
    if (_busy) return _dacGainFailure('Another ICP5 transaction is active.');
    _busy = true;
    try {
      final frame = Icp5FrameCodec.buildOutputDac1GainWrite(value);
      final ack = await _exchange(frame, Icp5FrameCodec.parseOutputDac1GainAck);
      if (ack == null) {
        return _dacGainFailure('Malformed or mismatched ACK.',
            actual: true, mayHaveReached: true);
      }
      return Icp5OutputDac1GainResult(
          success: true,
          wasActualWrite: true,
          writeMayHaveReachedDevice: true,
          rawAck: ack,
          message: 'PASS_ACK');
    } on TimeoutException {
      return _dacGainFailure('ACK timeout.',
          actual: true, mayHaveReached: true);
    } catch (error) {
      return _dacGainFailure('$error', actual: true, mayHaveReached: true);
    } finally {
      _busy = false;
    }
  }

  Future<Icp5OutputDac1GainDiagnosticOutcome>
      runOutputDac1GainTestWithGuardedRestore() async {
    final test = await writeCapturedOutputDac1Gain(-4.9);
    if (test.success || !test.writeMayHaveReachedDevice) {
      return Icp5OutputDac1GainDiagnosticOutcome(
          test: test, stopActivated: false);
    }
    final restore = await writeCapturedOutputDac1Gain(-4.8);
    if (!restore.success) {
      _activateStop(
          'ICP5 Output DAC 1 Gain restore failed; shared DSP STOP activated.');
    }
    return Icp5OutputDac1GainDiagnosticOutcome(
        test: test, restore: restore, stopActivated: !restore.success);
  }

  Future<Icp5OutputDac1GainResult> restoreOutputDac1GainWithStop() async {
    final restore = await writeCapturedOutputDac1Gain(-4.8);
    if (!restore.success && restore.writeMayHaveReachedDevice) {
      _activateStop(
          'ICP5 Output DAC 1 Gain restore failed; shared DSP STOP activated.');
    }
    return restore;
  }

  Future<Icp5PhaseCResult> writeCapturedOutputGain(int channel, double value) =>
      _writePhaseC(Icp5FrameCodec.buildOutputGainWrite(channel, value),
          Icp5FrameCodec.parseOutputGainAck);

  Future<Icp5PhaseCResult> writeCapturedDelayCandidate(
          int channel, double value) =>
      _writePhaseC(Icp5FrameCodec.buildDelayCandidateWrite(channel, value),
          Icp5FrameCodec.parseDelayCandidateAck);

  Future<Icp5PhaseCResult> writeCapturedFilterCutoff(int channel, int value) =>
      _writePhaseC(Icp5FrameCodec.buildFilterCutoffWrite(channel, value),
          Icp5FrameCodec.parseFilterCutoffAck);

  /// Writes an arbitrary PEQ gain in −6.0 .. +3.0 dB for [channel] and [band]
  /// (0 = Band 1). Uses the confirmed parameter-ID 0x18 encoding. Band 0 is
  /// capture-proven; bands 1..9 reuse the confirmed band payload byte and are
  /// hardware-unverified. Range-validated only.
  @override
  Future<Adau1701WriteAck> writePeqGain(int channel, double gainDb,
      {int band = 0}) async {
    final r = await _writePhaseC(
      Icp5FrameCodec.buildPeqGainWriteArbitrary(channel, gainDb, band: band),
      Icp5FrameCodec.parsePeqGainAck,
    );
    return Adau1701WriteAck(success: r.success, message: r.message);
  }

  /// Writes an arbitrary filter frequency in 20 .. 20 000 Hz for [channel] and
  /// [band] (0 = Band 1). Uses the confirmed parameter-ID 0x15 encoding. Band 0
  /// is capture-proven; bands 1..9 are hardware-unverified. Range-validated only.
  @override
  Future<Adau1701WriteAck> writeFilterFrequency(int channel, int frequencyHz,
      {int band = 0}) async {
    final r = await _writePhaseC(
      Icp5FrameCodec.buildFilterFrequencyWriteArbitrary(channel, frequencyHz,
          band: band),
      Icp5FrameCodec.parseFilterFrequencyAck,
    );
    return Adau1701WriteAck(success: r.success, message: r.message);
  }

  /// Writes an arbitrary PEQ Q in 0.3 .. 10.0 for [channel] and [band]
  /// (0 = Band 1).
  ///
  /// NOT capture-proven: the encoding is adopted from the hardware-proven
  /// Consumer Q builder (parameter 0x18, property 0x00) — hardware ACK +
  /// readback verification is PENDING. Goes through the identical STOP /
  /// handshake / profile / busy guards as [writePeqGain] via [_writePhaseC];
  /// the working transport request/response path is unchanged.
  @override
  Future<Adau1701WriteAck> writePeqQ(int channel, double q,
      {int band = 0}) async {
    final r = await _writePhaseC(
      Icp5FrameCodec.buildPeqQWriteArbitrary(channel, q, band: band),
      Icp5FrameCodec.parsePeqQAck,
    );
    return Adau1701WriteAck(success: r.success, message: r.message);
  }

  Future<Icp5PhaseCResult> writeCapturedPeqBand1Gain(
          int channel, double value) =>
      _writePhaseC(Icp5FrameCodec.buildPeqBand1GainWrite(channel, value),
          Icp5FrameCodec.parsePeqBand1GainAck);

  Future<Icp5PhaseCOutcome> runOutputGainTest(int channel) => _runPhaseC(
      () => writeCapturedOutputGain(channel, _outputGainPair(channel).$1),
      () => writeCapturedOutputGain(channel, _outputGainPair(channel).$2),
      'Output Gain DAC$channel');

  Future<Icp5PhaseCOutcome> runDelayCandidateTest(int channel) => _runPhaseC(
      () => writeCapturedDelayCandidate(channel, 1.0),
      () => writeCapturedDelayCandidate(channel, 0.04),
      'Delay candidate DAC$channel');

  Future<Icp5PhaseCOutcome> runFilterCutoffTest(int channel) => _runPhaseC(
      () => writeCapturedFilterCutoff(channel, _cutoffPair(channel).$1),
      () => writeCapturedFilterCutoff(channel, _cutoffPair(channel).$2),
      'Filter Cutoff DAC$channel');

  Future<Icp5PhaseCOutcome> runPeqBand1GainTest(int channel) => _runPhaseC(
      () => writeCapturedPeqBand1Gain(channel, _peqPair(channel).$1),
      () => writeCapturedPeqBand1Gain(channel, _peqPair(channel).$2),
      'PEQ Band 1 DAC$channel');

  Future<Icp5PhaseCResult> restoreOutputGain(int channel) => _restorePhaseC(
      () => writeCapturedOutputGain(channel, _outputGainPair(channel).$2),
      'Output Gain DAC$channel');
  Future<Icp5PhaseCResult> restoreDelayCandidate(int channel) => _restorePhaseC(
      () => writeCapturedDelayCandidate(channel, 0.04),
      'Delay candidate DAC$channel');
  Future<Icp5PhaseCResult> restoreFilterCutoff(int channel) => _restorePhaseC(
      () => writeCapturedFilterCutoff(channel, _cutoffPair(channel).$2),
      'Filter Cutoff DAC$channel');
  Future<Icp5PhaseCResult> restorePeqBand1Gain(int channel) => _restorePhaseC(
      () => writeCapturedPeqBand1Gain(channel, _peqPair(channel).$2),
      'PEQ Band 1 DAC$channel');

  (double, double) _outputGainPair(int channel) => switch (channel) {
        0 => (-4.9, -4.8),
        1 => (-4.8, -4.7),
        2 || 3 => (-0.16666946, -0.06666946),
        _ => throw ArgumentError.value(channel, 'channel'),
      };

  (int, int) _cutoffPair(int channel) => switch (channel) {
        0 || 1 => (2001, 2000),
        2 || 3 => (21, 20),
        _ => throw ArgumentError.value(channel, 'channel'),
      };

  (double, double) _peqPair(int channel) => switch (channel) {
        0 => (-0.9, -1.0),
        1 => (4.2, 4.1),
        2 => (-1.0, -2.0),
        3 => (2.1, 2.0),
        _ => throw ArgumentError.value(channel, 'channel'),
      };

  Future<Icp5PhaseCResult> _writePhaseC(
      List<int> frame, bool Function(List<int>) parseAck) async {
    if (_stopped) return _phaseCFailure('Shared DSP STOP is active.');
    if (!_handshakeComplete ||
        _state != DspConnectionState.connected ||
        _profile != Icp5FrameCodec.expectedProfile) {
      return _phaseCFailure(
          'Successful ADAU1701 identity handshake is required.');
    }
    if (_busy) return _phaseCFailure('Another ICP5 transaction is active.');
    _busy = true;
    try {
      final ack = await _exchange(frame, parseAck);
      if (ack == null) {
        return _phaseCFailure('Malformed or mismatched ACK.',
            actual: true, mayHaveReached: true);
      }
      return Icp5PhaseCResult(
          success: true,
          wasActualWrite: true,
          writeMayHaveReachedDevice: true,
          rawAck: ack,
          message: 'PASS_ACK');
    } on TimeoutException {
      return _phaseCFailure('ACK timeout.', actual: true, mayHaveReached: true);
    } catch (error) {
      return _phaseCFailure('$error', actual: true, mayHaveReached: true);
    } finally {
      _busy = false;
    }
  }

  Future<Icp5PhaseCOutcome> _runPhaseC(
      Future<Icp5PhaseCResult> Function() testWrite,
      Future<Icp5PhaseCResult> Function() restoreWrite,
      String label) async {
    final test = await testWrite();
    if (test.success || !test.writeMayHaveReachedDevice) {
      return Icp5PhaseCOutcome(test: test, stopActivated: false);
    }
    final restore = await restoreWrite();
    if (!restore.success) {
      _activateStop('ICP5 $label restore failed; shared DSP STOP activated.');
    }
    return Icp5PhaseCOutcome(
        test: test, restore: restore, stopActivated: !restore.success);
  }

  Future<Icp5PhaseCResult> _restorePhaseC(
      Future<Icp5PhaseCResult> Function() restoreWrite, String label) async {
    final restore = await restoreWrite();
    if (!restore.success && restore.writeMayHaveReachedDevice) {
      _activateStop('ICP5 $label restore failed; shared DSP STOP activated.');
    }
    return restore;
  }

  /// Routes every complete frame extracted from the receive buffer, mirroring
  /// ConsumerBleService._onNotification: the handshake completer takes priority;
  /// otherwise a frame is delivered only to an active, generation-current
  /// request whose matcher accepts it. Every other frame is discarded so a
  /// stale or unsolicited response can never satisfy a later request.
  void _onBytes(List<int> chunk) {
    for (final frame in _buffer.add(chunk)) {
      final handshake = _handshakeResponse;
      if (handshake != null && !handshake.isCompleted) {
        handshake.complete(frame);
        continue;
      }
      final application = _pendingResponse;
      final matcher = _pendingAccepts;
      if (application != null &&
          !application.isCompleted &&
          _activeGeneration >= 0 &&
          matcher != null &&
          matcher(frame)) {
        application.complete(frame);
      }
    }
  }

  // On a transport-level stream error or close, invalidate the active
  // generation so no in-flight frame can satisfy the pending request, and mark
  // the connection errored. The pending handshake or application operation then
  // fails closed via its own timeout — PRO has no auto-reconnect, so (unlike the
  // Consumer, which fails fast to trigger reconnect) it must not surface a raw
  // stream error that races the synchronous notify path.
  void _onConnectionError(Object error, StackTrace stackTrace) {
    _activeGeneration = -1;
    _state = DspConnectionState.error;
  }

  void _onConnectionClosed() {
    _activeGeneration = -1;
  }

  /// Releases generation/completer ownership, mirroring
  /// ConsumerBleService._clearApplicationRequest.
  void _clearApplicationRequest(int generation, Completer<List<int>> response) {
    if (_activeGeneration == generation) _activeGeneration = -1;
    if (_applicationGeneration == generation &&
        (_pendingResponse == null || identical(_pendingResponse, response))) {
      _pendingResponse = null;
      _pendingAccepts = null;
    }
  }

  /// Writes one request frame and returns the next matching notification, or
  /// null on timeout. Structurally equivalent to
  /// ConsumerBleService.sendApplicationFrameAndAwaitExchange: exactly one
  /// request may await a response at a time; the generation-guarded completer
  /// and matcher are armed BEFORE the write so a fast notify is never missed.
  Future<List<int>?> _exchange(
      List<int> tx, bool Function(List<int>) accepts) async {
    if (_pendingResponse != null) {
      throw StateError('Another ICP5 command is awaiting a response.');
    }
    final generation = ++_applicationGeneration;
    _activeGeneration = generation;
    _pendingAccepts = accepts;
    final response = Completer<List<int>>();
    _pendingResponse = response;
    try {
      final written =
          await _connection!.write(tx, writeTimeout).timeout(writeTimeout);
      if (written != tx.length) {
        throw StateError('Partial serial write: $written/${tx.length}.');
      }
      return await response.future.timeout(readTimeout);
    } on TimeoutException {
      // Consumer-proven fail-closed timeout handling: invalidate the generation
      // so an in-flight notification is discarded immediately, quarantine to
      // absorb a delayed BLE frame, then flush any partial receive bytes.
      _clearApplicationRequest(generation, response);
      await Future<void>.delayed(staleAckQuarantine);
      _buffer.reset();
      return null;
    } finally {
      _clearApplicationRequest(generation, response);
    }
  }

  void _activateStop(String warning) {
    _stopped = true;
    onDspWriteStop?.call(warning);
  }

  DspTransportResult _fail(DspTransportFailure failure, String message) =>
      DspTransportResult(success: false, failure: failure, message: message);
  Icp5MasterVolumeResult _volumeFailure(String message,
          {bool actual = false, bool mayHaveReached = false}) =>
      Icp5MasterVolumeResult(
          success: false,
          wasActualWrite: actual,
          writeMayHaveReachedDevice: mayHaveReached,
          message: message);
  Icp5MasterMuteResult _muteFailure(String message,
          {bool actual = false, bool mayHaveReached = false}) =>
      Icp5MasterMuteResult(
          success: false,
          wasActualWrite: actual,
          writeMayHaveReachedDevice: mayHaveReached,
          message: message);
  Icp5OutputDac1GainResult _dacGainFailure(String message,
          {bool actual = false, bool mayHaveReached = false}) =>
      Icp5OutputDac1GainResult(
          success: false,
          wasActualWrite: actual,
          writeMayHaveReachedDevice: mayHaveReached,
          message: message);
  Icp5PhaseCResult _phaseCFailure(String message,
          {bool actual = false, bool mayHaveReached = false}) =>
      Icp5PhaseCResult(
          success: false,
          wasActualWrite: actual,
          writeMayHaveReachedDevice: mayHaveReached,
          message: message);
}

class Icp5BluetoothTransport extends Icp5UsbTransport {
  Icp5BluetoothTransport(
      {Icp5SerialDriver? driver,
      super.readTimeout,
      super.writeTimeout,
      super.onDspWriteStop})
      : super(driver: driver ?? Icp5BluetoothGattDriver());

  @override
  DspTransportIdentity get identity => DspTransportIdentity.icp5Bluetooth;
  @override
  String get displayName => 'ICP5 Bluetooth';
  @override
  String? get missingEvidence =>
      'BLE GATT FFF2 TX / FFF1 Notify and raw ICP5 framing are proven; physical command QA remains pending.';

  /// The BLE scan owns the exact CoreBluetooth object selected by the UI.
  /// Connecting must never rescan or silently substitute a different device.
  @override
  Future<DspTransportResult> open() => _open(discoverFirst: false);
}
