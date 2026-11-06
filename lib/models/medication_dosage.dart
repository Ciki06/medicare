/// The prescribed dose is stored as one amount-and-unit string. Inventory
/// quantities are a separate contract and are never converted by this helper.
class MedicationDosage {
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

  static String? canonicalType(String? type) =>
      switch (type?.trim().toLowerCase()) {
        'tablet' => 'Pill',
        'solution' || 'solution (liquid)' || 'liquid' => 'Liquid',
        _ => type,
      };

  static bool countsStockAsDoses(String? type) =>
      canonicalType(type) == 'Liquid' || _kind(type) == 'syrup';

  static String _kind(String? type) => (type ?? 'Pill').trim().toLowerCase();

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

  static String defaultUnitFor(String? type) => unitsForType(type).first;

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

  static String? amountError(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return 'Enter a dosage amount.';
    if (text.length > 32 ||
        !RegExp(r'^(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$').hasMatch(text)) {
      return 'Enter a number such as 1 or 2.5.';
    }
    final number = double.tryParse(text);
    if (number == null || !number.isFinite || number <= 0) {
      return 'Dosage must be greater than zero.';
    }
    return null;
  }

  /// Normalize notation without rounding or converting the prescribed amount.
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

  static String? unitError(String raw, {String? type}) {
    if (RegExp(r'[\x00-\x1f\x7f]').hasMatch(raw)) {
      return 'Use a short dosage unit, such as ml, g or spray.';
    }
    final unit = normalizeUnit(raw);
    if (unit.isEmpty) return 'Enter a dosage unit.';
    if (!RegExp(r'^[A-Za-zµμ%][A-Za-z0-9µμ%/ .()_-]{0,31}$').hasMatch(unit)) {
      return 'Use a short dosage unit, such as ml, g or spray.';
    }
    if (type != null && defaultUnitFor(type) != 'pill' && unit == 'pill') {
      return 'Choose a unit appropriate for this medication type.';
    }
    return null;
  }

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

  static String format({required String amount, required String unit}) {
    final number = normalizeAmount(amount);
    final error = unitError(unit);
    if (error != null) throw FormatException(error);
    final result = '$number ${unitLabel(unit, number)}';
    if (result.length > 128) {
      throw const FormatException('The dosage is too long.');
    }
    return result;
  }

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
      final conflictingOralUnit =
          defaultUnitFor(type) != 'pill' &&
          RegExp(
            r'^(tablets?|capsules?|tablet\(s\)|capsule\(s\))$',
            caseSensitive: false,
          ).hasMatch(rawUnit.trim());
      var unit = rawUnit.isEmpty
          ? defaultUnitFor(type)
          : normalizeUnit(rawUnit);
      // Older forms appended pill(s) to every type. Correct that known label
      // error while keeping the entered numeric amount. Other explicit units
      // (for example an existing mg prescription) retain their meaning.
      if (unit == 'pill' && defaultUnitFor(type) != 'pill') {
        unit = defaultUnitFor(type);
      }
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
      final hasInstructions = RegExp(
        r'\b(after|before|daily|twice|once|every|with|needed|morning|night)\b',
        caseSensitive: false,
      ).hasMatch(rawUnit);
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
    return ParsedMedicationDosage(
      amount: dosage,
      unit: defaultUnitFor(type),
      original: dosage,
      isStructured: false,
    );
  }

  static String display(String dosage, String type) {
    final parsed = parse(dosage: dosage, type: type);
    return parsed.isStructured
        ? format(amount: parsed.amount, unit: parsed.unit)
        : dosage;
  }
}

class ParsedMedicationDosage {
  const ParsedMedicationDosage({
    required this.amount,
    required this.unit,
    required this.original,
    required this.isStructured,
  });

  final String amount;
  final String unit;
  final String original;
  final bool isStructured;
}
