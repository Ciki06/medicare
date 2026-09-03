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

class _MedEntry {
  final nameCtrl = TextEditingController();
  final doseCtrl = TextEditingController();
  final stockCtrl = TextEditingController();
  final thresholdCtrl = TextEditingController(text: '5');
  String? type;
  String? frequency;
  bool remindRefill = true;
  Uint8List? imageBytes;
  bool pickingImage = false;

  void dispose() {
    nameCtrl.dispose();
    doseCtrl.dispose();
    stockCtrl.dispose();
    thresholdCtrl.dispose();
  }
}

class _AddMedicationPageState extends State<AddMedicationPage> {
  final _firestoreService = FirestoreService();
  final _storageService = StorageService();
  final _picker = ImagePicker();
  final _scrollCtrl = ScrollController();

  UserModel? _selectedPatient;
  TimeOfDay _selectedTime = const TimeOfDay(hour: 8, minute: 0);
  bool _saving = false;

  final List<_MedEntry> _entries = [_MedEntry()];

  static const _types = [
    'Pill',
    'Injection',
    'Solution (Liquid)',
    'Drops',
    'Inhaler',
  ];
  static const _frequencies = [
    'Once',
    'Daily',
    'Weekly',
    'Monthly',
    'Every X days',
  ];

  @override
  void dispose() {
    for (final e in _entries) {
      e.dispose();
    }
    _scrollCtrl.dispose();
    super.dispose();
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      initialEntryMode: TimePickerEntryMode.dial,
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  Future<void> _pickImage(int index) async {
    final entry = _entries[index];
    if (entry.pickingImage) return;
    setState(() => entry.pickingImage = true);
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 70,
      );
      if (file != null) {
        final bytes = await file.readAsBytes();
        if (mounted) setState(() => entry.imageBytes = bytes);
      }
    } finally {
      if (mounted) setState(() => entry.pickingImage = false);
    }
  }

  void _addEntry() {
    setState(() => _entries.add(_MedEntry()));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _removeEntry(int index) {
    if (_entries.length <= 1) return;
    setState(() {
      _entries[index].dispose();
      _entries.removeAt(index);
    });
  }

  Future<void> _saveAll() async {
    final patient = _selectedPatient;
    if (patient == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a patient.')));
      return;
    }

    final valid = _entries
        .where((e) => e.nameCtrl.text.trim().isNotEmpty)
        .toList();
    if (valid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter at least one medication name.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      int count = 0;
      for (final e in valid) {
        final medId = await _firestoreService.addMedication(
          caregiverId: widget.caregiver.uid,
          patientId: patient.uid,
          patientName: patient.name,
          name: e.nameCtrl.text.trim(),
          type: e.type ?? 'Pill',
          dosage: e.doseCtrl.text.isNotEmpty
              ? '${e.doseCtrl.text} pill(s)'
              : '1 pill',
          time: _fmtTime(_selectedTime),
          currentStock: int.tryParse(e.stockCtrl.text) ?? 0,
          imageUrl: null,
          remindRefill: e.remindRefill,
          remindThreshold: int.tryParse(e.thresholdCtrl.text) ?? 5,
        );

        if (e.imageBytes != null) {
          try {
            final url = await _storageService.uploadMedicationImage(
              medId,
              e.imageBytes!,
            );
            await _firestoreService.updateMedicationImage(medId, url);
          } catch (err) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Image failed for ${e.nameCtrl.text}'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          }
        }
        count++;
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$count medication(s) added!')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ─── BUILD ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
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
          'Add Medication',
          style: TextStyle(
            color: AppTheme.navy,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: StreamBuilder<List<UserModel>>(
          stream: _firestoreService.getPatientsByCaregiver(
            widget.caregiver.uid,
          ),
          builder: (context, snapshot) {
            final patients = snapshot.data ?? [];
            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Patient ──
                        const Text(
                          'Select Patient',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.navy,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _buildPatientDropdown(patients),
                        const SizedBox(height: 16),

                        // ── Time ──
                        const Text(
                          'Time',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.navy,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: _pickTime,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFBFC2C5),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _fmtTime(_selectedTime),
                                  style: const TextStyle(fontSize: 14),
                                ),
                                const Icon(
                                  Icons.access_time,
                                  size: 18,
                                  color: AppTheme.muted,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ── Medicine entries ──
                        ...List.generate(
                          _entries.length,
                          (i) => _buildMedCard(i),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Bottom buttons ──
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFE5E5E5))),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 46,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF1E3A8A),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _saving ? null : _saveAll,
                              icon: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                              label: Text(
                                _saving
                                    ? 'Saving...'
                                    : 'Save (${_entries.where((e) => e.nameCtrl.text.isNotEmpty).length})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 46,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF48AF75),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _addEntry,
                              icon: const Icon(
                                Icons.add,
                                color: Colors.white,
                                size: 18,
                              ),
                              label: const Text(
                                'Medicine',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ─── MED CARD ───────────────────────────────────────────────────────────

  Widget _buildMedCard(int index) {
    final e = _entries[index];
    final isPicking = e.pickingImage;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFC2C5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppTheme.navy,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Medicine',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppTheme.navy,
                  ),
                ),
              ),
              if (_entries.length > 1)
                GestureDetector(
                  onTap: () => _removeEntry(index),
                  child: const Icon(
                    Icons.delete_outline,
                    color: Color(0xFFE85B61),
                    size: 20,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Med Name
          _label('Medicine Name'),
          const SizedBox(height: 6),
          TextFormField(
            controller: e.nameCtrl,
            onChanged: (_) => setState(() {}),
            decoration: _inputDeco(
              hint: 'Type Medication Name',
              icon: Icons.search,
            ),
          ),
          const SizedBox(height: 14),

          // Type + Dose
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Type'),
                    const SizedBox(height: 6),
                    _dropdown(
                      hint: 'Select Type',
                      value: e.type,
                      items: _types,
                      onChanged: (v) => setState(() => e.type = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Dose'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: e.doseCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _inputDeco(hint: '1', suffix: 'pill(s)'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // How Often
          _label('How often?'),
          const SizedBox(height: 6),
          _dropdown(
            hint: 'Select Frequency',
            value: e.frequency,
            items: _frequencies,
            onChanged: (v) => setState(() => e.frequency = v),
          ),
          const SizedBox(height: 14),

          // Stock
          _label('Current Stock'),
          const SizedBox(height: 6),
          TextFormField(
            controller: e.stockCtrl,
            keyboardType: TextInputType.number,
            decoration: _inputDeco(
              hint: 'e.g. 30',
              suffix: 'units',
              icon: Icons.inventory_2,
            ),
          ),
          const SizedBox(height: 14),

          // Refill Reminder
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD5D5D5)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.notifications_outlined,
                  size: 18,
                  color: AppTheme.navy,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Refill Reminder',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppTheme.navy,
                    ),
                  ),
                ),
                Switch(
                  value: e.remindRefill,
                  onChanged: (v) => setState(() => e.remindRefill = v),
                  activeThumbColor: const Color(0xFF48AF75),
                  activeTrackColor: const Color(
                    0xFF48AF75,
                  ).withValues(alpha: .4),
                ),
              ],
            ),
          ),
          if (e.remindRefill) ...[
            const SizedBox(height: 10),
            _label('Remind when stock reaches'),
            const SizedBox(height: 6),
            TextFormField(
              controller: e.thresholdCtrl,
              keyboardType: TextInputType.number,
              decoration: _inputDeco(
                hint: 'e.g. 5',
                suffix: 'pills',
                icon: Icons.notifications_active,
              ),
            ),
          ],
          const SizedBox(height: 14),

          // Photo
          _label('Photo (optional)'),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: isPicking ? null : () => _pickImage(index),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD5D5D5)),
              ),
              child: isPicking
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : e.imageBytes != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        e.imageBytes!,
                        height: 100,
                        fit: BoxFit.contain,
                      ),
                    )
                  : Column(
                      children: const [
                        Icon(
                          Icons.add_photo_alternate,
                          size: 30,
                          color: AppTheme.muted,
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Tap to upload image',
                          style: TextStyle(color: AppTheme.muted, fontSize: 12),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── HELPERS ────────────────────────────────────────────────────────────

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      fontWeight: FontWeight.w600,
      color: AppTheme.navy,
      fontSize: 13,
    ),
  );

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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFBFC2C5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFBFC2C5)),
        ),
      ),
      dropdownMenuEntries: patients
          .map((p) => DropdownMenuEntry(value: p, label: p.name))
          .toList(),
      onSelected: (val) => setState(() => _selectedPatient = val),
    );
  }

  Widget _dropdown({
    required String hint,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownMenu<String>(
      expandedInsets: EdgeInsets.zero,
      menuHeight: 200,
      initialSelection: value,
      hintText: hint,
      textStyle: const TextStyle(fontSize: 13, color: Colors.black),
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
      dropdownMenuEntries: items
          .map((s) => DropdownMenuEntry(value: s, label: s))
          .toList(),
      onSelected: onChanged,
    );
  }

  InputDecoration _inputDeco({
    required String hint,
    String? suffix,
    IconData? icon,
  }) {
    return InputDecoration(
      prefixIcon: icon != null
          ? Icon(icon, color: AppTheme.muted, size: 20)
          : null,
      hintText: hint,
      suffixText: suffix,
      hintStyle: const TextStyle(color: AppTheme.muted, fontSize: 13),
      fillColor: Colors.white,
      filled: true,
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
