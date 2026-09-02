import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../models/user_role.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/change_password_dialog.dart';
import 'edit_profile_page.dart';

class ProfilePage extends StatefulWidget {
  final UserModel user;

  const ProfilePage({super.key, required this.user});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late UserModel _user;

  @override
  void initState() {
    super.initState();
    _user = widget.user;
  }

  Future<void> _refresh() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_user.uid)
        .get();
    if (doc.exists && mounted) {
      setState(() => _user = UserModel.fromMap(doc.data()!));
    }
  }

  Future<void> _editProfile() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfilePage(user: _user),
      ),
    );
    if (changed == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final fields = _buildFields();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(25, 18, 25, 18),
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 56,
                backgroundColor: _user.role.color.withValues(alpha: .2),
                backgroundImage: _user.profilePicUrl != null
                    ? NetworkImage(_user.profilePicUrl!)
                    : null,
                child: _user.profilePicUrl == null
                    ? Icon(
                        _roleIcon(_user.role),
                        color: _user.role.color,
                        size: 56,
                      )
                    : null,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: _editProfile,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _user.role.color,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.edit,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _user.name,
            style: const TextStyle(
              color: AppTheme.navy,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              fontFamily: 'serif',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _user.role.label,
            style: TextStyle(
              color: _user.role.color,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              children: [
                ...fields.map((f) => _ProfileRow(
                    icon: f.$1, label: f.$2, value: f.$3)),
                if (_user.role == UserRole.family) ...[
                  const SizedBox(height: 4),
                  _ProfileRow(
                    icon: Icons.medical_information_outlined,
                    label: 'Linked Patients',
                    value: _user.linkedPatientEmails.isEmpty
                        ? 'None'
                        : _user.linkedPatientEmails.join(', '),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: OutlinedButton.icon(
                      onPressed: _editProfile,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.navy,
                        side: const BorderSide(color: AppTheme.navy),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.link, size: 18),
                      label: const Text(
                        'Link / Relink Patients',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
                if (_user.role == UserRole.patient)
                  _LinkedFamilyMembers(patientId: _user.uid),
              ],
            ),
          ),
          if (_user.role == UserRole.patient ||
            _user.role == UserRole.family ||
            _user.role == UserRole.pharmacist) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: () => showChangePasswordDialog(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.navy,
                  side: const BorderSide(color: AppTheme.navy),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.lock_reset, size: 20),
                label: const Text(
                  'Change Password',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          TextButton.icon(
            onPressed: () => AuthService().signOut(),
            icon: const Icon(Icons.logout, color: Colors.red),
            label: const Text(
              'Log Out',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  List<(IconData, String, String)> _buildFields() {
    switch (_user.role) {
      case UserRole.patient:
        return [
          _field(Icons.person, 'Name', _user.name),
          _field(Icons.badge_outlined, 'IC Number', _user.icNumber ?? 'N/A'),
          _field(Icons.wc, 'Gender', _user.gender ?? 'N/A'),
          _field(Icons.cake, 'Date of Birth', _user.dateOfBirth ?? 'N/A'),
          _field(Icons.calendar_today, 'Age', _user.age?.toString() ?? 'N/A'),
          _field(Icons.phone, 'Contact No.', _user.phone ?? 'N/A'),
          _field(Icons.email, 'Email', _user.email),
          _field(Icons.home_outlined, 'Address', _user.address ?? 'N/A'),
          _field(
            Icons.medical_information_outlined,
            'Medical History',
            _user.medicalHistory.isEmpty
                ? 'None'
                : _user.medicalHistory.join(', '),
          ),
          if (_user.medicalNotes != null && _user.medicalNotes!.isNotEmpty)
            _field(Icons.notes, 'Medical Notes', _user.medicalNotes!),
        ];
      case UserRole.caregiver:
        return [
          _field(Icons.person, 'Name', _user.name),
          _field(Icons.qr_code, 'ID', _user.displayId),
          _field(Icons.phone, 'Contact No.', _user.phone ?? 'N/A'),
          _field(Icons.email, 'Email', _user.email),
        ];
      case UserRole.family:
        return [
          _field(Icons.person, 'Name', _user.name),
          _field(Icons.family_restroom, 'Relationship',
              _user.address ?? 'N/A'),
          _field(Icons.phone, 'Contact No.', _user.phone ?? 'N/A'),
          _field(Icons.email, 'Email', _user.email),
        ];
      case UserRole.pharmacist:
        return [
          _field(Icons.person, 'Name', _user.name),
          _field(Icons.qr_code, 'ID', _user.displayId),
          _field(Icons.phone, 'Contact', _user.phone ?? 'N/A'),
          _field(Icons.email, 'Email', _user.email),
        ];
    }
  }

  IconData _roleIcon(UserRole role) => switch (role) {
    UserRole.caregiver => Icons.admin_panel_settings,
    UserRole.patient => Icons.person,
    UserRole.family => Icons.people,
    UserRole.pharmacist => Icons.medical_services,
  };

  (IconData, String, String) _field(
          IconData icon, String label, String value) =>
      (icon, label, value);
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF777777), size: 24),
          const SizedBox(width: 16),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkedFamilyMembers extends StatelessWidget {
  const _LinkedFamilyMembers({required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: StreamBuilder<List<UserModel>>(
        stream: FirestoreService().getFamilyLinkedToPatient(patientId),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Text(
              'Unable to load linked family.',
              style: TextStyle(fontSize: 12, color: AppTheme.muted),
            );
          }
          final families = snap.data ?? [];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.family_restroom,
                        color: Color(0xFF777777), size: 24),
                    SizedBox(width: 16),
                    Text(
                      'Linked Family Members',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (families.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(left: 40, bottom: 8),
                  child: Text(
                    'No family members linked yet.',
                    style: TextStyle(fontSize: 12, color: AppTheme.muted),
                  ),
                )
              else
                for (final f in families)
                  Padding(
                    padding: const EdgeInsets.only(left: 40, bottom: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.person,
                            color: AppTheme.muted, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                f.name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                f.email,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}


