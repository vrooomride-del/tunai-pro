// P0 — no Linkwitz-Riley option is deployable for ADAU1701 in the XO tab.
//
// Only Butterworth and Bessel are capture-proven ADAU1701 filter types, and
// only 6/12/24 dB/oct are capture-proven slopes (Adau1701XoParameterRegistry).
// The TYPE/SLOPE dropdowns must not offer Linkwitz-Riley or 36/48 dB/oct as a
// NEW selection for an ADAU1701 project — but must not crash if the project's
// already-stored data holds one of those values (defensive union with the
// current value, see xo_tab.dart's _FilterCard).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/core/pro_tuning_data.dart';
import 'package:tunai_pro/features/workbench/tabs/xo_tab.dart';

const _kProjectsKey = 'tunai_pro_projects';

const _kChannels = [
  DriverChannel(
      id: 'ch_tw_l',
      name: 'Tweeter L',
      role: DriverRole.tweeter,
      side: DriverSide.left,
      dspOutputIndex: 1),
];

ProProject _project() => ProProject(
      id: 'p1',
      name: 'ADAU1701 XO filter option test',
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 1),
      dspTarget: 'ADAU1701',
      acousticState: MeasurementProjectState.createDefault()
          .copyWith(driverChannels: _kChannels),
      tuningState: TuningProjectState(
        crossoverChannels: [
          CrossoverChannelState(
            channelId: 'ch_tw_l',
            // Already-stored out-of-range value (pre-existing project data)
            // — must still render without crashing.
            highPass: CrossoverFilter(
              side: FilterSide.highPass,
              type: CrossoverFilterType.linkwitzRiley,
              slope: CrossoverSlope.db24,
              frequencyHz: 2800.0,
            ),
          ),
        ],
      ),
    );

void _seed(ProProject project) {
  SharedPreferences.setMockInitialValues({
    _kProjectsKey: ProProject.encodeList([project]),
  });
}

void main() {
  testWidgets(
      'TYPE dropdown excludes Linkwitz-Riley as a new selection; existing '
      'LR-stored value still renders without crashing', (tester) async {
    _seed(_project());
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: XoTab(projectId: 'p1')),
      ),
    ));
    await tester.pumpAndSettle();

    final typeDropdownFinder =
        find.byType(DropdownButton<CrossoverFilterType>);
    expect(typeDropdownFinder, findsOneWidget);
    final typeDropdown =
        tester.widget<DropdownButton<CrossoverFilterType>>(typeDropdownFinder);
    final typeValues =
        typeDropdown.items!.map((i) => i.value).toSet();

    // The already-stored LR value is present (so it renders/selects fine)...
    expect(typeValues.contains(CrossoverFilterType.linkwitzRiley), isTrue);
    // ...but nothing else offers LR as a fresh choice: only the stored value
    // plus the capture-proven set are present.
    expect(
      typeValues,
      {
        CrossoverFilterType.linkwitzRiley, // only because it's already stored
        CrossoverFilterType.butterworth,
        CrossoverFilterType.bessel,
      },
    );

    final slopeDropdownFinder = find.byType(DropdownButton<CrossoverSlope>);
    expect(slopeDropdownFinder, findsOneWidget);
    final slopeDropdown =
        tester.widget<DropdownButton<CrossoverSlope>>(slopeDropdownFinder);
    final slopeValues = slopeDropdown.items!.map((i) => i.value).toSet();
    expect(
      slopeValues,
      {CrossoverSlope.db6, CrossoverSlope.db12, CrossoverSlope.db24},
    );
  });
}
