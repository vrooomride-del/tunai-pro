import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/orchestrator/pro_acoustic_intent.dart';
import 'package:tunai_pro/core/orchestrator/pro_explanation.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_context.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_plan.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_result.dart';
import 'package:tunai_pro/core/orchestrator/pro_orchestrator_types.dart';

/// A JSON round-trip through real encode/decode, so nothing relies on the
/// in-memory map identity.
Map<String, dynamic> _cycle(Map<String, dynamic> j) =>
    jsonDecode(jsonEncode(j)) as Map<String, dynamic>;

ProAcousticIntent _intent() => const ProAcousticIntent(
      userGoal: 'tighter low end without losing warmth',
      perceivedProblem: 'boomy near the wall',
      systemScope: 'full_system',
      tuningPriority: ProTuningPriority.roomAdaptation,
      allowedChangeAreas: [ProToneArea.lowEnd],
      protectedAreas: [ProToneArea.highEnd],
      listeningContext: 'near-field desk, small room',
      explanationLevel: ProExplanationLevel.intermediate,
      freeTextContext: 'note only',
    );

ProOrchestratorPlan _plan() => const ProOrchestratorPlan(
      planId: 'plan1',
      intentRef: 'intent1',
      contextRef: 'ctx1',
      steps: [
        ProOrchestratorStep(
          stepId: 's1',
          toolId: ProOrchestratorToolId.measurementAnalyze,
          objective: 'read the room',
          inputRefs: ['meas1'],
          outputRef: 'out1',
          requiresUserConfirmation: false,
        ),
        ProOrchestratorStep(
          stepId: 's2',
          toolId: ProOrchestratorToolId.peqOptimize,
          objective: 'draft a candidate',
          inputRefs: ['out1'],
          outputRef: 'out2',
          requiresUserConfirmation: true,
        ),
      ],
      summary: 'analyze then optimize',
      completionCriteria: 'a candidate exists',
    );

ProOrchestratorContext _context() => const ProOrchestratorContext(
      projectId: 'p1',
      measurementRefs: ['meas1'],
      connectionState: ProConnectionState.readbackVerified,
      readbackEvidence: 'ch0_band0_verified',
      candidateRefs: ['cand1'],
    );

ProOrchestratorResult _result() => const ProOrchestratorResult(
      resultId: 'r1',
      toolId: ProOrchestratorToolId.peqOptimize,
      inputRefs: ['meas1'],
      outputRef: 'out2',
      candidateRefs: ['cand1', 'cand2'],
      confidence: ProConfidence.medium,
      summary: 'two candidates drafted',
    );

ProExplanation _explanation() => const ProExplanation(
      title: 'Tighter bass',
      summary: 'We eased the low end where the wall was adding boom.',
      reasons: ['wall proximity builds low energy'],
      explanationLevel: ProExplanationLevel.beginner,
      candidateRefs: ['cand1'],
    );

