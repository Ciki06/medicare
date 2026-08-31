/// Helpers for Malaysian Identity Card (MyKad) numbers in the
/// `YYMMDD-STATE-XXXX` format (e.g. `920601-01-2345`).
class MalaysianIc {
  MalaysianIc._();

  static final RegExp _digitsOnly = RegExp(r'^\d{12}$');
  static final RegExp _dashed = RegExp(
    r'^(\d{2})(\d{2})(\d{2})-(\d{2})-(\d{4})$',
  );

  /// Strips everything except digits (max 12) and inserts dashes as
  /// `YYMMDD-STATE-XXXX`.
  static String format(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final s = digits.length > 12 ? digits.substring(0, 12) : digits;
    final a = s.length > 6 ? s.substring(0, 6) : s;
    final b = s.length > 8
        ? s.substring(6, 8)
        : (s.length > 6 ? s.substring(6) : '');
    final c = s.length > 8 ? s.substring(8) : '';
    return [a, b, c].where((p) => p.isNotEmpty).join('-');
  }

  /// Validates either a `YYMMDD-STATE-XXXX` string or a plain 12-digit number.
  static bool isValid(String value) {
    final normalized = value.replaceAll(RegExp(r'\D'), '');
    if (!_digitsOnly.hasMatch(normalized)) return false;
    final m = _dashed.matchAsPrefix(format(normalized));
    if (m == null) return false;
    final month = int.parse(m.group(2)!);
    final day = int.parse(m.group(3)!);
    if (month < 1 || month > 12) return false;
    if (day < 1 || day > 31) return false;
    return MalaysianIc.birthDate(normalized) != null;
  }

  /// Parses the YYMMDD part into a birth date, or null when invalid.
  static DateTime? birthDate(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 12) return null;
    final m = _dashed.matchAsPrefix(format(digits));
    if (m == null) return null;
    final yy = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    final day = int.parse(m.group(3)!);
    final currentYY = DateTime.now().year % 100;
    final year = (yy > currentYY ? 1900 : 2000) + yy;
    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  /// Returns the birth date formatted as `DD/MM/YYYY`, or null when invalid.
  static String? dateOfBirth(String value) {
    final d = birthDate(value);
    if (d == null) return null;
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  /// Computes current age (in years) from the IC, or null when invalid.
  static int? age(String value) {
    final d = birthDate(value);
    if (d == null) return null;
    final now = DateTime.now();
    var age = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) {
      age--;
    }
    return age;
  }
}