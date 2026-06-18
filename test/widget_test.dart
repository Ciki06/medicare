import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/main.dart';

void main() {
  testWidgets('login opens patient home and navigation works', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MediCareApp());

    expect(find.text('MediCare'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);

    await tester.tap(find.byKey(const Key('login-button')));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Daily Mood'), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav-1')));
    await tester.pumpAndSettle();

    expect(find.text('Upcoming Reminders'), findsOneWidget);
    expect(find.text('Recently Missed / Snoozed'), findsOneWidget);
  });
}
