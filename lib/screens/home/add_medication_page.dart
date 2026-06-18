import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';

class AddMedicationPage extends StatefulWidget {
  final UserModel caregiver;

  const AddMedicationPage({super.key, required this.caregiver});

  @override
  State<AddMedicationPage> createState() => _AddMedicationPageState();
}

class _AddMedicationPageState extends State<AddMedicationPage> {
  final _firestoreService = FirestoreService();
  final _storageService = StorageService();
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  UserModel? _selectedPatient;
  final _nameController = TextEditingController();
  final _doseController = TextEditingController();
  final _stockController = TextEditingController();
  final _remindThresholdController = TextEditingController(text: '5');
  String? _selectedType;
  String? _selectedFrequency;
  TimeOfDay _selectedTime = const TimeOfDay(hour: 8, minute: 0);
  bool _remindRefill = true;

  Uint8List? _medImageBytes;
  bool _saving = false;
  bool _pickingImage = false;

  final List<String> _medicationTypes = [
    'Pill', 'Injection', 'Solution (Liquid)', 'Drops', 'Inhaler',
  ];
  final List<String> _frequencies = [
    'Daily', 'Weekly', 'Monthly', 'Every X days',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _doseController.dispose();
    _stockController.dispose();
    _remindThresholdController.dispose();
    super.dispose();
  }

