// TUNAI PRO — Phase S-2: Overflow smoke tests
// Tests that key screens render without RenderFlex overflow at common window widths.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/main.dart';

const _widths = [1024.0, 1280.0, 1440.0];
const _height = 800.0;

void main() {
  for (final w in _widths) {
    testWidgets('No overflow at ${w.toInt()}×${_height.toInt()}', (tester) async {
      tester.view.physicalSize = Size(w, _height);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final overflows = <String>[];
      final original = FlutterError.onError;
      FlutterError.onError = (details) {
        final msg = details.toString();
        if (msg.contains('overflowed') && msg.contains('RIGHT')) {
          overflows.add(msg.split('\n').first);
        }
      };

      await tester.pumpWidget(const TunaiProApp());
      await tester.pump();

      FlutterError.onError = original;

      expect(overflows, isEmpty,
          reason: 'RIGHT overflow at ${w.toInt()}×${_height.toInt()}:\n${overflows.join('\n')}');
    });
  }
}
