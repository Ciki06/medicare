import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_service.dart' show NotificationService;

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
  final data = message.data;
  if (data['type'] != 'sos') return;

  final alertId = data['alertId'] as String? ?? '';
  final patientName = data['patientName'] as String? ?? 'Patient';

  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings();
  final notificationId = alertId.hashCode & 0x7fffffff;
  try {
    await plugin.initialize(
      settings: const InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      ),
    );
    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            NotificationService.sosAlertsChannel,
            'SOS Alerts',
            description: 'Immediate emergency alerts from linked patients',
            importance: Importance.max,
            playSound: true,
            sound: NotificationService.sosSound,
          ),
        );
    await plugin.show(
      id: notificationId,
      title: '🚨 SOS from $patientName',
      body: '$patientName needs help immediately!',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationService.sosAlertsChannel,
          'SOS Alerts',
          channelDescription: 'Immediate emergency alerts from linked patients',
          importance: Importance.max,
          priority: Priority.max,
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
  } catch (error) {
    debugPrint('sosBackgroundMessageHandler failed: $error');
  }
}