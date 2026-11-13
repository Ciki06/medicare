import 'dart:async';

import 'package:flutter/material.dart';

import '../models/medication_action.dart';
import '../services/reminder_service.dart';

class PatientMedicationActions extends StatefulWidget {
  const PatientMedicationActions({
    super.key,
    required this.medicationId,
    required this.todayAction,
    required this.onTake,
    required this.onSkip,
    required this.onSnooze,
    this.enabled = true,
    this.beforeActions,
  });

  final String medicationId;
  final MedicationAction? todayAction;
  final VoidCallback onTake, onSkip, onSnooze;
  final bool enabled;
  final Widget? beforeActions;

  @override
  State<PatientMedicationActions> createState() =>
      _PatientMedicationActionsState();
}

class _PatientMedicationActionsState extends State<PatientMedicationActions> {
  final _reminders = ReminderService();
  Timer? _snoozeExpiry;

  int? get _snoozeUntil =>
      _reminders.activeSnoozeUntil(widget.medicationId, widget.todayAction);

  @override
  void initState() {
    super.initState();
    _reminders.addListener(_refreshSnooze);
    _scheduleSnoozeExpiry();
  }

  @override
  void didUpdateWidget(covariant PatientMedicationActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleSnoozeExpiry();
  }

  void _scheduleSnoozeExpiry() {
    _snoozeExpiry?.cancel();
    final until = _snoozeUntil;
    if (until == null) return;
    _snoozeExpiry = Timer(
      Duration(milliseconds: until - DateTime.now().millisecondsSinceEpoch),
      _refreshSnooze,
    );
  }

  void _refreshSnooze() {
    setState(_scheduleSnoozeExpiry);
  }

  @override
  void dispose() {
    _snoozeExpiry?.cancel();
    _reminders.removeListener(_refreshSnooze);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badge = switch (widget.todayAction?.action) {
      'taken' => ('Taken', const Color(0xFF48AF75), Icons.check_circle),
      'skipped' => ('Skipped', const Color(0xFFE85B61), Icons.cancel),
      _ when _snoozeUntil != null => (
        'Snoozed',
        const Color(0xFFF2AE36),
        Icons.alarm,
      ),
      _ => null,
    };
    if (badge != null) {
      final (label, color, icon) = badge;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      );
    }
    const style = TextStyle(fontSize: 11, fontWeight: FontWeight.w700);
    final buttons = Row(
      children: [
        for (final (index, action) in [
          ('Take', const Color(0xFF48AF75), widget.onTake),
          ('Skip', const Color(0xFFE85B61), widget.onSkip),
          ('Snooze', const Color(0xFFF2AE36), widget.onSnooze),
        ].indexed) ...[
          if (index != 0) const SizedBox(width: 6),
          Expanded(
            child: SizedBox(
              height: 32,
              child: FilledButton(
                onPressed: widget.enabled
                    ? () {
                        if (_snoozeUntil == null) action.$3();
                      }
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: action.$2,
                  disabledBackgroundColor: action.$2.withValues(alpha: .4),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(action.$1, maxLines: 1, style: style),
                ),
              ),
            ),
          ),
        ],
      ],
    );
    final beforeActions = widget.beforeActions;
    return beforeActions == null
        ? buttons
        : Column(children: [beforeActions, buttons]);
  }
}
