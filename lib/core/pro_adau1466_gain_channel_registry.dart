import 'dart:math';

import 'pro_adau1466_sigma_candidate.dart';
import 'pro_usbi_packet_builder.dart';

/// A non-executing registry of only the physically mapped Gain targets from
/// the current ADAU1466 SigmaStudio export.
///
/// This registry creates byte plans for review and Capture comparison. It has
/// no backend, executor, device handle, or actual-write entry point.
class ProAdau1466GainChannelRegistry {
  static const List<Adau1466MappedGainChannel> channels = [
    Adau1466MappedGainChannel(
      channel: 'WFL',
      sigmaCellName: 'Single 1',
      sigmaParameterName: 'HWGainADAU145XAlg3target',
      targetAddress: 0x03B8,
      testWord: 0x00000840,
      exportedRestoreWord: 0x0000068E,
      sigmaOutputCell: 'Output1',
      plannedPhysicalOutput: 'OUT3',
      restoreValueConfirmedByCapture: true,
      physicalMappingConfirmed: false,
      requiresAdditionalSigmaCapture: false,
      validationStatus: CandidateValidationStatus.passAck,
    ),
    Adau1466MappedGainChannel(
      channel: 'MID_L',
      sigmaCellName: 'Single 1_4',
      sigmaParameterName: 'HWGainADAU145XAlg4target',
      targetAddress: 0x03C4,
      testWord: 0x000014B9,
      exportedRestoreWord: 0x00001076,
      sigmaOutputCell: 'Output2',
      plannedPhysicalOutput: 'OUT2',
      restoreValueConfirmedByCapture: true,
      requiresAdditionalSigmaCapture: false,
    ),
    Adau1466MappedGainChannel(
      channel: 'TWL',
      sigmaCellName: 'Single 1_5',
      sigmaParameterName: 'HWGainADAU145XAlg5target',
      targetAddress: 0x03C7,
      testWord: 0x000020D8,
      exportedRestoreWord: 0x00001A17,
      sigmaOutputCell: 'Output3',
      plannedPhysicalOutput: 'OUT1',
      restoreValueConfirmedByCapture: true,
      requiresAdditionalSigmaCapture: false,
    ),
    Adau1466MappedGainChannel(
      channel: 'WFR',
      sigmaCellName: 'Single 1_6',
      sigmaParameterName: 'HWGainADAU145XAlg6target',
      targetAddress: 0x03BB,
      testWord: 0x00000840,
      exportedRestoreWord: 0x0000068E,
      sigmaOutputCell: 'Output4',
      plannedPhysicalOutput: 'OUT8',
      restoreValueConfirmedByCapture: true,
      requiresAdditionalSigmaCapture: false,
    ),
    Adau1466MappedGainChannel(
      channel: 'MID_R',
      sigmaCellName: 'Single 1_7',
      sigmaParameterName: 'HWGainADAU145XAlg7target',
      targetAddress: 0x03CA,
      testWord: 0x00005281,
      exportedRestoreWord: 0x00004189,
      sigmaOutputCell: 'Output5',
      plannedPhysicalOutput: 'OUT7',
      restoreValueConfirmedByCapture: true,
      requiresAdditionalSigmaCapture: false,
    ),
    Adau1466MappedGainChannel(
      channel: 'TWR',
      sigmaCellName: 'Single 1_8',
      sigmaParameterName: 'HWGainADAU145XAlg8target',
      targetAddress: 0x03CD,
      testWord: 0x00001A17,
      exportedRestoreWord: 0x000014B9,
      sigmaOutputCell: 'Output6',
      plannedPhysicalOutput: 'OUT4',
      restoreValueConfirmedByCapture: true,
      requiresAdditionalSigmaCapture: false,
    ),
  ];

  const ProAdau1466GainChannelRegistry._();

  static Adau1466MappedGainChannel? findByChannel(String channel) {
    for (final candidate in channels) {
      if (candidate.channel == channel) return candidate;
    }
    return null;
  }

  static Adau1466MappedGainChannel? findByTargetAddress(int targetAddress) {
    for (final candidate in channels) {
      if (candidate.targetAddress == targetAddress) return candidate;
    }
    return null;
  }

  /// ADAU1466 8.24 linear +2 dB step, clamped strictly below unity.
  static int computeConservativePlus2DbTestWord(int restoreWord) {
    final stepped = (restoreWord * pow(10, 2 / 20)).round();
    return min(stepped, 0x00FFFFFF);
  }

