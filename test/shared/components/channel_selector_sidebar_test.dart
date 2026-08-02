import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai_pro/shared/components/channel_selector_sidebar.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

const _items = [
  ChannelSelectorItem(id: 'ch_tw_l', label: 'Tweeter L'),
  ChannelSelectorItem(id: 'ch_wf_l', label: 'Woofer L', subtitle: '2 bands'),
  ChannelSelectorItem(
      id: 'ch_tw_r', label: 'Tweeter R', status: Colors.green),
];

void main() {
  group('ChannelSelectorSidebar', () {
    testWidgets('renders every item label', (tester) async {
      await tester.pumpWidget(_host(
        ChannelSelectorSidebar(items: _items, onSelected: (_) {}),
      ));
      expect(find.text('Tweeter L'), findsOneWidget);
      expect(find.text('Woofer L'), findsOneWidget);
      expect(find.text('Tweeter R'), findsOneWidget);
    });

    testWidgets('renders optional subtitle', (tester) async {
      await tester.pumpWidget(_host(
        ChannelSelectorSidebar(items: _items, onSelected: (_) {}),
      ));
      expect(find.text('2 bands'), findsOneWidget);
    });

    testWidgets('tapping a row calls onSelected with that item\'s id',
        (tester) async {
      String? selected;
      await tester.pumpWidget(_host(
        ChannelSelectorSidebar(
          items: _items,
          onSelected: (id) => selected = id,
        ),
      ));

      await tester.tap(find.text('Woofer L'));
      await tester.pump();

      expect(selected, 'ch_wf_l');
    });

    testWidgets('title defaults to "Channels" and is overridable',
        (tester) async {
      await tester.pumpWidget(_host(
        ChannelSelectorSidebar(items: _items, onSelected: (_) {}),
      ));
      expect(find.text('Channels'), findsOneWidget);

      await tester.pumpWidget(_host(
        ChannelSelectorSidebar(
            items: _items, onSelected: (_) {}, title: 'DRIVERS'),
      ));
      expect(find.text('DRIVERS'), findsOneWidget);
    });
  });
}
