import 'dart:math';

/// Exactly representable by Firestore, JavaScript and SQLite. The high bit
/// keeps new disconnected-device IDs separate from existing small IDs.
class IntegerRecordId {
  static final _random = Random.secure();
  static int next() =>
      4503599627370496 +
      _random.nextInt(1 << 26) * (1 << 26) +
      _random.nextInt(1 << 26);
}
