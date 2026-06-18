import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/medication_model.dart';
import '../../models/refill_request.dart';
import '../../models/user_model.dart';
import '../../models/user_role.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brand_logo.dart';
import 'notification_page.dart';

class CaregiverHomePage extends StatefulWidget {
  const CaregiverHomePage({
    super.key,
    required this.user,
    this.onNavigateToMedication,
  });

  final UserModel user;
  final VoidCallback? onNavigateToMedication;

  @override
  State<CaregiverHomePage> createState() => _CaregiverHomePageState();
}

class _CaregiverHomePageState extends State<CaregiverHomePage> {
  final _firestore = FirestoreService();
  late final Stream<List<UserModel>> _patientsStream;
  late final Stream<List<Medication>> _medicationsStream;
  late final Stream<List<Appointment>> _appointmentsStream;
  List<RefillRequest> _refillRequests = [];
  StreamSubscription<List<RefillRequest>>? _refillSub;

  @override
  void initState() {
    super.initState();
    _patientsStream = _firestore.getPatientsByCaregiver(widget.user.uid);
    _medicationsStream = _firestore.getMedicationsByCaregiver(widget.user.uid);
    _appointmentsStream = _firestore.getAppointmentsByCaregiver(widget.user.uid);
    _refillSub = _firestore
        .getRefillRequestsByCaregiver(widget.user.uid)
        .listen((data) {
      if (mounted) setState(() => _refillRequests = data);
    });
  }

  @override
  void dispose() {
    _refillSub?.cancel();
    super.dispose();
  }

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
    return Column(
      children: [
        _Header(user: widget.user, refillRequests: _refillRequests),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Today's Schedule",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.navy,
                  ),
                ),
                const SizedBox(height: 12),
                StreamBuilder(
                  stream: _patientsStream,
                  builder: (context, patSnapshot) {
                    final patients = patSnapshot.data ?? [];
                    if (patients.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.only(top: 30),
                        child: Center(
                          child: Text(
                            'No patients yet.',
                            style: TextStyle(color: AppTheme.muted),
                          ),
                        ),
                      );
                    }
                    return StreamBuilder(
                      stream: _medicationsStream,
                      builder: (context, medSnapshot) {
                        final meds = medSnapshot.data ?? [];
                        return StreamBuilder(
                          stream: _appointmentsStream,
                          builder: (context, aptSnapshot) {
                            final apts = aptSnapshot.data ?? [];
                            final reqByMedId = <String, RefillRequest>{};
                            for (final r in _refillRequests) {
                              reqByMedId[r.medicationId] = r;
                            }
                            if (meds.isEmpty && apts.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.only(top: 30),
                                child: Center(
                                  child: Text(
                                    'No schedules yet.',
                                    style: TextStyle(color: AppTheme.muted),
                                  ),
                                ),
                              );
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ...patients.map((patient) {
                                  final patientMeds = meds
                                      .where((m) => m.patientId == patient.uid)
                                      .toList();
                                  if (patientMeds.isEmpty) return const SizedBox();
                                  return _PatientScheduleCard(
                                    patient: patient,
                                    medications: patientMeds,
                                    onViewMed: (med) => _showMedicationDetail(context, med, patient),
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
                                const SizedBox(height: 16),
                                const Text('Refill Status',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppTheme.navy),
                                ),
                                const SizedBox(height: 10),
                                ...meds.map((m) {
                                  final req = reqByMedId[m.id];
                                  String? reqLabel;
                                  Color? reqColor;
                                  if (req != null && req.status != 'pending') {
                                    reqLabel = req.status == 'ready_for_pickup' ? 'Ready for Pickup' : 'Completed';
                                    reqColor = req.status == 'ready_for_pickup' ? const Color(0xFFF2AE36) : const Color(0xFF48AF75);
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _RefillStatusCard(
                                      patientName: m.patientName,
                                      medName: m.name,
                                      quantity: m.currentStock,
                                      status: m.currentStock <= 0 ? 'Out of Stock' : m.currentStock <= 5 ? 'Low Stock' : 'In Stock',
                                      statusColor: m.currentStock <= 0 ? Colors.red : m.currentStock <= 5 ? const Color(0xFFF2AE36) : const Color(0xFF48AF75),
                                      requestStatus: reqLabel,
                                      requestColor: reqColor,
                                    ),
                                  );
                                }),
                              ],
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.user, required this.refillRequests});
  final UserModel user;
  final List<RefillRequest> refillRequests;

  @override
  Widget build(BuildContext context) {
    final updatedCount = refillRequests.where((r) => r.status == 'ready_for_pickup' || r.status == 'completed').length;
    return Container(
      height: 70,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const BrandLogo(compact: true, showName: false),
          const SizedBox(width: 8),
          const Text(
            'Caregiver Dashboard',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppTheme.navy,
            ),
          ),
          const Spacer(),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NotificationPage(user: user),
                  ),
                ),
                icon: const Icon(Icons.notifications_outlined, size: 28),
                color: AppTheme.navy,
              ),
              if (updatedCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$updatedCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
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

class _RefillStatusCard extends StatelessWidget {
  const _RefillStatusCard({
    required this.patientName, required this.medName,
    required this.quantity, required this.status, required this.statusColor,
    this.requestStatus, this.requestColor,
  });
  final String patientName;
  final String medName;
  final int quantity;
  final String status;
  final Color statusColor;
  final String? requestStatus;
  final Color? requestColor;

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
          if (requestStatus != null && requestColor != null)
            Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: requestColor!.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(requestStatus!,
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: requestColor),
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
