import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/widgets/app_header.dart';

void main() {
  int opens = 0;
  Future<void> open(
    WidgetTester tester, {
    String title = 'Profile',
    bool enabled = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppHeader(
            title: title,
            onTitleTripleTap: enabled ? () => opens++ : null,
          ),
        ),
      ),
    );
  }

  setUp(() => opens = 0);

  testWidgets(
    'only three quick taps open the database, and the gesture can repeat',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Profile'));
      await tester.tap(find.text('Profile'));
      expect(opens, 0);
      await tester.tap(find.text('Profile'));
      expect(opens, 1);
      await tester.tap(find.text('Profile'));
      await tester.tap(find.text('Profile'));
      await tester.tap(find.text('Profile'));
      expect(opens, 2);
    },
  );

  testWidgets(
    'slow taps do not accumulate and title changes reset pending taps',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Profile'));
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.tap(find.text('Profile'));
      await tester.tap(find.text('Profile'));
      expect(opens, 0);
      await open(tester, title: 'Account', enabled: false);
      await open(tester);
      await tester.tap(find.text('Profile'));
      expect(opens, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('other headers have no database gesture', (tester) async {
    await open(tester, title: 'Health', enabled: false);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Health'));
    }
    expect(opens, 0);
  });

  testWidgets('screen readers have an accessible open database action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await open(tester);
    final widget = tester.widget<Semantics>(
      find
          .ancestor(of: find.text('Profile'), matching: find.byType(Semantics))
          .first,
    );
    final actions = widget.properties.customSemanticsActions!;
    expect(actions.keys.single.label, 'Open local database');
    actions.values.single();
    expect(opens, 1);
    semantics.dispose();
  });
}
