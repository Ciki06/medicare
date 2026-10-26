import 'package:flutter/material.dart';

import '../models/medication_model.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/reminder_service.dart';
import '../services/schedule_time.dart';
import '../theme/app_theme.dart';

/// Opening an upcoming schedule is different from acknowledging a due alert.
/// Patients can still complete an appointment after dismissing its reminder.
Future<void> showPatientAppointmentDetails(
  BuildContext context,
  Appointment appointment, {
  FirestoreService? firestore,
}) async {
  final records = firestore ?? FirestoreService();
  final due = appointment.reminderAt;
  if (due != null && !due.isAfter(ScheduleTime.now())) {
    await NotificationService.instance.cancelAppointmentReminder(
      appointment.id,
    );
    await records.markAppointmentReminderViewed(appointment);
    ReminderService().markAppointmentHandled(appointment.id, due);
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      if (appointment.status == 'completed') {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 440,
              maxHeight: MediaQuery.sizeOf(dialogContext).height * .8,
            ),
            child: _CompletedAppointmentDetail(appointment: appointment),
          ),
        );
      }
      return AlertDialog(
        title: Text(appointment.title),
        content: SingleChildScrollView(
          child: Text(
            '${appointment.date} · ${appointment.displayTime}'
            '${appointment.location.isEmpty ? '' : '\n\n${appointment.location}'}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          if (appointment.status != 'completed')
            FilledButton(
              onPressed: () async {
                try {
                  await NotificationService.instance.cancelAppointmentReminder(
                    appointment.id,
                  );
                  await records.updateAppointmentStatus(
                    appointment.id,
                    'completed',
                  );
                  if (due != null) {
                    ReminderService().markAppointmentHandled(
                      appointment.id,
                      due,
                    );
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                } catch (_) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Could not complete the appointment. Please retry.',
                        ),
                      ),
                    );
                  }
                }
              },
              child: const Text('Complete appointment'),
            ),
        ],
      );
    },
  );
}

class _CompletedAppointmentDetail extends StatelessWidget {
  const _CompletedAppointmentDetail({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.event_available,
                    color: Color(0xFF48AF75),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appointment.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.navy,
                        ),
                      ),
                      Text(
                        appointment.patientName,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _detailRow('Date', appointment.date),
            _detailRow('Time', appointment.displayTime),
            if (appointment.location.isNotEmpty)
              _detailRow('Location', appointment.location),
            _detailRow('Status', 'Completed'),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
