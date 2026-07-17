import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/dsp_readback.dart';
import 'package:tunai_pro/core/transport/icp5_protocol_evidence.dart';

class _ReadCapability implements DspReadCapability {
  final DspSnapshot snapshot;
  int calls = 0;

  _ReadCapability(this.snapshot);

  @override
  bool get isAvailable => true;
  @override
  bool get isConnected => true;
  @override
  bool get identityValidated => true;
  @override
  String? get deviceIdentifier => snapshot.deviceIdentifier;

  @override
  Future<ReadResult> readPeqBands(List<PeqBandAddress> bands) async {
    calls++;
    return ReadResult.success(snapshot);
  }
}

class _UnavailableSpyCapability implements DspReadCapability {
  int calls = 0;

  @override
  bool get isAvailable => false;
  @override
  bool get isConnected => true;
  @override
  bool get identityValidated => true;
  @override
  String? get deviceIdentifier => 'icp5-1';

  @override
  Future<ReadResult> readPeqBands(List<PeqBandAddress> bands) async {
    calls++;
    return const ReadResult.failure(
      ReadResultStatus.unavailable,
      'DSP readback capability is unavailable.',
    );
  }
}

void main() {
  const band0 = PeqBandAddress(channel: 0, bandId: 0);

  DspSnapshot snapshot(List<PeqBandState> bands) => DspSnapshot(
        deviceIdentifier: 'icp5-1',
        capturedAt: DateTime.utc(2026, 7, 17),
        peqBands: bands,
      );

  const validBand = PeqBandState(
    channel: 0,
    bandId: 0,
    frequencyHz: 1800,
    gainDb: -1,
    q: 2,
    enabled: true,
  );

  test('ICP5 PEQ read remains unsupported without capture evidence', () {
    expect(Icp5ProtocolEvidenceRegistry.usb.hasPeqReadEvidence, isFalse);
    expect(Icp5ProtocolEvidenceRegistry.usb.peqReadRequest, isNull);
    expect(Icp5ProtocolEvidenceRegistry.usb.peqReadResponseFormat, isNull);
  });

  test('unavailable capability returns no state and performs no read',
      () async {
    final capability = _UnavailableSpyCapability();
    final result = await GuardedDspReadTransaction(capability).readPeqSnapshot(
      expectedDeviceIdentifier: 'icp5-1',
      requiredBands: const [band0],
    );
    expect(result.status, ReadResultStatus.unavailable);
    expect(result.snapshot, isNull);
    expect(capability.calls, 0);
  });

  test('complete hardware snapshot passes validation', () async {
    final capability = _ReadCapability(snapshot(const [validBand]));
    final result = await GuardedDspReadTransaction(capability).readPeqSnapshot(
      expectedDeviceIdentifier: 'icp5-1',
      requiredBands: const [band0],
    );
    expect(result.succeeded, isTrue);
    expect(result.snapshot?.stateFor(band0)?.gainDb, -1);
    expect(capability.calls, 1);
  });

  test('invalid and duplicate snapshot state is rejected', () {
    final invalid = snapshot(const [
      validBand,
      validBand,
    ]);
    expect(invalid.isStructurallyValid, isFalse);
    expect(
        ReadResult.success(invalid).status, ReadResultStatus.invalidResponse);
  });

  test('incomplete snapshot is rejected after guarded read', () async {
    final capability = _ReadCapability(snapshot(const [validBand]));
    final result = await GuardedDspReadTransaction(capability).readPeqSnapshot(
      expectedDeviceIdentifier: 'icp5-1',
      requiredBands: const [
        band0,
        PeqBandAddress(channel: 0, bandId: 1),
      ],
    );
    expect(result.status, ReadResultStatus.incompleteSnapshot);
    expect(result.snapshot, isNull);
  });
}
