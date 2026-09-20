import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/models/mood_model.dart';
import 'package:medicare/widgets/home_monitoring_sections.dart';

void main() {
  testWidgets(
    'mood history expands, filters, and clears back to five records',
    (tester) async {
      final records = List.generate(
        8,
        (i) => DailyMood(
          id: '$i',
          patientId: 'p',
          moodIndex: i.isEven ? 2 : 6,
          moodLabel: i.isEven ? 'Happy' : 'Sad',
          emoji: '',
          date: '2026-09-18',
          timestamp: i,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DailyMoodSection(
                patients: const [],
                moodStream: Stream.value(records),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNWidgets(5));
      await tester.ensureVisible(find.text('View More'));
      await tester.tap(find.text('View More'));
      await tester.pump();
      expect(find.byType(ListTile), findsNWidgets(8));
      await tester.ensureVisible(find.text('Show Less'));
      await tester.tap(find.text('Show Less'));
      await tester.pump();
      expect(find.byType(ListTile), findsNWidgets(5));
      await tester.ensureVisible(find.byTooltip('Filter moods'));
      await tester.tap(find.byTooltip('Filter moods'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilterChip, 'Happy'));
      await tester.pump();
      expect(find.byType(ListTile), findsNWidgets(4));
      expect(find.text('Patient • Sad'), findsNothing);
      await tester.tap(find.text('Clear All'));
      await tester.pump();
      expect(find.byType(ListTile), findsNWidgets(5));
      await tester.tap(find.widgetWithText(FilterChip, 'Angry'));
      await tester.pump();
      expect(find.text('No mood records match these filters.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
