/// Handles Malaysian IC formatting, validation, and birth date details.
/// `YYMMDD-STATE-XXXX` format (e.g. `920601-01-2345`).
class MalaysianIc {
  MalaysianIc._();

  /// Defines the accepted IC number formats.
  static final RegExp _digitsOnly = RegExp(r'^\d{12}$');
  static final RegExp _dashed = RegExp(
    r'^(\d{2})(\d{2})(\d{2})-(\d{2})-(\d{4})$',
  );

  /// Formats the IC number into YYMMDD-STATE-XXXX.
  static String format(String raw) {
    /// Removes non-numeric characters and limits the input to 12 digits.
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final s = digits.length > 12 ? digits.substring(0, 12) : digits;

    /// Separates the IC number into three parts.
    final a = s.length > 6 ? s.substring(0, 6) : s;
    final b = s.length > 8
        ? s.substring(6, 8)
        : (s.length > 6 ? s.substring(6) : '');
    final c = s.length > 8 ? s.substring(8) : '';
    return [a, b, c].where((p) => p.isNotEmpty).join('-');
  }

  /// Checks whether the IC number has a valid format and birth date.
  static bool isValid(String value) {
    final normalized = value.replaceAll(RegExp(r'\D'), '');

    /// Checks that the IC contains exactly 12 digits.
    if (!_digitsOnly.hasMatch(normalized)) return false;
    final m = _dashed.matchAsPrefix(format(normalized));
    if (m == null) return false;

    /// Checks whether the month and day are within the allowed range.
    final month = int.parse(m.group(2)!);
    final day = int.parse(m.group(3)!);
    if (month < 1 || month > 12) return false;
    if (day < 1 || day > 31) return false;

    /// Checks whether the birth date can be generated.
    return MalaysianIc.birthDate(normalized) != null;
  }

  /// Extracts the birth date from the IC number.
  static DateTime? birthDate(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 12) return null;
    final m = _dashed.matchAsPrefix(format(digits));
    if (m == null) return null;

    /// Gets the year, month, and day from the IC number.
    final yy = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    final day = int.parse(m.group(3)!);
    // Determines the birth year based on the current year.
    final currentYY = DateTime.now().year % 100;
    final year = (yy > currentYY ? 1900 : 2000) + yy;

    /// Creates the birth date or returns null if an error occurs.
    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  /// Converts the birth date into DD/MM/YYYY format.
  static String? dateOfBirth(String value) {
    final d = birthDate(value);
    if (d == null) return null;
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  /// Calculates the age based on the birth date in the IC number.
  static int? age(String value) {
    final d = birthDate(value);
    if (d == null) return null;
    final now = DateTime.now();
    var age = now.year - d.year;

    /// Subtracts one year if the birthday has not occurred yet.
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) {
      age--;
    }
    return age;
  }
}
