import 'dart:math';

/// Secure random business IDs, exactly representable by Firestore, JavaScript
/// and SQLite, allocated before a local action is queued.
class IntegerRecordId {
  static final _random = Random.secure();
  static int next() =>
      4503599627370496 +
      _random.nextInt(1 << 26) * (1 << 26) +
      _random.nextInt(1 << 26);
}