  String _formatTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final min = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$min $period';
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      initialEntryMode: TimePickerEntryMode.dial,
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  Future<void> _pickImage() async {
    if (_pickingImage) return;
    setState(() => _pickingImage = true);
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 70,
      );
      if (file != null) {
        final bytes = await file.readAsBytes();
        if (mounted) setState(() => _medImageBytes = bytes);
      }
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<void> _saveMedication() async {
    final patient = _selectedPatient;
    if (patient == null || _nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill out patient and medication name.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final medId = await _firestoreService.addMedication(
        caregiverId: widget.caregiver.uid,
        patientId: patient.uid,
        patientName: patient.name,
        name: _nameController.text.trim(),
        type: _selectedType ?? 'Pill',
        dosage: _doseController.text.isNotEmpty
            ? '${_doseController.text} pill(s)'
            : '1 pill',
        time: _formatTime(_selectedTime),
        currentStock: int.tryParse(_stockController.text) ?? 0,
        imageUrl: null,
        remindRefill: _remindRefill,
        remindThreshold: int.tryParse(_remindThresholdController.text) ?? 5,
      );

      if (_medImageBytes != null) {
        try {
          final imageUrl = await _storageService.uploadMedicationImage(medId, _medImageBytes!);
          await _firestoreService.updateMedicationImage(medId, imageUrl);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Medication saved but image upload failed: ${e.toString().substring(0, e.toString().length.clamp(0, 80))}'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Medication successfully added!')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppTheme.navy, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Medication',
          style: TextStyle(color: AppTheme.navy, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: StreamBuilder<List<UserModel>>(
          stream: _firestoreService.getPatientsByCaregiver(widget.caregiver.uid),
          builder: (context, snapshot) {
            final patients = snapshot.data ?? [];
            return Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Select a patient',
                      style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.navy)),
                    const SizedBox(height: 6),
                    _buildPatientDropdown(patients),
                    const SizedBox(height: 18),

                    const Text('Medication Name:',
                      style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.navy)),
                    const SizedBox(height: 6),
                    _buildField(controller: _nameController, hint: 'Type Medication Name', icon: Icons.search),
                    const SizedBox(height: 18),

                    const Text('Medication Type:',
                      style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.navy)),
                    const SizedBox(height: 6),
                    _buildStringDropdown(
                      hint: 'Select Medication Type',
                      value: _selectedType,
                      items: _medicationTypes,
                      onChanged: (v) => setState(() => _selectedType = v),
                    ),
                    const SizedBox(height: 18),

                    const Text('How often do patient take it?',
                      style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.navy)),
                    const SizedBox(height: 6),
                    _buildStringDropdown(
                      hint: 'Select Days',
                      value: _selectedFrequency,
                      items: _frequencies,
                      onChanged: (v) => setState(() => _selectedFrequency = v),
                    ),
                    const SizedBox(height: 18),

                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Time:',
                                style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.navy)),
                              const SizedBox(height: 6),
                              InkWell(
                                onTap: _pickTime,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFBFC2C5)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(_formatTime(_selectedTime), style: const TextStyle(fontSize: 14)),
                                      const Icon(Icons.access_time, size: 18, color: AppTheme.muted),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Dose:',
                                style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.navy)),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _doseController,
                                keyboardType: TextInputType.number,
                                decoration: _inputDeco(hint: '1', suffix: 'pill(s)'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    const Text('Current Stock / Quantity:',
                      style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.navy)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _stockController,
                      keyboardType: TextInputType.number,
                      decoration: _inputDeco(hint: 'e.g. 30', suffix: 'units', icon: Icons.inventory_2),
                    ),
                    const SizedBox(height: 18),

                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBFC2C5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.notifications_outlined, size: 20, color: AppTheme.navy),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text('Refill Reminder',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.navy)),
                                Text('Notify when stock is low',
                                  style: TextStyle(fontSize: 11, color: AppTheme.muted)),
                              ],
                            ),
                          ),
                          Switch(
                            value: _remindRefill,
                            onChanged: (v) => setState(() => _remindRefill = v),
                            activeThumbColor: const Color(0xFF48AF75),
                            activeTrackColor: const Color(0xFF48AF75).withValues(alpha: .4),
                          ),
                        ],
                      ),
                    ),
                    if (_remindRefill) ...[
                      const SizedBox(height: 10),
                      const Text('Remind when stock reaches:',
                        style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.navy)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _remindThresholdController,
                        keyboardType: TextInputType.number,
                        decoration: _inputDeco(hint: 'e.g. 5', suffix: 'pills', icon: Icons.notifications_active),
                      ),
                    ],
                    const SizedBox(height: 18),

                    const Text('Medication Image (optional):',
                      style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.navy)),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: _pickingImage ? null : _pickImage,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFBFC2C5)),
                        ),
                        child: _pickingImage
                            ? const Center(child: SizedBox(
                                width: 24, height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ))
                            : _medImageBytes != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.memory(_medImageBytes!, height: 120, fit: BoxFit.contain),
                                  )
                                : Column(
                                    children: const [
                                      Icon(Icons.add_photo_alternate, size: 40, color: AppTheme.muted),
                                      SizedBox(height: 4),
                                      Text('Tap to upload image', style: TextStyle(color: AppTheme.muted, fontSize: 13)),
                                    ],
                                  ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    SizedBox(
                      width: double.infinity, height: 48,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1E3A8A),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _saving ? null : _saveMedication,
                        child: _saving
                            ? const SizedBox(width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Save',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPatientDropdown(List<UserModel> patients) {
    return DropdownMenu<UserModel>(
      expandedInsets: EdgeInsets.zero,
      menuHeight: 200,
      initialSelection: _selectedPatient,
      hintText: 'Select patient',
      textStyle: const TextStyle(fontSize: 14, color: Colors.black),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFBFC2C5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFBFC2C5)),
        ),
      ),
      dropdownMenuEntries: patients.map((p) =>
        DropdownMenuEntry(value: p, label: p.name)
      ).toList(),
      onSelected: (val) => setState(() => _selectedPatient = val),
    );
  }

  Widget _buildField({required TextEditingController controller, required String hint, IconData? icon}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFC2C5))),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          prefixIcon: icon != null ? Icon(icon, color: AppTheme.muted, size: 20) : null,
          hintText: hint,
          hintStyle: const TextStyle(color: AppTheme.muted, fontSize: 14),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        ),
      ),
    );
  }

  Widget _buildStringDropdown({
    required String hint, required String? value,
    required List<String> items, required ValueChanged<String?> onChanged,
  }) {
    return DropdownMenu<String>(
      expandedInsets: EdgeInsets.zero,
      menuHeight: 200,
      initialSelection: value,
      hintText: hint,
      textStyle: const TextStyle(fontSize: 14, color: Colors.black),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: Color(0xFFBFC2C5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: Color(0xFFBFC2C5)),
        ),
      ),
      dropdownMenuEntries: items.map((str) =>
        DropdownMenuEntry(value: str, label: str)
      ).toList(),
      onSelected: onChanged,
    );
  }

  InputDecoration _inputDeco({required String hint, String? suffix, IconData? icon}) {
    return InputDecoration(
      prefixIcon: icon != null ? Icon(icon, color: AppTheme.muted, size: 20) : null,
      hintText: hint,
      suffixText: suffix,
      hintStyle: const TextStyle(color: AppTheme.muted, fontSize: 14),
      fillColor: Colors.white, filled: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFBFC2C5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFBFC2C5)),
      ),
    );
  }
}
