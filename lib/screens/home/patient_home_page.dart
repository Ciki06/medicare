import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/medication_action.dart';
import '../../models/medication_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/reminder_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/medicine_art.dart';

class PatientHomePage extends StatefulWidget {
  const PatientHomePage({super.key, required this.user, required this.onOpenMood});

  final UserModel user;
  final VoidCallback onOpenMood;

  @override
  State<PatientHomePage> createState() => _PatientHomePageState();
}

class _PatientHomePageState extends State<PatientHomePage> {
  final _firestore = FirestoreService();
  List<Medication> _meds = [];
  List<MedicationAction> _actions = [];
  StreamSubscription<List<Medication>>? _medSub;
  StreamSubscription<List<MedicationAction>>? _actionSub;

  @override
  void initState() {
    super.initState();
    _medSub = _firestore.getMedicationsByPatient(widget.user.uid).listen((meds) {
      if (mounted) setState(() => _meds = meds);
    });
    _actionSub = _firestore.getMedicationActionsByPatient(widget.user.uid).listen((actions) {
      if (mounted) setState(() => _actions = actions);
    });
  }

  @override
  void dispose() {
    _medSub?.cancel();
    _actionSub?.cancel();
    super.dispose();
  }

  MedicationAction? _todayActionForMed(String medId) {
    final todayMs = DateTime(
      DateTime.now().year, DateTime.now().month, DateTime.now().day,
    ).millisecondsSinceEpoch;
    for (final action in _actions) {
      if (action.medicationId == medId && action.timestamp >= todayMs) {
        return action;
      }
    }
    return null;
  }

  void _showSos(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        icon: const Icon(Icons.notification_important, color: Colors.red, size: 40),
        title: const Text('SOS Alert Sent'),
        content: const Text(
          'Your caregiver has been notified.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayMeds = _meds.where((m) => m.isScheduledForDate(today)).toList()
      ..sort(Medication.compareByTime);

    Medication? nextMed;
    MedicationAction? nextMedAction;
    for (final med in todayMeds) {
      final action = _todayActionForMed(med.id);
      if (action != null && (action.action == 'taken' || action.action == 'skipped')) {
        continue;
      }
      nextMed = med;
      nextMedAction = action;
      break;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Today',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 7),
          if (_meds.isEmpty && _actions.isEmpty)
            const _HomeCard(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (todayMeds.isEmpty)
            const _HomeCard(
              child: Text('No medications scheduled today.',
                style: TextStyle(fontSize: 13)),
            )
          else if (nextMed == null)
            _HomeCard(
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Color(0xFF48AF75), size: 28),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('All medications taken for today!',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            )
          else
            _MedicationCard(
              medication: nextMed,
              todayAction: nextMedAction,
              firestore: _firestore,
              userUid: widget.user.uid,
            ),
          const SizedBox(height: 12),
          _HomeCard(
            child: Row(
              children: [
                const Icon(Icons.monitor_heart_outlined, size: 42, color: Color(0xFF2F6782)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Daily Mood',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                      const Text('How do you feel today?', style: TextStyle(fontSize: 11)),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          const Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text('🙂  🙁  😐', style: TextStyle(fontSize: 20)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: widget.onOpenMood,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.navy,
                              padding: const EdgeInsets.symmetric(horizontal: 9),
                              minimumSize: const Size(0, 32),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Start Check-in', style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          StreamBuilder(
            stream: _firestore.getAppointmentsByPatient(widget.user.uid),
            builder: (context, snap) {
              final apts = snap.data ?? [];
              if (apts.isEmpty) return const SizedBox();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Appointments',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  ...apts.map((apt) => Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF6DD),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFC4C8BC)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .6),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF8A8E84), width: 2),
                          ),
                          child: const Icon(Icons.event_available, color: Color(0xFF8A6D42), size: 18),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(apt.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                              Text('${apt.date} ${apt.time}',
                                style: const TextStyle(fontSize: 10, color: AppTheme.muted),
                              ),
                              if (apt.location.isNotEmpty)
                                Text(apt.location, style: const TextStyle(fontSize: 10, color: AppTheme.muted)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4F4),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: const Color(0xFFC8BEBE)),
            ),
            child: Column(
              children: [
                Container(
                  width: 170,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFB71C1C)),
                  ),
                  child: const Text(
                    'Emergency Support',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  key: const Key('sos-button'),
                  onTap: () => _showSos(context),
                  borderRadius: BorderRadius.circular(50),
                  child: Container(
                    width: 68, height: 68,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFE0E0),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Color(0xFFFFC6C6), blurRadius: 0, spreadRadius: 7)],
                    ),
                    child: Center(
                      child: Container(
                        width: 35, height: 35,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE94141), shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'SOS', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Press & Hold for 2 seconds',
                  style: TextStyle(fontSize: 10, color: Color(0xFF555555)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFBFC2C5)),
      ),
      child: child,
    );
  }
}

class _MedicationCard extends StatefulWidget {
  const _MedicationCard({
    required this.medication,
    required this.firestore,
    required this.userUid,
    this.todayAction,
  });

  final Medication medication;
  final FirestoreService firestore;
  final String userUid;
  final MedicationAction? todayAction;

  @override
  State<_MedicationCard> createState() => _MedicationCardState();
}

class _MedicationCardState extends State<_MedicationCard> {
  bool _processing = false;

  bool get _taken => widget.todayAction?.action == 'taken';
  bool get _skipped => widget.todayAction?.action == 'skipped';
  bool get _snoozed => widget.todayAction?.action == 'snoozed';

  Future<void> _take() async {
    if (_processing) return;
    setState(() => _processing = true);
    final med = widget.medication;
    ReminderService().clearSnooze(med.id);
    await widget.firestore.logMedicationAction(
      medicationId: med.id,
      medicationName: med.name,
      patientId: widget.userUid,
      action: 'taken',
    );
    if (med.currentStock > 0) {
      await widget.firestore.updateMedicationStock(med.id, med.currentStock - 1);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Medicine marked as taken')),
      );
    }
  }

  Future<void> _skip() async {
    if (_processing) return;
    setState(() => _processing = true);
    final med = widget.medication;
    ReminderService().clearSnooze(med.id);
    await widget.firestore.logMedicationAction(
      medicationId: med.id,
      medicationName: med.name,
      patientId: widget.userUid,
      action: 'skipped',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Medicine marked as skipped')),
      );
    }
  }

