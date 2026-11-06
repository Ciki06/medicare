import 'package:flutter/material.dart';

import '../models/medication_dosage.dart';
import '../theme/app_theme.dart';

/// Keeps the numeric prescription separate from its unit during type changes.
class MedicationDosageController extends ChangeNotifier {
  MedicationDosageController({String? type, String? dosage})
    : _type = MedicationDosage.canonicalType(type) {
    final parsed = dosage == null
        ? null
        : MedicationDosage.parse(dosage: dosage, type: effectiveType);
    amountController = TextEditingController(text: parsed?.amount ?? '');
    unitController = TextEditingController(
      text: parsed?.unit ?? MedicationDosage.defaultUnitFor(type),
    );
    _legacyOriginal = parsed?.isStructured == false ? parsed!.original : null;
    _initialType = _type;
    _initialAmount = amountController.text;
    _initialUnit = unitController.text;
    amountController.addListener(notifyListeners);
    unitController.addListener(notifyListeners);
  }

  late final TextEditingController amountController;
  late final TextEditingController unitController;
  String? _type;
  String? _legacyOriginal;
  late final String? _initialType;
  late final String _initialAmount;
  late final String _initialUnit;

  String? get type => _type;
  String get effectiveType => _type ?? 'Pill';
  String get stockUnit =>
      MedicationDosage.countsStockAsDoses(effectiveType) ? 'doses' : 'units';
  String get unit => unitController.text;
  bool get keepsLegacyInstructions =>
      _legacyOriginal != null &&
      _legacyOriginal!.trim().isNotEmpty &&
      _type == _initialType &&
      amountController.text == _initialAmount &&
      unitController.text == _initialUnit;

  List<String> get typeOptions => [
    ...MedicationDosage.types,
    if (_type != null && !MedicationDosage.types.contains(_type)) _type!,
  ];

  List<String> get unitOptions => {
    ...MedicationDosage.unitsForType(_type),
    if (unit.isNotEmpty) unit,
  }.toList();

  void changeType(String? value) {
    if (value == null || value == _type) return;
    _type = value;
    // Never rewrite the amount: selecting another form is not a conversion.
    unitController.text = MedicationDosage.defaultUnitFor(value);
    notifyListeners();
  }

  void changeUnit(String? value) {
    if (value != null) unitController.text = value;
  }

  String? validationError({bool defaultAmount = false}) {
    if (keepsLegacyInstructions) return null;
    final amount = defaultAmount && amountController.text.trim().isEmpty
        ? '1'
        : amountController.text;
    final error =
        MedicationDosage.amountError(amount) ??
        MedicationDosage.unitError(unit, type: effectiveType);
    if (error != null) return error;
    try {
      MedicationDosage.format(amount: amount, unit: unit);
    } on FormatException catch (error) {
      return error.message;
    }
    return null;
  }

  String dosage({bool defaultAmount = false}) {
    if (keepsLegacyInstructions) return _legacyOriginal!;
    final error = validationError(defaultAmount: defaultAmount);
    if (error != null) throw FormatException(error);
    return MedicationDosage.format(
      amount: defaultAmount && amountController.text.trim().isEmpty
          ? '1'
          : amountController.text,
      unit: unit,
    );
  }

  @override
  void dispose() {
    amountController.removeListener(notifyListeners);
    unitController.removeListener(notifyListeners);
    amountController.dispose();
    unitController.dispose();
    super.dispose();
  }
}

/// Shared by medication creation, full editing and caregiver quick editing.
class MedicationDosageFields extends StatelessWidget {
  const MedicationDosageFields({
    super.key,
    required this.controller,
    this.enabled = true,
    this.includeType = true,
  });

  final MedicationDosageController controller;
  final bool enabled;
  final bool includeType;

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      color: AppTheme.navy,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    ),
  );

  InputDecoration _decoration({String? hint, String? suffix}) =>
      InputDecoration(
        hintText: hint,
        suffixText: suffix,
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final unit = controller.unit;
      final units = controller.unitOptions;
      final custom = MedicationDosage.isCustomType(controller.type);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (includeType) ...[
            _label('Medication type'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              key: ValueKey('medication-type-${controller.type}'),
              initialValue: controller.type,
              isExpanded: true,
              decoration: _decoration(hint: 'Select type'),
              items: controller.typeOptions
                  .map(
                    (type) => DropdownMenuItem(value: type, child: Text(type)),
                  )
                  .toList(),
              onChanged: enabled ? controller.changeType : null,
            ),
            const SizedBox(height: 14),
          ],
          _label('Dosage'),
          const SizedBox(height: 6),
          TextFormField(
            key: const Key('medication-dose-amount'),
            controller: controller.amountController,
            enabled: enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _decoration(
              hint: '1',
              // Custom units have their own full-width field below. A long
              // suffix would otherwise squeeze the editable amount to zero.
              suffix: controller.keepsLegacyInstructions || custom
                  ? null
                  : MedicationDosage.unitLabel(
                      unit,
                      controller.amountController.text,
                    ),
            ),
          ),
          if (custom || units.length > 1) ...[
            const SizedBox(height: 10),
            _label('Dosage unit'),
            const SizedBox(height: 6),
            if (custom)
              TextFormField(
                key: const Key('medication-dose-custom-unit'),
                controller: controller.unitController,
                enabled: enabled,
                maxLength: 32,
                decoration: _decoration(hint: 'e.g. mg, patch or spray'),
              )
            else
              DropdownButtonFormField<String>(
                key: ValueKey('medication-dose-unit-$unit'),
                initialValue: units.contains(unit) ? unit : null,
                isExpanded: true,
                decoration: _decoration(),
                items: units
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: enabled ? controller.changeUnit : null,
              ),
          ],
          if (controller.keepsLegacyInstructions) ...[
            const SizedBox(height: 6),
            const Text(
              'Existing dosage instructions will be kept unless you edit them. To change the dose, enter an amount and choose its unit.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ],
        ],
      );
    },
  );
}
