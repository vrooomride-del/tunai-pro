import 'dart:math' as math;
import 'pro_adau1466_sigma_candidate.dart';
import 'pro_adau1466_sigma_executor.dart';

const int kOperationalMasterVolumeL = 0x0067;
const int kOperationalMasterVolumeR = 0x0064;
const int kAdau1466Fixed824Scale = 1 << 24;

int encodeAdau1466Linear824(double linear) {
  final clamped = linear.clamp(0.0, 1.0);
  return (clamped * kAdau1466Fixed824Scale).round();
}

double adau1466LinearToDb(double linear) =>
    linear <= 0 ? double.negativeInfinity : 20 * math.log(linear) / math.ln10;

class Adau1466StereoWriteResult {
  final CandidateValidationStatus status;
  final bool lAckOk;
  final bool rAckOk;
  final bool rollbackAttempted;
  final bool rollbackAckOk;
  final bool confirmed;
  final String? error;

  const Adau1466StereoWriteResult({
    required this.status,
    required this.lAckOk,
    required this.rAckOk,
    required this.rollbackAttempted,
    required this.rollbackAckOk,
    required this.confirmed,
    this.error,
  });

  factory Adau1466StereoWriteResult.blocked(String error) =>
      Adau1466StereoWriteResult(
        status: CandidateValidationStatus.blocked,
        lAckOk: false,
        rAckOk: false,
        rollbackAttempted: false,
        rollbackAckOk: false,
        confirmed: false,
        error: error,
      );
}

/// Transactional linked-stereo writer for the two verified ADAU1466 MV words.
/// No SafeLoad, EEPROM, Selfboot, or arbitrary-address entry point exists here.
class ProAdau1466MasterVolumeExecutor {
  final ProUsbiSigmaVerificationExecutor sigmaExecutor;

  const ProAdau1466MasterVolumeExecutor({required this.sigmaExecutor});

  bool get isRealExecutorAvailable => sigmaExecutor.isRealExecutorAvailable;

  Future<Adau1466StereoWriteResult> writeLinkedStereo({
    required double previousLinear,
    required double requestedLinear,
    required bool deviceOpen,
  }) async {
    if (!deviceOpen) {
      return Adau1466StereoWriteResult.blocked('USBi device is not open.');
    }
    if (!isRealExecutorAvailable) {
      return Adau1466StereoWriteResult.blocked(
          'Windows real USBi executor is unavailable.');
    }
    if (requestedLinear < 0.0 || requestedLinear > 1.0) {
      return Adau1466StereoWriteResult.blocked(
          'Master Volume must be within 0.0–1.0.');
    }

    final next824 = encodeAdau1466Linear824(requestedLinear);
    final previous824 = encodeAdau1466Linear824(previousLinear);

    final left = await sigmaExecutor.writeSingleValue(
      addressInt: kOperationalMasterVolumeL,
      fixedPointValue: next824,
    );
    if (!left.ackOk) {
      return Adau1466StereoWriteResult(
        status: CandidateValidationStatus.fail,
        lAckOk: false,
        rAckOk: false,
        rollbackAttempted: false,
        rollbackAckOk: false,
        confirmed: false,
        error: left.error ?? 'Left write failed.',
      );
    }

    final right = await sigmaExecutor.writeSingleValue(
      addressInt: kOperationalMasterVolumeR,
      fixedPointValue: next824,
    );
    if (!right.ackOk) {
      final rollback = await sigmaExecutor.writeSingleValue(
        addressInt: kOperationalMasterVolumeL,
        fixedPointValue: previous824,
      );
      return Adau1466StereoWriteResult(
        status: CandidateValidationStatus.fail,
        lAckOk: true,
        rAckOk: false,
        rollbackAttempted: true,
        rollbackAckOk: rollback.ackOk,
        confirmed: false,
        error: right.error ?? 'Right write failed.',
      );
    }

    return const Adau1466StereoWriteResult(
      status: CandidateValidationStatus.passAck,
      lAckOk: true,
      rAckOk: true,
      rollbackAttempted: false,
      rollbackAckOk: false,
      confirmed: true,
    );
  }
}
