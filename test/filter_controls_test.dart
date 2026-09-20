import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/widgets/medication_activity_filter.dart';
import 'package:medicare/widgets/report_month_picker.dart';
import 'package:medicare/widgets/report_week_picker.dart';

void main() {
  testWidgets('weekly picker selects a full week across the year boundary', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var selected = DateTime(2026, 1, 14);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ReportWeekPicker(
              selected: selected,
              onChanged: (v) => setState(() => selected = v),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('29 Dec – 4 Jan'));
    await tester.pump();
    expect(selected, DateTime(2025, 12, 29));
    expect(find.text('Selected: 29/12/2025 – 4/1/2026'), findsOneWidget);
    expect(find.byType(CalendarDatePicker), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Clear All resets filter values and visible input', (
    tester,
  ) async {
    MedicationActivityCriteria? criteria;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MedicationActivityFilter(
              patients: const [],
              onChanged: (v) => criteria = v,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Filter medication activity'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Paracetamol');
    await tester.tap(find.text('All statuses'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Snoozed').last);
    await tester.pumpAndSettle();
    expect(criteria!.status, 'snoozed');
    await tester.tap(find.text('Clear All'));
    await tester.pumpAndSettle();
    expect(criteria!.status, isNull);
    expect(criteria!.name, isEmpty);
    expect(criteria!.patientId, isNull);
    expect(criteria!.range, isNull);
    expect(find.text('Paracetamol'), findsNothing);
    expect(find.text('All statuses'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('month grid selects non-consecutive months at phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Set<DateTime> months = {DateTime(2026, 1)};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => ReportMonthPicker(
                selected: months,
                onChanged: (v) => setState(() => months = v),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(OutlinedButton), findsNWidgets(12));
    await tester.tap(find.text('Mar'));
    await tester.pump();
    expect(months, {DateTime(2026, 1), DateTime(2026, 3)});
    expect(find.byType(CalendarDatePicker), findsNothing);
    await tester.tap(find.text('Clear All'));
    await tester.pump();
    expect(months, isEmpty);
    expect(find.text('Select at least one month to export.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
