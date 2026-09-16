import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_service.dart' show NotificationService;
import 'notification_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../firebase_options.dart';
import 'sos_access.dart';

/// Android background/killed-state SOS handler.
///
/// The Cloud Function sends SOS as a data-only message to Android, so when the
/// app is in the background or fully terminated Firebase Messaging starts a
/// headless isolate and calls this entry point. It shows a full-screen alarm
/// notification (custom SOS sound, `fullScreenIntent`, red) so caregivers and
/// family still get an unmistakable alert even with the app closed.
///
/// The alarm sound lives in the `sosAlertsChannel`; using the same channel id
/// everywhere guarantees the raw `sos_alarm` resource is baked in on fresh
/// installs (Android freezes channel sound after first creation).
///
/// Tapping the notification reopens the app; the `sos:<alertId>` payload is
/// routed by `AppShell` to the full-screen red emergency screen.
@pragma('vm:entry-point')
Future<void> sosBackgroundMessageHandler(RemoteMessage message) async {
  // iOS already presents aps.alert + sound natively. Never post a second alert.
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  final data = message.data;
  if (data['type'] != 'sos') return;

  final alertId = data['alertId'] as String? ?? '';
  final patientName = data['patientName'] as String? ?? 'Patient';

  if (alertId.isEmpty) return;
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final current = await currentSosForRecipient(
    alertId,
    uid,
  ).timeout(const Duration(seconds: 10), onTimeout: () => null);
  if (current == null || FirebaseAuth.instance.currentUser?.uid != uid) return;
  final preferences = SharedPreferencesAsync();
  final seen = await preferences.getStringList('shown_sos_alerts') ?? [];
  if (seen.contains(alertId)) return;
  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings();
  final id = notificationId('sos:$alertId');
  try {
    await plugin.initialize(
      settings: const InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      ),
    );
    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            NotificationService.sosAlertsChannel,
            'SOS Alerts',
            description: 'Immediate emergency alerts from linked patients',
            importance: Importance.max,
            playSound: true,
            sound: NotificationService.sosSound,
            audioAttributesUsage: AudioAttributesUsage.alarm,
          ),
        );
    await plugin.show(
      id: id,
      title: '🚨 SOS from $patientName',
      body: '$patientName needs help immediately!',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationService.sosAlertsChannel,
          'SOS Alerts',
          channelDescription: 'Immediate emergency alerts from linked patients',
          importance: Importance.max,
          priority: Priority.max,
          onlyAlertOnce: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          category: AndroidNotificationCategory.alarm,
          playSound: true,
          sound: NotificationService.sosSound,
          fullScreenIntent: true,
          color: NotificationService.sosColor,
          visibility: NotificationVisibility.public,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentSound: true,
          sound: 'sos_alarm.wav',
        ),
      ),
      payload: 'sos:$alertId',
    );
    await preferences.setStringList('shown_sos_alerts', [
      ...seen.skip(seen.length > 199 ? seen.length - 199 : 0),
      alertId,
    ]);
  } catch (error) {
    debugPrint('sosBackgroundMessageHandler failed: $error');
  }
}
