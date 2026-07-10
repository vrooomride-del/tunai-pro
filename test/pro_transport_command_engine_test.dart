// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_transport_command_data.dart';
import 'package:tunai_pro/core/pro_transport_command_engine.dart';
import 'package:tunai_pro/core/pro_hardware_transport.dart';
import 'package:tunai_pro/core/pro_adau1466_3way_address_map_embedded.dart';
import 'package:tunai_pro/core/pro_dsp_address_registry.dart';

void main() {
  late DspAddressRegistry registry;

  setUp(() => registry = createTunaiAdau1466ThreeWayRegistry());

  // ── Master Volume address assignment ────────────────────────────────────────
  group('Master Volume address assignment', () {
    test('creates L command at 0x0067', () {
      final cmd = createMasterVolumeCommand(
        backend:      HardwareTransportBackend.simulation,
        side:         'L',
        linearValue:  1.0,
        registry:     registry,
      );
      expect(cmd.addressInt, 0x0067);
      expect(cmd.addressHex.toUpperCase(), contains('0067'));
      expect(cmd.parameterId, contains('master_volume_l'));
    });

    test('creates R command at 0x0064', () {
      final cmd = createMasterVolumeCommand(
        backend:      HardwareTransportBackend.simulation,
        side:         'R',
        linearValue:  1.0,
        registry:     registry,
      );
      expect(cmd.addressInt, 0x0064);
      expect(cmd.addressHex.toUpperCase(), contains('0064'));
      expect(cmd.parameterId, contains('master_volume_r'));
    });
  });

  // ── 8.24 fixed-point encoding ───────────────────────────────────────────────
  group('8.24 fixed-point encoding', () {
    test('1.0 encodes to 0x01000000', () {
      final cmd = createMasterVolumeCommand(
        backend:     HardwareTransportBackend.simulation,
        side:        'L',
        linearValue: 1.0,
        registry:    registry,
      );
      expect(cmd.status, TransportCommandStatus.dryRunReady);
      expect(cmd.fixedPointHex?.toUpperCase(), '0X01000000');
      expect(cmd.fixedPointInt, 0x01000000);
    });

    test('0.5 encodes to 0x00800000', () {
      final cmd = createMasterVolumeCommand(
        backend:     HardwareTransportBackend.simulation,
        side:        'L',
        linearValue: 0.5,
        registry:    registry,
      );
      expect(cmd.fixedPointHex?.toUpperCase(), '0X00800000');
      expect(cmd.fixedPointInt, 0x00800000);
    });

    test('0.0 encodes to 0x00000000', () {
      final cmd = createMasterVolumeCommand(
        backend:     HardwareTransportBackend.simulation,
        side:        'L',
        linearValue: 0.0,
        registry:    registry,
      );
      expect(cmd.fixedPointHex?.toUpperCase(), '0X00000000');
      expect(cmd.fixedPointInt, 0x00000000);
    });
  });

  // ── Value validation ─────────────────────────────────────────────────────────
  group('value validation', () {
    test('rejects value above 1.0', () {
      final cmd = createMasterVolumeCommand(
        backend:     HardwareTransportBackend.simulation,
        side:        'L',
        linearValue: 1.5,
        registry:    registry,
      );
      expect(cmd.status, TransportCommandStatus.blocked);
      expect(cmd.blockedReason, isNotNull);
      expect(cmd.blockedReason, contains('1.5'));
    });

    test('rejects negative value', () {
      final cmd = createMasterVolumeCommand(
        backend:     HardwareTransportBackend.simulation,
        side:        'L',
        linearValue: -0.1,
        registry:    registry,
      );
      expect(cmd.status, TransportCommandStatus.blocked);
      expect(cmd.blockedReason, isNotNull);
    });

    test('accepts value at boundary 0.0', () {
      final cmd = createMasterVolumeCommand(
        backend:     HardwareTransportBackend.simulation,
        side:        'L',
        linearValue: 0.0,
        registry:    registry,
      );
      expect(cmd.status, TransportCommandStatus.dryRunReady);
    });

    test('accepts value at boundary 1.0', () {
      final cmd = createMasterVolumeCommand(
        backend:     HardwareTransportBackend.simulation,
        side:        'L',
        linearValue: 1.0,
        registry:    registry,
      );
      expect(cmd.status, TransportCommandStatus.dryRunReady);
    });

    test('rejects invalid side parameter', () {
      final cmd = createMasterVolumeCommand(
        backend:     HardwareTransportBackend.simulation,
        side:        'X',
        linearValue: 0.5,
        registry:    registry,
      );
      expect(cmd.status, TransportCommandStatus.blocked);
      expect(cmd.blockedReason, contains('"X"'));
    });
  });

  // ── Blocked parameter scope ──────────────────────────────────────────────────
  group('blocked unsupported parameters', () {
    test('blocks PEQ parameter', () {
      final cmd = createBlockedCommandForUnsupportedParameter(
        backend:     HardwareTransportBackend.simulation,
        parameterId: 'peq_b0_1',
        logicalName: 'PEQ Band 1 B0',
        addressHex:  '0x036C',
        addressInt:  0x036C,
      );
      expect(cmd.status, TransportCommandStatus.blocked);
      expect(cmd.commandType, TransportCommandType.unsupported);
      expect(cmd.blockedReason, contains('Master Volume L/R'));
      expect(cmd.blockedReason, contains('Phase T3'));
    });

    test('blocks XO parameter', () {
      final cmd = createBlockedCommandForUnsupportedParameter(
        backend:     HardwareTransportBackend.simulation,
        parameterId: 'xo_hpf_coeff',
        logicalName: 'XO HPF Coefficient',
        addressHex:  '0x0100',
        addressInt:  0x0100,
      );
      expect(cmd.status, TransportCommandStatus.blocked);
      expect(cmd.blockedReason, contains('Master Volume L/R'));
    });

    test('blocks Gain parameter', () {
      final cmd = createBlockedCommandForUnsupportedParameter(
        backend:     HardwareTransportBackend.simulation,
        parameterId: 'gain_ch1',
        logicalName: 'Channel 1 Gain',
        addressHex:  '0x0200',
        addressInt:  0x0200,
      );
      expect(cmd.status, TransportCommandStatus.blocked);
    });

    test('blocks SafeLoad parameter', () {
      final cmd = createBlockedCommandForUnsupportedParameter(
        backend:     HardwareTransportBackend.simulation,
        parameterId: 'safeload_data0',
        logicalName: 'SafeLoad Data 0',
        addressHex:  '0x6000',
        addressInt:  0x6000,
      );
      expect(cmd.status, TransportCommandStatus.blocked);
      expect(cmd.actualWriteAllowed, isFalse);
    });

    test('blocked parameter note mentions scope', () {
      final cmd = createBlockedCommandForUnsupportedParameter(
        backend:     HardwareTransportBackend.simulation,
        parameterId: 'mute_ch1',
        logicalName: 'Mute Channel 1',
        addressHex:  '0x0050',
        addressInt:  0x0050,
      );
      expect(cmd.notes, isNotNull);
      expect(cmd.notes!.toLowerCase(), anyOf(
        contains('peq'), contains('blocked'), contains('validation')));
    });
  });

  // ── Safety locks: isExecutableNow always false ───────────────────────────────
  group('isExecutableNow always false', () {
    test('dryRunReady command is not executable', () {
      final cmd = createMasterVolumeCommand(
        backend:     HardwareTransportBackend.simulation,
        side:        'L',
        linearValue: 0.8,
        registry:    registry,
      );
      expect(cmd.isExecutableNow, isFalse);
    });

    test('blocked command is not executable', () {
      final cmd = createBlockedCommandForUnsupportedParameter(
        backend:     HardwareTransportBackend.simulation,
        parameterId: 'x', logicalName: 'X',
        addressHex:  '0x0000', addressInt: 0,
      );
      expect(cmd.isExecutableNow, isFalse);
    });

    for (final side in ['L', 'R']) {
      for (final value in [0.0, 0.5, 1.0]) {
        test('isExecutableNow=false for side=$side value=$value', () {
          final cmd = createMasterVolumeCommand(
            backend:     HardwareTransportBackend.simulation,
            side:        side,
            linearValue: value,
            registry:    registry,
          );
          expect(cmd.isExecutableNow, isFalse);
        });
      }
    }
  });

  // ── Safety locks: actualWriteAllowed always false ────────────────────────────
  group('actualWriteAllowed always false', () {
    test('dryRunReady command: actualWriteAllowed false', () {
      final cmd = createMasterVolumeCommand(
        backend:     HardwareTransportBackend.simulation,
        side:        'L',
        linearValue: 0.8,
        registry:    registry,
      );
      expect(cmd.actualWriteAllowed, isFalse);
    });

    test('blocked command: actualWriteAllowed false', () {
      final cmd = createBlockedCommandForUnsupportedParameter(
        backend:     HardwareTransportBackend.simulation,
        parameterId: 'x', logicalName: 'X',
        addressHex:  '0x0000', addressInt: 0,
      );
      expect(cmd.actualWriteAllowed, isFalse);
    });

    for (final backend in HardwareTransportBackend.values) {
      test('actualWriteAllowed=false for backend=$backend', () {
        final cmd = createMasterVolumeCommand(
          backend:     backend,
          side:        'L',
          linearValue: 0.5,
          registry:    registry,
        );
        expect(cmd.actualWriteAllowed, isFalse);
      });
    }
  });

  // ── Transport selection does not enable execution ────────────────────────────
  group('transport selection does not enable execution', () {
    for (final backend in HardwareTransportBackend.values) {
      test('backend=$backend does not enable execute', () {
        final cmd = createMasterVolumeCommand(
          backend:     backend,
          side:        'R',
          linearValue: 0.5,
          registry:    registry,
        );
        expect(cmd.isExecutableNow, isFalse);
        expect(cmd.actualWriteAllowed, isFalse);
      });
    }
  });

  // ── isDryRunOnly ─────────────────────────────────────────────────────────────
  group('isDryRunOnly always true', () {
    test('dryRunReady is dry-run only', () {
      final cmd = createMasterVolumeCommand(
        backend:     HardwareTransportBackend.simulation,
        side:        'L',
        linearValue: 0.8,
        registry:    registry,
      );
      expect(cmd.isDryRunOnly, isTrue);
    });

    test('blocked command is dry-run only', () {
      final cmd = createBlockedCommandForUnsupportedParameter(
        backend:     HardwareTransportBackend.simulation,
        parameterId: 'x', logicalName: 'X',
        addressHex:  '0x0000', addressInt: 0,
      );
      expect(cmd.isDryRunOnly, isTrue);
    });
  });

  // ── isMasterVolumeCommand ────────────────────────────────────────────────────
  group('isMasterVolumeCommand', () {
    test('L command at 0x0067 is master volume', () {
      final cmd = createMasterVolumeCommand(
        backend:     HardwareTransportBackend.simulation,
        side:        'L',
        linearValue: 0.5,
        registry:    registry,
      );
      expect(cmd.isMasterVolumeCommand, isTrue);
    });

    test('R command at 0x0064 is master volume', () {
      final cmd = createMasterVolumeCommand(
        backend:     HardwareTransportBackend.simulation,
        side:        'R',
        linearValue: 0.5,
        registry:    registry,
      );
      expect(cmd.isMasterVolumeCommand, isTrue);
    });

    test('blocked PEQ command is NOT master volume', () {
      final cmd = createBlockedCommandForUnsupportedParameter(
        backend:     HardwareTransportBackend.simulation,
        parameterId: 'peq_b0_1', logicalName: 'PEQ',
        addressHex:  '0x036C', addressInt: 0x036C,
      );
      expect(cmd.isMasterVolumeCommand, isFalse);
    });
  });

  // ── JSON round-trip ──────────────────────────────────────────────────────────
  group('JSON round-trip', () {
    test('dryRunReady command round-trips correctly', () {
      final cmd = createMasterVolumeCommand(
        backend:     HardwareTransportBackend.simulation,
        side:        'L',
        linearValue: 0.75,
        registry:    registry,
      );
      final json    = cmd.toJson();
      final restored = TransportCommandEnvelope.fromJson(json);
      expect(restored.addressInt,      cmd.addressInt);
      expect(restored.status,          cmd.status);
      expect(restored.valueFloat,      closeTo(cmd.valueFloat!, 0.0001));
      expect(restored.fixedPointHex,   cmd.fixedPointHex);
      expect(restored.fixedPointInt,   cmd.fixedPointInt);
      expect(restored.actualWriteAllowed, isFalse);
      expect(restored.isExecutableNow,    isFalse);
    });

    test('blocked command round-trips correctly', () {
      final cmd = createBlockedCommandForUnsupportedParameter(
        backend:     HardwareTransportBackend.bleMacos,
        parameterId: 'gain_ch1', logicalName: 'Gain CH1',
        addressHex:  '0x0200', addressInt: 0x0200,
      );
      final json     = cmd.toJson();
      final restored = TransportCommandEnvelope.fromJson(json);
      expect(restored.status,              TransportCommandStatus.blocked);
      expect(restored.actualWriteAllowed,  isFalse);
      expect(restored.blockedReason,       isNotNull);
    });

    test('toJson does not contain packet bytes', () {
      final cmd = createMasterVolumeCommand(
        backend:     HardwareTransportBackend.bleMacos,
        side:        'L',
        linearValue: 0.5,
        registry:    registry,
      );
      final json = cmd.toJson().toString().toLowerCase();
      expect(json, isNot(contains('blepacket')));
      expect(json, isNot(contains('usbpacket')));
      expect(json, isNot(contains('icp5packet')));
      expect(json, isNot(contains('rawbytes')));
      expect(json, isNot(contains('controltransfer')));
    });

    test('actualWriteAllowed always serialises as false', () {
      for (final side in ['L', 'R']) {
        final cmd = createMasterVolumeCommand(
          backend:     HardwareTransportBackend.simulation,
          side:        side,
          linearValue: 0.8,
          registry:    registry,
        );
        expect(cmd.toJson()['actualWriteAllowed'], isFalse);
        expect(cmd.toJson()['isExecutableNow'],    isFalse);
        expect(cmd.toJson()['isDryRunOnly'],        isTrue);
      }
    });
  });

  // ── Enum round-trips ─────────────────────────────────────────────────────────
  group('enum round-trips', () {
    test('TransportCommandType round-trip', () {
      for (final t in TransportCommandType.values) {
        expect(TransportCommandType.fromJson(t.toJson()), t);
      }
    });

    test('TransportCommandStatus round-trip', () {
      for (final s in TransportCommandStatus.values) {
        expect(TransportCommandStatus.fromJson(s.toJson()), s);
      }
    });

    test('TransportWriteMode round-trip', () {
      for (final m in TransportWriteMode.values) {
        expect(TransportWriteMode.fromJson(m.toJson()), m);
      }
    });
  });

  // ── No USB/BLE/ICP5 packet bytes produced ────────────────────────────────────
  group('no packet bytes produced', () {
    test('dryRunReady command has no raw packet bytes', () {
      final cmd = createMasterVolumeCommand(
        backend:     HardwareTransportBackend.bleMacos,
        side:        'L',
        linearValue: 1.0,
        registry:    registry,
      );
      final json = cmd.toJson();
      expect(json.containsKey('rawBytes'),         isFalse);
      expect(json.containsKey('blePacket'),         isFalse);
      expect(json.containsKey('usbPacket'),         isFalse);
      expect(json.containsKey('icp5Packet'),        isFalse);
      expect(json.containsKey('controlTransfer'),   isFalse);
    });

    test('blocked command has no raw packet bytes', () {
      final cmd = createBlockedCommandForUnsupportedParameter(
        backend:     HardwareTransportBackend.icp5,
        parameterId: 'peq_b0_1', logicalName: 'PEQ',
        addressHex:  '0x036C', addressInt: 0x036C,
      );
      final json = cmd.toJson();
      expect(json.containsKey('rawBytes'),   isFalse);
      expect(json.containsKey('blePacket'),  isFalse);
      expect(json.containsKey('usbPacket'),  isFalse);
      expect(json.containsKey('icp5Packet'), isFalse);
    });
  });

  // ── isMasterVolumeAddress helper ─────────────────────────────────────────────
  group('isMasterVolumeAddress helper', () {
    test('0x0067 is master volume', () =>
        expect(isMasterVolumeAddress(0x0067), isTrue));
    test('0x0064 is master volume', () =>
        expect(isMasterVolumeAddress(0x0064), isTrue));
    test('0x036C is not master volume', () =>
        expect(isMasterVolumeAddress(0x036C), isFalse));
    test('0x6000 is not master volume', () =>
        expect(isMasterVolumeAddress(0x6000), isFalse));
  });

  // ── Safety: blocked parameters explicitly mention phase ───────────────────────
  group('safety messaging', () {
    test('blocked reason mentions Phase T3', () {
      final cmd = createBlockedCommandForUnsupportedParameter(
        backend:     HardwareTransportBackend.simulation,
        parameterId: 'delay_ch1', logicalName: 'Delay CH1',
        addressHex:  '0x0300', addressInt: 0x0300,
      );
      expect(cmd.blockedReason?.toLowerCase(), contains('phase t3'));
    });

    test('safetyNote in dryRunReady JSON', () {
      final cmd = createMasterVolumeCommand(
        backend:     HardwareTransportBackend.simulation,
        side:        'L',
        linearValue: 0.5,
        registry:    registry,
      );
      final json = cmd.toJson();
      expect(json.containsKey('safetyNote'), isTrue);
      expect((json['safetyNote'] as String).toLowerCase(),
          contains('no write'));
    });
  });
}
