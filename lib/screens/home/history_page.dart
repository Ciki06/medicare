import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/medication_action.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.user});

  final UserModel user;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _firestore = FirestoreService();

  List<UserModel> _patients = [];
  StreamSubscription<List<MedicationAction>>? _actionSub;
  String? _selectedPatientId;
  List<MedicationAction> _actions = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    final caregiverId = widget.user.caregiverId ?? '';
    _firestore.getPatientsByCaregiver(caregiverId).first.then((patients) {
      if (!mounted) return;
      setState(() => _patients = patients);
      if (patients.isNotEmpty) {
        _selectPatient(patients.first.uid);
      }
    });
  }

  void _selectPatient(String patientId) {
    setState(() => _selectedPatientId = patientId);
    _actionSub?.cancel();
    _loaded = false;
    _actionSub = _firestore.getMedicationActionsByPatient(patientId).listen((
      actions,
    ) {
      if (mounted)
        setState(() {
          _actions = actions;
          _loaded = true;
        });
    });
  }

  @override
  void dispose() {
    _actionSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_patients.isEmpty) {
      return const Center(
        child: Text(
          'No patients linked yet.',
          style: TextStyle(color: AppTheme.muted, fontSize: 14),
        ),
      );
    }

    final taken = _actions.where((a) => a.action == 'taken').length;
    final skipped = _actions.where((a) => a.action == 'skipped').length;
    final snoozed = _actions.where((a) => a.action == 'snoozed').length;
    final total = _actions.length;
    final adherenceRate = total > 0
        ? (taken / total * 100).toStringAsFixed(0)
        : '--';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PatientSelector(
            patients: _patients,
            selectedId: _selectedPatientId,
            onSelected: _selectPatient,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _StatCard(
                label: 'Taken',
                value: taken.toString(),
                color: const Color(0xFF48AF75),
                icon: Icons.check_circle,
              ),
              const SizedBox(width: 8),
              _StatCard(
                label: 'Missed',
                value: skipped.toString(),
                color: const Color(0xFFE85B61),
                icon: Icons.cancel,
              ),
              const SizedBox(width: 8),
              _StatCard(
                label: 'Snoozed',
                value: snoozed.toString(),
                color: const Color(0xFFF2AE36),
                icon: Icons.alarm,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _AdherenceRate(rate: adherenceRate, total: total),
          const SizedBox(height: 16),
          const Text(
            'Medication History',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: AppTheme.navy,
            ),
          ),
          const SizedBox(height: 10),
          if (!_loaded)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_actions.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: Text(
                'No activity recorded yet.',
                style: TextStyle(color: AppTheme.muted, fontSize: 13),
              ),
            )
          else
            ..._buildTimeline(),
        ],
      ),
    );
  }

  List<Widget> _buildTimeline() {
    final grouped = <String, List<MedicationAction>>{};
    for (final action in _actions) {
      final dt = DateTime.fromMillisecondsSinceEpoch(action.timestamp);
      final key =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(key, () => []).add(action);
    }

    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return sortedKeys.take(14).expand((date) {
      final actions = grouped[date]!;
      final dt = DateTime.parse(date);
      final label = _dateLabel(dt);
      return [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 4),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.muted,
            ),
          ),
        ),
        ...actions.map((a) => _ActionTile(action: a)),
        const SizedBox(height: 4),
      ];
    }).toList();
  }

  String _dateLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(date).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7)
      return ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][dt.weekday - 1];
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

class _PatientSelector extends StatelessWidget {
  const _PatientSelector({
    required this.patients,
    required this.selectedId,
    required this.onSelected,
  });

  final List<UserModel> patients;
  final String? selectedId;
  final void Function(String) onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFC2C5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Patient',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF393939),
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final patientWidth = (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: patients.map((p) {
                  final isSelected = p.uid == selectedId;
                  return SizedBox(
                    width: patientWidth,
                    child: GestureDetector(
                      onTap: () => onSelected(p.uid),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF2E72B7)
                              : const Color(0xFFE4F1FC),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          p.name,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF2E72B7),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFBFC2C5)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: AppTheme.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdherenceRate extends StatelessWidget {
  const _AdherenceRate({required this.rate, required this.total});

  final String rate;
  final int total;

  @override
  Widget build(BuildContext context) {
    final parsed = double.tryParse(rate);
    final pct = parsed ?? 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFC2C5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    value: pct / 100,
                    strokeWidth: 5,
                    backgroundColor: const Color(0xFFE8E8E8),
                    valueColor: AlwaysStoppedAnimation(
                      pct >= 80
                          ? const Color(0xFF48AF75)
                          : pct >= 50
                          ? const Color(0xFFF2AE36)
                          : const Color(0xFFE85B61),
                    ),
                  ),
                ),
                Text(
                  '$rate%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: pct >= 80
                        ? const Color(0xFF48AF75)
                        : pct >= 50
                        ? const Color(0xFFF2AE36)
                        : const Color(0xFFE85B61),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Adherence Rate',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.navy,
                  ),
                ),
                Text(
                  '$total total action(s) recorded',
                  style: const TextStyle(fontSize: 11, color: AppTheme.muted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: pct >= 80
                  ? const Color(0xFFE8F5E1)
                  : pct >= 50
                  ? const Color(0xFFFFF6DD)
                  : const Color(0xFFFFE5E8),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              pct >= 80
                  ? 'Good'
                  : pct >= 50
                  ? 'Fair'
                  : 'Low',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: pct >= 80
                    ? const Color(0xFF48AF75)
                    : pct >= 50
                    ? const Color(0xFFF2AE36)
                    : const Color(0xFFE85B61),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action});

  final MedicationAction action;

  @override
  Widget build(BuildContext context) {
    String icon;
    Color color;
    String label;
    switch (action.action) {
      case 'taken':
        icon = '✓';
        color = const Color(0xFF48AF75);
        label = 'Taken';
        break;
      case 'skipped':
        icon = '✗';
        color = const Color(0xFFE85B61);
        label = 'Missed';
        break;
      case 'snoozed':
        icon = '⏰';
        color = const Color(0xFFF2AE36);
        label = 'Snoozed';
        break;
      default:
        icon = '?';
        color = AppTheme.muted;
        label = 'Unknown';
    }

    final dt = DateTime.fromMillisecondsSinceEpoch(action.timestamp);
    final timeStr =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBFC2C5)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                icon,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action.medicationName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            timeStr,
            style: const TextStyle(fontSize: 11, color: AppTheme.muted),
          ),
        ],
      ),
    );
  }
}
