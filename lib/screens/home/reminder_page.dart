import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/medication_action.dart';
import '../../models/medication_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/reminder_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/medicine_art.dart';
import '../../widgets/calendar_art.dart';

class ReminderPage extends StatefulWidget {
  const ReminderPage({super.key, required this.user});

  final UserModel user;

  @override
  State<ReminderPage> createState() => _ReminderPageState();
}

class _ReminderPageState extends State<ReminderPage> {
  final _firestore = FirestoreService();

  List<Medication> _meds = [];
  List<Appointment> _apts = [];
  List<MedicationAction> _actions = [];
  StreamSubscription<List<Medication>>? _medSub;
  StreamSubscription<List<Appointment>>? _aptSub;
  StreamSubscription<List<MedicationAction>>? _actionSub;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _medSub = _firestore.getMedicationsByPatient(widget.user.uid).listen((meds) {
      if (mounted) setState(() { _meds = meds; _loaded = true; });
    });
    _aptSub = _firestore.getAppointmentsByPatient(widget.user.uid).listen((apts) {
      if (mounted) setState(() { _apts = apts; _loaded = true; });
    });
    _actionSub = _firestore.getMedicationActionsByPatient(widget.user.uid).listen((actions) {
      if (mounted) setState(() { _actions = actions; _loaded = true; });
    });
  }

  @override
  void dispose() {
    _medSub?.cancel();
    _aptSub?.cancel();
    _actionSub?.cancel();
    super.dispose();
  }

  MedicationAction? _todayActionForMed(String medId) {
    final todayMs = DateTime(
      DateTime.now().year, DateTime.now().month, DateTime.now().day,
    ).millisecondsSinceEpoch;
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PatientMedicationDetail(medication: med),
    );
  }

  Future<void> _takeMedication(BuildContext context, Medication med) async {
    ReminderService().clearSnooze(med.id);
    await _firestore.logMedicationAction(
      medicationId: med.id,
      medicationName: med.name,
      patientId: widget.user.uid,
      action: 'taken',
    );
    if (med.currentStock > 0) {
      await _firestore.updateMedicationStock(med.id, med.currentStock - 1);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Medicine marked as taken')),
      );
    }
  }

  Future<void> _skipMedication(BuildContext context, Medication med) async {
    ReminderService().clearSnooze(med.id);
    await _firestore.logMedicationAction(
      medicationId: med.id,
      medicationName: med.name,
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
    final snoozedUntil = DateTime.now().millisecondsSinceEpoch + 10 * 60 * 1000;
    ReminderService().snoozeMedication(med.id, snoozedUntil);
    await _firestore.logMedicationAction(
      medicationId: med.id,
      medicationName: med.name,
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
    final recentActions = _actions.take(5).toList();

    return SingleChildScrollView(
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
          if (!_loaded)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_meds.isEmpty && _apts.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: Text('No reminders yet.', style: TextStyle(color: AppTheme.muted)),
            )
          else ...[
            if (_meds.isNotEmpty) ...[
              const Text('Medications',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppTheme.navy),
              ),
              const SizedBox(height: 10),
              ..._meds.map((med) => _ReminderMedCard(
                medication: med,
                todayAction: _todayActionForMed(med.id),
                onView: () => _showMedicineDetail(context, med),
                onTake: () => _takeMedication(context, med),
                onSkip: () => _skipMedication(context, med),
                onSnooze: () => _snoozeMedication(context, med),
              )),
            ],
            if (_apts.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('Appointments',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppTheme.navy),
              ),
              const SizedBox(height: 10),
              ..._apts.map((apt) => _ReminderAptCard(appointment: apt)),
            ],
          ],
          const SizedBox(height: 14),
          const Text(
            'Recently Missed / Snoozed',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppTheme.navy),
          ),
          const SizedBox(height: 10),
          if (recentActions.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text('No activity recorded yet.',
                style: TextStyle(color: AppTheme.muted, fontSize: 12)),
            )
          else
            ...recentActions.map((a) => _ActionHistoryCard(action: a)),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

