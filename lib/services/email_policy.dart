/// Shared validation for sign-in and contact email addresses.
class EmailPolicy {
  static final _pattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  static bool isValid(String? email) {
    final value = email?.trim() ?? '';
    return value.length <= 254 && _pattern.hasMatch(value);
  }

  static String? validate(String? email) =>
      isValid(email) ? null : 'Invalid email.';
}
