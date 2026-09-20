import 'package:flutter/material.dart';
import '../services/history_filter.dart';
import '../theme/app_theme.dart';

class ReportMonthPicker extends StatefulWidget {
  const ReportMonthPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });
  final Set<DateTime> selected;
  final ValueChanged<Set<DateTime>> onChanged;
  @override
  State<ReportMonthPicker> createState() => _ReportMonthPickerState();
}

class _ReportMonthPickerState extends State<ReportMonthPicker> {
  late int _year = widget.selected.isEmpty
      ? DateTime.now().year
      : (widget.selected.toList()..sort()).last.year;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFD0DFEA)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Choose report months',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppTheme.navy,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Select any months.',
          style: TextStyle(fontSize: 12, color: AppTheme.muted),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              tooltip: 'Previous year',
              onPressed: _year > 2000 ? () => setState(() => _year--) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              '$_year',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            IconButton(
              tooltip: 'Next year',
              onPressed: _year < DateTime.now().year
                  ? () => setState(() => _year++)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(12, (i) {
              final month = DateTime(_year, i + 1);
              final active = widget.selected.contains(month);
              return SizedBox(
                width: (constraints.maxWidth - 24) / 4,
                child: Semantics(
                  selected: active,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      minimumSize: const Size(0, 36),
                      textStyle: const TextStyle(fontSize: 12),
                      backgroundColor: active
                          ? AppTheme.navy
                          : const Color(0xFFF5F8FB),
                      foregroundColor: active ? Colors.white : AppTheme.navy,
                      side: BorderSide(
                        color: active ? AppTheme.navy : const Color(0xFFD0DFEA),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {
                      final updated = {...widget.selected};
                      active ? updated.remove(month) : updated.add(month);
                      widget.onChanged(updated);
                    },
                    child: Text('${active ? '✓ ' : ''}${reportMonthNames[i]}'),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => widget.onChanged({
                ...widget.selected,
                for (var m = 1; m <= 12; m++) DateTime(_year, m),
              }),
              child: Text('Select all $_year'),
            ),
            TextButton(
              onPressed: widget.selected.isEmpty
                  ? null
                  : () => widget.onChanged({}),
              child: const Text('Clear All'),
            ),
          ],
        ),
        Text(
          widget.selected.isEmpty
              ? 'Select at least one month to export.'
              : selectedMonthsLabel(widget.selected),
          style: const TextStyle(fontSize: 12, color: AppTheme.muted),
        ),
      ],
    ),
  );
}
