/// Hardware-neutral address of a parametric equalizer band.
class PeqBandAddress {
  final int channel;
  final int bandId;

  const PeqBandAddress({required this.channel, required this.bandId});

  bool get isValid => channel >= 0 && bandId >= 0;
}

/// PEQ state returned by a validated hardware read transaction.
class PeqBandState {
  final int channel;
  final int bandId;
  final int frequencyHz;
  final double gainDb;
  final double q;
  final bool enabled;

  const PeqBandState({
    required this.channel,
    required this.bandId,
    required this.frequencyHz,
    required this.gainDb,
    required this.q,
    required this.enabled,
  });

  PeqBandAddress get address =>
      PeqBandAddress(channel: channel, bandId: bandId);

  bool get isValid =>
      address.isValid &&
      frequencyHz >= 20 &&
      frequencyHz <= 20000 &&
      gainDb.isFinite &&
      q.isFinite &&
      q > 0;
}

/// Device-bound, point-in-time state obtained through hardware readback.
class DspSnapshot {
  final String deviceIdentifier;
  final DateTime capturedAt;
  final List<PeqBandState> peqBands;

  DspSnapshot({
    required this.deviceIdentifier,
    required this.capturedAt,
    required List<PeqBandState> peqBands,
  }) : peqBands = List.unmodifiable(peqBands);

  bool get isStructurallyValid =>
      deviceIdentifier.isNotEmpty &&
      peqBands.isNotEmpty &&
      peqBands.every((band) => band.isValid) &&
      _hasUniqueAddresses;

  bool get _hasUniqueAddresses {
    final addresses = <String>{};
    for (final band in peqBands) {
      if (!addresses.add('${band.channel}:${band.bandId}')) return false;
    }
    return true;
  }

  PeqBandState? stateFor(PeqBandAddress address) => peqBands
      .where((band) =>
          band.channel == address.channel && band.bandId == address.bandId)
      .firstOrNull;

  bool covers(Iterable<PeqBandAddress> requiredBands) =>
      isStructurallyValid &&
      requiredBands.every(
        (address) => address.isValid && stateFor(address) != null,
      );
}

enum ReadResultStatus {
  success,
  unavailable,
  disconnected,
  identityNotValidated,
  deviceIdentityMismatch,
  invalidRequest,
  invalidResponse,
  incompleteSnapshot,
  transportFailure,
}

class ReadResult {
  final ReadResultStatus status;
  final DspSnapshot? snapshot;
  final String message;

  const ReadResult._({
    required this.status,
    required this.message,
    this.snapshot,
  });

  factory ReadResult.success(DspSnapshot snapshot) {
    if (!snapshot.isStructurallyValid) {
      return const ReadResult._(
        status: ReadResultStatus.invalidResponse,
        message: 'Hardware read returned an invalid DSP snapshot.',
      );
    }
    return ReadResult._(
      status: ReadResultStatus.success,
      snapshot: snapshot,
      message: 'DSP state read succeeded.',
    );
  }

  const ReadResult.failure(this.status, this.message) : snapshot = null;

  bool get succeeded => status == ReadResultStatus.success && snapshot != null;
}

/// Read-only hardware capability. Implementations must not perform writes as
/// part of [readPeqBands].
abstract interface class DspReadCapability {
  bool get isAvailable;
  bool get isConnected;
  bool get identityValidated;
  String? get deviceIdentifier;

  Future<ReadResult> readPeqBands(List<PeqBandAddress> bands);
}

/// Fail-closed implementation used until a hardware read protocol has capture
/// evidence. It sends no transport bytes and returns no synthetic state.
class UnavailableDspReadCapability implements DspReadCapability {
  const UnavailableDspReadCapability();

  @override
  bool get isAvailable => false;
  @override
  bool get isConnected => false;
  @override
  bool get identityValidated => false;
  @override
  String? get deviceIdentifier => null;

  @override
  Future<ReadResult> readPeqBands(List<PeqBandAddress> bands) async =>
      const ReadResult.failure(
        ReadResultStatus.unavailable,
        'DSP readback capability is unavailable.',
      );
}

/// Applies connection, identity, request, and snapshot guards around a
/// read-only hardware capability. This class has no write API.
class GuardedDspReadTransaction {
  final DspReadCapability capability;

  const GuardedDspReadTransaction(this.capability);

  Future<ReadResult> readPeqSnapshot({
    required String expectedDeviceIdentifier,
    required List<PeqBandAddress> requiredBands,
  }) async {
    if (!capability.isAvailable) {
      return const ReadResult.failure(
        ReadResultStatus.unavailable,
        'DSP readback capability is unavailable.',
      );
    }
    if (!capability.isConnected) {
      return const ReadResult.failure(
        ReadResultStatus.disconnected,
        'DSP transport is disconnected.',
      );
    }
    if (!capability.identityValidated) {
      return const ReadResult.failure(
        ReadResultStatus.identityNotValidated,
        'DSP identity has not been validated.',
      );
    }
    if (expectedDeviceIdentifier.isEmpty ||
        capability.deviceIdentifier != expectedDeviceIdentifier) {
      return const ReadResult.failure(
        ReadResultStatus.deviceIdentityMismatch,
        'DSP identity does not match the requested device.',
      );
    }
    if (requiredBands.isEmpty || requiredBands.any((band) => !band.isValid)) {
      return const ReadResult.failure(
        ReadResultStatus.invalidRequest,
        'At least one valid PEQ band address is required.',
      );
    }

    final result = await capability.readPeqBands(
      List.unmodifiable(requiredBands),
    );
    if (!result.succeeded) return result;
    final snapshot = result.snapshot!;
    if (snapshot.deviceIdentifier != expectedDeviceIdentifier) {
      return const ReadResult.failure(
        ReadResultStatus.deviceIdentityMismatch,
        'Readback snapshot belongs to a different device.',
      );
    }
    if (!snapshot.covers(requiredBands)) {
      return const ReadResult.failure(
        ReadResultStatus.incompleteSnapshot,
        'Readback snapshot does not contain every requested PEQ band.',
      );
    }
    return result;
  }
}
