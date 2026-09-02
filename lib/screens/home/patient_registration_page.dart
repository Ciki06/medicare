import 'package:flutter/material.dart';

import '../../models/malaysian_ic.dart';
import '../../models/medical_history.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';

/// Full patient registration page used by the caregiver. Captures the
/// patient's personal details and builds their medical profile from a
/// predefined disease dataset.
class PatientRegistrationPage extends StatefulWidget {
  const PatientRegistrationPage({super.key, required this.caregiverId});

  final String caregiverId;

  @override
  State<PatientRegistrationPage> createState() =>
      _PatientRegistrationPageState();
}

class _PatientRegistrationPageState extends State<PatientRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _firestore = FirestoreService();

  final _nameController = TextEditingController();
  final _icController = TextEditingController();
  final _dobController = TextEditingController();
  final _ageController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _addressController = TextEditingController();
  final _otherConditionController = TextEditingController();
  final _notesController = TextEditingController();

  String? _gender;
  final Set<String> _selectedConditions = {};
  bool _hidePassword = true;
  bool _loading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _icController.dispose();
    _dobController.dispose();
    _ageController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _addressController.dispose();
    _otherConditionController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  bool _isValidPhone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return RegExp(r'^01\d{7,9}$').hasMatch(digits);
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
    _dobController.text = MalaysianIc.dateOfBirth(formatted) ?? '';
    _ageController.text = MalaysianIc.age(formatted)?.toString() ?? '';
  }

  void _onPhoneChanged(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    final s = digits.length > 11 ? digits.substring(0, 11) : digits;
    final formatted = s.length > 3 ? '${s.substring(0, 3)}-${s.substring(3)}' : s;
    if (formatted != _phoneController.text) {
      _phoneController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
  }

  void _toggleCondition(String condition, bool selected) {
    setState(() {
      if (selected) {
        _selectedConditions.add(condition);
      } else {
        _selectedConditions.remove(condition);
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final conditions = <String>[..._selectedConditions];
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

      await _firestore.createPatientAccount(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        caregiverId: widget.caregiverId,
        icNumber: _icController.text.trim(),
        gender: _gender ?? '',
        phone: _phoneController.text.trim(),
        address: _addressController.text.trim(),
        medicalHistory: conditions,
        medicalNotes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        const SnackBar(content: Text('Patient account registered successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.paleBlue,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppTheme.navy, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Register Patient',
          style: TextStyle(
            color: AppTheme.navy,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('Personal Details', Icons.badge_outlined),
              const SizedBox(height: 12),
              _card(
                child: Column(
                  children: [
                    _buildField(
                      controller: _nameController,
                      label: 'Full Name',
                      icon: Icons.person_outline,
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Name is required' : null,
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      controller: _icController,
                      label: 'IC Number',
                      icon: Icons.credit_card,
                      hint: 'YYMMDD-STATE-XXXX  e.g. 920601-01-2345',
                      keyboardType: TextInputType.number,
                      onChanged: _onIcChanged,
                      validator: (v) {
                        final val = (v ?? '').trim();
                        if (val.isEmpty) return 'IC number is required';
                        if (!MalaysianIc.isValid(val)) {
                          return 'Invalid IC (format: YYMMDD-STATE-XXXX)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildReadOnlyField(
                            controller: _dobController,
                            label: 'Date of Birth (auto)',
                            icon: Icons.cake_outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildReadOnlyField(
                            controller: _ageController,
                            label: 'Age',
                            icon: Icons.calendar_today,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: _gender,
                      decoration: _decoration(
                        label: 'Gender',
                        icon: Icons.wc,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Male', child: Text('Male')),
                        DropdownMenuItem(value: 'Female', child: Text('Female')),
                      ],
                      onChanged: (v) => setState(() => _gender = v),
                      validator: (v) => v == null ? 'Select gender' : null,
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      controller: _phoneController,
                      label: 'Phone Number',
                      icon: Icons.phone_outlined,
                      hint: 'e.g. 012-3456789',
                      keyboardType: TextInputType.phone,
                      onChanged: _onPhoneChanged,
                      validator: (v) {
                        final val = (v ?? '').trim();
                        if (val.isEmpty) return 'Phone number is required';
                        if (!_isValidPhone(val)) {
                          return 'Invalid Malaysian number (e.g. 012-3456789)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      controller: _emailController,
                      label: 'Account Registered Email',
                      icon: Icons.email_outlined,
                      hint: 'Used for patient to log in',
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) =>
                          v == null || !v.contains('@')
                              ? 'Valid email required'
                              : null,
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      controller: _passwordController,
                      label: 'Password',
                      icon: Icons.lock_outline,
                      obscure: _hidePassword,
                      suffix: IconButton(
                        onPressed: () => setState(() => _hidePassword = !_hidePassword),
                        icon: Icon(
                          _hidePassword ? Icons.visibility : Icons.visibility_off,
                          color: AppTheme.muted,
                        ),
                      ),
                      validator: (v) =>
                          v == null || v.length < 6
                              ? 'Min 6 characters'
                              : null,
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      controller: _addressController,
                      label: 'Home Address',
                      icon: Icons.home_outlined,
                      hint: 'Patient home address',
                      maxLines: 3,
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Address is required' : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _sectionTitle('Patient Medical Profile', Icons.medical_information_outlined),
              const SizedBox(height: 6),
              const Text(
                'Select the patient\u2019s past medical history or current medical '
                'record from the disease list.',
                style: TextStyle(fontSize: 12, color: AppTheme.muted),
              ),
              const SizedBox(height: 12),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Select Conditions',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.muted,
                          ),
                        ),
                        TextButton(
                          onPressed: _selectedConditions.isEmpty
                              ? null
                              : () => setState(() => _selectedConditions.clear()),
                          style: TextButton.styleFrom(
                            foregroundColor: _selectedConditions.isEmpty
                                ? AppTheme.muted
                                : Colors.red,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: const Size(0, 32),
                          ),
                          child: const Text(
                            'Clear All',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final condition in MedicalHistoryCatalog.conditions)
                          FilterChip(
                            selected: _selectedConditions.contains(condition),
                            onSelected: (sel) =>
                                _toggleCondition(condition, sel),
                            label: Text(
                              condition,
                              style: const TextStyle(fontSize: 12),
                            ),
                            selectedColor: AppTheme.navy.withValues(alpha: .18),
                            checkmarkColor: AppTheme.navy,
                            side: BorderSide(
                              color: _selectedConditions.contains(condition)
                                  ? AppTheme.navy
                                  : AppTheme.border,
                            ),
                          ),
                      ],
                    ),
                    if (_selectedConditions.contains('Other')) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Specify Other Condition(s)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.muted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _otherConditionController,
                        decoration: _decoration(
                          label: null,
                          icon: Icons.edit_note,
                          hint: 'Separate with commas',
                        ),
                        maxLines: 2,
                        validator: (v) => _selectedConditions.contains('Other') &&
                                (v == null || v.trim().isEmpty)
                            ? 'Specify the other condition(s)'
                            : null,
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Text(
                      'Details / Extra Notes',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.muted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _notesController,
                      decoration: _decoration(
                        label: null,
                        icon: Icons.notes,
                        hint: 'Additional medical notes for the patient',
                      ),
                      maxLines: 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.navy,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    disabledBackgroundColor: AppTheme.navy.withValues(alpha: .5),
                  ),
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Register Patient Account',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.navy, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppTheme.navy,
          ),
        ),
      ],
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFC2C5)),
      ),
      child: child,
    );
  }

  InputDecoration _decoration({
    String? label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 12, color: AppTheme.muted),
      prefixIcon: Icon(icon, color: AppTheme.muted, size: 20),
      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(9))),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(9)),
        borderSide: BorderSide(color: AppTheme.border),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(9)),
        borderSide: BorderSide(color: AppTheme.navy, width: 1.5),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? suffix,
    int maxLines = 1,
    void Function(String)? onChanged,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      maxLines: maxLines,
      onChanged: onChanged,
      validator: validator,
      decoration: _decoration(label: label, icon: icon, hint: hint)
          .copyWith(suffixIcon: suffix),
    );
  }

  Widget _buildReadOnlyField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      decoration: _decoration(label: label, icon: icon),
    );
  }
}