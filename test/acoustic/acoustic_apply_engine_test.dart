import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/core/acoustic/acoustic_apply_engine.dart';
import 'package:tunai_pro/core/acoustic/acoustic_problem_classifier.dart';
import 'package:tunai_pro/core/acoustic/candidate_optimizer.dart';
import 'package:tunai_pro/core/acoustic/candidate_safety.dart';
import 'package:tunai_pro/core/acoustic/candidate_scoring.dart';
import 'package:tunai_pro/core/acoustic/candidate_set.dart';
import 'package:tunai_pro/core/acoustic/correction_plan.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';

// ── Test helpers ──────────────────────────────────────────────────────────────

// Build a SelectedCandidate for test use.
SelectedCandidate _sel({
  required String featureId,
  required double frequencyHz,
  double gainDb = -6.0,
  double q = 4.0,
  int applicationOrder = 1,
}) =>
    SelectedCandidate(
      scoredCandidate: ScoredCandidate(
        candidate: PeqCandidate(
          candidateId: 'candidate:$featureId',
          featureId: featureId,
          featureType: AcousticFeatureType.narrowPeak,
          frequencyHz: frequencyHz,
          gainDb: gainDb,
          q: q,
          intent: CorrectionIntent.cut,
          reason: 'test',
        ),
        prominenceDb: 6.0,
        prominenceScore: 40.0,
        magnitudeConsistencyScore: 30.0,
        qualityFactor: 1.0,
        compositeScore: 70.0,
        rank: applicationOrder,
        grade: CandidateScoreGrade.excellent,
        reasons: const ['test'],
      ),
      applicationOrder: applicationOrder,
      selectionReason: 'test selection',
    );

// Build a permitted CandidateSafetyResult.
CandidateSafetyResult _permitted(List<SelectedCandidate> verified) =>
    CandidateSafetyResult(
      applyPermitted: true,
      issues: const [],
      verifiedCandidates: verified,
      policyId: 'safety_policy',
      policyVersion: 1,
      evidenceRefs: const ['ev1'],
    );

// Build a not-permitted CandidateSafetyResult.
CandidateSafetyResult _notPermitted() => const CandidateSafetyResult(
      applyPermitted: false,
      issues: [
        CandidateSafetyIssue(
          code: CandidateSafetyViolationCode.propagatedStatus,
          detail: 'test block',
        ),
      ],
      verifiedCandidates: [],
      policyId: 'safety_policy',
      policyVersion: 1,
      evidenceRefs: ['ev1'],
    );

// Empty channel: 10 disabled slots, 0 active bands.
PeqChannelState _emptyChannel([String id = 'ch_main']) =>
    PeqChannelState.fixed(id);

// Full channel: all 10 slots enabled.
PeqChannelState _fullChannel([String id = 'ch_main']) {
  var ch = PeqChannelState.fixed(id);
  for (var i = 0; i < PeqChannelState.bandCount; i++) {
    ch = ch.fillNextFreeSlot(
      type: PeqBandType.peak,
      frequencyHz: 1000.0,
      gainDb: -3.0,
      q: 1.0,
    );
  }
  return ch;
}

