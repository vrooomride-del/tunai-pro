// ── TUNAI PRO Phase 3-D1 — record package input-device adapter ─────────────
//
// The only place in this codebase allowed to call
// AudioRecorder.listInputDevices()/hasPermission() for measurement-setup
// purposes — every controller consults this service instead of calling the
// plugin directly, so device enumeration/resolution logic exists in exactly
// one tested place.

import 'package:record/record.dart' as record_pkg;

import 'measurement_input_device.dart';

/// Thin, mockable seam over the two `record` package calls this module
/// needs. [RecordPackageInputDeviceApi] is the real implementation; tests
/// supply a fake instead of standing up a platform channel.
abstract class MeasurementInputDeviceApi {
  Future<bool> hasPermission({bool request = true});
  Future<List<MeasurementInputDeviceDescriptor>> listInputDevices();
}

/// Real implementation wrapping an existing `AudioRecorder` instance —
/// deliberately takes the recorder rather than owning one, so it can share
/// the same recorder instance MicMeasurementController already manages
/// (this module never starts/stops recording itself).
class RecordPackageInputDeviceApi implements MeasurementInputDeviceApi {
  final record_pkg.AudioRecorder _recorder;
  const RecordPackageInputDeviceApi(this._recorder);

  @override
  Future<bool> hasPermission({bool request = true}) =>
      _recorder.hasPermission(request: request);

  @override
  Future<List<MeasurementInputDeviceDescriptor>> listInputDevices() async {
    final devices = await _recorder.listInputDevices();
    return [
      for (final d in devices)
        MeasurementInputDeviceDescriptor(id: d.id, label: d.label),
    ];
  }
}

/// Composes [MeasurementInputDeviceApi] with [MeasurementInputDeviceResolver]
/// for the one operation that matters for safety: resolving a project's
/// selection against a FRESH enumeration immediately before recording.
class MeasurementInputDeviceService {
  final MeasurementInputDeviceApi _api;
  const MeasurementInputDeviceService(this._api);

  Future<bool> hasPermission({bool request = true}) =>
      _api.hasPermission(request: request);

  Future<List<MeasurementInputDeviceDescriptor>> listAvailableDevices() =>
      _api.listInputDevices();

  /// Re-enumerates and resolves [selection] against the result — never
  /// trusts a previously-cached device list. Returns null for "use system
  /// default" (pass `RecordConfig(device: null)`); throws
  /// [MeasurementInputDeviceUnavailable] if a specific selected device is
  /// no longer present.
  Future<MeasurementInputDeviceDescriptor?> resolveForRecording(
    MeasurementInputDeviceSelection selection,
  ) async {
    final available = await listAvailableDevices();
    return MeasurementInputDeviceResolver.resolve(
      selection: selection,
      available: available,
    );
  }

  /// Converts a resolved descriptor (or null for system default) into the
  /// `record` package's own [record_pkg.InputDevice] for use in a
  /// `RecordConfig(device: ...)` — the one place this module's types cross
  /// back into the plugin's types.
  static record_pkg.InputDevice? toRecordConfigDevice(
    MeasurementInputDeviceDescriptor? resolved,
  ) =>
      resolved == null
          ? null
          : record_pkg.InputDevice(id: resolved.id, label: resolved.label);
}
