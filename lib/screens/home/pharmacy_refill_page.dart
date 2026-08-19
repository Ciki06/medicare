import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/medication_model.dart';
import '../../models/refill_request.dart';
import '../../models/user_model.dart';
import '../../models/user_role.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/medicine_art.dart';

class PharmacyRefillPage extends StatefulWidget {
  const PharmacyRefillPage({super.key, required this.user});

  final UserModel user;

  @override
  State<PharmacyRefillPage> createState() => _PharmacyRefillPageState();
}

class _PharmacyRefillPageState extends State<PharmacyRefillPage> {
  final Set<String> _sendingMeds = {};
  final _firestore = FirestoreService();
  final Map<String, TextEditingController> _qtyControllers = {};
  List<RefillRequest> _refillRequests = [];
  late final Stream<List<Medication>> _medicationsStream;
  StreamSubscription<List<RefillRequest>>? _refillSub;

  @override
  void initState() {
    super.initState();
    _medicationsStream = _firestore.getMedicationsByCaregiver(widget.user.uid);
    final refillRequests = widget.user.role == UserRole.pharmacist
        ? _firestore.getAllRefillRequests()
        : _firestore.getRefillRequestsByCaregiver(widget.user.uid);
    _refillSub = refillRequests.listen((data) {
      if (mounted) setState(() => _refillRequests = data);
    });
  }

