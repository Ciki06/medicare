import '../../widgets/medication_meal_timing.dart';
import '../../services/schedule_time.dart';
import '../../widgets/appointment_details_dialog.dart';
import '../../widgets/offline_image.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/medication_action.dart';
import '../../models/medication_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';
import '../../services/reminder_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/medicine_art.dart';
import '../../widgets/calendar_art.dart';
import '../../widgets/patient_medication_actions.dart';
import 'patient_appointment_history.dart';
import 'patient_medication_history.dart';

class ReminderPage extends StatefulWidget {
  const ReminderPage({
    super.key,
    required this.user,
    this.firestore,
    this.medicationTap,
  });

  final UserModel user;
  final FirestoreService? firestore;
  final (String, int)? medicationTap;

  @override
  State<ReminderPage> createState() => _ReminderPageState();
}

class _ReminderPageState extends State<ReminderPage> {
  late final _firestore = widget.firestore ?? FirestoreService();
  final _scrollController = ScrollController();

  List<Medication> _meds = [];
  List<Appointment> _apts = [];
  List<MedicationAction> _actions = [];
  StreamSubscription<List<Medication>>? _medSub;
  StreamSubscription<List<Appointment>>? _aptSub;
  StreamSubscription<List<MedicationAction>>? _actionSub;
  bool _medicationsLoading = true;
  bool _medicationLoadFailed = false;

  @override
  void initState() {
    super.initState();
    _medSub = _firestore
        .getMedicationsByPatient(widget.user.uid)
        .listen(
          (meds) {
            if (!mounted) return;
            setState(() {
              _meds = meds;
              _medicationsLoading = false;
              _medicationLoadFailed = false;
            });
          },
          onError: (Object _, StackTrace _) {
            if (!mounted) return;
            setState(() {
              _medicationsLoading = false;
              _medicationLoadFailed = true;
            });
          },
          onDone: () {
            if (!mounted || !_medicationsLoading) return;
            setState(() => _medicationsLoading = false);
          },
        );
    _aptSub = _firestore.getAppointmentsByPatient(widget.user.uid).listen((
      apts,
    ) {
      if (mounted) {
        setState(() {
          _apts = apts;
        });
      }
    });
    _actionSub = _firestore
        .getMedicationActionsByPatient(widget.user.uid)
        .listen((actions) {
          if (mounted) {
            setState(() {
              _actions = actions;
            });
          }
        });
  }

  @override
  void didUpdateWidget(covariant ReminderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.medicationTap != widget.medicationTap &&
        widget.medicationTap != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _medSub?.cancel();
    _aptSub?.cancel();
    _actionSub?.cancel();
    super.dispose();
  }

  MedicationAction? _todayActionForMed(String medId) {
    final todayMs = ScheduleTime.startOfToday().millisecondsSinceEpoch;
    MedicationAction? latest;
    for (final action in _actions) {
      if (action.medicationId == medId && action.timestamp >= todayMs) {
        if (latest == null || action.timestamp > latest.timestamp) {
          latest = action;
        }
      }
    }
    return latest;
  }

