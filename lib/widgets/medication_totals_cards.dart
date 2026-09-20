import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class MedicationTotalsCards extends StatelessWidget {
  const MedicationTotalsCards({
    super.key,
    required this.taken,
    required this.missed,
    required this.snoozed,
    this.compact = false,
  });
  final int taken, missed, snoozed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        'Taken',
        taken,
        Icons.check_circle_outline,
        const Color(0xFF18754D),
        const Color(0xFFEDF6F0),
      ),
      (
        'Missed',
        missed,
        Icons.cancel_outlined,
        const Color(0xFFAC4247),
        const Color(0xFFFBEEEE),
      ),
      (
        'Snoozed',
        snoozed,
        Icons.snooze_rounded,
        const Color(0xFF956214),
        const Color(0xFFFFF6E6),
      ),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: 8,
                vertical: compact ? 10 : 14,
              ),
              decoration: BoxDecoration(
                color: items[i].$5,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: items[i].$4.withValues(alpha: .12)),
              ),
              child: Column(
                children: [
                  if (!compact) ...[
                    Icon(items[i].$3, color: items[i].$4, size: 22),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    '${items[i].$2}',
                    style: TextStyle(
                      fontSize: compact ? 22 : 28,
                      fontWeight: FontWeight.w800,
                      color: items[i].$4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    items[i].$1,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: items[i].$4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class PatientMedicationSummary extends StatelessWidget {
  const PatientMedicationSummary({
    super.key,
    required this.name,
    required this.taken,
    required this.missed,
    required this.snoozed,
  });
  final String name;
  final int taken, missed, snoozed;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFD0DFEA)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.lightBlue,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.person_outline_rounded,
                color: AppTheme.navy,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.navy,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        MedicationTotalsCards(
          taken: taken,
          missed: missed,
          snoozed: snoozed,
          compact: true,
        ),
      ],
    ),
  );
}
