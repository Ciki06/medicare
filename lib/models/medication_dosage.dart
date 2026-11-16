/// Handles medication dosage types, units, validation, and formatting.
class MedicationDosage {
  /// List of medication types available for selection.
  static const types = <String>[
    'Pill',
    'Capsule',
    'Injection',
    'Liquid',
    'Cream',
    'Ointment',
    'Powder',
    'Drops',
    'Inhaler',
    'Other',
  ];

  /// Converts alternative medication type names into standard names.
  static String? canonicalType(String? type) =>
      switch (type?.trim().toLowerCase()) {
        'tablet' => 'Pill',
        'solution' || 'solution (liquid)' || 'liquid' => 'Liquid',
        _ => type,
      };

  /// Checks whether liquid medication stock is counted by doses.
  static bool countsStockAsDoses(String? type) =>
      canonicalType(type) == 'Liquid' || _kind(type) == 'syrup';

  static String _kind(String? type) => (type ?? 'Pill').trim().toLowerCase();

  /// Returns the dosage units based on the selected medication type.
  static List<String> unitsForType(String? type) => switch (_kind(type)) {
    'pill' || 'tablet' || 'capsule' => const ['pill'],
    'injection' ||
    'solution (liquid)' ||
    'solution' ||
    'liquid' ||
    'syrup' => const ['ml'],
    'cream' || 'ointment' => const ['g'],
    'powder' => const ['g', 'mg'],
    'drops' || 'drop' => const ['drop'],
    'inhaler' => const ['puff'],
    _ => const ['dose'],
  };

  /// Gets the default dosage unit for a medication type.
  static String defaultUnitFor(String? type) => unitsForType(type).first;

  /// Checks whether the medication type is not in the predefined list.
  static bool isCustomType(String? type) => !const {
    'pill',
    'tablet',
    'capsule',
    'injection',
    'solution (liquid)',
    'solution',
    'liquid',
    'syrup',
    'cream',
    'ointment',
    'powder',
    'drops',
    'drop',
    'inhaler',
  }.contains(_kind(type));

  /// Converts different unit names into a consistent format.
  static String normalizeUnit(String unit) {
    final trimmed = unit.trim().replaceAll(RegExp(r'\s+'), ' ');
    return switch (trimmed.toLowerCase()) {
      'pill' ||
      'pills' ||
      'pill(s)' ||
      'tablet' ||
      'tablets' ||
      'tablet(s)' ||
      'capsule' ||
      'capsules' ||
      'capsule(s)' => 'pill',
      'ml' ||
      'milliliter' ||
      'milliliters' ||
      'millilitre' ||
      'millilitres' => 'ml',
      'g' || 'gram' || 'grams' => 'g',
      'mg' || 'milligram' || 'milligrams' => 'mg',
      'mcg' || 'µg' || 'μg' || 'microgram' || 'micrograms' => 'mcg',
      'drop' || 'drops' || 'drop(s)' => 'drop',
      'puff' || 'puffs' || 'puff(s)' => 'puff',
      'dose' || 'doses' || 'dose(s)' => 'dose',
      'unit' || 'units' || 'unit(s)' => 'unit',
      _ => trimmed,
    };
  }

  /// Validates the dosage amount and returns an error if invalid.
  static String? amountError(String raw) {
    final text = raw.trim();

    /// Checks whether the dosage amount is empty.
    if (text.isEmpty) return 'Enter a dosage amount.';
    // Checks whether the amount contains a valid number.
    if (text.length > 32 ||
        !RegExp(r'^(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$').hasMatch(text)) {
      return 'Enter a number such as 1 or 2.5.';
    }
    // Ensures the dosage amount is greater than zero.
    final number = double.tryParse(text);
    if (number == null || !number.isFinite || number <= 0) {
      return 'Dosage must be greater than zero.';
    }
    return null;
  }

  /// Removes unnecessary zeros without changing the dosage value.
  static String normalizeAmount(String raw) {
    final error = amountError(raw);
    if (error != null) throw FormatException(error);
    final parts = raw.trim().split('.');
    var whole = parts.first.replaceFirst(RegExp(r'^0+'), '');
    if (whole.isEmpty) whole = '0';
    final fraction = parts.length > 1
        ? parts[1].replaceFirst(RegExp(r'0+$'), '')
        : '';
    return fraction.isEmpty ? whole : '$whole.$fraction';
  }