  Future<void> _snooze() async {
    if (_processing) return;
    setState(() => _processing = true);
    final snoozedUntil = DateTime.now().millisecondsSinceEpoch + 10 * 60 * 1000;
    final med = widget.medication;
    ReminderService().snoozeMedication(med.id, snoozedUntil);
    await widget.firestore.logMedicationAction(
      medicationId: med.id,
      medicationName: med.name,
      patientId: widget.userUid,
      action: 'snoozed',
      snoozedUntil: snoozedUntil,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reminder snoozed for 10 minutes')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final med = widget.medication;
    final scheduled = med.scheduledDateTime;
    final timeReady = scheduled == null || !DateTime.now().isBefore(scheduled);
    final buttonsEnabled = !_processing && !_taken && !_skipped && timeReady;
    return _HomeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Next Medicine',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: med.imageUrl != null
                    ? Image.network(med.imageUrl!, width: 56, height: 56, fit: BoxFit.cover)
                    : const SizedBox(
                        width: 56, height: 56,
                        child: MedicineArt(size: 56),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      med.time,
                      style: const TextStyle(
                        color: AppTheme.navy, fontSize: 20, fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(med.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    Text(med.dosage, style: const TextStyle(fontSize: 10)),
                    Text('Stock: ${med.currentStock}',
                      style: TextStyle(
                        fontSize: 11, color: med.currentStock <= 5 ? Colors.red : AppTheme.muted,
                        fontWeight: med.currentStock <= 5 ? FontWeight.w700 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          if (_taken || _skipped)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: (_taken ? const Color(0xFF48AF75) : const Color(0xFFE85B61)).withValues(alpha: .12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _taken ? Icons.check_circle : Icons.cancel,
                    color: _taken ? const Color(0xFF48AF75) : const Color(0xFFE85B61),
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _taken ? 'Taken' : 'Skipped',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _taken ? const Color(0xFF48AF75) : const Color(0xFFE85B61),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            if (_snoozed)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2AE36).withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.alarm, color: Color(0xFFF2AE36), size: 14),
                    SizedBox(width: 4),
                    Text('Snoozed - will remind again soon',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFF2AE36)),
                    ),
                  ],
                ),
              ),
            if (!timeReady)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.navy.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.lock_clock, color: AppTheme.navy, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'Available at ${med.time}',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.navy),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: 'Take', color: const Color(0xFF48AF75),
                    enabled: buttonsEnabled,
                    onTap: _take,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionButton(
                    label: 'Skip', color: const Color(0xFFE85B61),
                    enabled: buttonsEnabled,
                    onTap: _skip,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionButton(
                    label: 'Snooze', color: const Color(0xFFF2AE36),
                    enabled: buttonsEnabled,
                    onTap: _snooze,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.color, required this.onTap, this.enabled = true});
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
