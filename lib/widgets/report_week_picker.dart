import 'package:flutter/material.dart';
import '../services/history_filter.dart';
import '../theme/app_theme.dart';

class ReportWeekPicker extends StatefulWidget {
  const ReportWeekPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });
  final DateTime selected;
  final ValueChanged<DateTime> onChanged;
  @override
  State<ReportWeekPicker> createState() => _ReportWeekPickerState();
}

class _ReportWeekPickerState extends State<ReportWeekPicker> {
  late DateTime _month = DateTime(widget.selected.year, widget.selected.month);
  DateTime _monday(DateTime date) =>
      DateTime(date.year, date.month, date.day - date.weekday + 1);
  String _label(DateTime date) =>
      '${date.day} ${reportMonthNames[date.month - 1]}';
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final first = _monday(_month);
    final last = DateTime(_month.year, _month.month + 1, 0);
    final weeks = <DateTime>[];
    for (
      var day = first;
      !day.isAfter(last);
      day = DateTime(day.year, day.month, day.day + 7)
    ) {
      if (!day.isAfter(now)) weeks.add(day);
    }
    return Container(
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
            'Choose report week',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.navy,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Select a Monday-to-Sunday week.',
            style: TextStyle(fontSize: 12, color: AppTheme.muted),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                tooltip: 'Previous month',
                onPressed: _month.isAfter(DateTime(2000))
                    ? () => setState(
                        () => _month = DateTime(_month.year, _month.month - 1),
                      )
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                '${reportMonthNames[_month.month - 1]} ${_month.year}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: _month.isBefore(DateTime(now.year, now.month))
                    ? () => setState(
                        () => _month = DateTime(_month.year, _month.month + 1),
                      )
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: weeks.map((week) {
                final active = week == _monday(widget.selected);
                final end = DateTime(week.year, week.month, week.day + 6);
                return SizedBox(
                  width: (constraints.maxWidth - 8) / 2,
                  child: Semantics(
                    selected: active,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 8,
                        ),
                        minimumSize: const Size(0, 36),
                        textStyle: const TextStyle(fontSize: 12),
                        backgroundColor: active
                            ? AppTheme.navy
                            : const Color(0xFFF5F8FB),
                        foregroundColor: active ? Colors.white : AppTheme.navy,
                        side: BorderSide(
                          color: active
                              ? AppTheme.navy
                              : const Color(0xFFD0DFEA),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => widget.onChanged(week),
                      child: Text(
                        '${_label(week)} – ${_label(end)}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Selected: ${shortDate(_monday(widget.selected))} – ${shortDate(DateTime(widget.selected.year, widget.selected.month, widget.selected.day - widget.selected.weekday + 7))}',
            style: const TextStyle(fontSize: 12, color: AppTheme.muted),
          ),
        ],
      ),
    );
  }
}
