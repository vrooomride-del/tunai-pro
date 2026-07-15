import 'dart:async';
import 'dsp_command.dart';
import 'dsp_transport.dart';
import 'icp5_frame_codec.dart';
import 'icp5_serial_driver.dart';

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

class Icp5UsbTransport implements DspTransport {
  final Icp5SerialDriver driver;
  final Duration readTimeout;
  final Duration writeTimeout;
  final void Function(String warning)? onDspWriteStop;
  Icp5SerialConnection? _connection;
  StreamSubscription<List<int>>? _subscription;
  final Icp5FrameBuffer _buffer = Icp5FrameBuffer();
  final StreamController<List<int>> _frames =
      StreamController<List<int>>.broadcast();
  List<Icp5SerialDevice> _devices = const [];
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
      this.onDspWriteStop})
      : driver = driver ?? WindowsIcp5SerialDriver();

  List<Icp5SerialDevice> discover() {
    _devices = driver.discover();
    return List.unmodifiable(_devices);
  }

  List<Icp5SerialDevice> get discoveredDevices => List.unmodifiable(_devices);
  String? get selectedPort => _selectedPort;
  bool get handshakeComplete => _handshakeComplete;
  String? get detectedProfile => _profile;
  bool get stopped => _stopped;
  bool get busy => _busy;

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
      readbackSupport: false,
      reconnectSupport: true,
      maximumPayloadSize: 12,
      boardDetectionSupport: true);
  @override
  String? get missingEvidence =>
      'SafeLoad, arbitrary parameters/range, dB mapping, ADAU1466, and Bluetooth remain unproven.';

  @override
  Future<DspTransportResult> open() async {
    if (_connection != null || _state == DspConnectionState.connected) {
      return _fail(DspTransportFailure.unavailable,
          'ICP5 port is already exclusively owned by this session.');
    }
    if (_busy) {
      return _fail(
          DspTransportFailure.unavailable, 'Transaction already active.');
    }
    final devices = discover();
    if (devices.isEmpty) {
      return _fail(DspTransportFailure.unavailable,
          'No capture-proven ICP5 USB serial device found.');
    }
    _state = DspConnectionState.connecting;
    try {
      _selectedPort = devices.first.portName;
      _connection = await driver.open(_selectedPort!);
      _subscription = _connection!.bytes.listen((chunk) {
        for (final frame in _buffer.add(chunk)) {
          _frames.add(frame);
        }
      }, onError: (_) => _state = DspConnectionState.error);
      final identity = await _exchange(Icp5FrameCodec.identificationRequest,
          (frame) => Icp5FrameCodec.parseIdentity(frame) != null);
      final profile =
          identity == null ? null : Icp5FrameCodec.parseIdentity(identity);
      if (profile == null) {
        await close();
        return _fail(
            DspTransportFailure.ackFailed, 'ICP5 identity handshake failed.');
      }
      _handshakeComplete = true;
      _profile = profile;
      _state = DspConnectionState.connected;
      return const DspTransportResult(
          success: true,
          failure: DspTransportFailure.none,
          message: 'ICP5 connected · ADAU1701 profile proven.');
    } on TimeoutException {
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
    await _subscription?.cancel();
    _subscription = null;
    await _connection?.close();
    _connection = null;
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

  Future<List<int>?> _exchange(
      List<int> tx, bool Function(List<int>) accepts) async {
    final future = _frames.stream.firstWhere(accepts).timeout(readTimeout);
    final written =
        await _connection!.write(tx, writeTimeout).timeout(writeTimeout);
    if (written != tx.length) {
      throw StateError('Partial serial write: $written/${tx.length}.');
    }
    return future;
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
}

class Icp5BluetoothTransport implements DspTransport {
  const Icp5BluetoothTransport();
  @override
  DspTransportIdentity get identity => DspTransportIdentity.icp5Bluetooth;
  @override
  String get displayName => 'ICP5 Bluetooth';
  @override
  bool get isAvailable => false;
  @override
  DspConnectionState get connectionState => DspConnectionState.unavailable;
  @override
  DspTransportCapabilities get capabilities =>
      DspTransportCapabilities.unproven;
  @override
  String get missingEvidence => 'PROTOCOL EVIDENCE REQUIRED — WRITES BLOCKED';
  DspTransportResult get _blocked => const DspTransportResult(
      success: false,
      failure: DspTransportFailure.protocolEvidenceMissing,
      message: 'PROTOCOL EVIDENCE REQUIRED — WRITES BLOCKED');
  @override
  Future<DspTransportResult> open() async => _blocked;
  @override
  Future<void> close() async {}
  @override
  Future<DspTransportResult> execute(DspCommand command) async => _blocked;
}
