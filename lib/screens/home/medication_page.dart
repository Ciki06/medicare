import '../../widgets/medication_activity_card.dart';
import '../../widgets/offline_image.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/medication_action.dart';
import '../../models/medication_model.dart';

import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../services/schedule_time.dart';
import '../../widgets/medication_frequency_fields.dart';
import '../../widgets/medicine_art.dart';
import '../../widgets/calendar_art.dart';
import 'add_medication_page.dart';
import 'history_page.dart';
import '../../widgets/completed_appointments_section.dart';
import '../../widgets/home_monitoring_sections.dart';
import '../../widgets/medication_activity_filter.dart';
import '../../services/history_filter.dart';

class MedicationPage extends StatelessWidget {
  const MedicationPage({super.key, required this.user, this.readOnly = false});

  final UserModel user;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _MedicationContent(user: user, readOnly: readOnly),
        ),
        if (!readOnly)
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
                        backgroundColor: AppTheme.navy,
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
                        backgroundColor: AppTheme.navy,
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
    final locationCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? selectedPatientId;
    String selectedPatientName = '';
    DateTime? selectedDate;
    TimeOfDay? selectedTime;
    int remindBefore = 0;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
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
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Required'
                                : null,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            readOnly: true,
                            onTap: () async {
                              final now = ScheduleTime.now();
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: selectedDate ?? now,
                                firstDate: DateTime(now.year - 1),
                                lastDate: DateTime(now.year + 5),
                              );
                              if (picked != null) {
                                setDialogState(() => selectedDate = picked);
                              }
                            },
                            controller: TextEditingController(
                              text: selectedDate == null
                                  ? ''
                                  : _formatDate(selectedDate!),
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Date',
                              hintText: 'Select date',
                              prefixIcon: Icon(Icons.calendar_today),
                            ),
                            validator: (v) =>
                                selectedDate == null ? 'Required' : null,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            readOnly: true,
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime:
                                    selectedTime ??
                                    const TimeOfDay(hour: 8, minute: 0),
                              );
                              if (picked != null) {
                                setDialogState(() => selectedTime = picked);
                              }
                            },
                            controller: TextEditingController(
                              text: selectedTime == null
                                  ? ''
                                  : _formatTime(selectedTime!),
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Time',
                              hintText: 'Select time',
                              prefixIcon: Icon(Icons.schedule),
                            ),
                            validator: (v) =>
                                selectedTime == null ? 'Required' : null,
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
                          DropdownButtonFormField<int>(
                            initialValue: remindBefore,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Remind before',
                              prefixIcon: Icon(Icons.notifications_active),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 0,
                                child: Text(
                                  'At appointment time',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem(
                                value: 10,
                                child: Text(
                                  '10 minutes before',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem(
                                value: 30,
                                child: Text(
                                  '30 minutes before',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem(
                                value: 60,
                                child: Text(
                                  '1 hour before',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            onChanged: (v) {
                              setDialogState(() => remindBefore = v ?? 0);
                            },
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            decoration: const InputDecoration(
                              labelText: 'Patient',
                            ),
                            items: patients
                                .map(
                                  (p) => DropdownMenuItem(
                                    value: p.uid,
                                    child: Text(p.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              setDialogState(() {
                                selectedPatientId = v;
                                selectedPatientName = patients
                                    .firstWhere((p) => p.uid == v)
                                    .name;
                              });
                            },
                            validator: (v) =>
                                v == null ? 'Select a patient' : null,
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
                            selectedPatientId == null ||
                            selectedDate == null ||
                            selectedTime == null) {
                          return;
                        }
                        final apt = Appointment(
                          id: '',
                          title: titleCtrl.text.trim(),
                          date: _formatDate(selectedDate!),
                          time: _formatTime(selectedTime!),
                          location: locationCtrl.text.trim(),
                          patientId: selectedPatientId!,
                          patientName: selectedPatientName,
                          caregiverId: user.uid,
                          remindBefore: remindBefore,
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
      },
    );
  }

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _MedicationContent extends StatefulWidget {
  const _MedicationContent({required this.user, this.readOnly = false});
  final UserModel user;
  final bool readOnly;

  @override
  State<_MedicationContent> createState() => _MedicationContentState();
}

class _MedicationContentState extends State<_MedicationContent> {
  bool _showAllActivity = false;
  MedicationActivityCriteria _activityFilter =
      const MedicationActivityCriteria();
  Timer? _autoCompleteTimer;
  final _firestore = FirestoreService();

  @override
  void initState() {
    super.initState();
    _autoCompleteTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _modifyAppointments();
    });
  }

  @override
  void dispose() {
    _autoCompleteTimer?.cancel();
    super.dispose();
  }

  Future<void> _modifyAppointments() async {
    if (widget.readOnly) return;
    final caregiverId = widget.user.caregiverId?.isNotEmpty == true
        ? widget.user.caregiverId!
        : widget.user.uid;
    final apts = await FirestoreService().getAppointmentsByCaregiverOnce(
      caregiverId,
    );
    final now = ScheduleTime.now();
    for (final apt in apts) {
      if (apt.status == 'completed') continue;
      final aptDateTime = _parseAppointmentTime(apt);
      if (aptDateTime != null && !aptDateTime.isAfter(now)) {
        await _firestore.updateAppointmentStatus(apt.id, 'completed');
      }
    }
  }

  DateTime? _parseAppointmentTime(Appointment apt) {
    final date = DateTime.tryParse(apt.date.replaceAll('/', '-'));
    return date == null ? null : ScheduleTime.onDate(apt.time, date);
  }

  void _showEditMedication(BuildContext context, Medication medication) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _MedicationEditDialog(medication: medication),
      ),
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

  void _confirmMarkCompleteAppointment(
    BuildContext context,
    Appointment appointment,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Mark Appointment Complete'),
        content: Text('Mark "${appointment.title}" as completed?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await FirestoreService().updateAppointmentStatus(
                appointment.id,
                'completed',
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF48AF75),
            ),
            child: const Text('Mark Complete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firestore = FirestoreService();
    final ctx = context;
    final caregiverId = widget.user.caregiverId?.isNotEmpty == true
        ? widget.user.caregiverId!
        : widget.user.uid;
    final linkedIds = widget.user.linkedPatientIds.toSet();

    final patientSource = widget.readOnly
        ? Stream<List<UserModel>>.fromFuture(
            firestore.getPatientsByIds(widget.user.linkedPatientIds),
          )
        : firestore.getPatientsByCaregiver(widget.user.uid);

    return StreamBuilder<List<UserModel>>(
      stream: patientSource,
      builder: (_, patSnap) {
        final patients = patSnap.data ?? [];
        return StreamBuilder<List<Medication>>(
          stream: widget.readOnly
              ? firestore.getMedicationsByPatients(linkedIds.toList())
              : firestore.getMedicationsByCaregiver(caregiverId),
          builder: (_, medSnap) {
            final meds = widget.readOnly
                ? (medSnap.data ?? [])
                      .where((m) => linkedIds.contains(m.patientId))
                      .toList()
                : (medSnap.data ?? []);
            return StreamBuilder<List<Appointment>>(
              stream: widget.readOnly
                  ? firestore.getAppointmentsByPatients(linkedIds.toList())
                  : firestore.getAppointmentsByCaregiver(caregiverId),
              builder: (_, aptSnap) {
                final apts = widget.readOnly
                    ? (aptSnap.data ?? [])
                          .where((a) => linkedIds.contains(a.patientId))
                          .toList()
                    : (aptSnap.data ?? []);
                final completedApts = apts
                    .where((a) => a.status == 'completed')
                    .toList();
                final hasPatients = patSnap.hasData;
                final hasMeds = medSnap.hasData;
                final hasApts = aptSnap.hasData;

                if (!hasPatients && !hasMeds && !hasApts) {
                  return const Center(child: CircularProgressIndicator());
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PageBanner(
                        title: widget.readOnly
                            ? 'Linked Patients Schedule'
                            : 'All Patients Schedule',
                        subtitle:
                            'Medication and appointments • Malaysia time (UTC+08:00)',
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
                          if (widget.readOnly) {
                            return _PatientScheduleCard(
                              patient: patient,
                              medications: patientMeds,
                              appointments: patientAppointments,
                              readOnly: true,
                              onEditMed: (_) {},
                              onDeleteMed: (_) {},
                              onEditAppointment: (_) {},
                              onDeleteAppointment: (_) {},
                            );
                          }
                          return GestureDetector(
                            onTap: () {
                              Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => _PatientSchedulePage(
                                    patient: patient,
                                    caregiverId: caregiverId,
                                    readOnly: widget.readOnly,
                                    onMarkCompleteAppointment: (appointment) =>
                                        _confirmMarkCompleteAppointment(
                                          ctx,
                                          appointment,
                                        ),
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
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: AppTheme.navy,
                                  width: 1.5,
                                ),
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
                                      color: AppTheme.navy,
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
                                          '${patientMeds.length} medication${patientMeds.length == 1 ? '' : 's'} · ${patientAppointments.where((a) => a.status != 'completed').length} appointment${patientAppointments.where((a) => a.status != 'completed').length == 1 ? '' : 's'}',
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
                                    color: AppTheme.navy,
                                    size: 22,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      DailyMoodSection(patients: patients),
                      ...[
                        if (completedApts.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          CompletedAppointmentsSection(
                            appointments: completedApts,
                            patients: patients,
                            cardBuilder: (a) => _AppointmentCard(
                              appointment: a,
                              showActions: false,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        const SizedBox(height: 10),
                        MedicationActivityFilter(
                          patients: patients,
                          onChanged: (v) => setState(() {
                            _activityFilter = v;
                            _showAllActivity = false;
                          }),
                          onReport: widget.readOnly
                              ? null
                              : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => Scaffold(
                                      appBar: AppBar(
                                        title: const Text('Report'),
                                        centerTitle: true,
                                      ),
                                      body: HistoryPage(
                                        user: widget.user,
                                        report: true,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
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
                            final allActions = filterMedicationActions(
                              actionSnap.data!,
                              patientId: _activityFilter.patientId,
                              status: _activityFilter.status,
                              name: _activityFilter.name,
                              start: _activityFilter.range?.start,
                              end: _activityFilter.range?.end,
                            );
                            final visibleActions = _showAllActivity
                                ? allActions
                                : allActions.take(5).toList();
                            if (visibleActions.isEmpty) {
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
                              children: [
                                ...visibleActions.map(
                                  (action) => MedicationActivityCard(
                                    action: action,
                                    patientName:
                                        patientNames[action.patientId] ??
                                        'Patient',
                                  ),
                                ),
                                if (!_showAllActivity && allActions.length > 5)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton(
                                        onPressed: () => setState(
                                          () => _showAllActivity = true,
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppTheme.navy,
                                          side: const BorderSide(
                                            color: AppTheme.navy,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                        ),
                                        child: const Text(
                                          'View More',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (_showAllActivity && allActions.length > 5)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton(
                                        onPressed: () => setState(
                                          () => _showAllActivity = false,
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppTheme.navy,
                                          side: const BorderSide(
                                            color: AppTheme.navy,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                        ),
                                        child: const Text(
                                          'Show Less',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
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
    required this.caregiverId,
    required this.onEditMed,
    required this.onDeleteMed,
    required this.onEditAppointment,
    required this.onDeleteAppointment,
    this.onMarkCompleteAppointment,
    this.readOnly = false,
  });

  final UserModel patient;
  final String caregiverId;
  final void Function(Medication) onEditMed;
  final void Function(Medication) onDeleteMed;
  final void Function(Appointment) onEditAppointment;
  final void Function(Appointment) onDeleteAppointment;
  final void Function(Appointment)? onMarkCompleteAppointment;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final firestore = FirestoreService();
    return Scaffold(
      backgroundColor: AppTheme.paleBlue,
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
      body: StreamBuilder<List<Medication>>(
        stream: firestore.getMedicationsByCaregiver(caregiverId),
        builder: (_, medSnap) {
          if (!medSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final medications = (medSnap.data!)
              .where((m) => m.patientId == patient.uid)
              .toList();
          return StreamBuilder<List<Appointment>>(
            stream: firestore.getAppointmentsByCaregiver(caregiverId),
            builder: (_, aptSnap) {
              if (!aptSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final appointments = (aptSnap.data!)
                  .where((a) => a.patientId == patient.uid)
                  .toList();
              final upcomingApts = appointments
                  .where((a) => a.status != 'completed')
                  .toList();
              final totalApts = appointments
                  .where((a) => a.status != 'completed')
                  .length;
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.navy, width: 1.5),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: AppTheme.navy.withValues(alpha: .1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.person,
                              color: AppTheme.navy,
                            ),
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
                                    color: AppTheme.navy,
                                  ),
                                ),
                                Text(
                                  '${medications.length} medication${medications.length == 1 ? '' : 's'} · $totalApts appointment${totalApts == 1 ? '' : 's'}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.navy,
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
                        backgroundColor: AppTheme.navy,
                        foregroundColor: Colors.white,
                      ),
                      const SizedBox(height: 10),
                      ...medications.map(
                        (med) => Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(0xFFBFC2C5),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: med.imageUrl != null
                                    ? OfflineImage(
                                        med.imageUrl!,
                                        width: 48,
                                        height: 48,
                                        fit: BoxFit.cover,
                                      )
                                    : Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: .8,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: const MedicineArt(size: 48),
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
                                        Flexible(
                                          child: Text(
                                            med.displayTime,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                            ),
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
                              if (!readOnly)
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
                                      filled: true,
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    const _ScheduleCategoryLabel(
                      label: 'Appointment',
                      icon: Icons.event_available_outlined,
                      backgroundColor: AppTheme.navy,
                      foregroundColor: Colors.white,
                    ),
                    const SizedBox(height: 10),
                    if (upcomingApts.isNotEmpty)
                      ...upcomingApts.map(
                        (appointment) => _AppointmentCard(
                          appointment: appointment,
                          onEdit: () => onEditAppointment(appointment),
                          onDelete: () => onDeleteAppointment(appointment),
                          showActions: !readOnly,
                          onMarkComplete: onMarkCompleteAppointment == null
                              ? null
                              : () => onMarkCompleteAppointment!(appointment),
                        ),
                      )
                    else
                      const _PastelEmptyState(
                        icon: Icons.event_busy,
                        message: 'No appointment...',
                        backgroundColor: Color(0xFFEAF3FF),
                        foregroundColor: Color(0xFF376A9F),
                      ),
                    const SizedBox(height: 12),

                    // CLOSING BODY
                    SizedBox(height: MediaQuery.of(context).padding.bottom),
                  ],
                ),
              );
            },
          );
        },
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
    final now = ScheduleTime.now();
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
        color: AppTheme.navy,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const CalendarArt(size: 42),
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
                    color: Colors.white,
                  ),
                ),
                Text(
                  '$subtitle - $todayStr',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
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
    this.readOnly = false,
  });

  final UserModel patient;
  final List<Medication> medications;
  final List<Appointment> appointments;
  final void Function(Medication) onEditMed;
  final void Function(Medication) onDeleteMed;
  final void Function(Appointment) onEditAppointment;
  final void Function(Appointment) onDeleteAppointment;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final upcomingApts = appointments
        .where((a) => a.status != 'completed')
        .toList();
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
              backgroundColor: AppTheme.navy,
              foregroundColor: Colors.white,
            ),
          if (medications.isNotEmpty) const SizedBox(height: 7),
          ...medications.map(
            (med) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade700, width: 1.5),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: med.imageUrl != null
                        ? OfflineImage(
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
                            child: const MedicineArt(size: 48),
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
                            Flexible(
                              child: Text(
                                med.displayTime,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          med.name,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
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
                  if (!readOnly)
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
          if (upcomingApts.isNotEmpty) ...[
            const _ScheduleCategoryLabel(
              label: 'Appointment',
              icon: Icons.event_available_outlined,
              backgroundColor: AppTheme.navy,
              foregroundColor: Colors.white,
            ),
            const SizedBox(height: 7),
            ...upcomingApts.map(
              (appointment) => _AppointmentCard(
                appointment: appointment,
                onEdit: () => onEditAppointment(appointment),
                onDelete: () => onDeleteAppointment(appointment),
                showActions: !readOnly,
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
    this.onEdit,
    this.onDelete,
    this.showActions = true,
    this.onMarkComplete,
  });

  final Appointment appointment;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool showActions;
  bool get completed => appointment.status == 'completed';
  final VoidCallback? onMarkComplete;

  @override
  Widget build(BuildContext context) {
    final borderColor = completed
        ? const Color(0xFF2E8B57)
        : const Color(0xFF2E72B7);
    final bgColor = Colors.white;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Row(
        children: [
          completed
              ? Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E8B57).withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    color: Color(0xFF2E8B57),
                    size: 20,
                  ),
                )
              : Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F0E3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const CalendarArt(size: 36),
                ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appointment.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
                Text(
                  '${appointment.patientName} - ${appointment.date} ${appointment.displayTime}',
                  style: TextStyle(
                    fontSize: 10,
                    color: completed ? Colors.black : AppTheme.muted,
                  ),
                ),
                if (appointment.location.isNotEmpty)
                  Text(
                    appointment.location,
                    style: TextStyle(
                      fontSize: 10,
                      color: completed ? Colors.black : AppTheme.muted,
                    ),
                  ),
                if (!completed && onMarkComplete != null) ...[
                  const SizedBox(height: 8),
                  _AppointmentActionButton(
                    label: 'Complete',
                    icon: Icons.check_circle_outline,
                    onPressed: onMarkComplete!,
                    filled: true,
                    color: const Color(0xFF48AF75),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (showActions)
            Column(
              children: [
                _AppointmentActionButton(
                  label: 'Edit',
                  icon: Icons.edit_outlined,
                  onPressed: onEdit ?? () {},
                  filled: true,
                ),
                const SizedBox(height: 6),
                _AppointmentActionButton(
                  label: 'Delete',
                  icon: Icons.delete_outline,
                  onPressed: onDelete ?? () {},
                  filled: true,
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
    this.color,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool filled;
  final bool isDestructive;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final destructiveColor = const Color(0xFFC64F5E);
    final bgColor = color != null
        ? color!
        : isDestructive
        ? destructiveColor
        : filled
        ? AppTheme.navy
        : Colors.white.withValues(alpha: .82);
    return SizedBox(
      height: 28,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 13),
        label: Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(68, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: color != null
              ? Colors.white
              : isDestructive
              ? destructiveColor
              : filled
              ? Colors.white
              : AppTheme.navy,
          backgroundColor: bgColor,
          side: BorderSide(
            color: color != null
                ? color!
                : isDestructive
                ? destructiveColor.withValues(alpha: .35)
                : AppTheme.navy,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
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
  late int _remindBefore;
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
    _remindBefore = appointment.remindBefore;
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
      remindBefore: _remindBefore,
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
              DropdownButtonFormField<int>(
                initialValue: _remindBefore,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Remind before',
                  prefixIcon: Icon(Icons.notifications_active),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 0,
                    child: Text(
                      'At appointment time',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: 10,
                    child: Text(
                      '10 minutes before',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: 30,
                    child: Text(
                      '30 minutes before',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: 60,
                    child: Text(
                      '1 hour before',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _remindBefore = value);
                },
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

  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _timeCtrl;
  late final TextEditingController _doseCtrl;
  late final TextEditingController _stockCtrl;
  late final TextEditingController _thresholdCtrl;
  late String _type;
  late String _frequency;
  late String _startDate;
  late int _intervalDays;
  late bool _remindRefill;
  bool _saving = false;
  bool _pickingImage = false;
  Uint8List? _newImageBytes;
  bool _imageChanged = false;

  @override
  void initState() {
    super.initState();
    final med = widget.medication;
    _nameCtrl = TextEditingController(text: med.name);
    _timeCtrl = TextEditingController(text: med.time24h);
    _doseCtrl = TextEditingController(text: med.dosage);
    _stockCtrl = TextEditingController(text: med.currentStock.toString());
    _thresholdCtrl = TextEditingController(
      text: med.remindThreshold.toString(),
    );
    _type = _types.contains(med.type) ? med.type : _types.first;
    _frequency = med.days.isEmpty ? 'Daily' : med.days.join(', ');
    _startDate = med.startDate ?? ScheduleTime.today();
    _intervalDays = med.intervalDays.clamp(1, 365);
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

  Future<void> _pickImage() async {
    if (_pickingImage) return;
    setState(() => _pickingImage = true);
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 70,
      );
      if (file != null) {
        final bytes = await file.readAsBytes();
        if (mounted) {
          setState(() {
            _newImageBytes = bytes;
            _imageChanged = true;
          });
        }
      }
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
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
      days: MedicationFrequencyFields.frequencies.contains(_frequency)
          ? [_frequency]
          : med.days,
      startDate: _startDate,
      intervalDays: _intervalDays,
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

      if (_imageChanged && _newImageBytes != null) {
        try {
          final imageUrl = await StorageService().uploadMedicationImage(
            med.id,
            _newImageBytes!,
          );
          await FirestoreService().updateMedicationImage(med.id, imageUrl);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Medication saved but image upload failed: ${e.toString().substring(0, e.toString().length.clamp(0, 80))}',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }

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
              MedicationFrequencyFields(
                frequency: _frequency,
                startDate: _startDate,
                intervalDays: _intervalDays,
                onChanged: (frequency, date, interval) => setState(() {
                  _frequency = frequency;
                  _startDate = date;
                  _intervalDays = interval;
                }),
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
                        TextFormField(
                          controller: _timeCtrl,
                          readOnly: true,
                          decoration: _inputDeco(
                            hint: 'Select time',
                            icon: Icons.schedule,
                          ),
                          validator: (v) => ScheduleTime.parse(v ?? '') == null
                              ? 'Choose a valid time'
                              : null,
                          onTap: () async {
                            final time = ScheduleTime.parse(_timeCtrl.text);
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay(
                                hour: time?.hour ?? 8,
                                minute: time?.minute ?? 0,
                              ),
                              initialEntryMode: TimePickerEntryMode.dial,
                            );
                            if (picked != null && mounted) {
                              setState(
                                () => _timeCtrl.text =
                                    '${picked.hour.toString().padLeft(2, "0")}:${picked.minute.toString().padLeft(2, "0")}',
                              );
                            }
                          },
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
              const SizedBox(height: 18),

              const Text(
                'Medication Image (optional):',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.navy,
                ),
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _pickingImage ? null : _pickImage,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFBFC2C5)),
                  ),
                  child: _pickingImage
                      ? const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _newImageBytes != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            _newImageBytes!,
                            height: 120,
                            fit: BoxFit.contain,
                          ),
                        )
                      : widget.medication.imageUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: OfflineImage(
                            widget.medication.imageUrl!,
                            height: 120,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => Column(
                              children: const [
                                Icon(
                                  Icons.add_photo_alternate,
                                  size: 40,
                                  color: AppTheme.muted,
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Tap to upload image',
                                  style: TextStyle(
                                    color: AppTheme.muted,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Column(
                          children: const [
                            Icon(
                              Icons.add_photo_alternate,
                              size: 40,
                              color: AppTheme.muted,
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Tap to upload image',
                              style: TextStyle(
                                color: AppTheme.muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
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
