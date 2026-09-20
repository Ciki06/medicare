import 'package:flutter/material.dart';
import '../models/medication_action.dart';
import '../theme/app_theme.dart';
import '../services/schedule_time.dart';
import '../services/history_filter.dart';

class MedicationActivityCard extends StatelessWidget {
  const MedicationActivityCard({
    super.key,
    required this.action,
    required this.patientName,
    this.showDate = false,
  });

  final MedicationAction action;
  final String patientName;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.fromMillisecondsSinceEpoch(action.timestamp);
    final time = ScheduleTime.display(
      "${date.hour}:${date.minute.toString().padLeft(2, '0')}",
    );
    final (label, icon, color, _) = switch (action.action) {
      'taken' => (
        'Taken',
        Icons.check_circle_outline,
        const Color(0xFF2E8B57),
        const Color(0xFFE2F6EA),
      ),
      'skipped' || 'missed' => (
        'Missed',
        Icons.cancel_outlined,
        const Color(0xFFA0522D),
        const Color(0xFFFFE7EC),
      ),
      'snoozed' => (
        'Snoozed',
        Icons.snooze,
        const Color(0xFFB8860B),
        const Color(0xFFEDE5FF),
      ),
      _ => ('Updated', Icons.history, AppTheme.muted, const Color(0xFFF0F2F5)),
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$patientName • ${action.medicationName}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            showDate
                ? '${shortDate(date)}\n$time'
                : _relativeTime(action.timestamp),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 10, color: AppTheme.muted),
          ),
        ],
      ),
    );
  }

  String _relativeTime(int milliseconds) {
    final dt = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    final actualTime =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final difference = ScheduleTime.now().difference(dt);
    if (difference.inMinutes < 1) return '$actualTime · Now';
    if (difference.inMinutes < 60) {
      return '$actualTime · ${difference.inMinutes}m ago';
    }
    if (difference.inHours < 24) {
      return '$actualTime · ${difference.inHours}h ago';
    }
    return '$actualTime · ${difference.inDays}d ago';
  }
}
