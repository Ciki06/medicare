import 'package:flutter/material.dart';

import '../../models/refill_request.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';

class PharmacyRefillPage extends StatelessWidget {
  const PharmacyRefillPage({super.key, required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final firestore = FirestoreService();

    return Scaffold(
      backgroundColor: AppTheme.paleBlue,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppTheme.navy, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Refill Requests',
          style: TextStyle(
            color: AppTheme.navy,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<List<RefillRequest>>(
        stream: firestore.getAllRefillRequests(),
        builder: (context, snap) {
          final requests = snap.data ?? [];
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (requests.isEmpty) {
            return const Center(
              child: Text('No refill requests yet.',
                style: TextStyle(color: AppTheme.muted, fontSize: 14)),
            );
          }

          final pending = requests.where((r) => r.status == 'pending').toList();
          final completed = requests
              .where((r) => r.status == 'completed' || r.status == 'ready_for_pickup')
              .toList();

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (pending.isNotEmpty) ...[
                const Text('Pending Requests',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.navy)),
                const SizedBox(height: 10),
                ...pending.map((req) => _RefillRequestCard(
                  request: req,
                  onTap: () => _showUpdateDialog(context, firestore, req),
                )),
                const SizedBox(height: 20),
              ],
              if (completed.isNotEmpty) ...[
                const Text('Completed',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.navy)),
                const SizedBox(height: 10),
                ...completed.map((req) => _RefillRequestCard(request: req)),
              ],
            ],
          );
        },
      ),
    );
  }

  void _showUpdateDialog(BuildContext context, FirestoreService firestore, RefillRequest req) {
    String selectedStatus = 'ready_for_pickup';
    final stockCtrl = TextEditingController(text: req.quantityLeft.toString());

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Update Refill Status',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Patient: ${req.patientName}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Medication: ${req.medicationName}',
                style: const TextStyle(color: AppTheme.muted)),
              const SizedBox(height: 4),
              Text('Quantity Left: ${req.quantityLeft}',
                style: const TextStyle(color: AppTheme.muted)),
              const SizedBox(height: 4),
              Text('Current Status: ${req.status}',
                style: const TextStyle(color: AppTheme.muted)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedStatus,
                decoration: const InputDecoration(
                  labelText: 'Update Status',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'ready_for_pickup', child: Text('Ready for Pickup')),
                  DropdownMenuItem(value: 'completed', child: Text('Completed')),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => selectedStatus = v);
                },
              ),
              if (selectedStatus == 'completed') ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: stockCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'New Stock Quantity',
                    hintText: 'e.g. 30',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await firestore.updateRefillRequestStatus(req.id, selectedStatus);
                  if (selectedStatus == 'completed') {
                    final newStock = int.tryParse(stockCtrl.text);
                    if (newStock != null) {
                      await firestore.updateMedicationStock(req.medicationId, newStock);
                    }
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Status updated to "${selectedStatus == 'ready_for_pickup' ? 'Ready for Pickup' : 'Completed'}"')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RefillRequestCard extends StatelessWidget {
  const _RefillRequestCard({required this.request, this.onTap});

  final RefillRequest request;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isPending = request.status == 'pending';
    final statusColor = switch (request.status) {
      'completed' => const Color(0xFF48AF75),
      'ready_for_pickup' => const Color(0xFFF2AE36),
      _ => const Color(0xFFE85B61),
    };
    final statusLabel = switch (request.status) {
      'completed' => 'Completed',
      'ready_for_pickup' => 'Ready for Pickup',
      _ => 'Pending',
    };

    return GestureDetector(
      onTap: isPending ? onTap : null,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isPending ? const Color(0xFF2E72B7) : const Color(0xFFBFC2C5),
            width: isPending ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.inventory_2, color: Color(0xFF2E72B7), size: 24),
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
                color: statusColor.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(statusLabel,
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: statusColor)),
            ),
          ],
        ),
      ),
    );
  }
}