  /// Checks whether the dosage unit is valid for the medication.
  static String? unitError(String raw, {String? type}) {
    if (RegExp(r'[\x00-\x1f\x7f]').hasMatch(raw)) {
      return 'Use a short dosage unit, such as ml, g or spray.';
    }
    final unit = normalizeUnit(raw);
    // Checks for an empty or incorrectly formatted unit.
    if (unit.isEmpty) return 'Enter a dosage unit.';
    if (!RegExp(r'^[A-Za-zµμ%][A-Za-z0-9µμ%/ .()_-]{0,31}$').hasMatch(unit)) {
      return 'Use a short dosage unit, such as ml, g or spray.';
    }

    /// Prevents using pill units for other medication types.
    if (type != null && defaultUnitFor(type) != 'pill' && unit == 'pill') {
      return 'Choose a unit appropriate for this medication type.';
    }
    return null;
  }

  /// Adds a plural form when the dosage amount is not one.
  static String unitLabel(String unit, String amount) {
    final base = normalizeUnit(unit);
    final singular =
        amount.trim().isEmpty ||
        (amountError(amount) == null && normalizeAmount(amount) == '1');
    return const {'pill', 'drop', 'puff', 'dose', 'unit'}.contains(base) &&
            !singular
        ? '${base}s'
        : base;
  }

  /// Combines the dosage amount and unit into a readable format.
  static String format({required String amount, required String unit}) {
    final number = normalizeAmount(amount);
    final error = unitError(unit);
    if (error != null) throw FormatException(error);
    final result = '$number ${unitLabel(unit, number)}';
    // Prevents storing dosage text that is too long.
    if (result.length > 128) {
      throw const FormatException('The dosage is too long.');
    }
    return result;
  }

  /// Separates existing dosage text into an amount and unit when possible.
  static ParsedMedicationDosage parse({
    required String dosage,
    required String type,
  }) {
    final match = RegExp(
      r'^\s*([0-9]+(?:\.[0-9]*)?|\.[0-9]+)\s*(.*?)\s*$',
    ).firstMatch(dosage);
    if (match != null) {
      final amount = match[1]!;
      final rawUnit = match[2]!;

      /// Checks for incorrect tablet or capsule units in older records.
      final conflictingOralUnit =
          defaultUnitFor(type) != 'pill' &&
          RegExp(
            r'^(tablets?|capsules?|tablet\(s\)|capsule\(s\))$',
            caseSensitive: false,
          ).hasMatch(rawUnit.trim());

      /// Uses the default unit when no unit is provided.
      var unit = rawUnit.isEmpty
          ? defaultUnitFor(type)
          : normalizeUnit(rawUnit);

      /// Older forms appended pill(s) to every type. Correct that known label
      /// error while keeping the entered numeric amount. Other explicit units
      /// (for example an existing mg prescription) retain their meaning.
      if (unit == 'pill' && defaultUnitFor(type) != 'pill') {
        unit = defaultUnitFor(type);
      }

      /// Defines the supported dosage units.
      const known = {
        'pill',
        'ml',
        'g',
        'mg',
        'mcg',
        'drop',
        'puff',
        'dose',
        'unit',
        'IU',
      };

      /// Checks whether the dosage text contains additional instructions.
      final hasInstructions = RegExp(
        r'\b(after|before|daily|twice|once|every|with|needed|morning|night)\b',
        caseSensitive: false,
      ).hasMatch(rawUnit);

      /// Returns the separated amount and unit if the format is valid.
      if (amountError(amount) == null &&
          unitError(unit) == null &&
          !conflictingOralUnit &&
          !hasInstructions &&
          (known.contains(unit) || isCustomType(type))) {
        return ParsedMedicationDosage(
          amount: amount,
          unit: unit,
          original: dosage,
          isStructured: true,
        );
      }
    }

    /// Keeps the original dosage text if it cannot be separated.
    return ParsedMedicationDosage(
      amount: dosage,
      unit: defaultUnitFor(type),
      original: dosage,
      isStructured: false,
    );
  }

  /// Displays the formatted dosage or keeps the original text.
  static String display(String dosage, String type) {
    final parsed = parse(dosage: dosage, type: type);
    return parsed.isStructured
        ? format(amount: parsed.amount, unit: parsed.unit)
        : dosage;
  }
}

/// Stores the dosage amount, unit, and original text.
class ParsedMedicationDosage {
  /// Creates a dosage record with its parsed details.
  const ParsedMedicationDosage({
    required this.amount,
    required this.unit,
    required this.original,
    required this.isStructured,
  });

  /// Stores the dosage details and whether parsing was successful.
  final String amount;
  final String unit;
  final String original;
  final bool isStructured;
}
