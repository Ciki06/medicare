import 'package:flutter/material.dart';
import '../services/history_filter.dart';

class DateRangeFilter extends StatelessWidget {
  const DateRangeFilter({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final DateTimeRange? value;
  final ValueChanged<DateTimeRange?> onChanged;
  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      OutlinedButton.icon(
        icon: const Icon(Icons.date_range),
        label: Text(
          value == null
              ? 'All dates'
              : '${shortDate(value!.start)} – ${shortDate(value!.end)}',
        ),
        onPressed: () async {
          final range = await showDateRangePicker(
            context: context,
            firstDate: DateTime(2000),
            lastDate: DateTime.now().add(const Duration(days: 365)),
            initialDateRange: value,
          );
          if (range != null) onChanged(range);
        },
      ),
      if (value != null)
        IconButton(
          tooltip: 'Clear dates',
          onPressed: () => onChanged(null),
          icon: const Icon(Icons.close),
        ),
    ],
  );
}
