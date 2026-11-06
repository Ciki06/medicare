/// Shared policy for choosing a new password, never for signing in with an
/// existing password. Keep the symbol set aligned with Firebase Authentication.
class PasswordPolicy {
  static const minLength = 6;
  static const maxLength = 4096;
  static const symbols = r'''^$*.[]{}()?"!@#%&/\,><':;|_~''';
  static const requirements =
      'At least 6 characters: uppercase, lowercase, number and symbol (e.g. !@#).';

  static final _uppercase = RegExp(r'[A-Z]');
  static final _lowercase = RegExp(r'[a-z]');
  static final _number = RegExp(r'[0-9]');
  static final _symbolCodes = symbols.codeUnits.toSet();

  static String? validate(String? password) {
    if (password == null || password.isEmpty) return 'Password is required.';
    if (password.length < minLength) return 'Use at least 6 characters.';
    if (password.length > maxLength) return 'Use no more than 15 characters.';
    if (!_uppercase.hasMatch(password)) {
      return 'Include at least one uppercase letter.';
    }
    if (!_lowercase.hasMatch(password)) {
      return 'Include at least one lowercase letter.';
    }
    if (!_number.hasMatch(password)) return 'Include at least one number.';
    if (!password.codeUnits.any(_symbolCodes.contains)) {
      return 'Include at least one symbol, such as !, @ or #.';
    }
    return null;
  }
}
