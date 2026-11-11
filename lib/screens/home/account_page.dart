import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../models/user_role.dart';
import '../../services/firestore_service.dart';
import '../../services/password_policy.dart';
import '../../theme/app_theme.dart';
import '../../widgets/medical_record_sheet.dart';
import '../../widgets/patient_link_editor.dart';
import '../../widgets/profile_picture.dart';
import 'edit_profile_page.dart';
import 'patient_registration_page.dart';

class AccountPage extends StatelessWidget {
  const AccountPage({super.key, this.user});

  final UserModel? user;

  void _showCreateAccountDialog(
    BuildContext context,
    UserModel user,
    String type,
  ) {
    if (type == 'patient') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PatientRegistrationPage(caregiverId: user.uid),
        ),
      );
      return;
    }

    final isFamily = type == 'family';
    final accountType = isFamily ? 'Family' : 'Pharmacist';
    final formKey = GlobalKey<FormState>();
    final fs = FirestoreService();
    final patientsByEmail = <String, UserModel>{};
    final relationships = <String, String>{};
    var patientEmails = <String>[];
    var name = '';
    var email = '';
    var password = '';
    var phone = '';
    var submitting = false;
    var hidePassword = true;
    String? errorMessage;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => PopScope(
          canPop: !submitting,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text('Create $accountType Account'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      enabled: !submitting,
                      onSaved: (value) => name = value!.trim(),
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        hintText: 'Enter name',
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      enabled: !submitting,
                      onSaved: (value) => email = value!.trim(),
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        hintText: 'Enter email',
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => v == null || !v.contains('@')
                          ? 'Valid email required'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      enabled: !submitting,
                      onSaved: (value) => password = value ?? '',
                      decoration: InputDecoration(
                        labelText: 'Password',
                        hintText: 'Choose a password',
                        helperText: PasswordPolicy.requirements,
                        helperMaxLines: 4,
                        errorMaxLines: 3,
                        suffixIcon: IconButton(
                          onPressed: () => setDialogState(
                            () => hidePassword = !hidePassword,
                          ),
                          icon: Icon(
                            hidePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                        ),
                      ),
                      obscureText: hidePassword,
                      validator: PasswordPolicy.validate,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      enabled: !submitting,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number (optional)',
                        prefixIcon: Icon(Icons.phone),
                      ),
                      keyboardType: TextInputType.phone,
                      onSaved: (value) => phone = (value ?? '').trim(),
                    ),
                    if (isFamily) ...[
                      const SizedBox(height: 10),
                      PatientLinkEditor(
                        emails: patientEmails,
                        relationships: relationships,
                        enabled: !submitting,
                        saveButtonLabel: 'Create',
                        findPatient: (email) async {
                          final patient = await fs.getUserByEmail(email);
                          if (patient == null ||
                              patient.role != UserRole.patient ||
                              patient.caregiverId != user.uid) {
                            return null;
                          }
                          patientsByEmail[patient.email] = patient;
                          return patient;
                        },
                        onChanged: (emails) => setDialogState(() {
                          patientEmails = emails;
                          relationships.removeWhere(
                            (email, _) => !emails.contains(email),
                          );
                        }),
                        onRelationshipChanged: (email, value) {
                          relationships[email] = value;
                        },
                      ),
                    ],
                    if (errorMessage != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: submitting
                    ? null
                    : () async {
                        final form = formKey.currentState!;
                        if (!form.validate()) return;
                        form.save();
                        setDialogState(() {
                          submitting = true;
                          errorMessage = null;
                        });
                        final phoneNumber = phone.isEmpty ? null : phone;
                        try {
                          if (isFamily) {
                            await fs.createFamilyAccount(
                              name: name,
                              email: email,
                              password: password,
                              caregiverId: user.uid,
                              phone: phoneNumber,
                              linkedPatientIds: [
                                for (final email in patientEmails)
                                  patientsByEmail[email]!.uid,
                              ],
                              linkedPatientEmails: patientEmails,
                              patientRelationships: {
                                for (final email in patientEmails)
                                  patientsByEmail[email]!.uid:
                                      relationships[email]!.trim(),
                              },
                            );
                          } else {
                            await fs.createPharmacistAccount(
                              name: name,
                              email: email,
                              password: password,
                              caregiverId: user.uid,
                              phone: phoneNumber,
                            );
                          }
                          if (!ctx.mounted) return;
                          final messenger = ScaffoldMessenger.of(ctx);
                          Navigator.pop(ctx);
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('$accountType account created'),
                            ),
                          );
                        } catch (error) {
                          if (!context.mounted) return;
                          setDialogState(() {
                            submitting = false;
                            errorMessage = error.toString();
                          });
                        }
                      },
                child: Text(submitting ? 'Creating…' : 'Create'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _AccountPageBody(
      user: user,
      onCreateAccount: _showCreateAccountDialog,
    );
  }
}

