import 'package:flutter/material.dart';
import '../services/schedule_time.dart';

/// Shared Add/Edit frequency controls with an explicit recurrence anchor.
class MedicationFrequencyFields extends StatelessWidget {
  const MedicationFrequencyFields({
    super.key,
    required this.frequency,
    required this.startDate,
    required this.intervalDays,
    required this.onChanged,
  });
  final String frequency;
  final String startDate;
  final int intervalDays;
  final void Function(String frequency, String startDate, int intervalDays)
  onChanged;
  static const frequencies = [
    'Once',
    'Daily',
    'Weekly',
    'Monthly',
    'Every X days',
  ];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DropdownButtonFormField<String>(
        initialValue: frequency,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'How often should it be taken?',
          filled: true,
          fillColor: Colors.white,
        ),
        items: {
          ...frequencies,
          frequency,
        }.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
        onChanged: (f) {
          if (f != null) onChanged(f, startDate, intervalDays);
        },
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.calendar_month),
        title: Text('Start date: $startDate'),
        subtitle: const Text(ScheduleTime.zoneLabel),
        onTap: () async {
          final date = await showDatePicker(
            context: context,
            initialDate: DateTime.parse(startDate),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (date != null) {
            onChanged(frequency, ScheduleTime.dateKey(date), intervalDays);
          }
        },
      ),
      if (frequency == 'Every X days')
        DropdownButtonFormField<int>(
          initialValue: intervalDays,
          decoration: const InputDecoration(labelText: 'Repeat every'),
          items: List.generate(
            365,
            (i) =>
                DropdownMenuItem(value: i + 1, child: Text('${i + 1} day(s)')),
          ),
          onChanged: (n) {
            if (n != null) onChanged(frequency, startDate, n);
          },
        ),
      if (frequency == 'Monthly')
        const Text(
          'Repeats on this day of each month. Months without this date are skipped.',
        ),
    ],
  );
}
