import 'package:flutter/material.dart';

import '../../models/medication_action.dart';
import '../../models/medication_model.dart';
import '../../models/refill_request.dart';
import '../../models/user_model.dart';
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
        Expanded(child: _MedicationContent(user: user)),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
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
                    label: const Text(
                      'Add Medication',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF7257B5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _showAddAppointmentDialog(context, user),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text(
                      'Add Appointment',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE88C72),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
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
              backgroundColor: const Color(0xFFFFFBF8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text('Add Appointment'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: titleCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Title',
                          hintText: "e.g. Doctor's Appointment",
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: dateCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Date',
                          hintText: 'e.g. 2026-06-20',
                          prefixIcon: Icon(Icons.calendar_today),
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: timeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Time',
                          hintText: 'e.g. 22:00',
                          prefixIcon: Icon(Icons.schedule),
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: locationCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Location',
                          hintText: 'e.g. City Medical Centre',
                          prefixIcon: Icon(Icons.location_on),
                        ),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(labelText: 'Patient'),
                        items: patients
                            .map(
                              (p) => DropdownMenuItem(
                                value: p.uid,
                                child: Text(p.name),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          selectedPatientId = v;
                          selectedPatientName = patients
                              .firstWhere((p) => p.uid == v)
                              .name;
                        },
                        validator: (v) => v == null ? 'Select a patient' : null,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate() ||
                        selectedPatientId == null) {
                      return;
                    }
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

  void _showMedicationDetail(
    BuildContext context,
    Medication med,
    UserModel patient,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF8F4FF),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) =>
          _MedicationDetailSheet(medication: med, patientName: patient.name),
    );
  }

  void _showEditMedication(BuildContext context, Medication medication) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _MedicationEditDialog(medication: medication),
      ),
    );
  }

  void _showAppointmentDetail(BuildContext context, Appointment appointment) {
    showDialog<void>(
      context: context,
      builder: (_) => _AppointmentDetailDialog(appointment: appointment),
    );
  }

  void _showEditAppointment(
    BuildContext context,
    Appointment appointment,
    List<UserModel> patients,
  ) {
    showDialog<void>(
      context: context,
      builder: (_) =>
          _AppointmentEditDialog(appointment: appointment, patients: patients),
    );
  }

  void _confirmDeleteMedication(BuildContext context, Medication med) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Medication'),
        content: Text(
          'Are you sure you want to delete "${med.name}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await FirestoreService().deleteMedication(med.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC64F5E),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAppointment(
    BuildContext context,
    Appointment appointment,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Appointment'),
        content: Text(
          'Are you sure you want to delete "${appointment.title}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await FirestoreService().deleteAppointment(appointment.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC64F5E),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
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
                      const _PageBanner(
                        title: 'All Patients Schedule',
                        subtitle:
                            'Medication and appointment overview for today',
                      ),
                      const SizedBox(height: 16),
                      if (meds.isEmpty && apts.isEmpty)
                        const _PastelEmptyState(
                          icon: Icons.medication_outlined,
                          message: 'No schedule yet.',
                          backgroundColor: Color(0xFFF1EBFF),
                          foregroundColor: Color(0xFF7257B5),
                        )
                      else
                        ...patients.map((patient) {
                          final patientMeds = meds
                              .where((m) => m.patientId == patient.uid)
                              .toList();
                          final patientAppointments = apts
                              .where((a) => a.patientId == patient.uid)
                              .toList();
                          if (patientMeds.isEmpty &&
                              patientAppointments.isEmpty) {
                            return const SizedBox();
                          }
                          return GestureDetector(
                            onTap: () {
                              Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => _PatientSchedulePage(
                                    patient: patient,
                                    medications: patientMeds,
                                    appointments: patientAppointments,
                                    onEditMed: (med) =>
                                        _showEditMedication(ctx, med),
                                    onDeleteMed: (med) =>
                                        _confirmDeleteMedication(ctx, med),
                                    onEditAppointment: (appointment) =>
                                        _showEditAppointment(
                                          ctx,
                                          appointment,
                                          patients,
                                        ),
                                    onDeleteAppointment: (appointment) =>
                                        _confirmDeleteAppointment(
                                          ctx,
                                          appointment,
                                        ),
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF4EFFF),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFD7C8F5),
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x107257B5),
                                    blurRadius: 6,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: Colors.white.withValues(
                                      alpha: .85,
                                    ),
                                    child: const Icon(
                                      Icons.person,
                                      color: Color(0xFF7257B5),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          patient.name,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            color: AppTheme.navy,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${patientMeds.length} medication${patientMeds.length == 1 ? '' : 's'} · ${patientAppointments.length} appointment${patientAppointments.length == 1 ? '' : 's'}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right,
                                    color: Color(0xFF7257B5),
                                    size: 22,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      const SizedBox(height: 20),
                      const _SectionTitle(
                        label: 'Recent Medication Activity',
                        icon: Icons.history_rounded,
                        backgroundColor: Color(0xFFEDE4FF),
                        foregroundColor: Color(0xFF6748A8),
                      ),
                      const SizedBox(height: 10),
                      StreamBuilder<List<MedicationAction>>(
                        stream: firestore.getMedicationActionsByPatients(
                          patients.map((patient) => patient.uid).toList(),
                        ),
                        builder: (_, actionSnap) {
                          if (!actionSnap.hasData) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }
                          final actions = actionSnap.data!.take(8).toList();
                          if (actions.isEmpty) {
                            return const _PastelEmptyState(
                              icon: Icons.history_rounded,
                              message: 'No patient activity recorded yet.',
                              backgroundColor: Color(0xFFEAF3FF),
                              foregroundColor: Color(0xFF376A9F),
                            );
                          }
                          final patientNames = {
                            for (final patient in patients)
                              patient.uid: patient.name,
                          };
                          return Column(
                            children: actions
                                .map(
                                  (action) => _CaregiverActionCard(
                                    action: action,
                                    patientName:
                                        patientNames[action.patientId] ??
                                        'Patient',
                                  ),
                                )
                                .toList(),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      const _SectionTitle(
                        label: 'Refill Status',
                        icon: Icons.local_pharmacy_outlined,
                        backgroundColor: Color(0xFFFFEBCF),
                        foregroundColor: Color(0xFF956018),
                      ),
                      const SizedBox(height: 10),
                      StreamBuilder<List<RefillRequest>>(
                        stream: firestore.getRefillRequestsByCaregiver(
                          user.uid,
                        ),
                        builder: (_, refillSnap) {
                          final requests = refillSnap.data ?? [];
                          final latestByMedication = <String, RefillRequest>{};
                          for (final request in requests) {
                            latestByMedication.putIfAbsent(
                              request.medicationId,
                              () => request,
                            );
                          }
                          if (latestByMedication.isEmpty) {
                            return const _PastelEmptyState(
                              icon: Icons.local_pharmacy_outlined,
                              message: 'No refill requests yet.',
                              backgroundColor: Color(0xFFE7F6EE),
                              foregroundColor: Color(0xFF287553),
                            );
                          }
                          return Column(
                            children: latestByMedication.values.map((request) {
                              final medication = meds.firstWhere(
                                (m) => m.id == request.medicationId,
                                orElse: () => meds.first,
                              );
                              return _RefillStatusCard(
                                medication: medication,
                                request: request,
                                onStatusChanged: (newStatus) async {
                                  await FirestoreService()
                                      .updateRefillRequestStatus(
                                        request.id,
                                        newStatus,
                                      );
                                },
                              );
                            }).toList(),
                          );
                        },
                      ),
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

class _PatientSchedulePage extends StatelessWidget {
  const _PatientSchedulePage({
    required this.patient,
    required this.medications,
    required this.appointments,
    required this.onEditMed,
    required this.onDeleteMed,
    required this.onEditAppointment,
    required this.onDeleteAppointment,
  });

  final UserModel patient;
  final List<Medication> medications;
  final List<Appointment> appointments;
  final void Function(Medication) onEditMed;
  final void Function(Medication) onDeleteMed;
  final void Function(Appointment) onEditAppointment;
  final void Function(Appointment) onDeleteAppointment;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios,
            color: AppTheme.navy,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          patient.name,
          style: const TextStyle(
            color: AppTheme.navy,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFECE4FF), Color(0xFFF7F2FF)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD4C4F4)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .75),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.person, color: Color(0xFF7257B5)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          patient.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF4D387F),
                          ),
                        ),
                        Text(
                          '${medications.length} medication${medications.length == 1 ? '' : 's'} · ${appointments.length} appointment${appointments.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF7B6B9E),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (medications.isNotEmpty) ...[
              const _ScheduleCategoryLabel(
                label: 'Medication',
                icon: Icons.medication_outlined,
                backgroundColor: Color(0xFFE3D8FA),
                foregroundColor: Color(0xFF6748A8),
              ),
              const SizedBox(height: 10),
              ...medications.map(
                (med) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F5FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFD9CBF3)),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: med.imageUrl != null
                            ? Image.network(
                                med.imageUrl!,
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .8),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.medication,
                                  color: Color(0xFF7257B5),
                                  size: 24,
                                ),
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
                                  med.time24h,
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
                            Text(
                              'Stock: ${med.currentStock}',
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
                      Column(
                        children: [
                          _AppointmentActionButton(
                            label: 'Edit',
                            icon: Icons.edit_outlined,
                            onPressed: () => onEditMed(med),
                            filled: true,
                          ),
                          const SizedBox(height: 6),
                          _AppointmentActionButton(
                            label: 'Delete',
                            icon: Icons.delete_outline,
                            onPressed: () => onDeleteMed(med),
                            isDestructive: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (appointments.isNotEmpty) ...[
              const SizedBox(height: 6),
              const _ScheduleCategoryLabel(
                label: 'Appointment',
                icon: Icons.event_available_outlined,
                backgroundColor: Color(0xFFFFDCCF),
                foregroundColor: Color(0xFFA95743),
              ),
              const SizedBox(height: 10),
              ...appointments.map(
                (appointment) => _AppointmentCard(
                  appointment: appointment,
                  onEdit: () => onEditAppointment(appointment),
                  onDelete: () => onDeleteAppointment(appointment),
                ),
              ),
            ],
            if (medications.isEmpty && appointments.isEmpty)
              const _PastelEmptyState(
                icon: Icons.medication_outlined,
                message: 'No schedule for this patient.',
                backgroundColor: Color(0xFFF1EBFF),
                foregroundColor: Color(0xFF7257B5),
              ),
            const SizedBox(height: 12),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }
}

class _PageBanner extends StatelessWidget {
  const _PageBanner({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    const months = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final todayStr = '${months[now.month]} ${now.day}, ${now.year}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFECE4FF), Color(0xFFF7F2FF)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD4C4F4)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .75),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.calendar_month_outlined,
              color: Color(0xFF7257B5),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF4D387F),
                  ),
                ),
                Text(
                  '$subtitle - $todayStr',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF7B6B9E),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF7257B5).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF7257B5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: foregroundColor),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: foregroundColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _PastelEmptyState extends StatelessWidget {
  const _PastelEmptyState({
    required this.icon,
    required this.message,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final IconData icon;
  final String message;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: foregroundColor, size: 26),
          const SizedBox(height: 6),
          Text(
            message,
            style: TextStyle(
              color: foregroundColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PatientScheduleCard extends StatelessWidget {
  const _PatientScheduleCard({
    required this.patient,
    required this.medications,
    required this.appointments,
    required this.onEditMed,
    required this.onDeleteMed,
    required this.onEditAppointment,
    required this.onDeleteAppointment,
  });

  final UserModel patient;
  final List<Medication> medications;
  final List<Appointment> appointments;
  final void Function(Medication) onEditMed;
  final void Function(Medication) onDeleteMed;
  final void Function(Appointment) onEditAppointment;
  final void Function(Appointment) onDeleteAppointment;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4EFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD7C8F5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x167257B5),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: Colors.white.withValues(alpha: .85),
                child: const Icon(
                  Icons.person,
                  color: Color(0xFF7257B5),
                  size: 16,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                patient.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (medications.isNotEmpty)
            const _ScheduleCategoryLabel(
              label: 'Medication',
              icon: Icons.medication_outlined,
              backgroundColor: Color(0xFFE3D8FA),
              foregroundColor: Color(0xFF6748A8),
            ),
          if (medications.isNotEmpty) const SizedBox(height: 7),
          ...medications.map(
            (med) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F5FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD9CBF3)),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: med.imageUrl != null
                        ? Image.network(
                            med.imageUrl!,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .8),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.medication,
                              color: Color(0xFF7257B5),
                              size: 24,
                            ),
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
                              med.time24h,
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
                        Text(
                          'Stock: ${med.currentStock}',
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
                  Column(
                    children: [
                      _AppointmentActionButton(
                        label: 'Edit',
                        icon: Icons.edit_outlined,
                        onPressed: () => onEditMed(med),
                        filled: true,
                      ),
                      const SizedBox(height: 6),
                      _AppointmentActionButton(
                        label: 'Delete',
                        icon: Icons.delete_outline,
                        onPressed: () => onDeleteMed(med),
                        isDestructive: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (appointments.isNotEmpty) ...[
            const _ScheduleCategoryLabel(
              label: 'Appointment',
              icon: Icons.event_available_outlined,
              backgroundColor: Color(0xFFFFDCCF),
              foregroundColor: Color(0xFFA95743),
            ),
            const SizedBox(height: 7),
            ...appointments.map(
              (appointment) => _AppointmentCard(
                appointment: appointment,
                onEdit: () => onEditAppointment(appointment),
                onDelete: () => onDeleteAppointment(appointment),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScheduleCategoryLabel extends StatelessWidget {
  const _ScheduleCategoryLabel({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foregroundColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: foregroundColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({
    required this.appointment,
    required this.onEdit,
    required this.onDelete,
  });

  final Appointment appointment;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0EA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF2C6B8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12E88C72),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .8),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2A18D)),
            ),
            child: const Icon(
              Icons.event_available,
              color: Color(0xFFA95743),
              size: 18,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appointment.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${appointment.patientName} - ${appointment.date} ${appointment.time}',
                  style: const TextStyle(fontSize: 10, color: AppTheme.muted),
                ),
                if (appointment.location.isNotEmpty)
                  Text(
                    appointment.location,
                    style: const TextStyle(fontSize: 10, color: AppTheme.muted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              _AppointmentActionButton(
                label: 'Edit',
                icon: Icons.edit_outlined,
                onPressed: onEdit,
                filled: true,
              ),
              const SizedBox(height: 6),
              _AppointmentActionButton(
                label: 'Delete',
                icon: Icons.delete_outline,
                onPressed: onDelete,
                isDestructive: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AppointmentActionButton extends StatelessWidget {
  const _AppointmentActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.filled = false,
    this.isDestructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool filled;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final destructiveColor = const Color(0xFFC64F5E);
    return SizedBox(
      width: 68,
      height: 28,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 13),
        label: Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 7),
          foregroundColor: isDestructive
              ? destructiveColor
              : filled
              ? Colors.white
              : const Color(0xFF7257B5),
          backgroundColor: isDestructive
              ? destructiveColor.withValues(alpha: .1)
              : filled
              ? const Color(0xFF7257B5)
              : Colors.white.withValues(alpha: .82),
          side: BorderSide(
            color: isDestructive
                ? destructiveColor.withValues(alpha: .35)
                : const Color(0xFFB9A6E5),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
    );
  }
}

class _AppointmentDetailDialog extends StatelessWidget {
  const _AppointmentDetailDialog({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.event_available, color: Color(0xFFE69A31)),
          const SizedBox(width: 10),
          Expanded(child: Text(appointment.title)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _detailRow(Icons.person_outline, 'Patient', appointment.patientName),
          _detailRow(Icons.calendar_today_outlined, 'Date', appointment.date),
          _detailRow(Icons.schedule_outlined, 'Time', appointment.time),
          _detailRow(
            Icons.location_on_outlined,
            'Location',
            appointment.location.isEmpty
                ? 'Not specified'
                : appointment.location,
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          style: FilledButton.styleFrom(backgroundColor: AppTheme.navy),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: AppTheme.muted),
          const SizedBox(width: 10),
          SizedBox(
            width: 62,
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

class _AppointmentEditDialog extends StatefulWidget {
  const _AppointmentEditDialog({
    required this.appointment,
    required this.patients,
  });

  final Appointment appointment;
  final List<UserModel> patients;

  @override
  State<_AppointmentEditDialog> createState() => _AppointmentEditDialogState();
}

class _AppointmentEditDialogState extends State<_AppointmentEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _dateCtrl;
  late final TextEditingController _timeCtrl;
  late final TextEditingController _locationCtrl;
  late String _patientId;
  late String _patientName;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final appointment = widget.appointment;
    _titleCtrl = TextEditingController(text: appointment.title);
    _dateCtrl = TextEditingController(text: appointment.date);
    _timeCtrl = TextEditingController(text: appointment.time);
    _locationCtrl = TextEditingController(text: appointment.location);
    _patientId = appointment.patientId;
    _patientName = appointment.patientName;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _dateCtrl.dispose();
    _timeCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final updated = Appointment(
      id: widget.appointment.id,
      title: _titleCtrl.text.trim(),
      date: _dateCtrl.text.trim(),
      time: _timeCtrl.text.trim(),
      location: _locationCtrl.text.trim(),
      patientId: _patientId,
      patientName: _patientName,
      caregiverId: widget.appointment.caregiverId,
    );

    try {
      await FirestoreService().updateAppointment(updated);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update appointment. Try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientIds = widget.patients.map((patient) => patient.uid).toSet();
    final selectedPatientId = patientIds.contains(_patientId)
        ? _patientId
        : null;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Edit Appointment'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: _required,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _dateCtrl,
                decoration: const InputDecoration(
                  labelText: 'Date',
                  hintText: 'e.g. 2026-06-20',
                  prefixIcon: Icon(Icons.calendar_today),
                ),
                validator: _required,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _timeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Time',
                  hintText: 'e.g. 04:00 PM',
                  prefixIcon: Icon(Icons.schedule),
                ),
                validator: _required,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _locationCtrl,
                decoration: const InputDecoration(
                  labelText: 'Location',
                  prefixIcon: Icon(Icons.location_on),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: selectedPatientId,
                decoration: const InputDecoration(labelText: 'Patient'),
                items: widget.patients
                    .map(
                      (patient) => DropdownMenuItem(
                        value: patient.uid,
                        child: Text(patient.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  final patient = widget.patients.firstWhere(
                    (item) => item.uid == value,
                  );
                  _patientId = patient.uid;
                  _patientName = patient.name;
                },
                validator: (value) => value == null ? 'Select a patient' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.navy),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Save Changes'),
        ),
      ],
    );
  }

  String? _required(String? value) {
    return value == null || value.trim().isEmpty ? 'Required' : null;
  }
}

class _MedicationDetailSheet extends StatelessWidget {
  final Medication medication;
  final String patientName;

  const _MedicationDetailSheet({
    required this.medication,
    required this.patientName,
  });

  @override
  Widget build(BuildContext context) {
    final med = medication;
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
            Center(
              child: Container(
                width: 40,
                height: 4,
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
                      ? Image.network(
                          med.imageUrl!,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.medication,
                            color: Color(0xFF48AF75),
                            size: 28,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        med.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.navy,
                        ),
                      ),
                      Text(
                        patientName,
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
            _infoRow('Time', med.time24h),
            _infoRow('Type', med.type),
            _infoRow('Dosage', med.dosage),
            _infoRow('Frequency', med.days.join(', ')),
            _infoRow('Stock', '${med.currentStock} units'),
            _infoRow(
              'Refill alert',
              med.remindRefill ? 'At ${med.remindThreshold} units' : 'Disabled',
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
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _MedicationEditDialog extends StatefulWidget {
  const _MedicationEditDialog({required this.medication});

  final Medication medication;

  @override
  State<_MedicationEditDialog> createState() => _MedicationEditDialogState();
}

class _MedicationEditDialogState extends State<_MedicationEditDialog> {
  static const _types = [
    'Pill',
    'Injection',
    'Solution (Liquid)',
    'Drops',
    'Inhaler',
  ];
  static const _frequencies = ['Daily', 'Weekly', 'Monthly', 'Every X days'];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _timeCtrl;
  late final TextEditingController _doseCtrl;
  late final TextEditingController _stockCtrl;
  late final TextEditingController _thresholdCtrl;
  late String _type;
  late String _frequency;
  late bool _remindRefill;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final med = widget.medication;
    _nameCtrl = TextEditingController(text: med.name);
    _timeCtrl = TextEditingController(text: med.time);
    _doseCtrl = TextEditingController(text: med.dosage);
    _stockCtrl = TextEditingController(text: med.currentStock.toString());
    _thresholdCtrl = TextEditingController(
      text: med.remindThreshold.toString(),
    );
    _type = _types.contains(med.type) ? med.type : _types.first;
    _frequency = med.days.isNotEmpty && _frequencies.contains(med.days.first)
        ? med.days.first
        : _frequencies.first;
    _remindRefill = med.remindRefill;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _timeCtrl.dispose();
    _doseCtrl.dispose();
    _stockCtrl.dispose();
    _thresholdCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final med = widget.medication;
    final updated = Medication(
      id: med.id,
      name: _nameCtrl.text.trim(),
      dosage: _doseCtrl.text.trim(),
      time: _timeCtrl.text.trim(),
      days: [_frequency],
      patientId: med.patientId,
      patientName: med.patientName,
      caregiverId: med.caregiverId,
      type: _type,
      currentStock: int.parse(_stockCtrl.text),
      imageUrl: med.imageUrl,
      remindRefill: _remindRefill,
      remindThreshold: int.tryParse(_thresholdCtrl.text) ?? med.remindThreshold,
    );

    try {
      await FirestoreService().updateMedication(updated);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update medication. Try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios,
            color: AppTheme.navy,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Edit Medication',
          style: TextStyle(
            color: AppTheme.navy,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Medication Name:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.navy,
                ),
              ),
              const SizedBox(height: 6),
              _buildField(
                controller: _nameCtrl,
                hint: 'Type Medication Name',
                icon: Icons.search,
              ),
              const SizedBox(height: 18),

              const Text(
                'Medication Type:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.navy,
                ),
              ),
              const SizedBox(height: 6),
              _buildStringDropdown(
                hint: 'Select Medication Type',
                value: _type,
                items: _types,
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
              const SizedBox(height: 18),

              const Text(
                'How often do patient take it?',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.navy,
                ),
              ),
              const SizedBox(height: 6),
              _buildStringDropdown(
                hint: 'Select Days',
                value: _frequency,
                items: _frequencies,
                onChanged: (v) => setState(() => _frequency = v ?? _frequency),
              ),
              const SizedBox(height: 18),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Time:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.navy,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _buildField(
                          controller: _timeCtrl,
                          hint: 'e.g. 08:00',
                          icon: Icons.schedule,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Dose:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.navy,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _buildField(
                          controller: _doseCtrl,
                          hint: '1',
                          suffix: 'pill(s)',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              const Text(
                'Current Stock / Quantity:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.navy,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _stockCtrl,
                keyboardType: TextInputType.number,
                decoration: _inputDeco(
                  hint: 'e.g. 30',
                  suffix: 'units',
                  icon: Icons.inventory_2,
                ),
                validator: _nonNegativeNumber,
              ),
              const SizedBox(height: 18),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBFC2C5)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.notifications_outlined,
                      size: 20,
                      color: AppTheme.navy,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Refill Reminder',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: AppTheme.navy,
                            ),
                          ),
                          Text(
                            'Notify when stock is low',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _remindRefill,
                      onChanged: (v) => setState(() => _remindRefill = v),
                      activeThumbColor: const Color(0xFF48AF75),
                      activeTrackColor: const Color(
                        0xFF48AF75,
                      ).withValues(alpha: .4),
                    ),
                  ],
                ),
              ),
              if (_remindRefill) ...[
                const SizedBox(height: 10),
                const Text(
                  'Remind when stock reaches:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.navy,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _thresholdCtrl,
                  keyboardType: TextInputType.number,
                  decoration: _inputDeco(
                    hint: 'e.g. 5',
                    suffix: 'pills',
                    icon: Icons.notifications_active,
                  ),
                  validator: _nonNegativeNumber,
                ),
              ],
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A8A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Save Changes',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _nonNegativeNumber(String? value) {
    final number = int.tryParse(value ?? '');
    return number == null || number < 0 ? 'Enter 0 or more' : null;
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    IconData? icon,
    String? suffix,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFC2C5)),
      ),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          prefixIcon: icon != null
              ? Icon(icon, color: AppTheme.muted, size: 20)
              : null,
          hintText: hint,
          suffixText: suffix,
          hintStyle: const TextStyle(color: AppTheme.muted, fontSize: 14),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 12,
            horizontal: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildStringDropdown({
    required String hint,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownMenu<String>(
      expandedInsets: EdgeInsets.zero,
      menuHeight: 200,
      initialSelection: value,
      hintText: hint,
      textStyle: const TextStyle(fontSize: 14, color: Colors.black),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: Color(0xFFBFC2C5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: Color(0xFFBFC2C5)),
        ),
      ),
      dropdownMenuEntries: items
          .map((str) => DropdownMenuEntry(value: str, label: str))
          .toList(),
      onSelected: onChanged,
    );
  }

  InputDecoration _inputDeco({
    required String hint,
    String? suffix,
    IconData? icon,
  }) {
    return InputDecoration(
      prefixIcon: icon != null
          ? Icon(icon, color: AppTheme.muted, size: 20)
          : null,
      hintText: hint,
      suffixText: suffix,
      hintStyle: const TextStyle(color: AppTheme.muted, fontSize: 14),
      fillColor: Colors.white,
      filled: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFBFC2C5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFBFC2C5)),
      ),
    );
  }
}

class _CaregiverActionCard extends StatelessWidget {
  const _CaregiverActionCard({required this.action, required this.patientName});

  final MedicationAction action;
  final String patientName;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color, background) = switch (action.action) {
      'taken' => (
        'Taken',
        Icons.check_circle_outline,
        const Color(0xFF287553),
        const Color(0xFFE2F6EA),
      ),
      'skipped' => (
        'Skipped',
        Icons.cancel_outlined,
        const Color(0xFFA84759),
        const Color(0xFFFFE7EC),
      ),
      'snoozed' => (
        'Snoozed',
        Icons.snooze,
        const Color(0xFF7257B5),
        const Color(0xFFEDE5FF),
      ),
      _ => ('Updated', Icons.history, AppTheme.muted, const Color(0xFFF0F2F5)),
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .35)),
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
          Text(
            _relativeTime(action.timestamp),
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
    final difference = DateTime.now().difference(dt);
    if (difference.inMinutes < 1) return '$actualTime · Now';
    if (difference.inMinutes < 60)
      return '$actualTime · ${difference.inMinutes}m ago';
    if (difference.inHours < 24)
      return '$actualTime · ${difference.inHours}h ago';
    return '$actualTime · ${difference.inDays}d ago';
  }
}

class _RefillStatusCard extends StatelessWidget {
  const _RefillStatusCard({
    required this.medication,
    required this.request,
    required this.onStatusChanged,
  });

  final Medication medication;
  final RefillRequest request;
  final ValueChanged<String> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final status = request.status;
    final (label, icon, color, background) = switch (status) {
      'pending' => (
        'Pending',
        Icons.hourglass_top_rounded,
        const Color(0xFF9A6818),
        const Color(0xFFFFF0C9),
      ),
      'ready_for_pickup' => (
        'Ready',
        Icons.local_pharmacy_outlined,
        const Color(0xFF6849AA),
        const Color(0xFFECE3FF),
      ),
      'completed' => (
        'Completed',
        Icons.check_circle_outline,
        const Color(0xFF287553),
        const Color(0xFFDFF5E8),
      ),
      _ => (
        'Pending',
        Icons.hourglass_top_rounded,
        const Color(0xFF9A6818),
        const Color(0xFFFFF0C9),
      ),
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      medication.patientName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${medication.name} • ${request.quantityLeft} units left',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusChip(label: label, color: color),
            ],
          ),
          if (status != 'completed') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (status == 'pending') ...[
                  Expanded(
                    child: _StatusUpdateButton(
                      label: 'Mark Ready',
                      color: const Color(0xFF6849AA),
                      onPressed: () => onStatusChanged('ready_for_pickup'),
                    ),
                  ),
                ],
                if (status == 'ready_for_pickup') ...[
                  Expanded(
                    child: _StatusUpdateButton(
                      label: 'Mark Completed',
                      color: const Color(0xFF287553),
                      onPressed: () => onStatusChanged('completed'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusUpdateButton extends StatelessWidget {
  const _StatusUpdateButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: Size.zero,
          backgroundColor: color.withValues(alpha: .12),
          foregroundColor: color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