  /// Builds a review-only plan using the capture-proven three-stage structure.
  /// The returned packets cannot be executed through this registry.
  static Adau1466GainSafeLoadPacketPlan buildTestPlan(
          Adau1466MappedGainChannel channel) =>
      _buildLockedPlan(channel, channel.testWord);

  static Adau1466GainSafeLoadPacketPlan buildRestorePlan(
          Adau1466MappedGainChannel channel) =>
      _buildLockedPlan(channel, channel.exportedRestoreWord);

  static Adau1466GainSafeLoadPacketPlan _buildLockedPlan(
      Adau1466MappedGainChannel channel, int lockedValue) {
    if (!channels.contains(channel)) {
      throw ArgumentError(
          'Gain channel is not in the export-derived registry.');
    }
    return _ProAdau1466GainSafeLoadPlanBuilder.build(
      targetAddress: channel.targetAddress,
      gainValue: lockedValue,
    );
  }
}

class Adau1466MappedGainChannel {
  final String channel;
  final String sigmaCellName;
  final String sigmaParameterName;
  final int targetAddress;
  final int testWord;
  final int exportedRestoreWord;
  final String sigmaOutputCell;
  final String plannedPhysicalOutput;
  final bool restoreValueConfirmedByCapture;
  final bool physicalMappingConfirmed;
  final bool requiresAdditionalSigmaCapture;
  final CandidateValidationStatus validationStatus;

  const Adau1466MappedGainChannel({
    required this.channel,
    required this.sigmaCellName,
    required this.sigmaParameterName,
    required this.targetAddress,
    required this.testWord,
    required this.exportedRestoreWord,
    required this.sigmaOutputCell,
    required this.plannedPhysicalOutput,
    this.restoreValueConfirmedByCapture = false,
    this.physicalMappingConfirmed = false,
    this.requiresAdditionalSigmaCapture = true,
    this.validationStatus = CandidateValidationStatus.blocked,
  });

  int get slewAddress => targetAddress + 1;
  bool get sameSafeLoadStructureApplies => true;

  /// Enabled only for the dedicated, guarded one-shot diagnostic executor.
  bool get diagnosticWriteEnabled => true;

  bool get readyForFutureExecutor =>
      restoreValueConfirmedByCapture && physicalMappingConfirmed;
}

class _ProAdau1466GainSafeLoadPlanBuilder {
  static const int slewValue = 0x0000208A;
  static const int safeLoadDataAddress = 0x6000;
  static const int safeLoadTargetCountAddress = 0x6005;

  const _ProAdau1466GainSafeLoadPlanBuilder._();

  static Adau1466GainSafeLoadPacketPlan build({
    required int targetAddress,
    required int gainValue,
  }) {
    final slewBody = buildParameterWriteBody(
      addressInt: targetAddress + 1,
      fixedPointInt: slewValue,
    );
    final dataBody = buildParameterWriteBody(
      addressInt: safeLoadDataAddress,
      fixedPointInt: gainValue,
    );
    final targetCountBody = <int>[
      (safeLoadTargetCountAddress >> 8) & 0xFF,
      safeLoadTargetCountAddress & 0xFF,
      (targetAddress >> 24) & 0xFF,
      (targetAddress >> 16) & 0xFF,
      (targetAddress >> 8) & 0xFF,
      targetAddress & 0xFF,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x00,
    ];
    return Adau1466GainSafeLoadPacketPlan(stages: [
      Adau1466GainSafeLoadPacketStage(
        setupPacket: buildParameterWriteSetup(bodyLength: slewBody.length),
        bodyPacket: slewBody,
      ),
      Adau1466GainSafeLoadPacketStage(
        setupPacket: buildParameterWriteSetup(bodyLength: dataBody.length),
        bodyPacket: dataBody,
      ),
      Adau1466GainSafeLoadPacketStage(
        setupPacket:
            buildParameterWriteSetup(bodyLength: targetCountBody.length),
        bodyPacket: targetCountBody,
      ),
    ]);
  }
}

class Adau1466GainSafeLoadPacketPlan {
  final List<Adau1466GainSafeLoadPacketStage> stages;

  const Adau1466GainSafeLoadPacketPlan({required this.stages});
}

class Adau1466GainSafeLoadPacketStage {
  final List<int> setupPacket;
  final List<int> bodyPacket;

  const Adau1466GainSafeLoadPacketStage({
    required this.setupPacket,
    required this.bodyPacket,
  });
}
