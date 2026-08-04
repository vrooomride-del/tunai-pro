// TUNAI PRO UI/UX v3 Phase V3-3.5 — Shared Current Driver Header.
//
// Consolidates the driver-identity block (name/role/side/DSP output) that
// was previously duplicated in each tab's private _ChannelHeader /
// _XoChannelHeader / _GainChannelHeader / _DelayChannelHeader, plus (when a
// [compareCurves] pair is supplied) the same current-vs-compare match
// readout PEQ already showed. Read-only, UI layer only:
//  - resolves the selected channel from channelCompareProvider
//    (currentChannelId — never a DriverChannel, see channel_compare_provider.dart)
//  - resolves DriverChannel objects fresh from [drivers] on every build via
//    driverChannelFor — never stores one
//  - never touches PeqChannelState/PeqBand/tuning data, XO/Gain/Delay
//    calculation, DSP export, deploy, or hardware writes

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/adau1701_peq_response.dart';
import '../../../core/channel_compare_provider.dart';
import '../../../core/pro_acoustic_data.dart';
import '../../../shared/components/section_header.dart';
import '../../../shared/components/stat_chip.dart';
import '../../../shared/pro_widgets.dart';
import 'graph_overlay_models.dart';

class CurrentDriverHeader extends ConsumerWidget {
  final List<DriverChannel> drivers;

  /// When supplied, exactly two curves — [current, compare] — used to
  /// compute the same Excellent/Good/Needs Tune readout PEQ's compare
  /// section already shows. Optional: only PEQ currently has curve data
  /// available; other tabs show the compare driver's name with no match
  /// pill.
  final List<PeqGraphCurve>? compareCurves;

  const CurrentDriverHeader({
    super.key,
    required this.drivers,
    this.compareCurves,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compareState = ref.watch(channelCompareProvider);
    final driverIds = [for (final d in drivers) d.id];
    final selectedId = resolveSelectedChannelId(compareState, driverIds);
    final driver = driverChannelFor(selectedId, drivers);
    if (driver == null) return const SizedBox.shrink();

    final pairId = pairChannelIdFor(driver.id, drivers);
    final compareDriver = (compareState.compareEnabled &&
            pairId != null &&
            compareState.compareChannelIds.contains(pairId))
        ? driverChannelFor(pairId, drivers)
        : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: kProSurface,
        border: Border.all(color: kProBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('CURRENT DRIVER', style: proLabel(size: 9, spacing: 2)),
        const SizedBox(height: 6),
        ProSectionHeader(
          title: driver.name,
          subtitle: '${driver.role.label} · ${driver.side.label}',
          trailing: ProStatChip(
            label: 'DSP',
            value: driver.dspOutputIndex == null
                ? '—'
                : 'Channel ${driver.dspOutputIndex}',
          ),
        ),
        if (compareDriver != null) ...[
          const SizedBox(height: 10),
          _CompareRow(compareDriver: compareDriver, curves: compareCurves),
        ],
      ]),
    );
  }
}

class _CompareRow extends StatelessWidget {
  final DriverChannel compareDriver;
  final List<PeqGraphCurve>? curves;
  const _CompareRow({required this.compareDriver, required this.curves});

  @override
  Widget build(BuildContext context) {
    final match = _resolveMatch(curves);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        Text('Compare:', style: proLabel(size: 9, spacing: 1)),
        Text(compareDriver.name,
            style: proValue(size: 11, color: Colors.white)),
        if (match != null) ProStatusPill(label: match.$1, color: match.$2),
      ],
    );
  }

  /// Same sampling density and formulas peq_tab.dart's own compare readout
  /// already used — moved here so every tab that supplies curve data gets
  /// byte-for-byte the same match computation, not re-derived per tab. Never
  /// writes back into PEQ data; display only.
  static (String, Color)? _resolveMatch(List<PeqGraphCurve>? curves) {
    if (curves == null || curves.length != 2) return null;
    final points = Adau1701PeqResponse.logFrequencyPoints(count: 220);
    final a = curves[0].curveFor(points);
    final b = curves[1].curveFor(points);
    final diff = PeqGraphOverlayMath.difference(a, b);
    if (diff == null) return null;
    final meanAbs = PeqGraphOverlayMath.meanAbsoluteDifference(diff);
    final match = PeqChannelMatch.fromMeanAbsDiff(meanAbs);
    final color = switch (match) {
      PeqChannelMatch.excellent => kProGreen,
      PeqChannelMatch.good => kProAmber,
      PeqChannelMatch.needsTune => kProRed,
    };
    return ('Match · ${match.label} · ${meanAbs.toStringAsFixed(1)}dB', color);
  }
}
