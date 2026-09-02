import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/widgets/sos_countdown_overlay.dart';

void main() {
  testWidgets('SOS countdown can be cancelled before dispatch', (tester) async {
    var sent = false;
    var cancelled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: SosCountdownOverlay(
          durationSeconds: 5,
          onComplete: () => sent = true,
          onCancel: () => cancelled = true,
        ),
      ),
    );

    expect(find.text('5'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Cancel'));
    await tester.pump();

    expect(cancelled, isTrue);
    expect(sent, isFalse);
    await tester.pump(const Duration(seconds: 6));
    expect(sent, isFalse);
  });

  testWidgets('three-second SOS countdown dispatches after the delay', (
    tester,
  ) async {
    var sent = false;

    await tester.pumpWidget(
      MaterialApp(
        home: SosCountdownOverlay(
          durationSeconds: 3,
          onComplete: () => sent = true,
        ),
      ),
    );

    expect(find.text('3'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(sent, isTrue);
  });
}
