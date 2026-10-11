import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aether_player/main.dart';

void main() {
  testWidgets('About screen exposes an Experimental switch, off by default', (
    tester,
  ) async {
    var enabled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: AboutScreen(
          youTubeSearchEnabled: enabled,
          onYouTubeSearchChanged: (value) => enabled = value,
          customWindowBarEnabled: true,
          onCustomWindowBarChanged: (_) {},
        ),
      ),
    );

    // The switch lives further down the list; scroll it into view.
    final switchFinder = find.widgetWithText(SwitchListTile, 'Experimental');
    await tester.scrollUntilVisible(
      switchFinder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(switchFinder, findsOneWidget);
    expect(find.text('Experimental'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);

    // Toggling it reports the new value.
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(enabled, isTrue);
  });
}
