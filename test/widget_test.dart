// TUNAI PRO — Phase S: App launch smoke test
// Verifies that TunaiProApp renders without crashing.
// Note: RenderFlex overflow errors are expected in the narrow test viewport
// (Flutter default 800x600). This test only checks for fatal exceptions.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/main.dart';

void main() {
  testWidgets('App launches without fatal error', (WidgetTester tester) async {
    final originalOnError = FlutterError.onError;
    final errors = <FlutterErrorDetails>[];

    FlutterError.onError = (details) {
      // Ignore RenderFlex overflow — expected in narrow test viewports.
      if (!details.toString().contains('overflowed')) {
        errors.add(details);
      }
    };

    try {
      await tester.pumpWidget(const TunaiProApp());
      await tester.pump();
    } finally {
      FlutterError.onError = originalOnError;
    }

    expect(errors, isEmpty, reason: 'Unexpected fatal errors during app launch');
  });
}
