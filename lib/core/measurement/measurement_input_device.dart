// ── TUNAI PRO Phase 3-D1 — Input device typed model ─────────────────────────
//
// Separate module from lib/core/calibration/ — an OS audio input device is a
// distinct concept from a microphone's calibration identity. See
// MeasurementMicrophoneProfile.inputDeviceId's doc comment for how the two
// relate: that field is an optional hint recorded when a profile was
// authored, never a live OS device handle. The types here ARE the live
// handle.
//
// Every field here is backed by an API actually present in
// package:record 6.2.1 / record_platform_interface 1.6.0 (audited directly
// from the pub-cache source for Phase 3-D). In particular:
//   - InputDevice (that package's type) has exactly `id` and `label` — no
//     capability metadata of any kind. This module must never invent a
//     capability field (e.g. "supports 48kHz") that API cannot back.
//   - There is no sample-rate/channel-count capability query anywhere in
//     that API. What a device "supports" is only ever knowable after the
//     fact, from the actual recorded file's own metadata — see
//     MeasurementWavParser and MeasurementInputDeviceSnapshot.actualSampleRate
//     /actualChannelCount below.
library;

/// A device as reported by `AudioRecorder.listInputDevices()` at the moment
/// of enumeration. Never cached/reused past that call without a fresh
/// re-check — see MeasurementInputDeviceResolver.
class MeasurementInputDeviceDescriptor {
  final String id;
  final String label;

  const MeasurementInputDeviceDescriptor({
    required this.id,
    required this.label,
  });

  Map<String, dynamic> toJson() => {'id': id, 'label': label};

