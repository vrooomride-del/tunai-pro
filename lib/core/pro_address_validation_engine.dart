// ── TUNAI PRO Phase U2 — Address Validation Engine ───────────────────────────
// Creates validation task lists from an address registry.
// Does NOT write to hardware. Does NOT send USB/BLE. Does NOT execute SafeLoad.
// Does NOT auto-mark addresses as liveWriteVerified.
// AI suggests. Expert verifies. AOS protects. DSP executes.

import 'pro_dsp_address_registry.dart';
import 'pro_address_validation_data.dart';

// Verified master volume addresses — listed as reference, not queued by default.
const _kMasterVolL = 0x0067;
const _kMasterVolR = 0x0064;

// ── Public API ────────────────────────────────────────────────────────────────

/// Creates validation tasks for all exportConfirmed / needsLiveValidation
/// addresses in [registry].
///
/// Master Volume L/R (0x0067, 0x0064) appear as verified references but are
/// NOT added to the active queue — they are already write-eligible.
///
/// PEQ rows tracked by [peqRowCount] only (no indexed address entry) are NOT
/// included — they require explicit address entries to be validated.
AddressValidationProjectState createValidationTasksFromRegistry({
  required DspAddressRegistry registry,
}) {
  final now = DateTime.now();
  final tasks = <AddressValidationTask>[];
  int seq = 0;

  // Sort addresses by recommended validation order (group order, then address)
  final sorted = List<VerifiedDspAddress>.from(registry.addresses)
    ..sort((a, b) {
      final ga = _groupFor(a).recommendedOrder;
      final gb = _groupFor(b).recommendedOrder;
      if (ga != gb) return ga.compareTo(gb);
      return a.addressInt.compareTo(b.addressInt);
    });

  for (final addr in sorted) {
    final isMasterVol = addr.addressInt == _kMasterVolL ||
        addr.addressInt == _kMasterVolR;

    // Master volume: include as a verified reference task (not queued).
    if (isMasterVol) {
      tasks.add(AddressValidationTask(
        id:            'vt_${addr.addressInt}_${seq++}',
        addressId:     addr.id,
        parameterId:   addr.parameterId,
        logicalName:   addr.logicalName,
        group:         AddressValidationGroup.masterVolume,
        risk:          AddressValidationRisk.low,
        currentStatus: AddressValidationStatus.liveWriteVerified, // already verified
        addressHex:    addr.addressHex,
        channel:       addr.channelId,
        outputIndex:   addr.physicalOutput,
        expectedEffect: 'Audio level change proportional to parameter value.',
        notes:         'Master Volume — verified reference. Not queued for live capture.',
        createdAt:     now,
        updatedAt:     now,
      ));
      continue;
    }

    // Only create tasks for export-confirmed or needs-live-validation addresses.
    final eligible =
        addr.verificationStatus == DspAddressVerificationStatus.exportConfirmed ||
        addr.verificationStatus == DspAddressVerificationStatus.needsLiveValidation;

    if (!eligible) continue;

    final group  = _groupFor(addr);
    final risk   = _riskFor(group);
    final effect = _expectedEffectFor(group, addr);

    tasks.add(AddressValidationTask(
      id:            'vt_${addr.addressInt}_${seq++}',
      addressId:     addr.id,
      parameterId:   addr.parameterId,
      logicalName:   addr.logicalName,
      group:         group,
      risk:          risk,
      currentStatus: AddressValidationStatus.queued,
      addressHex:    addr.addressHex,
      channel:       addr.channelId,
      outputIndex:   addr.physicalOutput,
      coefficient:   addr.coefficient,
      expectedEffect: effect,
      notes:         'Export-confirmed address. Requires live observation before write eligibility.',
      createdAt:     now,
      updatedAt:     now,
    ));
  }

  return AddressValidationProjectState(
    tasks:    tasks,
    attempts: const [],
    updatedAt: now,
    revision: 1,
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

AddressValidationGroup _groupFor(VerifiedDspAddress addr) {
  switch (addr.parameterKind) {
    case DspParameterKind.masterVolume:  return AddressValidationGroup.masterVolume;
    case DspParameterKind.safeload:      return AddressValidationGroup.safeLoad;
    case DspParameterKind.mute:          return AddressValidationGroup.mute;
    case DspParameterKind.gain:          return AddressValidationGroup.gain;
    case DspParameterKind.delay:         return AddressValidationGroup.delay;
    case DspParameterKind.peq:           return AddressValidationGroup.peq;
    case DspParameterKind.crossover:     return AddressValidationGroup.crossover;
    case DspParameterKind.polarity:      return AddressValidationGroup.polarity;
    case DspParameterKind.outputMapping: return AddressValidationGroup.outputRouting;
    case DspParameterKind.protection:    return AddressValidationGroup.limiter;
    case DspParameterKind.router:        return AddressValidationGroup.outputRouting;
    default:                             return AddressValidationGroup.unknown;
  }
}

AddressValidationRisk _riskFor(AddressValidationGroup group) => switch (group) {
  AddressValidationGroup.masterVolume  => AddressValidationRisk.low,
  AddressValidationGroup.mute          => AddressValidationRisk.low,
  AddressValidationGroup.gain          => AddressValidationRisk.low,
  AddressValidationGroup.delay         => AddressValidationRisk.medium,
  AddressValidationGroup.polarity      => AddressValidationRisk.medium,
  AddressValidationGroup.safeLoad      => AddressValidationRisk.high,
  AddressValidationGroup.peq           => AddressValidationRisk.high,
  AddressValidationGroup.limiter       => AddressValidationRisk.high,
  AddressValidationGroup.crossover     => AddressValidationRisk.critical,
  AddressValidationGroup.outputRouting => AddressValidationRisk.critical,
  AddressValidationGroup.unknown       => AddressValidationRisk.high,
};

String _expectedEffectFor(AddressValidationGroup group, VerifiedDspAddress addr) {
  final ch = addr.channelId != null ? ' (${addr.channelId})' : '';
  return switch (group) {
    AddressValidationGroup.masterVolume  => 'Global level change$ch.',
    AddressValidationGroup.safeLoad      => 'SafeLoad register update — no audible effect until data applied.',
    AddressValidationGroup.mute          => 'Channel silence or restoration$ch.',
    AddressValidationGroup.gain          => 'Level increase or decrease$ch. Audible but safe.',
    AddressValidationGroup.delay         => 'Phase shift / timing change$ch. Subtle at small values.',
    AddressValidationGroup.peq           => 'Frequency response change$ch. Verify with measurement.',
    AddressValidationGroup.crossover     => 'CRITICAL: Driver routing change$ch. Verify output pin before write.',
    AddressValidationGroup.polarity      => 'Polarity flip$ch. Verify with mono summing.',
    AddressValidationGroup.outputRouting => 'CRITICAL: Signal routing to output$ch. Verify with scope or SPL meter.',
    AddressValidationGroup.limiter       => 'Limiter threshold change$ch. Test at low signal level.',
    AddressValidationGroup.unknown       => 'Unknown effect. Expert verification required.',
  };
}