  void _showMedicineDetail(BuildContext context, Medication med) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 440,
            maxHeight: MediaQuery.sizeOf(ctx).height * .8,
          ),
          child: _PatientMedicationDetail(medication: med),
        ),
      ),
    );
  }

  Future<void> _takeMedication(BuildContext context, Medication med) async {
    NotificationService.instance.cancelMedicationReminder(med.id);
    ReminderService().clearSnooze(med.id);
    await _firestore.logMedicationAction(
      medicationId: med.id,
      medicationName: med.name,
      dosage: med.displayDosage,
      patientId: widget.user.uid,
      action: 'taken',
    );
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Medicine marked as taken')));
    }
  }

  Future<void> _skipMedication(BuildContext context, Medication med) async {
    NotificationService.instance.cancelMedicationReminder(med.id);
    ReminderService().clearSnooze(med.id);
    await _firestore.logMedicationAction(
      medicationId: med.id,
      medicationName: med.name,
      dosage: med.displayDosage,
      patientId: widget.user.uid,
      action: 'skipped',
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Medicine marked as skipped')),
      );
    }
  }

  Future<void> _snoozeMedication(BuildContext context, Medication med) async {
    final snoozedUntil =
        ScheduleTime.now().millisecondsSinceEpoch + 10 * 60 * 1000;
    ReminderService().snoozeMedication(med.id, snoozedUntil);
    NotificationService.instance.scheduleSnoozeReminder(
      medId: med.id,
      medName: med.name,
      dosage: med.displayDosage,
      medicationType: med.type,
      when: DateTime.fromMillisecondsSinceEpoch(snoozedUntil),
    );
    await _firestore.logMedicationAction(
      medicationId: med.id,
      medicationName: med.name,
      dosage: med.displayDosage,
      patientId: widget.user.uid,
      action: 'snoozed',
      snoozedUntil: snoozedUntil,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reminder snoozed for 10 minutes')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final recentActions = recentPatientMedicationActivity(
      actions: _actions,
      patientId: widget.user.uid,
    );
    final upcomingMeds = _meds.where((med) => !med.isCompleted).toList();
    final targetId = widget.medicationTap?.$1;
    final targetIndex = upcomingMeds.indexWhere((med) => med.id == targetId);
    if (targetIndex > 0) {
      upcomingMeds.insert(0, upcomingMeds.removeAt(targetIndex));
    }

    bool isCompleted(Appointment apt) => apt.status == 'completed';

    final upcomingApts = _apts.where((apt) => !isCompleted(apt)).toList();
    final completedApts = recentCompletedPatientAppointments(
      appointments: _apts,
      patientId: widget.user.uid,
    );

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 15, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFBFC2C5)),
            ),
            child: const Text(
              'Upcoming Reminders',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 16),
          if (_medicationsLoading)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if (_medicationLoadFailed)
              const Text(
                'Unable to load medication reminders. Please try again later.',
                style: TextStyle(color: AppTheme.muted, fontSize: 13),
              ),
            if (!_medicationLoadFailed && upcomingMeds.isEmpty)
              const Text(
                'No medication reminders',
                style: TextStyle(color: AppTheme.muted, fontSize: 13),
              ),
            if (!_medicationLoadFailed && targetId != null && targetIndex < 0)
              const Text('This medication reminder is no longer available.'),
            if (upcomingMeds.isNotEmpty) ...[
              const Text(
                'Medications',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.navy,
                ),
              ),
              const SizedBox(height: 10),
              ...upcomingMeds.map(
                (med) => _ReminderMedCard(
                  key: ValueKey(med.id),
                  medication: med,
                  todayAction: _todayActionForMed(med.id),
                  onView: () => _showMedicineDetail(context, med),
                  onTake: () => _takeMedication(context, med),
                  onSkip: () => _skipMedication(context, med),
                  onSnooze: () => _snoozeMedication(context, med),
                ),
              ),
            ],
            const SizedBox(height: 14),
            const Text(
              'Appointments',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: AppTheme.navy,
              ),
            ),
            const SizedBox(height: 10),
            if (upcomingApts.isNotEmpty)
              ...upcomingApts.map((apt) => _ReminderAptCard(appointment: apt))
            else
              const Text(
                'No appointment...',
                style: TextStyle(color: AppTheme.muted, fontSize: 13),
              ),
            if (completedApts.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'Completed Appointments',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.navy,
                ),
              ),
              const SizedBox(height: 10),
              ...completedApts.map(
                (apt) => _ReminderAptCard(appointment: apt, completed: true),
              ),
            ],
          ],
          const SizedBox(height: 14),
          const Text(
            'Recent Medication Activity',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: AppTheme.navy,
            ),
          ),
          const SizedBox(height: 10),
          if (recentActions.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'No activity recorded yet.',
                style: TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
            )
          else
            ...recentActions.map((a) {
              final medication = _meds
                  .where(
                    (med) =>
                        med.patientId == a.patientId &&
                        med.id == a.medicationId,
                  )
                  .firstOrNull;
              return _ActionHistoryCard(
                action: a,
                isCompleted:
                    medication != null &&
                    medication.isCompleted &&
                    medication.completedAt == a.timestamp &&
                    a.action == 'taken',
                onView: medication == null
                    ? null
                    : () => _showMedicineDetail(context, medication),
              );
            }),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

