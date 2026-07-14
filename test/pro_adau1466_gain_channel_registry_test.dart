import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_adau1466_gain_channel_registry.dart';
import 'package:tunai_pro/core/pro_adau1466_sigma_candidate.dart';

void main() {
  group('export-derived ADAU1466 mapped Gain channel registry', () {
    test(
        'contains exact current-export channel, cell, address, and mapping data',
        () {
      final expected = <String, (String, int, int, int, String, String)>{
        'WFL': ('Single 1', 0x03B8, 0x00000840, 0x0000068E, 'Output1', 'OUT3'),
        'MID_L': (
          'Single 1_4',
          0x03C4,
          0x000014B9,
          0x00001076,
          'Output2',
          'OUT2'
        ),
        'TWL': (
          'Single 1_5',
          0x03C7,
          0x000020D8,
          0x00001A17,
          'Output3',
          'OUT1'
        ),
        'WFR': (
          'Single 1_6',
          0x03BB,
          0x00000840,
          0x0000068E,
          'Output4',
          'OUT8'
        ),
        'MID_R': (
          'Single 1_7',
          0x03CA,
          0x00005281,
          0x00004189,
          'Output5',
          'OUT7'
        ),
        'TWR': (
          'Single 1_8',
          0x03CD,
          0x00001A17,
          0x000014B9,
          'Output6',
          'OUT4'
        ),
      };

      expect(ProAdau1466GainChannelRegistry.channels.length, 6);
      for (final entry in expected.entries) {
        final channel = ProAdau1466GainChannelRegistry.findByChannel(entry.key);
        expect(channel, isNotNull, reason: entry.key);
        expect(channel!.sigmaCellName, entry.value.$1);
        expect(channel.targetAddress, entry.value.$2);
        expect(channel.testWord, entry.value.$3);
        expect(channel.exportedRestoreWord, entry.value.$4);
        expect(channel.sigmaOutputCell, entry.value.$5);
        expect(channel.plannedPhysicalOutput, entry.value.$6);
      }
    });

    test('every mapped channel pairs its slew address as target plus one', () {
      for (final channel in ProAdau1466GainChannelRegistry.channels) {
        expect(channel.slewAddress, channel.targetAddress + 1,
            reason: channel.channel);
        expect(channel.sameSafeLoadStructureApplies, isTrue);
      }
    });

    test('review plan reuses exact capture-proven SafeLoad packet structure',
        () {
      for (final channel in ProAdau1466GainChannelRegistry.channels) {
        final plan = ProAdau1466GainChannelRegistry.buildRestorePlan(channel);
        expect(plan.stages.length, 3);
        expect(plan.stages[0].setupPacket, [0x40, 0xB2, 0, 0, 1, 1, 0x06, 0]);
        expect(plan.stages[0].bodyPacket, [
          (channel.slewAddress >> 8) & 0xFF,
          channel.slewAddress & 0xFF,
          0x00,
          0x00,
          0x20,
          0x8A,
        ]);
        expect(plan.stages[1].setupPacket, [0x40, 0xB2, 0, 0, 1, 1, 0x06, 0]);
        expect(plan.stages[1].bodyPacket, [
          0x60,
          0x00,
          (channel.exportedRestoreWord >> 24) & 0xFF,
          (channel.exportedRestoreWord >> 16) & 0xFF,
          (channel.exportedRestoreWord >> 8) & 0xFF,
          channel.exportedRestoreWord & 0xFF,
        ]);
        expect(plan.stages[2].setupPacket, [0x40, 0xB2, 0, 0, 1, 1, 0x0E, 0]);
        expect(plan.stages[2].bodyPacket, [
          0x60,
          0x05,
          0x00,
          0x00,
          (channel.targetAddress >> 8) & 0xFF,
          channel.targetAddress & 0xFF,
          0x00,
          0x00,
          0x00,
          0x01,
          0x00,
          0x00,
          0x00,
          0x00,
        ]);
      }
    });

    test('only the six mapped channels enable dedicated diagnostics', () {
      expect(
          ProAdau1466GainChannelRegistry.channels
              .where((channel) => channel.diagnosticWriteEnabled)
              .length,
          6);
      expect(
          ProAdau1466GainChannelRegistry.findByTargetAddress(0x0057), isNull);
      expect(
          ProAdau1466GainChannelRegistry.findByTargetAddress(0x0054), isNull);
      expect(
          ProAdau1466GainChannelRegistry.findByTargetAddress(0xFFFF), isNull);
    });

    test('all six keep physical mapping and VERIFIED state pending', () {
      for (final channel in ProAdau1466GainChannelRegistry.channels) {
        expect(channel.requiresAdditionalSigmaCapture, isFalse);
        expect(channel.restoreValueConfirmedByCapture, isTrue);
        expect(channel.physicalMappingConfirmed, isFalse);
        expect(channel.readyForFutureExecutor, isFalse);
        expect(channel.validationStatus,
            isNot(CandidateValidationStatus.verified));
      }
    });

    test('computed +2 dB words use 8.24 linear math and clamp below unity', () {
      final expected = {
        0x00001076: 0x000014B9,
        0x00001A17: 0x000020D8,
        0x00004189: 0x00005281,
        0x000014B9: 0x00001A17,
      };
      for (final entry in expected.entries) {
        expect(
            ProAdau1466GainChannelRegistry.computeConservativePlus2DbTestWord(
                entry.key),
            entry.value);
      }
      expect(
          ProAdau1466GainChannelRegistry.computeConservativePlus2DbTestWord(
              0x01000000),
          0x00FFFFFF);
    });

    test('Single 1 remains PASS_ACK only and is never automatically VERIFIED',
        () {
      final single1 = ProAdau1466GainChannelRegistry.findByChannel('WFL')!;
      expect(single1.validationStatus, CandidateValidationStatus.passAck);
      expect(
          single1.validationStatus, isNot(CandidateValidationStatus.verified));
      expect(single1.diagnosticWriteEnabled, isTrue);
      expect(single1.physicalMappingConfirmed, isFalse);
      expect(single1.readyForFutureExecutor, isFalse);
    });

    test('registry has no backend or legacy SafeLoad dependency', () {
      final source = File('lib/core/pro_adau1466_gain_channel_registry.dart')
          .readAsStringSync();
      expect(source, isNot(contains('sendPacketsAndReadAck')));
      expect(source, isNot(contains('buildSafeLoadWriteSequence')));
      expect(source, isNot(contains('Adau1466Adapter')));
      expect(source, isNot(contains('Adau1466UsbSpiTransport')));
      expect(source, isNot(contains('ADAU1701')));
      expect(source, isNot(contains('ProUsbiNativeBackend')));
      expect(source, isNot(contains('buildReviewPlan')));
      expect(
          source, isNot(contains('class ProAdau1466GainSafeLoadPlanBuilder')));
    });
  });
}
