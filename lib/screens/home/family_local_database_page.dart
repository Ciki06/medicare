import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/caregiver_sqlite_service.dart';
import '../../theme/app_theme.dart';

class FamilyLocalDatabasePage extends StatefulWidget {
  const FamilyLocalDatabasePage({super.key, required this.firebaseUid});
  final String firebaseUid;

  @override
  State<FamilyLocalDatabasePage> createState() =>
      _FamilyLocalDatabasePageState();
}

class _FamilyLocalDatabasePageState extends State<FamilyLocalDatabasePage> {
  Map<String, Object?>? _record;
  bool _loading = true;
  bool _error = false;
  bool _authorized = true;
  StreamSubscription<User?>? _session;

  @override
  void initState() {
    super.initState();
    _session = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user?.uid != widget.firebaseUid && mounted) {
        setState(() {
          _authorized = false;
          _record = null;
          _loading = false;
        });
      }
    });
    _load();
  }

  @override
  void dispose() {
    _session?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (FirebaseAuth.instance.currentUser?.uid != widget.firebaseUid) {
      if (mounted) {
        setState(() {
          _authorized = false;
          _loading = false;
        });
      }
      return;
    }
    try {
      final record = await CaregiverSqliteService.instance.getFamily(
        widget.firebaseUid,
      );
      if (mounted) {
        setState(() {
          _record = record;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = true;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Local Family record')),
    body: !_authorized
        ? const Center(
            child: Text(
              'Your account changed. Return to Profile to view the local record.',
            ),
          )
        : _loading
        ? const Center(child: CircularProgressIndicator())
        : _error
        ? const Center(child: Text('Could not read the local Family record.'))
        : _record == null
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No local Family record exists yet. It will be saved after successful Family registration or login.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _value('Local Family ID', _record!['family_id']),
              _value('Firebase UID', _record!['uid']),
              _value('Name', _record!['name']),
              _value('Relationship', _record!['relationship']),
              _value('Phone', _record!['phone']),
              _value('Email', _record!['email']),
              const SizedBox(height: 12),
              const Text(
                'Linked patients',
                style: TextStyle(
                  color: AppTheme.navy,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              ...((_record!['linked_patients'] as List?) ?? const []).map((
                patient,
              ) {
                final p = patient as Map;
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(
                      (p['name'] as String?)?.trim().isNotEmpty == true
                          ? p['name'] as String
                          : 'Patient',
                    ),
                    subtitle: Text(
                      'Local Patient ID ${p['patient_id']} • ${p['uid']}',
                    ),
                  ),
                );
              }),
              if (((_record!['linked_patients'] as List?) ?? const []).isEmpty)
                const Text(
                  'No linked patients are available in the local database.',
                ),
            ],
          ),
  );

  Widget _value(String label, Object? value) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(
      label,
      style: const TextStyle(color: AppTheme.muted, fontSize: 13),
    ),
    subtitle: SelectableText(
      value == null || value == '' ? 'Not provided' : value.toString(),
      style: const TextStyle(color: AppTheme.navy, fontSize: 16),
    ),
  );
}
