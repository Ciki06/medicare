import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/medication_action.dart';
import '../../models/medication_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';

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

class _ReminderMedCard extends StatelessWidget {
  const _ReminderMedCard({
    required this.medication,
    required this.onView,
    required this.onTake,
    required this.onSkip,
    required this.onSnooze,
  });

  final Medication medication;
  final VoidCallback onView;
  final VoidCallback onTake;
  final VoidCallback onSkip;
  final VoidCallback onSnooze;

  @override
  Widget build(BuildContext context) {
    final med = medication;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFECF7DD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFC4C8BC)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: med.imageUrl != null
                    ? Image.network(med.imageUrl!, width: 48, height: 48, fit: BoxFit.cover)
                    : Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.medication, color: Color(0xFF48AF75), size: 24),
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
                  onPressed: onView,
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
          Row(
            children: [
              Expanded(
                child: _ActionBtn(
                  label: 'Take', color: const Color(0xFF48AF75),
                  onTap: onTake,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _ActionBtn(
                  label: 'Skip', color: const Color(0xFFE85B61),
                  onTap: onSkip,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _ActionBtn(
                  label: 'Snooze', color: const Color(0xFFF2AE36),
                  onTap: onSnooze,
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
  const _ActionBtn({required this.label, required this.color, required this.onTap});
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
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
      case 'skipped':
        icon = '✗';
        color = const Color(0xFFE85B61);
      case 'snoozed':
        icon = '⏰';
        color = const Color(0xFFF2AE36);
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
                Text(appointment.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                Text('${appointment.date} ${appointment.time}',
                  style: const TextStyle(fontSize: 10, color: AppTheme.muted),
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