class _ReminderMedCard extends StatefulWidget {
  const _ReminderMedCard({
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

  int? _snoozeUntilMs() {
    int? until = ReminderService().snoozeUntilMs(widget.medication.id);
    final action = widget.todayAction;
    if (action != null &&
        action.action == 'snoozed' &&
        action.snoozedUntil != null) {
      final persisted = action.snoozedUntil!;
      until = until == null ? persisted : (persisted > until ? persisted : until);
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
    final snoozeActive = action != null &&
        action.action == 'snoozed' &&
        snoozeUntil != null &&
        DateTime.now().millisecondsSinceEpoch < snoozeUntil;
    final isActed = action != null &&
        (action.action == 'taken' ||
            action.action == 'skipped' ||
            snoozeActive);
    final scheduled = med.scheduledDateTime;
    final timeReady = scheduled == null || !DateTime.now().isBefore(scheduled);
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
                    ? Image.network(med.imageUrl!, width: 48, height: 48, fit: BoxFit.cover)
                    : const SizedBox(
                        width: 48, height: 48,
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
                        const Icon(Icons.schedule, size: 14, color: AppTheme.muted),
                        const SizedBox(width: 4),
                        Text(med.time, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    Text(med.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    Text('${med.dosage} - Stock: ${med.currentStock}',
                      style: TextStyle(
                        fontSize: 11,
                        color: med.currentStock <= 5 ? Colors.red : AppTheme.muted,
                        fontWeight: med.currentStock <= 5 ? FontWeight.w700 : FontWeight.normal,
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  child: const Text('View', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
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
            Row(
              children: [
                Expanded(
                  child: _ActionBtn(
                    label: 'Take', color: const Color(0xFF48AF75),
                    enabled: buttonsEnabled,
                    onTap: () => _run(widget.onTake),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _ActionBtn(
                    label: 'Skip', color: const Color(0xFFE85B61),
                    enabled: buttonsEnabled,
                    onTap: () => _run(widget.onSkip),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _ActionBtn(
                    label: 'Snooze', color: const Color(0xFFF2AE36),
                    enabled: buttonsEnabled,
                    onTap: () => _run(widget.onSnooze),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({required this.label, required this.color, required this.onTap, this.enabled = true});
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: FilledButton(
        onPressed: enabled ? onTap : null,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: color.withValues(alpha: 0.4),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _ActionHistoryCard extends StatelessWidget {
  const _ActionHistoryCard({required this.action});
  final MedicationAction action;

  @override
  Widget build(BuildContext context) {
    String icon;
    Color color;
    switch (action.action) {
      case 'taken':
        icon = '✓';
        color = const Color(0xFF48AF75);
        break;
      case 'skipped':
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
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBFC2C5)),
      ),
      child: Row(
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(color: color.withValues(alpha: .15), borderRadius: BorderRadius.circular(7)),
            child: Center(child: Text(icon, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(action.medicationName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                Text(action.action == 'taken' ? 'Taken' : action.action == 'skipped' ? 'Skipped' : 'Snoozed',
                  style: TextStyle(fontSize: 10, color: color),
                ),
              ],
            ),
          ),
          Text(_formatTime(action.timestamp), style: const TextStyle(fontSize: 10, color: AppTheme.muted)),
        ],
      ),
    );
  }

  String _formatTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _ReminderAptCard extends StatelessWidget {
  const _ReminderAptCard({required this.appointment});
  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E72B7), width: 1.5),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 36, height: 36,
            child: CalendarArt(size: 36),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(appointment.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                Text('${appointment.date} · ${appointment.time}',
                  style: const TextStyle(fontSize: 10, color: AppTheme.navy),
                ),
                if (appointment.location.isNotEmpty)
                  Text(appointment.location, style: const TextStyle(fontSize: 10, color: AppTheme.muted)),
              ],
            ),
          ),
        ],
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
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20, right: 20, top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD0D0D0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: med.imageUrl != null
                      ? Image.network(med.imageUrl!, width: 56, height: 56, fit: BoxFit.cover)
                      : Container(
                          width: 56, height: 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.medication, color: Color(0xFF48AF75), size: 28),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(med.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.navy)),
                      Text(med.patientName, style: const TextStyle(fontSize: 13, color: AppTheme.muted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _detailRow('Time', med.time),
            _detailRow('Type', med.type),
            _detailRow('Dosage', med.dosage),
            _detailRow('Frequency', med.days.join(', ')),
            _detailRow('Stock', '${med.currentStock} units'),
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
            child: Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.muted, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
