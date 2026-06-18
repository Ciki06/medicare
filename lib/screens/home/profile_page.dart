import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../models/user_role.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
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
              children: fields
                  .map((f) => _ProfileRow(
                      icon: f.$1, label: f.$2, value: f.$3))
                  .toList(),
            ),
          ),
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
          _field(Icons.wc, 'Gender', _user.gender ?? 'N/A'),
          _field(Icons.cake, 'Date of Birth', _user.dateOfBirth ?? 'N/A'),
          _field(Icons.phone, 'Contact No.', _user.phone ?? 'N/A'),
          _field(Icons.email, 'Email', _user.email),
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