void main() {
  group('1. JSON round-trip for every model', () {
    test('intent', () {
      final a = _intent();
      final b = ProAcousticIntent.fromJson(_cycle(a.toJson()));
      expect(b.toJson(), a.toJson());
    });
    test('plan (order preserved)', () {
      final a = _plan();
      final b = ProOrchestratorPlan.fromJson(_cycle(a.toJson()));
      expect(b.toJson(), a.toJson());
      expect(b.steps.map((s) => s.stepId).toList(), ['s1', 's2']);
    });
    test('context', () {
      final a = _context();
      final b = ProOrchestratorContext.fromJson(_cycle(a.toJson()));
      expect(b.toJson(), a.toJson());
    });
    test('result', () {
      final a = _result();
      final b = ProOrchestratorResult.fromJson(_cycle(a.toJson()));
      expect(b.toJson(), a.toJson());
    });
    test('explanation', () {
      final a = _explanation();
      final b = ProExplanation.fromJson(_cycle(a.toJson()));
      expect(b.toJson(), a.toJson());
    });
  });

  group('2. schemaVersion', () {
    test('unsupported version is rejected', () {
      final j = _plan().toJson()..['schemaVersion'] = 99;
      expect(() => ProOrchestratorPlan.fromJson(j),
          throwsA(isA<ProContractException>()));
    });
    test('non-int version is rejected', () {
      final j = _plan().toJson()..['schemaVersion'] = 'v1';
      expect(() => ProOrchestratorPlan.fromJson(j),
          throwsA(isA<ProContractException>()));
    });
    test('21. a contract-permitted number (schemaVersion=1) passes', () {
      final j = _plan().toJson();
      expect(j['schemaVersion'], 1);
      expect(() => ProOrchestratorPlan.fromJson(j), returnsNormally);
    });
  });

  group('3-5. unknown keys and enum values are rejected', () {
    test('3. unknown top-level key', () {
      final j = _plan().toJson()..['extra'] = 'x';
      expect(() => ProOrchestratorPlan.fromJson(j),
          throwsA(isA<ProContractException>()));
    });
    test('4. unknown nested step key', () {
      final j = _plan().toJson();
      (j['steps'] as List)[0]['surprise'] = 1;
      expect(() => ProOrchestratorPlan.fromJson(j),
          throwsA(isA<ProContractException>()));
    });
    test('5. unknown enum value', () {
      final j = _plan().toJson();
      (j['steps'] as List)[0]['toolId'] = 'notATool';
      expect(() => ProOrchestratorPlan.fromJson(j),
          throwsA(isA<ProContractException>()));
    });
  });

  group('6-9. forbidden DSP keys are rejected (any casing)', () {
    for (final key in [
      'frequencyHz',
      'gainDb',
      'q',
      'address',
      'payload',
      'coefficients',
      'frequency_hz',
      'GAIN_DB',
      'delayMs',
      'biquad',
      'safeLoad',
      'eeprom',
    ]) {
      test('nested step rejects "$key"', () {
        final j = _plan().toJson();
        (j['steps'] as List)[0][key] = 1;
        expect(() => ProOrchestratorPlan.fromJson(j),
            throwsA(isA<ProContractException>()),
            reason: '$key must be refused');
      });
      test('top-level result rejects "$key"', () {
        final j = _result().toJson()..[key] = 1;
        expect(() => ProOrchestratorResult.fromJson(j),
            throwsA(isA<ProContractException>()));
      });
    }
  });

  group('10-12. controlled actions / arbitrary tools rejected', () {
    for (final bad in [
      'apply',
      'deploy',
      'write',
      'transport',
      'anythingElse'
    ]) {
      test('toolId "$bad" is rejected', () {
        final j = _plan().toJson();
        (j['steps'] as List)[0]['toolId'] = bad;
        expect(() => ProOrchestratorPlan.fromJson(j),
            throwsA(isA<ProContractException>()));
      });
    }
  });

  test('13. no model exposes a dynamic parameter/arguments map', () {
    // Encoded JSON must contain only the declared keys — a "parameters" or
    // "arguments" bag would let a value map ride along.
    final all = [
      _intent().toJson(),
      _plan().toJson(),
      _context().toJson(),
      _result().toJson(),
      _explanation().toJson(),
    ];
    for (final j in all) {
      final text = jsonEncode(j).toLowerCase();
      expect(text.contains('parameters'), isFalse);
      expect(text.contains('arguments'), isFalse);
      expect(text.contains('"args"'), isFalse);
    }
  });

  group('14-19. plan structural invariants', () {
    test('14. a ref-only plan parses', () {
      expect(() => ProOrchestratorPlan.fromJson(_cycle(_plan().toJson())),
          returnsNormally);
    });
    test('15. step order is preserved', () {
      final p = ProOrchestratorPlan.fromJson(_cycle(_plan().toJson()));
      expect(p.steps[0].stepId, 's1');
      expect(p.steps[1].stepId, 's2');
    });
    test('16. duplicate stepId is rejected', () {
      final j = _plan().toJson();
      (j['steps'] as List)[1]['stepId'] = 's1';
      expect(() => ProOrchestratorPlan.fromJson(j),
          throwsA(isA<ProContractException>()));
    });
    test('17. duplicate outputRef is rejected', () {
      final j = _plan().toJson();
      (j['steps'] as List)[1]['outputRef'] = 'out1';
      expect(() => ProOrchestratorPlan.fromJson(j),
          throwsA(isA<ProContractException>()));
    });
    test('18. an empty plan is rejected', () {
      final j = _plan().toJson()..['steps'] = [];
      expect(() => ProOrchestratorPlan.fromJson(j),
          throwsA(isA<ProContractException>()));
    });
    test('19. protected/allowed area conflict is rejected', () {
      final j = _intent().toJson()
        ..['allowedChangeAreas'] = ['lowEnd', 'midRange']
        ..['protectedAreas'] = ['midRange'];
      expect(() => ProAcousticIntent.fromJson(j),
          throwsA(isA<ProContractException>()));
    });
  });

  group('20-22. numeric boundary semantics', () {
    test('20. freeTextContext with "cut 80 Hz" parses but yields no DSP field',
        () {
      final j = _intent().toJson()..['freeTextContext'] = '80 Hz를 줄여줘';
      final intent = ProAcousticIntent.fromJson(j);
      expect(intent.freeTextContext, '80 Hz를 줄여줘');
      // The serialized form has no numeric DSP field — the text is inert.
      final out = intent.toJson();
      expect(out.containsKey('frequency'), isFalse);
      expect(out.containsKey('gainDb'), isFalse);
      expect(out['freeTextContext'], isA<String>());
    });
    test('21. permitted numbers (schemaVersion) are not rejected wholesale',
        () {
      // Re-assert alongside the DSP-number rejections: not every number is bad.
      expect(() => ProAcousticIntent.fromJson(_cycle(_intent().toJson())),
          returnsNormally);
    });
    test('22. confidence accepts only the enum, refuses a raw double', () {
      final ok = _result().toJson()..['confidence'] = 'high';
      expect(() => ProOrchestratorResult.fromJson(ok), returnsNormally);

      final bad = _result().toJson()..['confidence'] = 0.9;
      expect(() => ProOrchestratorResult.fromJson(bad),
          throwsA(isA<ProContractException>()));
    });
  });

  group('static boundary', () {
    test('ProOrchestratorToolId has NO controlled-action members', () {
      final names = ProOrchestratorToolId.values.map((e) => e.name).toList();
      for (final forbidden in [
        'apply',
        'deploy',
        'write',
        'transport',
        'address',
        'safeLoad',
        'eeprom',
        'selfBoot',
      ]) {
        expect(names, isNot(contains(forbidden)),
            reason: 'tool set must be read/calculate only');
        // Also guard against substrings like "applyTune".
        expect(
            names.any((n) => n.toLowerCase().contains(forbidden.toLowerCase())),
            isFalse,
            reason: '"$forbidden" must not appear in any tool id');
      }
    });
    test('emitted JSON never contains a DSP number field', () {
      final all = [
        _intent().toJson(),
        _plan().toJson(),
        _context().toJson(),
        _result().toJson(),
        _explanation().toJson(),
      ];
      for (final j in all) {
        final keys = jsonEncode(j).toLowerCase();
        for (final token in ProContract.forbiddenKeyTokens) {
          // Guard as a JSON key ("token":) — substrings inside prose are fine.
          expect(keys.contains('"$token":'), isFalse,
              reason: '$token must never be an output key');
        }
      }
    });
    test('confidence enum has exactly low/medium/high', () {
      expect(ProConfidence.values.map((e) => e.name).toList(),
          ['low', 'medium', 'high']);
    });
  });
}
