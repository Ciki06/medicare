import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/medication_model.dart';
import '../../models/refill_request.dart';
import '../../models/user_model.dart';
import '../../models/user_role.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/medicine_art.dart';

class RoleDashboard extends StatelessWidget {
  const RoleDashboard({
    super.key,
    required this.role,
    this.user,
    this.onNavigateToRequest,
  });

  final UserRole role;
  final UserModel? user;
  final VoidCallback? onNavigateToRequest;

  @override
  Widget build(BuildContext context) {
    if (role == UserRole.family || role == UserRole.pharmacist) {
      if (role == UserRole.pharmacist) {
        return _PharmacyDashboard(
          user: user,
          onNavigateToRequest: onNavigateToRequest,
        );
      }
      return _MedicationOverview(role: role, user: user);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            role.label,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          const Text(
            'MediCare overview',
            style: TextStyle(color: AppTheme.muted),
          ),
        ],
      ),
    );
  }
}

class _MedicationOverview extends StatefulWidget {
  const _MedicationOverview({required this.role, this.user});

  final UserRole role;
  final UserModel? user;

  @override
  State<_MedicationOverview> createState() => _MedicationOverviewState();
}

class _MedicationOverviewState extends State<_MedicationOverview> {
  final _firestore = FirestoreService();
  List<UserModel> _patients = [];
  List<Medication> _meds = [];
  StreamSubscription<List<UserModel>>? _patSub;
  StreamSubscription<List<Medication>>? _medSub;

  @override
  void initState() {
    super.initState();
    final caregiverId = widget.user?.caregiverId ?? widget.user?.uid ?? '';

    _patSub = _firestore.getPatientsByCaregiver(caregiverId).listen((p) {
      if (!mounted) return;
      setState(() => _patients = p);
    }, onError: (_) {});
    _medSub = _firestore.getMedicationsByCaregiver(caregiverId).listen((m) {
      if (mounted) setState(() => _meds = m);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _patSub?.cancel();
    _medSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.role == UserRole.pharmacist
                ? 'Patient Medication Overview'
                : "Patient's Schedule",
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 18),
          if (_patients.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 30),
              child: Center(
                child: Text(
                  'No patients linked yet.',
                  style: TextStyle(color: AppTheme.muted),
                ),
              ),
            )
          else if (_meds.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 30),
              child: Center(
                child: Text(
                  'No medications scheduled.',
                  style: TextStyle(color: AppTheme.muted),
                ),
              ),
            )
          else
            ..._patients.map((patient) {
              final patientMeds = _meds
                  .where((m) => m.patientId == patient.uid)
                  .toList();
              if (patientMeds.isEmpty) return const SizedBox();
              return _PatientMedsCard(
                patient: patient,
                medications: patientMeds,
              );
            }),
        ],
      ),
    );
  }
}

class _PharmacyDashboard extends StatefulWidget {
  const _PharmacyDashboard({this.user, this.onNavigateToRequest});

  final UserModel? user;
  final VoidCallback? onNavigateToRequest;

  @override
  State<_PharmacyDashboard> createState() => _PharmacyDashboardState();
}

class _PharmacyDashboardState extends State<_PharmacyDashboard> {
  final _firestore = FirestoreService();
  List<UserModel> _patients = [];
  List<Medication> _meds = [];
  StreamSubscription<List<UserModel>>? _patSub;
  StreamSubscription<List<Medication>>? _medSub;

  @override
  void initState() {
    super.initState();
    final caregiverId = widget.user?.caregiverId ?? '';
    _patSub = _firestore.getPatientsByCaregiver(caregiverId).listen((p) {
      if (mounted) setState(() => _patients = p);
    }, onError: (_) {});
    _medSub = _firestore.getMedicationsByCaregiver(caregiverId).listen((m) {
      if (mounted) setState(() => _meds = m);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _patSub?.cancel();
    _medSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final caregiverId = widget.user?.caregiverId ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Current Refill Request',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 16),
          StreamBuilder<List<RefillRequest>>(
            stream: caregiverId.isNotEmpty
                ? _firestore.getRefillRequestsByCaregiver(caregiverId)
                : const Stream.empty(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.only(top: 30),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.only(top: 30),
                  child: Center(
                    child: Text(
                      'Error: ${snap.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                );
              }
              final requests = snap.data ?? [];
              final pending = requests
                  .where((r) => r.status == 'pending')
                  .toList();
              final readyForPickup = requests
                  .where((r) => r.status == 'ready_for_pickup')
                  .toList();
              final completed = requests
                  .where((r) => r.status == 'completed')
                  .toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _StatCard(
                        label: 'Pending',
                        count: pending.length,
                        color: const Color(0xFFE85B61),
                      ),
                      const SizedBox(width: 10),
                      _StatCard(
                        label: 'Ready',
                        count: readyForPickup.length,
                        color: const Color(0xFFF2AE36),
                      ),
                      const SizedBox(width: 10),
                      _StatCard(
                        label: 'Completed',
                        count: completed.length,
                        color: const Color(0xFF48AF75),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (pending.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 20),
                      child: Center(
                        child: Text(
                          'No pending refill requests.',
                          style: TextStyle(color: AppTheme.muted),
                        ),
                      ),
                    )
                  else ...[
                    Row(
                      children: [
                        const Text(
                          'Pending Requests',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.navy,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFE85B61,
                            ).withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${pending.length}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFE85B61),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ...pending
                        .take(3)
                        .map(
                          (req) => _HomeRefillRequestCard(
                            request: req,
                            onTap: widget.onNavigateToRequest,
                          ),
                        ),
                    if (pending.length > 3)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: TextButton(
                          onPressed: widget.onNavigateToRequest,
                          child: Text(
                            '+ ${pending.length - 3} more requests',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          if (caregiverId.isNotEmpty) ...[
            const Text(
              'Patient Medication Overview',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.navy,
              ),
            ),
            const SizedBox(height: 12),
            if (_patients.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Center(
                  child: Text(
                    'No patients linked yet.',
                    style: TextStyle(color: AppTheme.muted),
                  ),
                ),
              )
            else if (_meds.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Center(
                  child: Text(
                    'No medications scheduled.',
                    style: TextStyle(color: AppTheme.muted),
                  ),
                ),
              )
            else
              ..._patients.map((patient) {
                final patientMeds = _meds
                    .where((m) => m.patientId == patient.uid)
                    .toList();
                if (patientMeds.isEmpty) return const SizedBox();
                return _PatientMedsCard(
                  patient: patient,
                  medications: patientMeds,
                );
              }),
          ],
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: .3)),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeRefillRequestCard extends StatelessWidget {
  const _HomeRefillRequestCard({required this.request, this.onTap});

  final RefillRequest request;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
            const SizedBox(
              width: 48,
              height: 48,
              child: MedicineArt(size: 48),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.patientName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${request.medicationName} - Qty left: ${request.quantityLeft} | Requested: ${request.quantityRequested}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.muted),
                  ),
                  Text(
                    'From: ${request.caregiverName}',
                    style: const TextStyle(fontSize: 10, color: AppTheme.muted),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFE85B61).withValues(alpha: .15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'Pending',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE85B61),
                ),
              ),
            ),
          ],
        ),
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
        color: const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFC2C5), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
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
                  color: Color(0xFF7D8188),
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patient.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.navy,
                      ),
                    ),
                    Text(
                      '${medications.length} medication(s)',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...medications.map(
            (med) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF2E72B7),
                  width: 1.5,
                ),
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
                        Text(
                          med.name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