// Channel with exactly [free] free slots.
PeqChannelState _channelWithFreeSlots(int free, [String id = 'ch_main']) {
  final used = PeqChannelState.bandCount - free;
  var ch = PeqChannelState.fixed(id);
  for (var i = 0; i < used; i++) {
    ch = ch.fillNextFreeSlot(
      type: PeqBandType.peak,
      frequencyHz: 800.0 + i * 100,
      gainDb: -2.0,
      q: 2.0,
    );
  }
  return ch;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('normal apply', () {
    test('single candidate on empty channel → ok, applied=1', () {
      final result = AcousticApplyEngine.apply(
        _permitted([_sel(featureId: 'f1', frequencyHz: 500.0, gainDb: -5.0)]),
        _emptyChannel(),
      );

      expect(result.status, TuningApplyStatus.ok);
      expect(result.applied, hasLength(1));
      expect(result.skipped, isEmpty);
      expect(result.applied.single.candidateId, 'candidate:f1');
      expect(result.applied.single.frequencyHz, 500.0);
      expect(result.applied.single.gainDb, -5.0);
      expect(result.applied.single.applicationOrder, 1);
    });

    test('updatedChannel.activeBandCount increases by applied.length', () {
      final ch = _emptyChannel();
      final result = AcousticApplyEngine.apply(
        _permitted([
          _sel(featureId: 'f1', frequencyHz: 200.0, applicationOrder: 1),
          _sel(featureId: 'f2', frequencyHz: 1000.0, applicationOrder: 2),
        ]),
        ch,
      );

      expect(result.updatedChannel.activeBandCount,
          ch.activeBandCount + result.applied.length);
      expect(result.updatedChannel.activeBandCount, 2);
    });

    test('updatedChannel.channelId matches input channelId', () {
      final result = AcousticApplyEngine.apply(
        _permitted([_sel(featureId: 'f1', frequencyHz: 300.0)]),
        _emptyChannel('tweeter'),
      );
      expect(result.channelId, 'tweeter');
      expect(result.updatedChannel.channelId, 'tweeter');
    });

    test('applied bands carry correct frequencyHz/gainDb/q', () {
      final result = AcousticApplyEngine.apply(
        _permitted([
          _sel(featureId: 'f1', frequencyHz: 440.0, gainDb: -7.5, q: 3.2),
        ]),
        _emptyChannel(),
      );

      final band = result.applied.single;
      expect(band.frequencyHz, 440.0);
      expect(band.gainDb, -7.5);
      expect(band.q, 3.2);
    });
  });

  group('multiple candidates — applicationOrder', () {
    test('three candidates applied in applicationOrder 1,2,3', () {
      final result = AcousticApplyEngine.apply(
        _permitted([
          _sel(featureId: 'f1', frequencyHz: 100.0, applicationOrder: 1),
          _sel(featureId: 'f2', frequencyHz: 500.0, applicationOrder: 2),
          _sel(featureId: 'f3', frequencyHz: 4000.0, applicationOrder: 3),
        ]),
        _emptyChannel(),
      );

      expect(result.status, TuningApplyStatus.ok);
      expect(result.applied, hasLength(3));
      expect(result.skipped, isEmpty);

      final orders = result.applied.map((b) => b.applicationOrder).toList();
      expect(orders, [1, 2, 3]);

      final ids = result.applied.map((b) => b.featureId).toList();
      expect(ids, ['f1', 'f2', 'f3']);
    });

    test('candidates presented out of order are applied in applicationOrder', () {
      // Pass candidates in reverse order — engine must sort by applicationOrder.
      final result = AcousticApplyEngine.apply(
        _permitted([
          _sel(featureId: 'f3', frequencyHz: 4000.0, applicationOrder: 3),
          _sel(featureId: 'f1', frequencyHz: 100.0, applicationOrder: 1),
          _sel(featureId: 'f2', frequencyHz: 500.0, applicationOrder: 2),
        ]),
        _emptyChannel(),
      );

      expect(result.status, TuningApplyStatus.ok);
      expect(result.applied.map((b) => b.applicationOrder).toList(), [1, 2, 3]);
      expect(result.applied.map((b) => b.featureId).toList(), ['f1', 'f2', 'f3']);
    });
  });

  group('no slot available', () {
    test('full channel + 1 candidate → noSlotAvailable, skipped=1', () {
      final result = AcousticApplyEngine.apply(
        _permitted([_sel(featureId: 'f1', frequencyHz: 500.0)]),
        _fullChannel(),
      );

      expect(result.status, TuningApplyStatus.noSlotAvailable);
      expect(result.applied, isEmpty);
      expect(result.skipped, hasLength(1));
      expect(result.skipped.single.candidateId, 'candidate:f1');
      expect(result.skipped.single.reason, contains('no free slot'));
    });

    test('full channel → updatedChannel equals input (no mutation)', () {
      final ch = _fullChannel();
      final result = AcousticApplyEngine.apply(
        _permitted([_sel(featureId: 'f1', frequencyHz: 500.0)]),
        ch,
      );

      expect(result.updatedChannel.activeBandCount, ch.activeBandCount);
      expect(result.updatedChannel.activeBandCount, PeqChannelState.bandCount);
    });

    test('full channel + multiple candidates → all skipped', () {
      final result = AcousticApplyEngine.apply(
        _permitted([
          _sel(featureId: 'f1', frequencyHz: 200.0, applicationOrder: 1),
          _sel(featureId: 'f2', frequencyHz: 1000.0, applicationOrder: 2),
        ]),
        _fullChannel(),
      );

      expect(result.status, TuningApplyStatus.noSlotAvailable);
      expect(result.applied, isEmpty);
      expect(result.skipped, hasLength(2));
      expect(result.skipped.map((s) => s.applicationOrder).toList(), [1, 2]);
    });
  });

  group('partial apply', () {
    test('1 free slot + 2 candidates → partiallyApplied, applied=1 skipped=1',
        () {
      final result = AcousticApplyEngine.apply(
        _permitted([
          _sel(featureId: 'f1', frequencyHz: 200.0, applicationOrder: 1),
          _sel(featureId: 'f2', frequencyHz: 1000.0, applicationOrder: 2),
        ]),
        _channelWithFreeSlots(1),
      );

      expect(result.status, TuningApplyStatus.partiallyApplied);
      expect(result.applied, hasLength(1));
      expect(result.skipped, hasLength(1));
      expect(result.applied.single.featureId, 'f1'); // applicationOrder=1 wins
      expect(result.skipped.single.featureId, 'f2');
      expect(result.skipped.single.reason, contains('no free slot'));
    });

    test('2 free slots + 3 candidates → partiallyApplied, 2 applied 1 skipped',
        () {
      final result = AcousticApplyEngine.apply(
        _permitted([
          _sel(featureId: 'f1', frequencyHz: 100.0, applicationOrder: 1),
          _sel(featureId: 'f2', frequencyHz: 500.0, applicationOrder: 2),
          _sel(featureId: 'f3', frequencyHz: 4000.0, applicationOrder: 3),
        ]),
        _channelWithFreeSlots(2),
      );

      expect(result.status, TuningApplyStatus.partiallyApplied);
      expect(result.applied, hasLength(2));
      expect(result.skipped, hasLength(1));
      expect(result.skipped.single.featureId, 'f3');
    });
  });

  group('not permitted', () {
    test('applyPermitted=false → notPermitted, no channel mutation', () {
      final ch = _emptyChannel();
      final result = AcousticApplyEngine.apply(_notPermitted(), ch);

      expect(result.status, TuningApplyStatus.notPermitted);
      expect(result.applied, isEmpty);
      expect(result.skipped, isEmpty);
      expect(result.updatedChannel.activeBandCount, 0);
    });

    test('notPermitted: updatedChannel is the original (unchanged)', () {
      final ch = _channelWithFreeSlots(5);
      final activeBefore = ch.activeBandCount;
      final result = AcousticApplyEngine.apply(_notPermitted(), ch);

      expect(result.updatedChannel.channelId, ch.channelId);
      expect(result.updatedChannel.activeBandCount, activeBefore);
    });
  });

  group('empty verifiedCandidates', () {
    test('permitted with 0 candidates → ok, no changes, applied=0', () {
      final ch = _emptyChannel();
      final result = AcousticApplyEngine.apply(_permitted(const []), ch);

      expect(result.status, TuningApplyStatus.ok);
      expect(result.applied, isEmpty);
      expect(result.skipped, isEmpty);
      expect(result.updatedChannel.activeBandCount, 0);
    });
  });

  group('policy metadata and evidenceRefs', () {
    test('safetyPolicyId/Version carried into result', () {
      const safetyResult = CandidateSafetyResult(
        applyPermitted: true,
        issues: [],
        verifiedCandidates: [],
        policyId: 'my_safety_v2',
        policyVersion: 7,
        evidenceRefs: ['ref-abc'],
      );
      final result =
          AcousticApplyEngine.apply(safetyResult, _emptyChannel());

      expect(result.safetyPolicyId, 'my_safety_v2');
      expect(result.safetyPolicyVersion, 7);
    });

    test('evidenceRefs propagated from CandidateSafetyResult', () {
      const safetyResult = CandidateSafetyResult(
        applyPermitted: true,
        issues: [],
        verifiedCandidates: [],
        policyId: 'p',
        policyVersion: 1,
        evidenceRefs: ['sweep-001', 'measurement-abc'],
      );
      final result =
          AcousticApplyEngine.apply(safetyResult, _emptyChannel());

      expect(result.evidenceRefs,
          containsAll(['sweep-001', 'measurement-abc']));
    });
  });

  group('JSON — no DSP-forbidden fields', () {
    test('toJson() contains no address/payload/biquad/hardware fields', () {
      final result = AcousticApplyEngine.apply(
        _permitted([
          _sel(featureId: 'f1', frequencyHz: 1000.0, gainDb: -6.0),
        ]),
        _emptyChannel(),
      );
      final json = jsonEncode(result.toJson()).toLowerCase();

      for (final forbidden in [
        'address',
        'payload',
        'biquad',
        'coefficient',
        'register',
        'safeload',
        'hardware',
        'suggestion',
        'proposedgain',
      ]) {
        expect(json.contains(forbidden), isFalse,
            reason: 'forbidden field "$forbidden" found in JSON');
      }
    });

    test('toJson() includes status, channelId, applied/skipped counts', () {
      final result = AcousticApplyEngine.apply(
        _permitted([_sel(featureId: 'f1', frequencyHz: 500.0)]),
        _emptyChannel('tweeter'),
      );
      final map = result.toJson();

      expect(map['status'], 'ok');
      expect(map['channelId'], 'tweeter');
      expect(map['appliedCount'], 1);
      expect(map['skippedCount'], 0);
    });

    test('notPermitted result toJson has status=notPermitted, counts=0', () {
      final result =
          AcousticApplyEngine.apply(_notPermitted(), _emptyChannel());
      final map = result.toJson();

      expect(map['status'], 'notPermitted');
      expect(map['appliedCount'], 0);
      expect(map['skippedCount'], 0);
    });
  });

  group('determinism', () {
    test('same inputs → identical JSON output', () {
      final candidates = [
        _sel(featureId: 'f1', frequencyHz: 200.0, gainDb: -5.0, applicationOrder: 1),
        _sel(featureId: 'f2', frequencyHz: 1000.0, gainDb: -4.0, applicationOrder: 2),
      ];
      final safety = _permitted(candidates);
      final ch = _emptyChannel();

      final a = AcousticApplyEngine.apply(safety, ch);
      final b = AcousticApplyEngine.apply(safety, ch);

      expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
    });

    test('same inputs produce same activeBandCount', () {
      final safety = _permitted([
        _sel(featureId: 'f1', frequencyHz: 300.0, applicationOrder: 1),
      ]);
      final ch = _emptyChannel();

      final a = AcousticApplyEngine.apply(safety, ch);
      final b = AcousticApplyEngine.apply(safety, ch);

      expect(a.updatedChannel.activeBandCount,
          b.updatedChannel.activeBandCount);
    });
  });

  group('SkippedBand / AppliedBand — applicationOrder in result', () {
    test('skippedBand records original applicationOrder', () {
      final result = AcousticApplyEngine.apply(
        _permitted([
          _sel(featureId: 'f1', frequencyHz: 200.0, applicationOrder: 1),
          _sel(featureId: 'f2', frequencyHz: 1000.0, applicationOrder: 2),
        ]),
        _channelWithFreeSlots(1),
      );
      expect(result.skipped.single.applicationOrder, 2);
    });

    test('appliedBand.featureId matches candidate featureId', () {
      final result = AcousticApplyEngine.apply(
        _permitted([
          _sel(featureId: 'narrowPeak@440Hz#0', frequencyHz: 440.0),
        ]),
        _emptyChannel(),
      );
      expect(result.applied.single.featureId, 'narrowPeak@440Hz#0');
      expect(result.applied.single.candidateId, 'candidate:narrowPeak@440Hz#0');
    });
  });

  group('reasons field', () {
    test('ok result reason contains applied count and channelId', () {
      final result = AcousticApplyEngine.apply(
        _permitted([_sel(featureId: 'f1', frequencyHz: 500.0)]),
        _emptyChannel('woofer'),
      );
      expect(result.reasons.first, contains('1'));
      expect(result.reasons.first, contains('woofer'));
    });

    test('notPermitted result reason mentions safety gate', () {
      final result =
          AcousticApplyEngine.apply(_notPermitted(), _emptyChannel());
      expect(result.reasons.first, contains('not permitted'));
    });
  });

  // FINAL QA CLOSURE #3 §6/§7 — ADAU1701 automatic PEQ allocation must never
  // land on Band 9/10 (no write-verified hardware evidence there), while
  // manual/pre-existing project data on those bands is preserved untouched.
  group('maxSlotCount — ADAU1701 automatic Band 1-8 cap', () {
    test('an empty channel only fills slots within maxSlotCount, never '
        'beyond it', () {
      final result = AcousticApplyEngine.apply(
        _permitted([
          for (var i = 0; i < 10; i++)
            _sel(
                featureId: 'f$i',
                frequencyHz: 200.0 + i * 100,
                applicationOrder: i + 1),
        ]),
        _emptyChannel(),
        maxSlotCount: 8,
      );
      expect(result.applied.length, 8);
      expect(result.skipped.length, 2);
      expect(result.status, TuningApplyStatus.partiallyApplied);
      // Bands 0-7 (1-based slots 1-8) enabled; bands 8-9 (slots 9-10) untouched.
      final updated = result.updatedChannel.normalized();
      for (var i = 0; i < 8; i++) {
        expect(updated.bands[i].enabled, isTrue, reason: 'slot ${i + 1}');
      }
      for (var i = 8; i < 10; i++) {
        expect(updated.bands[i].enabled, isFalse, reason: 'slot ${i + 1}');
      }
    });

    test('pre-existing Band 9/10 data is preserved, never cleared or '
        'overwritten by the cap', () {
      // Simulate an existing project with Band 9 (index 8) already active
      // from before this cap existed.
      var seeded = _emptyChannel();
      final normSeed = seeded.normalized();
      final preExisting = normSeed.bands[8].copyWith(
        enabled: true,
        status: PeqBandStatus.active,
        type: PeqBandType.peak,
        frequencyHz: 5000.0,
        gainDb: -4.0,
        q: 2.0,
      );
      final seededBands = [...normSeed.bands];
      seededBands[8] = preExisting;
      seeded = normSeed.copyWith(bands: seededBands);

      final result = AcousticApplyEngine.apply(
        _permitted([_sel(featureId: 'new1', frequencyHz: 300.0)]),
        seeded,
        maxSlotCount: 8,
      );

      expect(result.applied.length, 1);
      final updated = result.updatedChannel.normalized();
      // Band 9 (index 8) is exactly as it was — new fill went to slot 1.
      expect(updated.bands[8].frequencyHz, 5000.0);
      expect(updated.bands[8].gainDb, -4.0);
      expect(updated.bands[0].enabled, isTrue);
      expect(updated.bands[0].frequencyHz, 300.0);
    });

    test('when Band 1-8 is already exhausted, new candidates are all '
        'skipped with a clear "no deployable slot" reason — no fallback '
        'to Band 9/10', () {
      // Fill bands 0-7 only (Band 1-8), leave 8-9 free.
      var ch = _emptyChannel();
      for (var i = 0; i < 8; i++) {
        ch = ch.fillNextFreeSlot(
          type: PeqBandType.peak,
          frequencyHz: 500.0 + i * 100,
          gainDb: -2.0,
          q: 1.0,
        );
      }
      final result = AcousticApplyEngine.apply(
        _permitted([_sel(featureId: 'overflow', frequencyHz: 1234.0)]),
        ch,
        maxSlotCount: 8,
      );

      expect(result.applied, isEmpty);
      expect(result.status, TuningApplyStatus.noSlotAvailable);
      expect(result.skipped.single.reason, contains('no deployable slot'));
      expect(result.skipped.single.reason, contains('8-band limit'));
      // Slots 9-10 remain untouched, not silently used as overflow.
      final updated = result.updatedChannel.normalized();
      expect(updated.bands[8].enabled, isFalse);
      expect(updated.bands[9].enabled, isFalse);
    });

    test('omitting maxSlotCount preserves the original unrestricted '
        '10-slot behavior (ADAU1466/simulation regression guard)', () {
      final result = AcousticApplyEngine.apply(
        _permitted([
          for (var i = 0; i < 10; i++)
            _sel(
                featureId: 'f$i',
                frequencyHz: 200.0 + i * 100,
                applicationOrder: i + 1),
        ]),
        _emptyChannel(),
      );
      expect(result.applied.length, 10);
      expect(result.skipped, isEmpty);
      expect(result.status, TuningApplyStatus.ok);
    });
  });
}
