import 'package:flutter/material.dart';

import '../../models/medication_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/medicine_art.dart';

class PatientHomePage extends StatelessWidget {
  const PatientHomePage({super.key, required this.user, required this.onOpenMood});

  final UserModel user;
  final VoidCallback onOpenMood;

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
    final firestore = FirestoreService();

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
          StreamBuilder(
            stream: firestore.getMedicationsByPatient(user.uid),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const _HomeCard(
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final meds = snapshot.data ?? [];
              if (meds.isEmpty) {
                return const _HomeCard(
                  child: Text('No medications scheduled today.',
                    style: TextStyle(fontSize: 13)),
                );
              }
              final med = meds.first;
              return _MedicationCard(
                medication: med,
                firestore: firestore,
                userUid: user.uid,
              );
            },
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
                            onPressed: onOpenMood,
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
            stream: firestore.getAppointmentsByPatient(user.uid),
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

class _MedicationCard extends StatelessWidget {
  const _MedicationCard({
    required this.medication,
    required this.firestore,
    required this.userUid,
  });

  final Medication medication;
  final FirestoreService firestore;
  final String userUid;

  Future<void> _take(BuildContext context) async {
    final med = medication;
    await firestore.logMedicationAction(
      medicationId: med.id,
      medicationName: med.name,
      patientId: userUid,
      action: 'taken',
    );
    if (med.currentStock > 0) {
      await firestore.updateMedicationStock(med.id, med.currentStock - 1);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Medicine marked as taken')),
      );
    }
  }

  Future<void> _skip(BuildContext context) async {
    await firestore.logMedicationAction(
      medicationId: medication.id,
      medicationName: medication.name,
      patientId: userUid,
      action: 'skipped',
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Medicine marked as skipped')),
      );
    }
  }

  Future<void> _snooze(BuildContext context) async {
    final snoozedUntil = DateTime.now().millisecondsSinceEpoch + 10 * 60 * 1000;
    await firestore.logMedicationAction(
      medicationId: medication.id,
      medicationName: medication.name,
      patientId: userUid,
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
    final med = medication;
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
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: 'Take', color: const Color(0xFF48AF75),
                  onTap: () => _take(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  label: 'Skip', color: const Color(0xFFE85B61),
                  onTap: () => _skip(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  label: 'Snooze', color: const Color(0xFFF2AE36),
                  onTap: () => _snooze(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.color, required this.onTap});
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 29,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
