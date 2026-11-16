import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../services/schedule_time.dart';
import '../../widgets/medication_frequency_fields.dart';
import '../../widgets/app_time_picker.dart';
import '../../widgets/medication_meal_timing.dart';
import '../../widgets/medication_dosage_fields.dart';

/// Lets a caregiver enter several medications for one patient and schedule time.
class AddMedicationPage extends StatefulWidget {
  final UserModel caregiver;

  const AddMedicationPage({super.key, required this.caregiver});

  @override
  State<AddMedicationPage> createState() => _AddMedicationPageState();
}

/// Keeps the fields and settings for one medication row together.
class _MedEntry {
  final nameCtrl = TextEditingController();
  final dosage = MedicationDosageController();
  final stockCtrl = TextEditingController();
  final thresholdCtrl = TextEditingController();
  String? mealTiming;
  String? frequency;
  String startDate = ScheduleTime.today();
  int intervalDays = 1;
  bool remindRefill = true;
  Uint8List? imageBytes;
  bool pickingImage = false;

  /// Release the controllers owned by this medication form.
  void dispose() {
    nameCtrl.dispose();
    dosage.dispose();
    stockCtrl.dispose();
    thresholdCtrl.dispose();
  }
}

class _AddMedicationPageState extends State<AddMedicationPage> {
  /// Use Firestore for medication records and Storage for optional photos.
  final _firestoreService = FirestoreService();
  final _storageService = StorageService();
  final _picker = ImagePicker();
  final _scrollCtrl = ScrollController();

  /// All rows share a patient and time. Each row has its own prescription and stock settings.
  UserModel? _selectedPatient;
  TimeOfDay? _selectedTime;
  bool _saving = false;

  /// Start with one blank row so the form is ready to use.
  final List<_MedEntry> _entries = [_MedEntry()];

  @override
  void dispose() {
    /// Release the remaining row controllers when the page closes.
    for (final e in _entries) {
      e.dispose();
    }
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// Save the selected time in 24-hour HH:mm format.
  /// Pad the hour and minute with zeros so 9:05 AM becomes 09:05.
  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime() async {
    final picked = await showAppTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.fromDateTime(ScheduleTime.now()),
      initialEntryMode: TimePickerEntryMode.dial,
    );

    /// Keep the current time if the picker is cancelled. Update the page only while it is mounted.
    if (picked != null && mounted) setState(() => _selectedTime = picked);
  }

