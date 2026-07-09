// TUNAI PRO — Phase Q: Hardware Connection Data tests

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_hardware_connection_data.dart';

void main() {
  group('HardwareProjectState — default', () {
    late HardwareProjectState state;
    setUp(() => state = HardwareProjectState.createDefault());

    test('default transport is simulationOnly', () {
      expect(state.connectionState.transportType,
          HardwareTransportType.simulationOnly);
    });

    test('default connection status is simulated', () {
      expect(state.connectionState.connectionStatus,
          HardwareConnectionStatus.simulated);
    });

    test('default target device is simulation', () {
      expect(state.connectionState.targetDevice, HardwareTargetDevice.simulation);
    });

    test('isHardwareWriteEnabled is always false', () {
      expect(state.isHardwareWriteEnabled, isFalse);
    });

    test('no write plans by default', () {
      expect(state.planCount, 0);
      expect(state.activePlan, isNull);
    });

    test('readiness label when no plan', () {
      expect(state.readinessLabel, 'No export package');
    });

    test('blockedCheckCount defaults to 0 without plan', () {
      expect(state.blockedCheckCount, 0);
    });

    test('warningCheckCount defaults to 0 without plan', () {
      expect(state.warningCheckCount, 0);
    });

    test('JSON round-trip preserves defaults', () {
      final restored = HardwareProjectState.fromJson(state.toJson());
      expect(restored.connectionState.transportType,
          HardwareTransportType.simulationOnly);
      expect(restored.connectionState.connectionStatus,
          HardwareConnectionStatus.simulated);
      expect(restored.isHardwareWriteEnabled, isFalse);
      expect(restored.planCount, 0);
    });
  });

  group('HardwareConnectionState', () {
    test('copyWith updates transport type', () {
      const s = HardwareConnectionState();
      final updated = s.copyWith(transportType: HardwareTransportType.usbi);
      expect(updated.transportType, HardwareTransportType.usbi);
      expect(s.transportType, HardwareTransportType.simulationOnly);
    });

    test('JSON round-trip', () {
      const s = HardwareConnectionState(
        transportType: HardwareTransportType.usbi,
        connectionStatus: HardwareConnectionStatus.disconnected,
        targetDevice: HardwareTargetDevice.adau1466,
      );
      final restored = HardwareConnectionState.fromJson(s.toJson());
      expect(restored.transportType, HardwareTransportType.usbi);
      expect(restored.connectionStatus, HardwareConnectionStatus.disconnected);
      expect(restored.targetDevice, HardwareTargetDevice.adau1466);
    });

    test('JSON contains no hardware packet fields', () {
      const s = HardwareConnectionState(
        transportType: HardwareTransportType.usbi,
      );
      final json = s.toJson().toString();
      expect(json.toLowerCase(), isNot(contains('safeload')));
      expect(json.toLowerCase(), isNot(contains('eeprom')));
      expect(json.toLowerCase(), isNot(contains('selfboot')));
      expect(json.toLowerCase(), isNot(contains('packet')));
    });
  });

  group('HardwareTransportType enum', () {
    test('toJson/fromJson round-trip', () {
      for (final t in HardwareTransportType.values) {
        expect(HardwareTransportType.fromJson(t.toJson()), t);
      }
    });
  });

  group('HardwareConnectionStatus enum', () {
    test('toJson/fromJson round-trip', () {
      for (final s in HardwareConnectionStatus.values) {
        expect(HardwareConnectionStatus.fromJson(s.toJson()), s);
      }
    });
  });

  group('HardwareTargetDevice enum', () {
    test('toJson/fromJson round-trip', () {
      for (final d in HardwareTargetDevice.values) {
        expect(HardwareTargetDevice.fromJson(d.toJson()), d);
      }
    });
  });

  group('HardwareWriteMode enum', () {
    test('toJson/fromJson round-trip', () {
      for (final m in HardwareWriteMode.values) {
        expect(HardwareWriteMode.fromJson(m.toJson()), m);
      }
    });
  });

  group('HardwareGuardStatus enum', () {
    test('toJson/fromJson round-trip', () {
      for (final s in HardwareGuardStatus.values) {
        expect(HardwareGuardStatus.fromJson(s.toJson()), s);
      }
    });
  });

  group('Readiness labels', () {
    test('hardware write disabled label', () {
      expect(HardwareProjectState.createDefault().isHardwareWriteEnabled, isFalse);
    });
  });
}
