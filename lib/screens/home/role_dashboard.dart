import 'package:flutter/material.dart';

import '../../models/medication_model.dart';
import '../../models/refill_request.dart';
import '../../models/user_model.dart';
import '../../models/user_role.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import 'pharmacy_refill_page.dart';

class RoleDashboard extends StatelessWidget {
  const RoleDashboard({super.key, required this.role, this.user});

  final UserRole role;
  final UserModel? user;

  @override
  Widget build(BuildContext context) {
    if (role == UserRole.family || role == UserRole.pharmacist) {
      if (role == UserRole.pharmacist) {
        return _PharmacyDashboard(user: user);
      }
      return _MedicationOverview(role: role, user: user);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(role.label, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text('MediCare overview', style: TextStyle(color: AppTheme.muted)),
        ],
      ),
    );
  }
}

class _MedicationOverview extends StatelessWidget {
  const _MedicationOverview({required this.role, this.user});

  final UserRole role;
  final UserModel? user;

  @override
  Widget build(BuildContext context) {
    final firestore = FirestoreService();
    final caregiverId = user?.caregiverId ?? user?.uid ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(role.label, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text('MediCare overview', style: TextStyle(color: AppTheme.muted)),
          const SizedBox(height: 18),
          StreamBuilder<List<UserModel>>(
            stream: firestore.getPatientsByCaregiver(caregiverId),
            builder: (context, patSnap) {
              final patients = patSnap.data ?? [];
              if (patients.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.only(top: 30),
                  child: Center(child: Text('No patients linked yet.', style: TextStyle(color: AppTheme.muted))),
                );
              }
              return StreamBuilder<List<Medication>>(
                stream: firestore.getMedicationsByCaregiver(caregiverId),
                builder: (context, medSnap) {
                  final meds = medSnap.data ?? [];
                  if (meds.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 30),
                      child: Center(child: Text('No medications scheduled.', style: TextStyle(color: AppTheme.muted))),
                    );
                  }
                  return Column(
                    children: patients.map((patient) {
                      final patientMeds = meds.where((m) => m.patientId == patient.uid).toList();
                      if (patientMeds.isEmpty) return const SizedBox();
                      return _PatientMedsCard(patient: patient, medications: patientMeds);
                    }).toList(),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PharmacyDashboard extends StatelessWidget {
  const _PharmacyDashboard({this.user});

  final UserModel? user;

  @override
  Widget build(BuildContext context) {
    final firestore = FirestoreService();
    final caregiverId = user?.caregiverId ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(user?.role.label ?? 'Pharmacy', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _buildRefillPage(context),
                    ),
                  );
                },
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('View All', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text('Refill notifications & overview', style: TextStyle(color: AppTheme.muted)),
          const SizedBox(height: 18),
          StreamBuilder<List<RefillRequest>>(
            stream: firestore.getAllRefillRequests(),
            builder: (context, snap) {
              final requests = snap.data ?? [];
              final pending = requests.where((r) => r.status == 'pending').toList();

              if (pending.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.only(top: 30),
                  child: Center(
                    child: Text('No pending refill requests.',
                      style: TextStyle(color: AppTheme.muted)),
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Pending Refill Requests',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.navy)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('${pending.length}',
                          style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700, color: Colors.red)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...pending.take(3).map((req) => _RefillNotificationCard(request: req)),
                  if (pending.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _buildRefillPage(context),
                            ),
                          );
                        },
                        child: Text('+ ${pending.length - 3} more requests',
                          style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          if (caregiverId.isNotEmpty)
            _MedicationOverview(role: UserRole.pharmacist, user: user),
        ],
      ),
    );
  }

  Widget _buildRefillPage(BuildContext context) {
    return PharmacyRefillPage(user: user!);
  }
}

class _RefillNotificationCard extends StatelessWidget {
  const _RefillNotificationCard({required this.request});

  final RefillRequest request;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E72B7), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0C8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.medication, color: Color(0xFFC78B4F), size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(request.patientName,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                Text('${request.medicationName} - Qty left: ${request.quantityLeft}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
                Text('From: ${request.caregiverName}',
                  style: const TextStyle(fontSize: 10, color: AppTheme.muted)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFE85B61).withValues(alpha: .15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('Pending',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFE85B61))),
          ),
        ],
      ),
    );
  }
}

class _PatientMedsCard extends StatelessWidget {
  const _PatientMedsCard({required this.patient, required this.medications});
  final UserModel patient;
  final List<Medication> medications;

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
                radius: 18,
                backgroundColor: patient.role.color.withValues(alpha: .15),
                child: Icon(Icons.person, color: patient.role.color, size: 20),
              ),
              const SizedBox(width: 8),
              Text(patient.name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppTheme.navy)),
            ],
          ),
          const SizedBox(height: 10),
          ...medications.map((med) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: med.imageUrl != null
                      ? Image.network(med.imageUrl!, width: 48, height: 48, fit: BoxFit.cover)
                      : Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E1),
                            borderRadius: BorderRadius.circular(8),
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
                          Text(med.time24h, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: med.currentStock > 0 ? const Color(0xFFE8F5E1) : const Color(0xFFFFE5E8),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    med.currentStock > 0 ? 'Available' : 'Out of Stock',
                    style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      color: med.currentStock > 0 ? const Color(0xFF48AF75) : Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          )),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('${medications.length} medication(s)',
                style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
            ],
          ),
        ],
      ),
    );
  }
}