class _ReminderMedCard extends StatefulWidget {
  const _ReminderMedCard({
    super.key,
    required this.medication,
    required this.onView,
    required this.onTake,
    required this.onSkip,
    required this.onSnooze,
    this.todayAction,
  });

  final Medication medication;
  final MedicationAction? todayAction;
  final VoidCallback onView;
  final Future<void> Function() onTake;
  final Future<void> Function() onSkip;
  final Future<void> Function() onSnooze;

  @override
  State<_ReminderMedCard> createState() => _ReminderMedCardState();
}

class _ReminderMedCardState extends State<_ReminderMedCard> {
  bool _processing = false;

  // Keep the later snooze deadline while saved and in-memory values update.
  int? _snoozeUntilMs() {
    int? until = ReminderService().snoozeUntilMs(widget.medication.id);
    final action = widget.todayAction;
    if (action != null &&
        action.action == 'snoozed' &&
        action.snoozedUntil != null) {
      final persisted = action.snoozedUntil!;
      until = until == null
          ? persisted
          : (persisted > until ? persisted : until);
    }
    return until;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final med = widget.medication;
    final action = widget.todayAction;
    final snoozeUntil = _snoozeUntilMs();
    final snoozeActive =
        action != null &&
        action.action == 'snoozed' &&
        snoozeUntil != null &&
        ScheduleTime.now().millisecondsSinceEpoch < snoozeUntil;
    final isActed =
        action != null &&
        (action.action == 'taken' ||
            action.action == 'skipped' ||
            snoozeActive);
    final scheduled = med.scheduledDateTime;
    final timeReady =
        scheduled == null || !ScheduleTime.now().isBefore(scheduled);
    final buttonsEnabled = !_processing && !isActed && timeReady;

    String? badgeText;
    Color? badgeColor;
    if (action != null) {
      switch (action.action) {
        case 'taken':
          badgeText = 'Taken';
          badgeColor = const Color(0xFF48AF75);
          break;
        case 'skipped':
          badgeText = 'Skipped';
          badgeColor = const Color(0xFFE85B61);
          break;
        case 'snoozed':
          if (snoozeActive) {
            badgeText = 'Snoozed';
            badgeColor = const Color(0xFFF2AE36);
          }
          break;
      }
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFBFC2C5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: med.imageUrl != null
                    ? OfflineImage(
                        med.imageUrl!,
                        zoomable: true,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox(
                          width: 48,
                          height: 48,
                          child: MedicineArt(size: 48),
                        ),
                      )
                    : const SizedBox(
                        width: 48,
                        height: 48,
                        child: MedicineArt(size: 48),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.schedule,
                          size: 14,
                          color: AppTheme.muted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          med.displayTime,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      med.name,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    MedicationMealTimingLabel(value: med.mealTiming),
                    Text(
                      '${med.displayDosage} - Stock: ${med.currentStock}',
                      style: TextStyle(
                        fontSize: 11,
                        color: med.currentStock <= 5
                            ? Colors.red
                            : AppTheme.muted,
                        fontWeight: med.currentStock <= 5
                            ? FontWeight.w700
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 28,
                child: TextButton(
                  onPressed: widget.onView,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: Size.zero,
                    backgroundColor: AppTheme.navy,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: const Text(
                    'View',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (badgeText != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: badgeColor!.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    action!.action == 'taken'
                        ? Icons.check_circle
                        : action.action == 'skipped'
                        ? Icons.cancel
                        : Icons.alarm,
                    color: badgeColor,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    badgeText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: badgeColor,
                    ),
                  ),
                ],
              ),
            )
          else
            PatientMedicationActions(
              spacing: 6,
              enabled: buttonsEnabled,
              onTake: () => _run(widget.onTake),
              onSkip: () => _run(widget.onSkip),
              onSnooze: () => _run(widget.onSnooze),
            ),
        ],
      ),
    );
  }
}