class _AccountPageBody extends StatefulWidget {
  const _AccountPageBody({required this.user, required this.onCreateAccount});

  final UserModel? user;
  final void Function(BuildContext context, UserModel user, String type)
  onCreateAccount;

  @override
  State<_AccountPageBody> createState() => _AccountPageBodyState();
}

class _AccountPageBodyState extends State<_AccountPageBody> {
  UserModel? _currentUser;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _currentUser ??= widget.user;
  }

  @override
  Widget build(BuildContext context) {
    final firestore = FirestoreService();
    final uid = _currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: AppTheme.paleBlue,
      body: StreamBuilder<List<UserModel>>(
        stream: firestore.getUsersByCaregiver(uid),
        builder: (context, snap) {
          final users = snap.data ?? [];
          final patients = users
              .where((u) => u.role == UserRole.patient)
              .toList();
          final families = users
              .where((u) => u.role == UserRole.family)
              .toList();
          final pharmacists = users
              .where((u) => u.role == UserRole.pharmacist)
              .toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (patients.isNotEmpty) ...[
                  const Text(
                    'Patients',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.navy,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...patients.map(
                    (p) => _AccountCard(
                      user: p,
                      details: _patientDetails(p),
                      chips: p.medicalHistory,
                      onTap: () => _openEditProfile(context, p),
                      onMedicalRecord:
                          p.medicalHistory.isNotEmpty ||
                              (p.medicalNotes != null &&
                                  p.medicalNotes!.isNotEmpty)
                          ? () => showMedicalRecordSheet(context, p)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (families.isNotEmpty) ...[
                  const Text(
                    'Family Members',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.navy,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...families.map(
                    (f) => _AccountCard(
                      user: f,
                      details: _familyDetails(f),
                      onTap: () => _openEditProfile(context, f),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (pharmacists.isNotEmpty) ...[
                  const Text(
                    'Pharmacists',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.navy,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...pharmacists.map(
                    (p) => _AccountCard(
                      user: p,
                      details: _pharmacistDetails(p),
                      onTap: () => _openEditProfile(context, p),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (users.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 30),
                    child: Center(
                      child: Text(
                        'No accounts yet.',
                        style: TextStyle(color: AppTheme.muted),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'account-add-button',
        backgroundColor: AppTheme.navy,
        child: const Icon(Icons.add, color: Colors.white, size: 28),
        onPressed: () {
          showModalBottomSheet(
            context: context,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (ctx) {
              final user = _currentUser;
              return Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 24,
                  horizontal: 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.person_add,
                        color: Color(0xFF2E72B7),
                        size: 28,
                      ),
                      title: const Text(
                        'Add Patient Account',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        if (user != null) {
                          widget.onCreateAccount(context, user, 'patient');
                        }
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(
                        Icons.group_add,
                        color: Color(0xFFE69A31),
                        size: 28,
                      ),
                      title: const Text(
                        'Add Family Account',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        if (user != null) {
                          widget.onCreateAccount(context, user, 'family');
                        }
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(
                        Icons.medical_services,
                        color: Color(0xFF5F9D47),
                        size: 28,
                      ),
                      title: const Text(
                        'Add Pharmacist Account',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        if (user != null) {
                          widget.onCreateAccount(context, user, 'pharmacist');
                        }
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(
                        Icons.link,
                        color: Color(0xFF2E72B7),
                        size: 28,
                      ),
                      title: const Text(
                        'Link Existing Account',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showLinkAccountDialog(context);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showLinkAccountDialog(BuildContext context) {
    final emailCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final firestore = FirestoreService();

    String? errorMessage;
    var linking = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void showError(String message) {
            if (ctx.mounted) setDialogState(() => errorMessage = message);
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Link Existing Account'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: emailCtrl,
                    enabled: !linking,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'Enter the account email',
                    ),
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) {
                      if (errorMessage != null) {
                        setDialogState(() => errorMessage = null);
                      }
                    },
                    validator: (v) => v == null || !v.contains('@')
                        ? 'Valid email required'
                        : null,
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        errorMessage!,
                        style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: linking ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: linking
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setDialogState(() {
                          linking = true;
                          errorMessage = null;
                        });
                        try {
                          final user = await firestore.getUserByEmail(
                            emailCtrl.text.trim(),
                          );
                          if (!ctx.mounted) return;
                          if (user == null) {
                            showError('No account found with this email');
                            return;
                          }
                          if (user.caregiverId != null) {
                            showError(
                              'This account is already linked to a caregiver',
                            );
                            return;
                          }
                          if (user.role == UserRole.caregiver) {
                            showError('Cannot link a caregiver account');
                            return;
                          }
                          final currentUser = _currentUser;
                          if (currentUser == null) {
                            showError(
                              'Please sign in again to link an account',
                            );
                            return;
                          }
                          await firestore.updateUserProfile(user.uid, {
                            'caregiverId': currentUser.uid,
                          });
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${user.name} linked successfully',
                                ),
                              ),
                            );
                          }
                        } catch (_) {
                          showError(
                            'Unable to link account. Please try again.',
                          );
                        } finally {
                          if (ctx.mounted) {
                            setDialogState(() => linking = false);
                          }
                        }
                      },
                child: Text(linking ? 'Linking...' : 'Link'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openEditProfile(BuildContext context, UserModel user) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditProfilePage(user: user)),
    );
  }

  String _patientDetails(UserModel p) {
    final parts = <String>[];
    parts.add('IC: ${p.icNumber ?? "N/A"}');
    parts.add('Age: ${p.age?.toString() ?? "N/A"}');
    parts.add('Date of Birth: ${p.displayDateOfBirth ?? "N/A"}');
    parts.add('Gender: ${p.gender ?? "N/A"}');
    parts.add('Phone: ${p.phone ?? "N/A"}');
    parts.add('Email: ${p.email}');
    if (p.address != null && p.address!.isNotEmpty) {
      parts.add('Address: ${p.address}');
    }
    if (p.medicalNotes != null && p.medicalNotes!.isNotEmpty) {
      parts.add('Notes: ${p.medicalNotes}');
    }
    return parts.join('\n');
  }

  String _familyDetails(UserModel f) {
    final parts = <String>[];
    parts.add('Phone: ${f.phone ?? "N/A"}');
    parts.add('Email: ${f.email}');
    if (f.linkedPatientIds.isNotEmpty) {
      parts.add(f.relationshipSummary);
    } else if (f.linkedPatientEmails.isNotEmpty) {
      parts.addAll(
        f.linkedPatientEmails.toSet().map(
          (email) => '$email | ${f.relationship ?? "Not specified"}',
        ),
      );
    } else if (f.relationship != null) {
      parts.add('Relationship: ${f.relationship}');
    }
    return parts.join('\n');
  }

  String _pharmacistDetails(UserModel p) {
    final parts = <String>[];
    parts.add('ID: ${p.displayId}');
    parts.add('Phone: ${p.phone ?? "N/A"}');
    parts.add('Email: ${p.email}');
    return parts.join('\n');
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.user,
    required this.details,
    this.chips = const [],
    this.onTap,
    this.onMedicalRecord,
  });

  final UserModel user;
  final String details;
  final List<String> chips;
  final VoidCallback? onTap;
  final VoidCallback? onMedicalRecord;

  Widget _actionIcon(IconData icon, VoidCallback onTap, String tooltip) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: AppTheme.navy.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppTheme.navy, size: 18),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = user.role.color;
    final icon = switch (user.role) {
      UserRole.patient => Icons.person,
      UserRole.family => Icons.people,
      UserRole.pharmacist => Icons.medical_services,
      UserRole.caregiver => Icons.admin_panel_settings,
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFBFC2C5)),
        ),
        child: Row(
          children: [
            if (user.role == UserRole.patient)
              ProfilePicture(
                user: user,
                size: 44,
                backgroundColor: color.withValues(alpha: .15),
                iconColor: color,
              )
            else
              CircleAvatar(
                radius: 22,
                backgroundColor: color.withValues(alpha: .15),
                child: Icon(icon, color: color, size: 24),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    details,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.muted,
                      height: 1.3,
                    ),
                  ),
                  if (chips.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final condition in chips)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF48AF75,
                              ).withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              condition,
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF3D8C5F),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                user.role.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
            if (onMedicalRecord != null) ...[
              const SizedBox(width: 6),
              _actionIcon(
                Icons.medical_information_outlined,
                onMedicalRecord!,
                'Medical record',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
