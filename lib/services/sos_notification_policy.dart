import 'package:flutter/widgets.dart';

import '../models/sos_alert.dart';

/// Background system notifications belong to FCM, never the Firestore listener.
class SosNotificationPolicy {
  SosNotificationPolicy({required this.startedAt});

  final DateTime startedAt;
  final Set<String> _seen = {};

  bool shouldShowLocal(
    SosAlert alert, {
    required AppLifecycleState? lifecycle,
    required DateTime now,
  }) {
    // Remember background arrivals too: resuming must not notify them again.
    if (!_seen.add(alert.id)) return false;
    return lifecycle == AppLifecycleState.resumed &&
        alert.isActive &&
        alert.createdAt.isAfter(startedAt) &&
        now.difference(alert.createdAt) <= const Duration(minutes: 5);
  }
}
