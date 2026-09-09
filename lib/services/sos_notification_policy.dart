import '../models/sos_alert.dart';

/// Decides which incoming SOS alerts should surface to the user.
///
/// A single alert is only ever surfaced once per session (whether it arrives
/// via FCM, a tapped notification, or the Firestore stream) so the full-screen
/// emergency UI does not re-appear. Alerts older than five minutes are ignored
/// unless the user explicitly taps the notification to open them.
class SosNotificationPolicy {
  SosNotificationPolicy({required this.startedAt});

  final DateTime startedAt;
  final Set<String> _seen = {};

  bool shouldSurface(SosAlert alert, {required DateTime now}) {
    if (!_seen.add(alert.id)) return false;
    return alert.isActive &&
        alert.createdAt.isAfter(startedAt) &&
        now.difference(alert.createdAt) <= const Duration(minutes: 5);
  }
}