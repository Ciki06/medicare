import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/local_patient_record.dart';
import '../../models/user_role.dart';
import '../../services/patient_local_profile_service.dart';
import '../../theme/app_theme.dart';

class PatientLocalDatabasePage extends StatefulWidget {
  const PatientLocalDatabasePage({
    super.key,
    required this.firebaseUid,
    this.service,
  });

  final String firebaseUid;
  final PatientLocalProfileService? service;

  @override
  State<PatientLocalDatabasePage> createState() =>
      _PatientLocalDatabasePageState();
}

class _PatientLocalDatabasePageState extends State<PatientLocalDatabasePage> {
  late final PatientLocalProfileService _service;
  StreamSubscription<String?>? _session;
  LocalPatientRecord? _record;
  String? _error;
  bool _busy = true;
  bool _sessionChanged = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PatientLocalProfileService();
    _session = _service.uidChanges.listen((uid) {
      if (uid != widget.firebaseUid) _denyAccess();
    }, onError: (Object _) => _denyAccess());
    _reload();
  }

  void _denyAccess() {
    if (!mounted) return;
    setState(() {
      _sessionChanged = true;
      _record = null;
      _error = 'Sign in as this patient to access the local record.';
    });
  }

  @override
  void dispose() {
    _session?.cancel();
    super.dispose();
  }

  Future<void> _reload({bool save = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final record = save
          ? await _service.saveCurrentProfile(widget.firebaseUid)
          : await _service.load(widget.firebaseUid);
      if (!mounted || _sessionChanged) return;
      setState(() => _record = record);
      if (save) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Patient profile saved locally.')),
        );
      }
    } catch (error) {
      if (!mounted || _sessionChanged) return;
      setState(() {
        _error = error is UnsupportedError
            ? 'Local SQLite records are available in the Android and iOS apps.'
            : save
            ? 'Could not save your current Firebase profile. Check your connection and patient session, then retry. Your previous local record is kept.'
            : 'Could not load your local record. Check your patient session and retry.';
        if (!save) _record = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Local Database'),
      foregroundColor: AppTheme.navy,
      actions: [
        IconButton(
          tooltip: 'Refresh local record',
          onPressed: _busy || _sessionChanged ? null : _reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Patient record on this device',
            style: TextStyle(
              color: AppTheme.navy,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your profile and medical history are saved automatically after account creation or sign-in. Refresh reloads only your local record. You can save again here to get your latest profile.',
          ),
          const SizedBox(height: 20),
          if (_busy) const Center(child: CircularProgressIndicator()),
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
          ],
          if (!_busy && _error == null && _record == null)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No local patient record yet. Sign in again to save automatically, or tap "Save current profile locally" to retry now.',
                ),
              ),
            ),
          if (_record case final record?)
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _field('Patient ID', record.patientId.toString()),
                  _field('Firebase UID', record.uid),
                  _field('Name', record.name),
                  _field('IC Number', record.icNumber),
                  _field('Gender', record.gender),
                  _field('Date of Birth', record.dateOfBirth),
                  _field('Age', record.age?.toString()),
                  _field('Phone', record.phone),
                  _field('Email', record.email),
                  _field('Address', record.address),
                  _field(
                    'Local caregiver ID',
                    record.caregiverId?.toString() ??
                        'Not linked on this device',
                  ),
                  const Text(
                    'Medical History',
                    style: TextStyle(
                      color: AppTheme.navy,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (record.medicalHistory.isEmpty)
                    const Text('No medical history saved locally.'),
                  for (final entry in record.medicalHistory)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(entry.medicalHistory),
                          if (entry.createdAt != null)
                            Text(
                              'Saved locally: ${entry.createdAt!.toLocal()}',
                              style: const TextStyle(
                                color: AppTheme.muted,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _busy || _sessionChanged
                ? null
                : () => _reload(save: true),
            style: ElevatedButton.styleFrom(
              backgroundColor: UserRole.patient.color,
            ),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save current profile locally'),
          ),
        ],
      ),
    ),
  );

  Widget _field(String label, String? value) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTheme.muted, fontSize: 12),
        ),
        const SizedBox(height: 4),
        SelectableText(value == null || value.isEmpty ? 'Not provided' : value),
      ],
    ),
  );
}
