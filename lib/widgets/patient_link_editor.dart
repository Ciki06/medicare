import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../models/user_role.dart';
import '../theme/app_theme.dart';

class PatientLinkEditor extends StatelessWidget {
  const PatientLinkEditor({
    super.key,
    required this.emails,
    required this.onChanged,
    required this.findPatient,
    this.enabled = true,
  });
  final List<String> emails;
  final ValueChanged<List<String>> onChanged;
  final Future<UserModel?> Function(String) findPatient;
  final bool enabled;

  Future<void> _add(BuildContext context) async {
    final patient = await showDialog<UserModel>(
      context: context,
      builder: (_) =>
          _FindPatientDialog(findPatient: findPatient, existing: emails),
    );
    if (patient != null && context.mounted) {
      onChanged([...emails, patient.email]);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFD0DFEA)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.diversity_1_outlined, color: AppTheme.navy),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Your care circle',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.navy,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.lightBlue,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${emails.length}',
                style: const TextStyle(
                  color: AppTheme.navy,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Find a patient by email, then add them to your circle.',
          style: TextStyle(fontSize: 12, color: AppTheme.muted),
        ),
        const SizedBox(height: 14),
        if (emails.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.lightBlue.withValues(alpha: .5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.person_add_alt_1_outlined,
                  color: AppTheme.navy,
                  size: 30,
                ),
                SizedBox(height: 8),
                Text(
                  'Who do you care for?',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.navy,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Add your first patient below.',
                  style: TextStyle(fontSize: 12, color: AppTheme.muted),
                ),
              ],
            ),
          ),
        for (final email in emails)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F8FC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 18,
                  backgroundColor: AppTheme.lightBlue,
                  child: Icon(
                    Icons.person_outline,
                    color: AppTheme.navy,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    email,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove $email',
                  onPressed: enabled
                      ? () =>
                            onChanged(emails.where((e) => e != email).toList())
                      : null,
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: AppTheme.muted,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: enabled ? () => _add(context) : null,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Add patient'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.navy,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Link changes apply when you tap Save Changes.',
          style: TextStyle(fontSize: 11, color: AppTheme.muted),
        ),
      ],
    ),
  );
}

class _FindPatientDialog extends StatefulWidget {
  const _FindPatientDialog({required this.findPatient, required this.existing});
  final Future<UserModel?> Function(String) findPatient;
  final List<String> existing;
  @override
  State<_FindPatientDialog> createState() => _FindPatientDialogState();
}

class _FindPatientDialogState extends State<_FindPatientDialog> {
  final _email = TextEditingController();
  UserModel? _patient;
  String? _error;
  bool _searching = false;
  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_searching) return;
    final email = _email.text.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _error = 'Enter a valid patient email.');
      return;
    }
    if (widget.existing.any((e) => e.toLowerCase() == email)) {
      setState(() => _error = 'This patient is already in your circle.');
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
      _patient = null;
    });
    try {
      final patient = await widget.findPatient(email);
      if (!mounted) return;
      setState(() {
        if (patient == null || patient.role != UserRole.patient) {
          _error = 'No patient account found. Check the email and try again.';
        } else {
          _patient = patient;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not search right now. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    title: const Text(
      'Find a patient',
      style: TextStyle(color: AppTheme.navy, fontWeight: FontWeight.w700),
    ),
    content: SizedBox(
      width: 340,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter the email used for their MediCare patient account.',
              style: TextStyle(fontSize: 13, color: AppTheme.muted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              enabled: !_searching,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              onSubmitted: (_) => _search(),
              onChanged: (_) => setState(() {
                _patient = null;
                _error = null;
              }),
              decoration: InputDecoration(
                labelText: 'Patient email',
                prefixIcon: const Icon(Icons.alternate_email),
                errorText: _error,
                errorMaxLines: 3,
              ),
            ),
            const SizedBox(height: 12),
            if (_patient == null)
              FilledButton.icon(
                onPressed: _searching ? null : _search,
                icon: _searching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(_searching ? 'Searching…' : 'Find patient'),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.navy),
              ),
            if (_patient != null)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.lightBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      color: Color(0xFF18754D),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _patient!.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.navy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(_patient!.email, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      if (_patient != null)
        FilledButton(
          onPressed: () => Navigator.pop(context, _patient),
          style: FilledButton.styleFrom(backgroundColor: AppTheme.navy),
          child: const Text('Add to circle'),
        ),
    ],
  );
}
