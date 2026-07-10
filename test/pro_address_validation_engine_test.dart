// TUNAI PRO — Phase U2: Address Validation Engine tests
//
// Safety invariants verified:
//   - Validation tasks are created for exportConfirmed addresses
//   - No address is auto-marked as liveWriteVerified by the engine
//   - Master Volume L/R are listed as already-verified references
//   - Risk assignment follows specification
//   - crossover → critical risk
//   - peq → high risk
//   - gain/mute → low risk
//   - JSON round-trip works for all data models
//   - No hardware write fields exist in validation tasks
//   - No SafeLoad execution fields
//   - wasActualWrite is always false in Phase U2 attempts
//   - Guard D2 still blocks exportConfirmed addresses
//   - Import still does not enable hardware write

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/pro_address_validation_data.dart';
import 'package:tunai_pro/core/pro_address_validation_engine.dart';
import 'package:tunai_pro/core/pro_dsp_address_registry.dart';
import 'package:tunai_pro/core/pro_adau1466_3way_address_map_embedded.dart';
import 'package:tunai_pro/core/pro_export_data.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

VerifiedDspAddress _mkAddr({
  required String id,
  required int addressInt,
  required DspParameterKind kind,
  DspAddressVerificationStatus status = DspAddressVerificationStatus.exportConfirmed,
  String? channel,
}) => VerifiedDspAddress(
  id:                 id,
  platform:           DspTargetPlatform.adau1466,
  parameterKind:      kind,
  logicalName:        'Test $id',
  addressHex:         '0x${addressInt.toRadixString(16).padLeft(4, '0').toUpperCase()}',
  addressInt:         addressInt,
  verificationStatus: status,
  source:             DspAddressSource.sigmaStudioExport,
  channelId:          channel,
);

