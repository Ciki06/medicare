import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/medication_model.dart';
import '../../models/user_model.dart';
import '../../models/user_role.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import 'add_medication_page.dart';

class MedicationPage extends StatelessWidget {
  const MedicationPage({super.key, required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _MedicationContent(user: user),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
          ),
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AddMedicationPage(caregiver: user),
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Medication', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.navy,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _showAddAppointmentDialog(context, user),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Appointment', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE69A31),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showAddAppointmentDialog(BuildContext context, UserModel user) {
    final titleCtrl = TextEditingController();
    final dateCtrl = TextEditingController();
    final timeCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? selectedPatientId;
    String selectedPatientName = '';

    showDialog(
      context: context,
      builder: (ctx) {
        return StreamBuilder<List<UserModel>>(
          stream: FirestoreService().getPatientsByCaregiver(user.uid),
          builder: (context, snap) {
            final patients = snap.data ?? [];
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Add Appointment'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: titleCtrl,
                        decoration: const InputDecoration(labelText: 'Title', hintText: "e.g. Doctor's Appointment"),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: dateCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Date', hintText: 'e.g. 2026-06-20', prefixIcon: Icon(Icons.calendar_today),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: timeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Time', hintText: 'e.g. 04:00 PM', prefixIcon: Icon(Icons.schedule),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: locationCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Location', hintText: 'e.g. City Medical Centre', prefixIcon: Icon(Icons.location_on),
                        ),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(labelText: 'Patient'),
                        items: patients
                            .map((p) => DropdownMenuItem(value: p.uid, child: Text(p.name)))
                            .toList(),
                        onChanged: (v) {
                          selectedPatientId = v;
                          selectedPatientName = patients.firstWhere((p) => p.uid == v).name;
                        },
                        validator: (v) => v == null ? 'Select a patient' : null,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate() || selectedPatientId == null) return;
                    final apt = Appointment(
                      id: '',
                      title: titleCtrl.text.trim(),
                      date: dateCtrl.text.trim(),
                      time: timeCtrl.text.trim(),
                      location: locationCtrl.text.trim(),
                      patientId: selectedPatientId!,
                      patientName: selectedPatientName,
                      caregiverId: user.uid,
                    );
                    await FirestoreService().createAppointment(apt);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _MedicationContent extends StatelessWidget {
  const _MedicationContent({required this.user});
  final UserModel user;

  void _showMedicationDetail(BuildContext context, Medication med, UserModel patient) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _MedicationDetailSheet(medication: med, patientName: patient.name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firestore = FirestoreService();
    final ctx = context;

    return StreamBuilder<List<UserModel>>(
      stream: firestore.getPatientsByCaregiver(user.uid),
      builder: (_, patSnap) {
        final patients = patSnap.data ?? [];
        return StreamBuilder<List<Medication>>(
          stream: firestore.getMedicationsByCaregiver(user.uid),
          builder: (_, medSnap) {
            final meds = medSnap.data ?? [];
            return StreamBuilder<List<Appointment>>(
              stream: firestore.getAppointmentsByCaregiver(user.uid),
              builder: (_, aptSnap) {
                final apts = aptSnap.data ?? [];
                final hasPatients = patSnap.hasData;
                final hasMeds = medSnap.hasData;
                final hasApts = aptSnap.hasData;

                if (!hasPatients && !hasMeds && !hasApts) {
                  return const Center(child: CircularProgressIndicator());
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Center(
                        child: Text('All Patients Schedule',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.navy),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (meds.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 30),
                          child: Center(child: Text('No schedule yet.', style: TextStyle(color: AppTheme.muted))),
                        )
                      else
                        ...patients.map((patient) {
                          final patientMeds = meds
                              .where((m) => m.patientId == patient.uid)
                              .toList();
                          if (patientMeds.isEmpty) return const SizedBox();
                          return _PatientScheduleCard(
                            patient: patient,
                            medications: patientMeds,
                            onViewMed: (med) => _showMedicationDetail(ctx, med, patient),
                          );
                        }),
                      if (apts.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text('Appointments',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppTheme.navy),
                        ),
                        const SizedBox(height: 10),
                        ...apts.map((apt) => _AppointmentCard(appointment: apt)),
                      ],
                      const SizedBox(height: 20),
                      const Text('Recently Missed / Snoozed',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppTheme.navy),
                      ),
                      const SizedBox(height: 10),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 4),
                        child: Text('No activity recorded yet.', style: TextStyle(color: AppTheme.muted, fontSize: 13)),
                      ),
                      const SizedBox(height: 16),
                      const Text('Refill Status',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppTheme.navy),
                      ),
                      const SizedBox(height: 10),
                      ...meds.map((m) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _RefillStatusCard(
                          patientName: m.patientName,
                          medName: m.name,
                          quantity: m.currentStock,
                          status: m.currentStock <= 0 ? 'Out of Stock' : m.currentStock <= 5 ? 'Low Stock' : 'In Stock',
                          statusColor: m.currentStock <= 0 ? Colors.red : m.currentStock <= 5 ? const Color(0xFFF2AE36) : const Color(0xFF48AF75),
                        ),
                      )),
                      const SizedBox(height: 12),
                      SizedBox(height: MediaQuery.of(ctx).padding.bottom),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _PatientScheduleCard extends StatelessWidget {
  const _PatientScheduleCard({
    required this.patient,
    required this.medications,
    required this.onViewMed,
  });

  final UserModel patient;
  final List<Medication> medications;
  final void Function(Medication) onViewMed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFC2C5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: patient.role.color.withValues(alpha: .15),
                child: Icon(Icons.person, color: patient.role.color, size: 16),
              ),
              const SizedBox(width: 6),
              Text(
                patient.name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppTheme.navy),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...medications.map((med) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: med.imageUrl != null
                      ? Image.network(med.imageUrl!, width: 48, height: 48, fit: BoxFit.cover)
                      : Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E1),
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
                      Text('Stock: ${med.currentStock}',
                        style: TextStyle(
                          fontSize: 11, color: med.currentStock <= 5 ? Colors.red : AppTheme.muted,
                          fontWeight: med.currentStock <= 5 ? FontWeight.w700 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 28,
                  child: TextButton(
                    onPressed: () => onViewMed(med),
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
          )),
        ],
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({required this.appointment});
  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6DD),
        borderRadius: BorderRadius.circular(10),
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
                Text('${appointment.patientName} - ${appointment.date} ${appointment.time}',
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

class _MedicationDetailSheet extends StatefulWidget {
  final Medication medication;
  final String patientName;

  const _MedicationDetailSheet({required this.medication, required this.patientName});

  @override
  State<_MedicationDetailSheet> createState() => _MedicationDetailSheetState();
}

class _MedicationDetailSheetState extends State<_MedicationDetailSheet> {
  late TextEditingController _stockCtrl;
  late TextEditingController _doseCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _stockCtrl = TextEditingController(text: widget.medication.currentStock.toString());
    _doseCtrl = TextEditingController(
      text: widget.medication.dosage.replaceAll(RegExp(r' pill\(s\)$'), ''),
    );
  }

  @override
  void dispose() {
    _stockCtrl.dispose();
    _doseCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('medications')
          .doc(widget.medication.id)
          .update({
        'currentStock': int.tryParse(_stockCtrl.text) ?? widget.medication.currentStock,
        'dosage': _doseCtrl.text.isNotEmpty
            ? '${_doseCtrl.text} pill(s)'
            : widget.medication.dosage,
      });
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final med = widget.medication;
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
                      Text(widget.patientName, style: const TextStyle(fontSize: 13, color: AppTheme.muted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _infoRow('Time', med.time),
            _infoRow('Type', med.type),
            _infoRow('Frequency', med.days.join(', ')),
            const Divider(height: 24),
            const Text('Edit', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _doseCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Dosage',
                suffixText: 'pill(s)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _stockCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Current Stock',
                suffixText: 'units',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity, height: 44,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(backgroundColor: AppTheme.navy),
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.muted, fontWeight: FontWeight.w600)),
          ),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _RefillStatusCard extends StatelessWidget {
  const _RefillStatusCard({
    required this.patientName, required this.medName,
    required this.quantity, required this.status, required this.statusColor,
  });
  final String patientName;
  final String medName;
  final int quantity;
  final String status;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBFC2C5)),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.inventory_2, color: Color(0xFF48AF75), size: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(patientName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                Text('$medName - Qty: $quantity', style: const TextStyle(fontSize: 10, color: AppTheme.muted)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(status,
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: statusColor),
            ),
          ),
        ],
      ),
    );
  }
}