  @override
  void dispose() {
    _refillSub?.cancel();
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _sendRefillRequest({
    required String medicationId,
    required String medicationName,
    required String patientId,
    required String patientName,
    required String caregiverName,
    required int quantityLeft,
    required int quantityRequested,
  }) async {
    setState(() => _sendingMeds.add(medicationId));
    try {
      await _firestore.createRefillRequest(
        RefillRequest(
          id: '',
          medicationId: medicationId,
          medicationName: medicationName,
          patientId: patientId,
          patientName: patientName,
          caregiverId: widget.user.uid,
          caregiverName: caregiverName,
          quantityLeft: quantityLeft,
          quantityRequested: quantityRequested,
          requestedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Refill request sent to pharmacy!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingMeds.remove(medicationId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPharmacist = widget.user.role == UserRole.pharmacist;
    return Scaffold(
      backgroundColor: AppTheme.paleBlue,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Medication Refill',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.navy,
              ),
            ),
            const SizedBox(height: 10),
            StreamBuilder<List<Medication>>(
              stream: _medicationsStream,
              builder: (context, medSnap) {
                final meds = medSnap.data ?? [];
                final pendingMedIds = _refillRequests
                    .where((r) => r.status == 'pending')
                    .map((r) => r.medicationId)
                    .toSet();
                final lowStockMeds = meds
                    .where((m) => m.currentStock <= m.remindThreshold)
                    .toList();
                if (lowStockMeds.isEmpty && medSnap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'No refill notifications.',
                      style: TextStyle(color: AppTheme.muted, fontSize: 13),
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: lowStockMeds
                      .map(
                        (med) => _buildRefillNotification(
                          context: context,
                          medication: med,
                          isSending: _sendingMeds.contains(med.id),
                          hasPendingRequest: pendingMedIds.contains(med.id),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 20),
            const Text(
              'Medication Refill Status',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.navy,
              ),
            ),
            const SizedBox(height: 10),
            ..._refillRequests
                .where((r) => r.status == 'pending')
                .map(
                  (req) => _buildSentRequest(
                    req,
                    onTap: isPharmacist
                        ? () => _confirmStatusUpdate(
                            context,
                            req,
                            'ready_for_pickup',
                          )
                        : null,
                  ),
                ),
            ..._refillRequests
                .where((r) => r.status != 'pending')
                .map(
                  (req) => _buildStatusUpdate(
                    req,
                    onTap: isPharmacist && req.status == 'ready_for_pickup'
                        ? () => _confirmStatusUpdate(context, req, 'completed')
                        : null,
                  ),
                ),
            if (_refillRequests.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'No recent status updates.',
                  style: TextStyle(color: AppTheme.muted, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmStatusUpdate(
    BuildContext context,
    RefillRequest request,
    String status,
  ) async {
    final label = status == 'completed' ? 'Completed' : 'Ready for Pickup';
    final shouldUpdate = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Update Refill Status'),
        content: Text('Mark ${request.medicationName} as $label?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Mark $label'),
          ),
        ],
      ),
    );
    if (shouldUpdate != true) return;

    try {
      await _firestore.updateRefillRequestStatus(request.id, status);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $error'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildRefillNotification({
    required BuildContext context,
    required Medication medication,
    required bool isSending,
    required bool hasPendingRequest,
  }) {
    final quantityLeft = medication.currentStock;
    final buttonDisabled = isSending || hasPendingRequest;
    final buttonLabel = hasPendingRequest
        ? 'Request Sent'
        : isSending
        ? 'Sending...'
        : 'Send';

    final ctrl = _qtyControllers.putIfAbsent(
      medication.id,
      () => TextEditingController(text: quantityLeft.toString()),
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: quantityLeft <= 3 ? const Color(0xFFE8F5E1) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: quantityLeft <= 3
              ? const Color(0xFFA8D5A2)
              : const Color(0xFFBFC2C5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0C8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const MedicineArt(size: 52),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Medication Refill',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: quantityLeft <= 3
                            ? const Color(0xFF2E7D32)
                            : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      medication.patientName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${medication.name} (${medication.type})',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.muted,
                      ),
                    ),
                    Text(
                      '$quantityLeft left in stock',
                      style: TextStyle(
                        fontSize: 11,
                        color: quantityLeft <= 3 ? Colors.red : AppTheme.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Qty to refill',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              width: 100,
                              height: 32,
                              child: TextField(
                                controller: ctrl,
                                keyboardType: TextInputType.number,
                                enabled: !buttonDisabled,
                                decoration: InputDecoration(
                                  hintText: 'e.g. 30',
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 0,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  isDense: true,
                                ),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        SizedBox(
                          height: 32,
                          child: FilledButton(
                            onPressed: buttonDisabled
                                ? null
                                : () {
                                    final qty = int.tryParse(ctrl.text) ?? 0;
                                    if (qty <= 0) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Please enter a valid quantity.',
                                          ),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                      return;
                                    }
                                    _sendRefillRequest(
                                      medicationId: medication.id,
                                      medicationName: medication.name,
                                      patientId: medication.patientId,
                                      patientName: medication.patientName,
                                      caregiverName: widget.user.name,
                                      quantityLeft: quantityLeft,
                                      quantityRequested: qty,
                                    );
                                  },
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.navy,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            child: Text(
                              buttonLabel,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSentRequest(RefillRequest req, {VoidCallback? onTap}) {
    final statusColor = switch (req.status) {
      'completed' => const Color(0xFF48AF75),
      'ready_for_pickup' => const Color(0xFFF2AE36),
      _ => AppTheme.muted,
    };
    final statusLabel = switch (req.status) {
      'completed' => 'Completed',
      'ready_for_pickup' => 'Ready for Pickup',
      _ => 'Pending',
    };
    final title = req.status == 'pending'
        ? 'Refill Request Sent'
        : 'Refill Status Updated';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: statusColor == AppTheme.muted
              ? Colors.white
              : statusColor.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFBFC2C5)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.inventory_2,
                color: Color(0xFF2E72B7),
                size: 24,
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
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    req.patientName,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${req.medicationName} - Qty left: ${req.quantityLeft} | Requested: ${req.quantityRequested}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.muted),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusUpdate(RefillRequest req, {VoidCallback? onTap}) {
    if (req.status == 'pending') return const SizedBox();
    final isCompleted = req.status == 'completed';
    final canMarkCompleted =
        !isCompleted && widget.user.role == UserRole.caregiver;
    final statusColor = isCompleted
        ? const Color(0xFF48AF75)
        : const Color(0xFFF2AE36);
    final statusLabel = req.status == 'completed'
        ? 'Completed'
        : 'Ready for Pickup';
    final icon = req.status == 'completed'
        ? Icons.check_circle
        : Icons.local_shipping;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: statusColor),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: statusColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$statusLabel by Pharmacy',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                      Text(
                        req.patientName,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${req.medicationName} - Qty left: ${req.quantityLeft} | Requested: ${req.quantityRequested}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            if (canMarkCompleted) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () =>
                      _confirmStatusUpdate(context, req, 'completed'),
                  style: FilledButton.styleFrom(backgroundColor: statusColor),
                  child: const Text('Mark as Completed'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
