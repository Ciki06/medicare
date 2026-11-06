import 'package:flutter/material.dart';

/// One optional instruction shared by medication creation and editing.
class MedicationMealTimingField extends StatelessWidget {
  const MedicationMealTimingField({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  static const options = ['Before Meal', 'After Meal'];
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: options.contains(value) ? value : null,
    isExpanded: true,
    decoration: const InputDecoration(
      labelText: 'Meal timing (optional)',
      hintText: 'Select meal timing',
      border: OutlineInputBorder(),
      isDense: true,
    ),
    items: options
        .map((option) => DropdownMenuItem(value: option, child: Text(option)))
        .toList(),
    onChanged: enabled ? onChanged : null,
  );
}

class MedicationMealTimingLabel extends StatelessWidget {
  const MedicationMealTimingLabel({super.key, required this.value});

  final String? value;

  @override
  Widget build(BuildContext context) => value == null || value!.isEmpty
      ? const SizedBox.shrink()
      : Text(value!, style: const TextStyle(fontSize: 12));
}
