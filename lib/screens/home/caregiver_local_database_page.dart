import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/local_caregiver_record.dart';
import '../../services/caregiver_local_profile_service.dart';
import '../../theme/app_theme.dart';

class CaregiverLocalDatabasePage extends StatefulWidget {
  const CaregiverLocalDatabasePage({
    super.key,
    required this.firebaseUid,
    this.service,
  });

  final String firebaseUid;
  final CaregiverLocalProfileService? service;

  @override
  State<CaregiverLocalDatabasePage> createState() =>
      _CaregiverLocalDatabasePageState();
}

class _CaregiverLocalDatabasePageState
    extends State<CaregiverLocalDatabasePage> {
  late final CaregiverLocalProfileService _service;
  StreamSubscription<String?>? _session;
  LocalCaregiverRecord? _record;
  String? _error;
  bool _busy = true;
  bool _sessionChanged = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? CaregiverLocalProfileService();
    _session = _service.uidChanges.listen((uid) {
      if (uid != widget.firebaseUid && mounted) {
        setState(() {
          _sessionChanged = true;
          _record = null;
          _error = 'Sign in as this caregiver to access the local record.';
        });
      }
    });
    _reload();
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
          const SnackBar(content: Text('Caregiver profile saved locally.')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is UnsupportedError
            ? 'Local SQLite records are available in the Android and iOS apps.'
            : save
            ? 'Could not save the current Firebase profile. Check your connection and caregiver session, then retry. Existing local values are kept.'
            : 'Could not load the local record. Check your caregiver session and retry.';
        // Do not retain a previous account's data after a failed access check.
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
            'Caregiver record on this device',
            style: TextStyle(
              color: AppTheme.navy,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Firebase remains the source of truth. Profiles are saved automatically after account creation or sign-in. Refresh reloads only the local record. You can save again here to get your latest profile.',
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
                  'No local caregiver record yet. Sign in again to save automatically, or tap "Save current profile locally" to retry now.',
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
                  _field('Local record ID', record.caregiverId.toString()),
                  _field('Firebase UID', record.firebaseUid),
                  _field('Name', record.name),
                  _field('Email', record.email),
                  _field('Phone', record.phone),
                  _field('Profile image reference', record.profilePicUrl),
                  _field(
                    'Local record created',
                    record.createdAt.toLocal().toString(),
                  ),
                  _field(
                    'Last local update',
                    record.updatedAt.toLocal().toString(),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _busy || _sessionChanged
                ? null
                : () => _reload(save: true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.green),
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