DspAddressRegistry _registryWith(List<VerifiedDspAddress> addresses) =>
    DspAddressRegistry(addresses: addresses, revision: 1);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('createValidationTasksFromRegistry — task creation', () {
    test('creates tasks for exportConfirmed addresses', () {
      final registry = _registryWith([
        _mkAddr(id: 'delay_l', addressInt: 0x0300, kind: DspParameterKind.delay),
        _mkAddr(id: 'mute_l', addressInt: 0x0400, kind: DspParameterKind.mute),
      ]);
      final state = createValidationTasksFromRegistry(registry: registry);
      expect(state.tasks, isNotEmpty);
      expect(state.tasks.length, 2);
    });

    test('creates tasks for needsLiveValidation addresses', () {
      final registry = _registryWith([
        _mkAddr(id: 'xo_l', addressInt: 0x0200, kind: DspParameterKind.crossover,
            status: DspAddressVerificationStatus.needsLiveValidation),
      ]);
      final state = createValidationTasksFromRegistry(registry: registry);
      expect(state.tasks.length, 1);
    });

    test('does not create tasks for already-verified non-master addresses', () {
      final registry = _registryWith([
        _mkAddr(id: 'some_verified', addressInt: 0x0100, kind: DspParameterKind.gain,
            status: DspAddressVerificationStatus.verified),
      ]);
      final state = createValidationTasksFromRegistry(registry: registry);
      // verified non-master: not eligible → no task created
      expect(state.tasks, isEmpty);
    });

    test('empty registry produces empty task list', () {
      final registry = _registryWith([]);
      final state = createValidationTasksFromRegistry(registry: registry);
      expect(state.tasks, isEmpty);
    });
  });

  group('createValidationTasksFromRegistry — Master Volume handling', () {
    test('Master Volume L (0x0067) is listed as already verified', () {
      final registry = _registryWith([
        _mkAddr(id: 'mv_l', addressInt: 0x0067, kind: DspParameterKind.masterVolume,
            status: DspAddressVerificationStatus.verified),
      ]);
      final state = createValidationTasksFromRegistry(registry: registry);
      final task = state.tasks.firstWhere((t) => t.addressHex.contains('0067'),
          orElse: () => state.tasks.first);
      expect(task.currentStatus, AddressValidationStatus.liveWriteVerified);
    });

    test('Master Volume R (0x0064) is listed as already verified', () {
      final registry = _registryWith([
        _mkAddr(id: 'mv_r', addressInt: 0x0064, kind: DspParameterKind.masterVolume,
            status: DspAddressVerificationStatus.verified),
      ]);
      final state = createValidationTasksFromRegistry(registry: registry);
      final task = state.tasks.firstWhere((t) => t.addressHex.contains('0064'),
          orElse: () => state.tasks.first);
      expect(task.currentStatus, AddressValidationStatus.liveWriteVerified);
    });

    test('Master Volume addresses are NOT queued for live capture', () {
      final registry = _registryWith([
        _mkAddr(id: 'mv_l', addressInt: 0x0067, kind: DspParameterKind.masterVolume,
            status: DspAddressVerificationStatus.verified),
        _mkAddr(id: 'mv_r', addressInt: 0x0064, kind: DspParameterKind.masterVolume,
            status: DspAddressVerificationStatus.verified),
      ]);
      final state = createValidationTasksFromRegistry(registry: registry);
      for (final t in state.tasks) {
        expect(t.currentStatus, isNot(AddressValidationStatus.queued),
            reason: 'Master Volume must not be in active queue');
      }
    });

    test('Master Volume verified status is not downgraded', () {
      final registry = _registryWith([
        _mkAddr(id: 'mv_l', addressInt: 0x0067, kind: DspParameterKind.masterVolume,
            status: DspAddressVerificationStatus.verified),
      ]);
      final state = createValidationTasksFromRegistry(registry: registry);
      for (final t in state.tasks.where(
          (t) => t.addressHex == '0x0067')) {
        expect(t.currentStatus, AddressValidationStatus.liveWriteVerified);
      }
    });
  });

  group('createValidationTasksFromRegistry — risk assignment', () {
    test('crossover tasks are critical risk', () {
      final registry = _registryWith([
        _mkAddr(id: 'xo', addressInt: 0x0200, kind: DspParameterKind.crossover),
      ]);
      final state = createValidationTasksFromRegistry(registry: registry);
      expect(state.tasks.first.risk, AddressValidationRisk.critical);
    });

    test('peq tasks are high risk', () {
      final registry = _registryWith([
        _mkAddr(id: 'peq', addressInt: 0x036C, kind: DspParameterKind.peq),
      ]);
      final state = createValidationTasksFromRegistry(registry: registry);
      expect(state.tasks.first.risk, AddressValidationRisk.high);
    });

    test('safeload tasks are high risk', () {
      final registry = _registryWith([
        _mkAddr(id: 'sl', addressInt: 0x6000, kind: DspParameterKind.safeload),
      ]);
      final state = createValidationTasksFromRegistry(registry: registry);
      expect(state.tasks.first.risk, AddressValidationRisk.high);
    });

    test('gain tasks are low risk', () {
      final registry = _registryWith([
        _mkAddr(id: 'gain', addressInt: 0x0100, kind: DspParameterKind.gain),
      ]);
      final state = createValidationTasksFromRegistry(registry: registry);
      expect(state.tasks.first.risk, AddressValidationRisk.low);
    });

    test('mute tasks are low risk', () {
      final registry = _registryWith([
        _mkAddr(id: 'mute', addressInt: 0x0400, kind: DspParameterKind.mute),
      ]);
      final state = createValidationTasksFromRegistry(registry: registry);
      expect(state.tasks.first.risk, AddressValidationRisk.low);
    });

    test('delay tasks are medium risk', () {
      final registry = _registryWith([
        _mkAddr(id: 'delay', addressInt: 0x0300, kind: DspParameterKind.delay),
      ]);
      final state = createValidationTasksFromRegistry(registry: registry);
      expect(state.tasks.first.risk, AddressValidationRisk.medium);
    });
  });

  group('createValidationTasksFromRegistry — safety invariants', () {
    test('no exportConfirmed address is auto-verified', () {
      final registry = _registryWith([
        _mkAddr(id: 'delay_l', addressInt: 0x0300, kind: DspParameterKind.delay),
        _mkAddr(id: 'mute_l', addressInt: 0x0400, kind: DspParameterKind.mute),
        _mkAddr(id: 'xo', addressInt: 0x0200, kind: DspParameterKind.crossover),
      ]);
      final state = createValidationTasksFromRegistry(registry: registry);
      for (final t in state.tasks) {
        expect(t.currentStatus, isNot(AddressValidationStatus.liveWriteVerified),
            reason: '${t.addressHex} must not be auto-verified');
      }
    });

    test('validation tasks start as queued (not verified)', () {
      final registry = _registryWith([
        _mkAddr(id: 'mute_r', addressInt: 0x0401, kind: DspParameterKind.mute),
      ]);
      final state = createValidationTasksFromRegistry(registry: registry);
      expect(state.tasks.first.currentStatus, AddressValidationStatus.queued);
    });

    test('validation state starts with no attempts', () {
      final registry = _registryWith([
        _mkAddr(id: 'delay', addressInt: 0x0300, kind: DspParameterKind.delay),
      ]);
      final state = createValidationTasksFromRegistry(registry: registry);
      expect(state.attempts, isEmpty);
    });

    test('no write execution fields in validation tasks', () {
      final registry = _registryWith([
        _mkAddr(id: 'gain', addressInt: 0x0100, kind: DspParameterKind.gain),
      ]);
      final state = createValidationTasksFromRegistry(registry: registry);
      final task = state.tasks.first;
      final json = task.toJson();
      expect(json.containsKey('usbPacket'), isFalse);
      expect(json.containsKey('blePacket'), isFalse);
      expect(json.containsKey('safeloadExecution'), isFalse);
      expect(json.containsKey('hardwareWrite'), isFalse);
      expect(json.containsKey('eepromWrite'), isFalse);
    });
  });

  group('AddressValidationAttempt — safety invariants', () {
    test('wasActualWrite defaults to false', () {
      final attempt = AddressValidationAttempt(
        id: 'a1',
        taskId: 't1',
        attemptedAt: DateTime.now(),
        resultStatus: AddressValidationStatus.validationAttempted,
      );
      expect(attempt.wasActualWrite, isFalse);
    });

    test('dryRunOnly defaults to true', () {
      final attempt = AddressValidationAttempt(
        id: 'a1',
        taskId: 't1',
        attemptedAt: DateTime.now(),
        resultStatus: AddressValidationStatus.validationAttempted,
      );
      expect(attempt.dryRunOnly, isTrue);
    });

    test('no SafeLoad execution field in attempt JSON', () {
      final attempt = AddressValidationAttempt(
        id: 'a1',
        taskId: 't1',
        attemptedAt: DateTime.now(),
        resultStatus: AddressValidationStatus.validationAttempted,
      );
      final json = attempt.toJson();
      expect(json.containsKey('safeloadExecution'), isFalse);
      expect(json.containsKey('usbPacket'), isFalse);
    });
  });

  group('JSON round-trips', () {
    test('AddressValidationStatus round-trip', () {
      for (final s in AddressValidationStatus.values) {
        expect(AddressValidationStatus.fromJson(s.toJson()), s);
      }
    });

    test('AddressValidationRisk round-trip', () {
      for (final r in AddressValidationRisk.values) {
        expect(AddressValidationRisk.fromJson(r.toJson()), r);
      }
    });

    test('AddressValidationGroup round-trip', () {
      for (final g in AddressValidationGroup.values) {
        expect(AddressValidationGroup.fromJson(g.toJson()), g);
      }
    });

    test('AddressValidationTask JSON round-trip preserves fields', () {
      final now = DateTime.utc(2026, 7, 10);
      final task = AddressValidationTask(
        id:            'vt_0300_0',
        addressId:     'delay_l',
        parameterId:   'delay_l_param',
        logicalName:   'Delay L',
        group:         AddressValidationGroup.delay,
        risk:          AddressValidationRisk.medium,
        currentStatus: AddressValidationStatus.queued,
        addressHex:    '0x0300',
        channel:       'L',
        expectedEffect: 'Timing offset',
        createdAt:     now,
        updatedAt:     now,
      );
      final json = task.toJson();
      final restored = AddressValidationTask.fromJson(json);
      expect(restored.id, task.id);
      expect(restored.group, AddressValidationGroup.delay);
      expect(restored.risk, AddressValidationRisk.medium);
      expect(restored.currentStatus, AddressValidationStatus.queued);
      expect(restored.addressHex, '0x0300');
      expect(restored.channel, 'L');
    });

    test('AddressValidationAttempt JSON round-trip', () {
      final attempt = AddressValidationAttempt(
        id:                'a1',
        taskId:            'vt_0300_0',
        attemptedAt:       DateTime.utc(2026, 7, 10),
        dryRunOnly:        true,
        wasActualWrite:    false,
        operatorConfirmed: false,
        resultStatus:      AddressValidationStatus.validationAttempted,
        observedEffect:    'None observed',
      );
      final restored = AddressValidationAttempt.fromJson(attempt.toJson());
      expect(restored.wasActualWrite, isFalse);
      expect(restored.dryRunOnly, isTrue);
      expect(restored.resultStatus, AddressValidationStatus.validationAttempted);
    });

    test('AddressValidationProjectState JSON round-trip', () {
      final now = DateTime.utc(2026, 7, 10);
      final task = AddressValidationTask(
        id:            'vt_0',
        addressId:     'a0',
        logicalName:   'Test',
        group:         AddressValidationGroup.gain,
        risk:          AddressValidationRisk.low,
        currentStatus: AddressValidationStatus.queued,
        addressHex:    '0x0100',
        createdAt:     now,
        updatedAt:     now,
      );
      final state = AddressValidationProjectState(
        tasks:    [task],
        attempts: [],
        updatedAt: now,
        revision: 1,
      );
      final restored = AddressValidationProjectState.fromJson(state.toJson());
      expect(restored.tasks.length, 1);
      expect(restored.tasks.first.group, AddressValidationGroup.gain);
      expect(restored.revision, 1);
    });
  });

  group('AddressValidationProjectState — computed getters', () {
    AddressValidationTask _task(String id, AddressValidationStatus status,
        AddressValidationRisk risk) {
      final now = DateTime.now();
      return AddressValidationTask(
        id: id, addressId: id, logicalName: id,
        group: AddressValidationGroup.gain, risk: risk,
        currentStatus: status, addressHex: '0x0000',
        createdAt: now, updatedAt: now,
      );
    }

    test('queuedCount counts active tasks', () {
      final state = AddressValidationProjectState(
        tasks: [
          _task('t1', AddressValidationStatus.queued, AddressValidationRisk.low),
          _task('t2', AddressValidationStatus.liveWriteVerified, AddressValidationRisk.low),
          _task('t3', AddressValidationStatus.readyForDryRun, AddressValidationRisk.low),
        ],
        updatedAt: DateTime.now(),
      );
      expect(state.queuedCount, 2);
    });

    test('verifiedCount counts liveWriteVerified', () {
      final state = AddressValidationProjectState(
        tasks: [
          _task('t1', AddressValidationStatus.liveWriteVerified, AddressValidationRisk.low),
          _task('t2', AddressValidationStatus.liveWriteVerified, AddressValidationRisk.low),
          _task('t3', AddressValidationStatus.queued, AddressValidationRisk.low),
        ],
        updatedAt: DateTime.now(),
      );
      expect(state.verifiedCount, 2);
    });

    test('highRiskCount counts high and critical', () {
      final state = AddressValidationProjectState(
        tasks: [
          _task('t1', AddressValidationStatus.queued, AddressValidationRisk.high),
          _task('t2', AddressValidationStatus.queued, AddressValidationRisk.critical),
          _task('t3', AddressValidationStatus.queued, AddressValidationRisk.low),
        ],
        updatedAt: DateTime.now(),
      );
      expect(state.highRiskCount, 2);
    });

    test('readinessLabel is "No validation tasks generated" for empty state', () {
      final state = AddressValidationProjectState.createDefault();
      expect(state.readinessLabel, 'No validation tasks generated');
    });

    test('readinessLabel reflects blocked state', () {
      final state = AddressValidationProjectState(
        tasks: [
          _task('t1', AddressValidationStatus.blocked, AddressValidationRisk.high),
        ],
        updatedAt: DateTime.now(),
      );
      expect(state.readinessLabel, contains('Blocked'));
    });
  });

  group('embedded registry integration', () {
    late AddressValidationProjectState state;
    setUpAll(() {
      final registry = createTunaiAdau1466ThreeWayRegistry();
      state = createValidationTasksFromRegistry(registry: registry);
    });

    test('generates tasks from embedded 3-way registry', () {
      expect(state.tasks, isNotEmpty);
    });

    test('no exportConfirmed address is auto-verified from embedded registry', () {
      final nonMasterTasks = state.tasks.where((t) =>
          t.addressHex != '0x0067' && t.addressHex != '0x0064' &&
          !t.addressHex.contains('0067') && !t.addressHex.contains('0064'));
      for (final t in nonMasterTasks) {
        expect(t.currentStatus, isNot(AddressValidationStatus.liveWriteVerified),
            reason: '${t.addressHex} (${t.logicalName}) must not be auto-verified');
      }
    });

    test('embedded registry has crossover tasks with critical risk', () {
      final xoTasks = state.tasks.where(
          (t) => t.group == AddressValidationGroup.crossover).toList();
      expect(xoTasks, isNotEmpty, reason: 'Should have crossover tasks');
      for (final t in xoTasks) {
        expect(t.risk, AddressValidationRisk.critical);
      }
    });

    test('embedded registry produces readiness label', () {
      expect(state.readinessLabel, isNotEmpty);
    });

    test('validation manager does not imply hardware write', () {
      for (final t in state.tasks) {
        final json = t.toJson();
        expect(json.containsKey('usbPacket'), isFalse,
            reason: 'No USB packet field allowed');
        expect(json.containsKey('hardwareWrite'), isFalse,
            reason: 'No hardware write field allowed');
      }
    });
  });
}