  /// Choose an optional picture for the selected medication row.
  Future<void> _pickImage(int index) async {
    final entry = _entries[index];

    /// Prevent a second image picker from opening for the same row.
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
        /// Keep the photo in memory for the preview and upload it when saving.
        final bytes = await file.readAsBytes();
        if (mounted) setState(() => entry.imageBytes = bytes);
      }
    } finally {
      if (mounted) setState(() => entry.pickingImage = false);
    }
  }

  /// Add a blank row and wait for layout before scrolling to it.
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

  /// Remove the row and release the input controllers it owns.
  void _removeEntry(int index) {
    /// Keep at least one row available for entering a medication.
    if (_entries.length <= 1) return;
    setState(() {
      _entries[index].dispose();
      _entries.removeAt(index);
    });
  }

  /// Validate the patient, time, and all filled rows before saving. Upload each optional picture after the medication has a record ID.
  Future<void> _saveAll() async {
    /// Require the shared patient and time before checking individual rows.
    final patient = _selectedPatient;
    if (patient == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a patient.')));
      return;
    }

    final selectedTime = _selectedTime;
    if (selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a medication time.')),
      );
      return;
    }

    /// Skip rows with blank names. The caregiver can leave an extra row empty.
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

    /// Validate each named medication and collect its dose settings before saving.
    final dosageSettings = <_MedEntry, ({String type, String dosage})>{};
    for (final entry in valid) {
      final error = entry.dosage.validationError(defaultAmount: true);
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${entry.nameCtrl.text.trim()}: $error')),
        );
        return;
      }
      dosageSettings[entry] = (
        type: entry.dosage.effectiveType,
        dosage: entry.dosage.dosage(defaultAmount: true),
      );
    }

    /// Check the stock threshold for each row that has refill reminders enabled.
    final refillSettings = <_MedEntry, ({bool enabled, int threshold})>{};
    for (final entry in valid) {
      /// A row with refill reminders disabled needs no stock threshold from the form.
      if (!entry.remindRefill) {
        refillSettings[entry] = (enabled: false, threshold: 0);
        continue;
      }
      final threshold = int.tryParse(entry.thresholdCtrl.text.trim());

      /// Require a non-negative whole number within JavaScript's safe integer range.
      if (threshold == null || threshold < 0 || threshold > 9007199254740991) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Enter a whole-number refill stock level (0 or more) for ${entry.nameCtrl.text.trim()}.',
            ),
          ),
        );
        return;
      }
      refillSettings[entry] = (enabled: true, threshold: threshold);
    }

    /// Show progress and disable the Save button while the requests run.
    setState(() => _saving = true);

    try {
      int count = 0;

      /// Save each row as its own medication record with the shared patient and time.
      for (final e in valid) {
        final refill = refillSettings[e]!;
        final prescription = dosageSettings[e]!;
        final medId = await _firestoreService.addMedication(
          caregiverId: widget.caregiver.uid,
          patientId: patient.uid,
          patientName: patient.name,
          name: e.nameCtrl.text.trim(),
          type: prescription.type,
          dosage: prescription.dosage,
          time: _fmtTime(selectedTime),
          mealTiming: e.mealTiming,
          days: [e.frequency ?? 'Daily'],
          startDate: e.startDate,
          intervalDays: e.intervalDays,
          currentStock: int.tryParse(e.stockCtrl.text) ?? 0,
          imageUrl: null,
          remindRefill: refill.enabled,
          remindThreshold: refill.threshold,
        );

        /// Upload the image after saving the medication so the upload can use its record ID.
        if (e.imageBytes != null) {
          try {
            final url = await _storageService.uploadMedicationImage(
              medId,
              e.imageBytes!,
            );

            /// Attach the uploaded photo URL to the medication record.
            await _firestoreService.updateMedicationImage(medId, url);

            /// Report the photo failure separately because the medication record already exists.
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

  /// Build the form for the selected patient, time, and medication rows.
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
        /// Keep the patient dropdown in sync with the caregiver's patient list.
        child: StreamBuilder<List<UserModel>>(
          stream: _firestoreService.getPatientsByCaregiver(
            widget.caregiver.uid,
          ),
          builder: (context, snapshot) {
            final patients = snapshot.data ?? [];
            return Column(
              children: [
                Expanded(
                  /// Let the form scroll while keeping the Save and Medicine buttons below it.
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
                          onTap: _saving ? null : _pickTime,
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
                                  _selectedTime == null
                                      ? 'Select time'
                                      : formatAppTime(_selectedTime!),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: _selectedTime == null
                                        ? AppTheme.muted
                                        : null,
                                  ),
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

            /// Refresh the count on the Save button when the name changes.
            onChanged: (_) => setState(() {}),
            decoration: _inputDeco(
              hint: 'Type Medication Name',
              icon: Icons.search,
            ),
          ),
          const SizedBox(height: 14),

          /// Use this row's dose controller for the type, amount, and unit.
          MedicationDosageFields(
            key: ObjectKey(e.dosage),
            controller: e.dosage,
            enabled: !_saving,
          ),
          const SizedBox(height: 14),

          /// Meal timing
          MedicationMealTimingField(
            key: ObjectKey(e),
            value: e.mealTiming,
            enabled: !_saving,
            onChanged: (value) => setState(() => e.mealTiming = value),
          ),
          const SizedBox(height: 14),

          // How Often
          _label('How often?'),
          const SizedBox(height: 6),
          // Store the repeat pattern and any start date or interval it uses.
          MedicationFrequencyFields(
            frequency: e.frequency ?? 'Daily',
            startDate: e.startDate,
            intervalDays: e.intervalDays,
            onChanged: (frequency, date, interval) => setState(() {
              e.frequency = frequency;
              e.startDate = date;
              e.intervalDays = interval;
            }),
          ),
          const SizedBox(height: 14),

          // Stock
          _label('Current Stock'),
          const SizedBox(height: 6),
          // Refresh the stock unit shown in this field when the medication type changes.
          ListenableBuilder(
            listenable: e.dosage,
            builder: (context, child) => TextFormField(
              controller: e.stockCtrl,
              keyboardType: TextInputType.number,
              decoration: _inputDeco(
                hint: 'e.g. 30',
                suffix: e.dosage.stockUnit,
                icon: Icons.inventory_2,
              ),
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
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => e.remindRefill = v),
                  activeThumbColor: const Color(0xFF48AF75),
                  activeTrackColor: const Color(
                    0xFF48AF75,
                  ).withValues(alpha: .4),
                ),
              ],
            ),
          ),

          /// Show the threshold field when refill reminders are enabled for this row.
          if (e.remindRefill) ...[
            const SizedBox(height: 10),
            _label('Remind when stock reaches'),
            const SizedBox(height: 6),
            ListenableBuilder(
              listenable: e.dosage,
              builder: (context, child) => TextFormField(
                controller: e.thresholdCtrl,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                decoration: _inputDeco(
                  hint: 'Enter stock level',
                  suffix: e.dosage.stockUnit,
                  icon: Icons.notifications_active,
                ),
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

  /// Reuse the same field styling while allowing different hints, icons, and units.
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
