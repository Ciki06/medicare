import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/user_model.dart';
import '../../models/user_role.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';

class EditProfilePage extends StatefulWidget {
  final UserModel user;

  const EditProfilePage({super.key, required this.user});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();
  final _storageService = StorageService();
  final _picker = ImagePicker();

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _dobController;
  late TextEditingController _genderController;
  late TextEditingController _addressController;
  late TextEditingController _relationshipController;

  String? _profilePicUrl;
  Uint8List? _newImageBytes;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    _nameController = TextEditingController(text: u.name);
    _phoneController = TextEditingController(text: u.phone ?? '');
    _dobController = TextEditingController(text: u.dateOfBirth ?? '');
    _genderController = TextEditingController(text: u.gender ?? '');
    _addressController = TextEditingController(text: u.address ?? '');
    _relationshipController = TextEditingController(text: u.address ?? '');
    _profilePicUrl = u.profilePicUrl;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    _genderController.dispose();
    _addressController.dispose();
    _relationshipController.dispose();
    super.dispose();
  }

  bool _picking = false;

  Future<void> _pickImage() async {
    if (_picking) return;
    _picking = true;
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      if (file != null) {
        final bytes = await file.readAsBytes();
        if (mounted) setState(() => _newImageBytes = bytes);
      }
    } finally {
      _picking = false;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _uploading = true);

    try {
      String? picUrl = _profilePicUrl;
      if (_newImageBytes != null) {
        try {
          picUrl = await _storageService.uploadProfilePicture(
            widget.user.uid,
            _newImageBytes!,
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Image upload failed: ${e.toString().substring(0, e.toString().length.clamp(0, 80))}'),
                  backgroundColor: Colors.orange),
            );
          }
        }
      }

      final data = <String, dynamic>{
        'name': _nameController.text.trim(),
        if (_phoneController.text.trim().isNotEmpty)
          'phone': _phoneController.text.trim(),
        if (_dobController.text.trim().isNotEmpty)
          'dateOfBirth': _dobController.text.trim(),
        if (_genderController.text.trim().isNotEmpty)
          'gender': _genderController.text.trim(),
        if (_addressController.text.trim().isNotEmpty)
          'address': _addressController.text.trim(),
      };
      if (picUrl != null) data['profilePicUrl'] = picUrl;

      await _firestoreService.updateUserProfile(widget.user.uid, data);
      await _firestoreService.cleanNullFields(widget.user.uid);

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully!')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppTheme.navy, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Edit Profile',
          style: TextStyle(
            color: AppTheme.navy,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              GestureDetector(
                onTap: _pickImage,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 56,
                      backgroundColor: u.role.color.withValues(alpha: .2),
                      backgroundImage: _newImageBytes != null
                          ? MemoryImage(_newImageBytes!)
                          : (_profilePicUrl != null
                              ? NetworkImage(_profilePicUrl!)
                              : null),
                      child: (_newImageBytes == null && _profilePicUrl == null)
                          ? Icon(
                              _roleIcon(u.role),
                              color: u.role.color,
                              size: 56,
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: AppTheme.navy,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildTextField(
                controller: _nameController,
                label: 'Name',
                icon: Icons.person,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 14),
              _buildTextField(
                controller: _phoneController,
                label: 'Contact No.',
                icon: Icons.phone,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 14),
              if (u.role == UserRole.pharmacist) ...[
                _buildReadOnlyField(
                  label: 'Email',
                  value: u.email,
                  icon: Icons.email,
                ),
                const SizedBox(height: 14),
                _buildReadOnlyField(
                  label: 'ID',
                  value: u.displayId,
                  icon: Icons.qr_code,
                ),
              ],
              if (u.role == UserRole.caregiver) ...[
                _buildReadOnlyField(
                  label: 'Email',
                  value: u.email,
                  icon: Icons.email,
                ),
                const SizedBox(height: 14),
                _buildReadOnlyField(
                    label: 'Caregiver ID',
                    value: u.displayId,
                  icon: Icons.qr_code,
                ),
              ],
              if (u.role == UserRole.patient) ...[
                _buildReadOnlyField(
                  label: 'Email',
                  value: u.email,
                  icon: Icons.email,
                ),
                const SizedBox(height: 14),
                _buildTextField(
                  controller: _dobController,
                  label: 'Date of Birth',
                  icon: Icons.cake,
                  hint: 'DD/MM/YYYY',
                ),
                const SizedBox(height: 14),
                _buildTextField(
                  controller: _genderController,
                  label: 'Gender',
                  icon: Icons.wc,
                  hint: 'Male / Female / Other',
                ),
              ],
              if (u.role == UserRole.family) ...[
                _buildReadOnlyField(
                  label: 'Email',
                  value: u.email,
                  icon: Icons.email,
                ),
                const SizedBox(height: 14),
                _buildTextField(
                  controller: _addressController,
                  label: 'Relationship to Patient',
                  icon: Icons.family_restroom,
                  hint: 'e.g. Son, Daughter, Spouse',
                ),
              ],
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.navy,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _uploading ? null : _save,
                  child: _uploading
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

  IconData _roleIcon(UserRole role) => switch (role) {
    UserRole.caregiver => Icons.admin_panel_settings,
    UserRole.patient => Icons.person,
    UserRole.family => Icons.people,
    UserRole.pharmacist => Icons.medical_services,
  };

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFC2C5)),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: AppTheme.muted, size: 20),
          hintText: hint,
          labelText: label,
          labelStyle: const TextStyle(color: AppTheme.muted, fontSize: 13),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _buildReadOnlyField({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextFormField(
        initialValue: value,
        readOnly: true,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: AppTheme.muted, size: 20),
          labelText: label,
          labelStyle: const TextStyle(color: AppTheme.muted, fontSize: 13),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}