class _ActionHistoryCard extends StatelessWidget {
  const _ActionHistoryCard({
    required this.action,
    this.isCompleted = false,
    this.onView,
  });
  final MedicationAction action;
  final bool isCompleted;
  final VoidCallback? onView;

  @override
  Widget build(BuildContext context) {
    final dosage = action.dosage?.trim();
    String icon;
    Color color;
    switch (action.action) {
      case 'taken':
        icon = '✓';
        color = const Color(0xFF48AF75);
        break;
      case 'skipped':
      case 'missed':
        icon = '✗';
        color = const Color(0xFFE85B61);
        break;
      case 'snoozed':
        icon = '⏰';
        color = const Color(0xFFF2AE36);
        break;
      default:
        icon = '?';
        color = AppTheme.muted;
    }
    return GestureDetector(
      onTap: onView,
      child: Container(
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
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Center(
                child: Text(
                  icon,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action.medicationName,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (dosage != null && dosage.isNotEmpty)
                    Text(
                      'Dosage: $dosage',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.muted,
                      ),
                    ),
                  Text(switch (action.action) {
                    'taken' => isCompleted ? 'Completed' : 'Taken',
                    'skipped' => 'Skipped',
                    'missed' => 'Missed',
                    'snoozed' => 'Snoozed',
                    _ => 'Updated',
                  }, style: TextStyle(fontSize: 10, color: color)),
                ],
              ),
            ),
            Text(
              _formatTime(action.timestamp),
              style: const TextStyle(fontSize: 10, color: AppTheme.muted),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = ScheduleTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _ReminderAptCard extends StatelessWidget {
  const _ReminderAptCard({required this.appointment, this.completed = false});
  final Appointment appointment;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        try {
          await showPatientAppointmentDetails(context, appointment);
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not open the appointment. Please retry.'),
              ),
            );
          }
        }
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: completed
                ? const Color(0xFF48AF75)
                : const Color(0xFF2E72B7),
            width: completed ? 1.5 : 1.5,
          ),
        ),
        child: Row(
          children: [
            completed
                ? Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Color(0xFF48AF75),
                      size: 18,
                    ),
                  )
                : const SizedBox(
                    width: 36,
                    height: 36,
                    child: CalendarArt(size: 36),
                  ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appointment.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                  Text(
                    '${appointment.date} · ${appointment.displayTime}',
                    style: TextStyle(
                      fontSize: 10,
                      color: completed ? AppTheme.muted : AppTheme.navy,
                    ),
                  ),
                  if (appointment.location.isNotEmpty)
                    Text(
                      appointment.location,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.muted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientMedicationDetail extends StatelessWidget {
  const _PatientMedicationDetail({required this.medication});
  final Medication medication;

  @override
  Widget build(BuildContext context) {
    final med = medication;
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = constraints.maxWidth - 32;
        final imageSize = contentWidth < 240 ? 56.0 : 72.0;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: med.imageUrl != null
                          ? OfflineImage(
                              med.imageUrl!,
                              zoomable: true,
                              width: imageSize,
                              height: imageSize,
                              fit: BoxFit.contain,
                            )
                          : Container(
                              width: imageSize,
                              height: imageSize,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F5E1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.medication,
                                color: const Color(0xFF48AF75),
                                size: imageSize * .5,
                              ),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            med.name,
                            softWrap: true,
                            style: TextStyle(
                              fontSize: contentWidth < 280 ? 18 : 20,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.navy,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            med.patientName,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close, size: 22),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _detailRow('Time', med.displayTime),
                _detailRow('Type', med.type),
                _detailRow('Dosage', med.displayDosage),
                if (med.mealTiming != null)
                  _detailRow('Meals', med.mealTiming!),
                _detailRow('Frequency', med.days.join(', ')),
                _detailRow('Stock', '${med.currentStock} units'),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
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
