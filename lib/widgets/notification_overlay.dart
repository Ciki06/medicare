import 'package:flutter/material.dart';
import '../models/medication_model.dart';
import '../services/firestore_service.dart';
import '../services/reminder_service.dart';
import '../theme/app_theme.dart';

class NotificationOverlay extends StatefulWidget {
  const NotificationOverlay({
    super.key,
    required this.patientId,
    required this.reminderService,
  });

  final String patientId;
  final ReminderService reminderService;

  @override
  State<NotificationOverlay> createState() => _NotificationOverlayState();
}

class _NotificationOverlayState extends State<NotificationOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  final _firestore = FirestoreService();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    widget.reminderService.addListener(_onReminderUpdate);
  }

  @override
  void dispose() {
    widget.reminderService.removeListener(_onReminderUpdate);
    _controller.dispose();
    super.dispose();
  }

  void _onReminderUpdate() {
    if (widget.reminderService.activeReminders.isNotEmpty && !_controller.isAnimating && _controller.value == 0) {
      _controller.forward();
    }
  }

  void _dismiss(Medication med) {
    widget.reminderService.markHandled(med.id, DateTime.now());
    if (widget.reminderService.activeReminders.isEmpty) {
      _controller.reverse();
    }
  }

  Future<void> _take(Medication med) async {
    await _firestore.logMedicationAction(
      medicationId: med.id,
      medicationName: med.name,
      patientId: widget.patientId,
      action: 'taken',
    );
    if (med.currentStock > 0) {
      await _firestore.updateMedicationStock(med.id, med.currentStock - 1);
    }
    _dismiss(med);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Medicine marked as taken')),
      );
    }
  }

  Future<void> _skip(Medication med) async {
    await _firestore.logMedicationAction(
      medicationId: med.id,
      medicationName: med.name,
      patientId: widget.patientId,
      action: 'skipped',
    );
    _dismiss(med);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Medicine marked as skipped')),
      );
    }
  }

  Future<void> _snooze(Medication med) async {
    final snoozedUntil = DateTime.now().millisecondsSinceEpoch + 10 * 60 * 1000;
    await _firestore.logMedicationAction(
      medicationId: med.id,
      medicationName: med.name,
      patientId: widget.patientId,
      action: 'snoozed',
      snoozedUntil: snoozedUntil,
    );
    _dismiss(med);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reminder snoozed for 10 minutes')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      listenable: _controller,
      builder: (context, child) {
        if (_controller.value == 0) return const SizedBox.shrink();
        final reminders = widget.reminderService.activeReminders;
        if (reminders.isEmpty) return const SizedBox.shrink();

        return SlideTransition(
          position: _slideAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: reminders.map((r) => _NotificationBanner(
                    reminder: r,
                    onTake: () => _take(r.medication),
                    onSkip: () => _skip(r.medication),
                    onSnooze: () => _snooze(r.medication),
                    onDismiss: () => _dismiss(r.medication),
                  )).toList(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class AnimatedBuilder extends AnimatedWidget {
  const AnimatedBuilder({
    super.key,
    required Animation<double> listenable,
    required this.builder,
  }) : super(listenable: listenable);

  final TransitionBuilder builder;

  @override
  Widget build(BuildContext context) {
    return builder(context, null);
  }
}

class _NotificationBanner extends StatelessWidget {
  const _NotificationBanner({
    required this.reminder,
    required this.onTake,
    required this.onSkip,
    required this.onSnooze,
    required this.onDismiss,
  });

  final MedicationReminder reminder;
  final VoidCallback onTake;
  final VoidCallback onSkip;
  final VoidCallback onSnooze;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final med = reminder.medication;
    final hour = reminder.scheduledTime.hour;
    final minute = reminder.scheduledTime.minute;
    final timeLabel = '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF48AF75), width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF48AF75).withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF48AF75),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.notifications_active, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Medication Reminder',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: onDismiss,
                  child: const Icon(Icons.close, color: Colors.white, size: 18),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: med.imageUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(med.imageUrl!, width: 44, height: 44, fit: BoxFit.cover),
                            )
                          : const Icon(Icons.medication, color: Color(0xFF48AF75), size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(med.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.navy)),
                          Text('${med.dosage} - $timeLabel', style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
                          Text('Patient: ${med.patientName}', style: const TextStyle(fontSize: 10, color: AppTheme.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 32,
                        child: FilledButton(
                          onPressed: onTake,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF48AF75),
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Take', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SizedBox(
                        height: 32,
                        child: FilledButton(
                          onPressed: onSkip,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFE85B61),
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Skip', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SizedBox(
                        height: 32,
                        child: FilledButton(
                          onPressed: onSnooze,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFF2AE36),
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Snooze', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
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
    );
  }
}
