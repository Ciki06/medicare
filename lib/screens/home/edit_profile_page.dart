import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/malaysian_ic.dart';
import '../../models/medical_history.dart';
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
  late TextEditingController _icController;
  final _ageController = TextEditingController();
  final _otherConditionController = TextEditingController();
  final Set<String> _medicalHistory = {};

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
    _icController = TextEditingController(text: u.icNumber ?? '');
    _ageController.text = (u.icNumber != null && u.icNumber!.isNotEmpty)
        ? (MalaysianIc.age(u.icNumber!)?.toString() ?? '')
        : '';
    _medicalHistory.addAll(u.medicalHistory);
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
    _icController.dispose();
    _ageController.dispose();
    _otherConditionController.dispose();
    super.dispose();
  }

  void _onIcChanged(String value) {
    final formatted = MalaysianIc.format(value);
    if (formatted != _icController.text) {
      _icController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
    if (formatted.trim().isEmpty) {
      _dobController.clear();
      _ageController.clear();
      return;
    }
    final dob = MalaysianIc.dateOfBirth(formatted);
    final age = MalaysianIc.age(formatted);
    _dobController.text = dob ?? _dobController.text;
    _ageController.text = age?.toString() ?? _ageController.text;
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
              SnackBar(
                content: Text(
                  'Image upload failed: ${e.toString().substring(0, e.toString().length.clamp(0, 80))}',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }

      final ic = _icController.text.trim();
      final dob = (ic.isNotEmpty && MalaysianIc.isValid(ic))
          ? MalaysianIc.dateOfBirth(ic)
          : _dobController.text.trim();

      var conditions = <String>[..._medicalHistory];
      if (conditions.contains('Other')) {
        conditions.remove('Other');
        final other = _otherConditionController.text.trim();
        if (other.isNotEmpty) {
          conditions.addAll(
            other
                .split(RegExp(r'[,;]'))
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty),
          );
        }
      }

      final data = <String, dynamic>{
        'name': _nameController.text.trim(),
        if (_phoneController.text.trim().isNotEmpty)
          'phone': _phoneController.text.trim(),
        if (dob != null && dob.isNotEmpty) 'dateOfBirth': dob,
        if (_genderController.text.trim().isNotEmpty)
          'gender': _genderController.text.trim(),
        if (_addressController.text.trim().isNotEmpty)
          'address': _addressController.text.trim(),
        if (ic.isNotEmpty) 'icNumber': ic,
        if (conditions.isNotEmpty) 'medicalHistory': conditions,
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
          icon: const Icon(
            Icons.arrow_back_ios,
            color: AppTheme.navy,
            size: 20,
          ),
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
                  controller: _icController,
                  label: 'IC Number',
                  icon: Icons.badge_outlined,
                  hint: 'e.g. 920601-01-2345',
                  keyboardType: TextInputType.number,
                  onChanged: _onIcChanged,
                  validator: (v) {
                    final val = (v ?? '').trim();
                    if (val.isEmpty) return null;
                    if (!MalaysianIc.isValid(val)) {
                      return 'Invalid IC (format: YYMMDD-STATE-XXXX)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                _buildReadOnlyField(
                  label: 'Age',
                  controller: _ageController,
                  icon: Icons.calendar_today,
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
                const SizedBox(height: 14),
                _buildTextField(
                  controller: _addressController,
                  label: 'Home Address',
                  icon: Icons.home_outlined,
                ),
                const SizedBox(height: 22),
                const Text(
                  'Patient Medical Profile',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.navy,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Past medical history / current medical record.',
                  style: TextStyle(fontSize: 11, color: AppTheme.muted),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFBFC2C5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final condition
                              in MedicalHistoryCatalog.conditions)
                            FilterChip(
                              selected: _medicalHistory.contains(condition),
                              onSelected: (sel) => setState(() {
                                if (sel) {
                                  _medicalHistory.add(condition);
                                } else {
                                  _medicalHistory.remove(condition);
                                }
                              }),
                              label: Text(
                                condition,
                                style: const TextStyle(fontSize: 12),
                              ),
                              selectedColor: AppTheme.navy.withValues(
                                alpha: .18,
                              ),
                              checkmarkColor: AppTheme.navy,
                            ),
                        ],
                      ),
                      if (_medicalHistory.contains('Other')) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _otherConditionController,
                          decoration: InputDecoration(
                            labelText: 'Specify Other Condition(s)',
                            hintText: 'Separate with commas',
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(9),
                            ),
                          ),
                          maxLines: 2,
                        ),
                      ],
                    ],
                  ),
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
    void Function(String)? onChanged,
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
        onChanged: onChanged,
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
    required IconData icon,
    String? value,
    TextEditingController? controller,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextFormField(
        initialValue: controller == null ? value : null,
        controller: controller,
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