  factory MeasurementInputDeviceDescriptor.fromJson(Map<String, dynamic> j) =>
      MeasurementInputDeviceDescriptor(
        id: j['id'] as String,
        label: j['label'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is MeasurementInputDeviceDescriptor &&
      other.id == id &&
      other.label == label;

  @override
  int get hashCode => Object.hash(id, label);
}

/// A project's current choice of input device. Persisted on [ProProject] —
/// never shared across projects, never auto-selected.
///
/// [useSystemDefault] and a specific [deviceId] are mutually exclusive and
/// BOTH explicit — there is no third "unset" value encoded as null-equals-
/// default. A [MeasurementInputDeviceSelection] existing at all means the
/// user made a choice; a project with no selection object simply has none
/// (see [ProProject] — the field itself is nullable for that state).
class MeasurementInputDeviceSelection {
  /// Null when [useSystemDefault] is true. Never both null and
  /// [useSystemDefault] false — that combination is not constructible via
  /// the named constructors below.
  final String? deviceId;

  /// True only when the user explicitly chose "use system default" —
  /// this is itself a decision, not what happens when nothing was picked.
  final bool useSystemDefault;

  /// The device's label AT SELECTION TIME, for display only — never used
  /// to re-identify the device (label-only matching is explicitly
  /// prohibited; see MeasurementInputDeviceResolver, which matches by id).
  final String labelSnapshot;

  final DateTime selectedAt;

  const MeasurementInputDeviceSelection._({
    required this.deviceId,
    required this.useSystemDefault,
    required this.labelSnapshot,
    required this.selectedAt,
  });

  factory MeasurementInputDeviceSelection.specificDevice({
    required String deviceId,
    required String labelSnapshot,
    required DateTime selectedAt,
  }) =>
      MeasurementInputDeviceSelection._(
        deviceId: deviceId,
        useSystemDefault: false,
        labelSnapshot: labelSnapshot,
        selectedAt: selectedAt,
      );

  factory MeasurementInputDeviceSelection.systemDefault({
    required DateTime selectedAt,
    String labelSnapshot = 'System Default',
  }) =>
      MeasurementInputDeviceSelection._(
        deviceId: null,
        useSystemDefault: true,
        labelSnapshot: labelSnapshot,
        selectedAt: selectedAt,
      );

  Map<String, dynamic> toJson() => {
        if (deviceId != null) 'deviceId': deviceId,
        'useSystemDefault': useSystemDefault,
        'labelSnapshot': labelSnapshot,
        'selectedAt': selectedAt.toIso8601String(),
      };

  /// Throws on a structurally invalid selection (neither system-default nor
  /// a device id) — callers (project decode) catch and fall back to "no
  /// selection", never fabricate one.
  factory MeasurementInputDeviceSelection.fromJson(Map<String, dynamic> j) {
    final useSystemDefault = j['useSystemDefault'] as bool? ?? false;
    final deviceId = j['deviceId'] as String?;
    if (!useSystemDefault && deviceId == null) {
      throw const FormatException(
          'MeasurementInputDeviceSelection: neither useSystemDefault nor a '
          'deviceId was present.');
    }
    return MeasurementInputDeviceSelection._(
      deviceId: useSystemDefault ? null : deviceId,
      useSystemDefault: useSystemDefault,
      labelSnapshot: j['labelSnapshot'] as String? ?? '',
      selectedAt:
          DateTime.tryParse(j['selectedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// The input device actually used for one capture, plus what the recorded
/// file itself proved about sample rate/channel count — never what was
/// merely requested. Immutable; embedded verbatim into a captured
/// measurement's quality record, the same "freeze at capture time" pattern
/// as MeasurementMicrophoneSnapshot.
class MeasurementInputDeviceSnapshot {
  final String? deviceId;
  final String label;
  final bool isSystemDefault;

  /// 'macos' / 'windows' / etc — Platform.operatingSystem verbatim. Not
  /// every platform-specific field record exposes is nullable-safe across
  /// OSes, so this module only ever carries the two fields that ARE
  /// universal (id/label) plus this tag for display/diagnostics.
  final String platform;

  /// From the actual recorded WAV file's fmt chunk — never the value that
  /// was merely requested in RecordConfig. Null only if the file could not
  /// be parsed (malformed capture).
  final int? actualSampleRate;
  final int? actualChannelCount;

  final DateTime capturedAt;

  const MeasurementInputDeviceSnapshot({
    required this.deviceId,
    required this.label,
    required this.isSystemDefault,
    required this.platform,
    required this.actualSampleRate,
    required this.actualChannelCount,
    required this.capturedAt,
  });

  Map<String, dynamic> toJson() => {
        if (deviceId != null) 'deviceId': deviceId,
        'label': label,
        'isSystemDefault': isSystemDefault,
        'platform': platform,
        if (actualSampleRate != null) 'actualSampleRate': actualSampleRate,
        if (actualChannelCount != null)
          'actualChannelCount': actualChannelCount,
        'capturedAt': capturedAt.toIso8601String(),
      };

  factory MeasurementInputDeviceSnapshot.fromJson(Map<String, dynamic> j) =>
      MeasurementInputDeviceSnapshot(
        deviceId: j['deviceId'] as String?,
        label: j['label'] as String? ?? '',
        isSystemDefault: j['isSystemDefault'] as bool? ?? false,
        platform: j['platform'] as String? ?? '',
        actualSampleRate: j['actualSampleRate'] as int?,
        actualChannelCount: j['actualChannelCount'] as int?,
        capturedAt: DateTime.tryParse(j['capturedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// Thrown when a [MeasurementInputDeviceSelection] names a specific device
/// id that is not present in a fresh enumeration — fail-closed, never a
/// silent fallback to system default or any other device.
class MeasurementInputDeviceUnavailable implements Exception {
  final String deviceId;
  const MeasurementInputDeviceUnavailable(this.deviceId);

  @override
  String toString() =>
      'MeasurementInputDeviceUnavailable: device "$deviceId" is not in the '
      'current input device list.';
}

/// Thrown when [MeasurementInputDeviceResolver.resolve] is called with a
/// selection that is neither system-default nor a specific device — i.e. no
/// selection was actually made. Callers must check for a selection before
/// resolving; this is a programming-error guard, not a normal user state.
class MeasurementInputDeviceNotSelected implements Exception {
  const MeasurementInputDeviceNotSelected();

  @override
  String toString() => 'MeasurementInputDeviceNotSelected: no input device '
      'selection was made (neither useSystemDefault nor a deviceId).';
}

/// Pure resolution: no I/O, no record package types. Given a selection and
/// an ALREADY-FRESH device list, decides what to record with.
abstract final class MeasurementInputDeviceResolver {
  /// Returns null for "use system default" (caller should pass
  /// `RecordConfig(device: null)`), or the matching descriptor for a
  /// specific-device selection.
  ///
  /// Throws [MeasurementInputDeviceUnavailable] if [selection] names a
  /// device id absent from [available] — never silently substitutes
  /// another device or falls back to default.
  ///
  /// Throws [MeasurementInputDeviceNotSelected] if [selection] is neither
  /// system-default nor a specific device (should not occur given the
  /// factory constructors, but this module never trusts a value it didn't
  /// construct itself without checking).
  static MeasurementInputDeviceDescriptor? resolve({
    required MeasurementInputDeviceSelection selection,
    required List<MeasurementInputDeviceDescriptor> available,
  }) {
    if (selection.useSystemDefault) return null;
    final id = selection.deviceId;
    if (id == null) {
      throw const MeasurementInputDeviceNotSelected();
    }
    for (final d in available) {
      if (d.id == id) return d;
    }
    throw MeasurementInputDeviceUnavailable(id);
  }
}
