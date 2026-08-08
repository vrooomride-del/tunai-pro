// P0-6 — PEQ Editor must warn on Band 9-10 (index 8-9) when the project's
// deploy target is ADAU1701, since HardwareDeviceProfiles.adau1701Icp5 only
// captureProven-verifies Band 1-8 for write; Band 9-10 are structurally
// unavailable for hardware deploy and would otherwise be silently blocked
// only at Deploy time, with no forewarning in the editor.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai_pro/core/pro_acoustic_data.dart';
import 'package:tunai_pro/core/pro_project.dart';
import 'package:tunai_pro/features/workbench/tabs/peq_tab.dart';

const _kProjectsKey = 'tunai_pro_projects';

const _kChannels = [
  DriverChannel(
      id: 'ch_wf_l',
      name: 'Woofer L',
      role: DriverRole.woofer,
      side: DriverSide.left,
      dspOutputIndex: 1),
];

ProProject _project({required String dspTarget}) => ProProject(
      id: 'p1',
      name: 'PEQ hardware band test',
      dspTarget: dspTarget,
      createdAt: DateTime.utc(2026, 8, 4),
      updatedAt: DateTime.utc(2026, 8, 4),
      acousticState: MeasurementProjectState.createDefault()
          .copyWith(driverChannels: _kChannels),
    );

void _seed(ProProject project) {
  SharedPreferences.setMockInitialValues({
    _kProjectsKey: ProProject.encodeList([project]),
  });
}

Widget _host() => const ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: PeqTab(projectId: 'p1')),
      ),
    );

void main() {
  testWidgets('ADAU1701 project shows NOT HW-VERIFIED on bands 9 and 10 only',
      (tester) async {
    _seed(_project(dspTarget: 'ADAU1701'));
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host());
    await tester.pump();

    expect(find.text('NOT HW-VERIFIED'), findsNWidgets(2),
        reason: 'exactly bands 9 and 10 (index 8-9) must be flagged');
  });

  testWidgets('ADAU1466 project shows no NOT HW-VERIFIED badges',
      (tester) async {
    _seed(_project(dspTarget: 'ADAU1466'));
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host());
    await tester.pump();

    expect(find.text('NOT HW-VERIFIED'), findsNothing,
        reason: 'the 1-8 write cap is ADAU1701-specific evidence');
  });

  group('P0-C — band row responsive overflow', () {
    testWidgets('no overflow at 1280x720, ADAU1701 project (badge present)',
        (tester) async {
      _seed(_project(dspTarget: 'ADAU1701'));
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host());
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'no overflow at a narrow workbench-equivalent width (900px), '
        'ADAU1701 project (badge present)', (tester) async {
      _seed(_project(dspTarget: 'ADAU1701'));
      tester.view.physicalSize = const Size(900, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host());
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow at 1280x720 with a bumped textScale',
        (tester) async {
      _seed(_project(dspTarget: 'ADAU1701'));
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: _host(),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow at 1280x720, ADAU1466 project (no badge)',
        (tester) async {
      _seed(_project(dspTarget: 'ADAU1466'));
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host());
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
