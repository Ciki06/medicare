import 'dart:ui' show Color;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/medication_model.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  /// Android notification channel for SOS emergencies.
  ///
  /// IMPORTANT: Android 8+ freezes a channel's sound after its first creation,
  /// so this channel id must never be reused if the installed sound changes.
  /// The alarm sound ships as `res/raw/sos_alarm.wav` and is baked in when this
  /// channel is created fresh.
  static const String sosAlertsChannel = 'sos_alarm';
  static const RawResourceAndroidNotificationSound sosSound =
      RawResourceAndroidNotificationSound('sos_alarm');
  static const Color sosColor = Color(0xFFE85B61);

  static const String chatChannel = 'chat_messages';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final ValueNotifier<String?> _tapNotifier = ValueNotifier<String?>(null);
  bool _initialized = false;
  bool _fcmInitialized = false;

  /// Called with the FCM SOS message payload when a message arrives while the
  /// app is in the foreground.
  void Function(Map<String, dynamic> data)? onForegroundSos;

  /// Called with the FCM SOS message payload when the user taps an SOS
  /// notification that opened the app (cold start or background resume).
  void Function(Map<String, dynamic> data)? onSosOpened;

  /// Called with the FCM chat message payload when a message arrives while the
  /// app is in the foreground.
  void Function(Map<String, dynamic> data)? onForegroundChat;

  /// Called with the FCM chat message payload when the user taps a chat
  /// notification that opened the app (cold start or background resume).
  void Function(Map<String, dynamic> data)? onChatOpened;

  /// Medication id from the last reminder notification the user tapped.
  /// Checked by AppShell to jump straight to the Reminders tab.
  String? get lastTappedMedicationId => _tapNotifier.value;

  ValueNotifier<String?> get tapNotifier => _tapNotifier;

  Future<void> init() async {
    if (_initialized) return;

    tzdata.initializeTimeZones();
    try {
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestSoundPermission: false,
      requestBadgePermission: false,
    );

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      ),
      onDidReceiveNotificationResponse: _onResponse,
    );
    await _plugin
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
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            NotificationService.chatChannel,
            'Chat Messages',
            description: 'New messages from your healthcare circle',
            importance: Importance.high,
            playSound: true,
          ),
        );
    _initialized = true;

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      _tapNotifier.value = launch?.notificationResponse?.payload;
    }
  }

  Future<void> initFcm() async {
    if (_fcmInitialized) return;
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final status = settings.authorizationStatus;
    if (status == AuthorizationStatus.denied) {
      // Notifications are disabled; in-app SOS alerts can still surface through
      // the Firestore stream, so only the push path is skipped.
      return;
    }
    // Forward foreground SOS messages to the app so it can show the
    // full-screen red emergency screen instantly.
    FirebaseMessaging.onMessage.listen((message) {
      if (message.data['type'] == 'sos') {
        onForegroundSos?.call(message.data);
      } else if (message.data['type'] == 'chat') {
        onForegroundChat?.call(message.data);
      }
    });
    // A tapped background SOS notification opens the app — surface the same
    // full-screen red emergency screen whether it was a cold start or a warm
    // resume from the notification tray.
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (message.data['type'] == 'sos') {
        onSosOpened?.call(message.data);
      } else if (message.data['type'] == 'chat') {
        onChatOpened?.call(message.data);
      }
    });
    // Cold start from a notification tap: the message is delivered to Flutter
    // before the first frame, so its handler must not require a mounted
    // widget; AppShell delays presentation with a post-frame callback.
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      if (initialMessage.data['type'] == 'sos') {
        onSosOpened?.call(initialMessage.data);
      } else if (initialMessage.data['type'] == 'chat') {
        onChatOpened?.call(initialMessage.data);
      }
    }
    // Ensure local-notification permission for foreground local bubbles.
    await requestPermissions();
    _fcmInitialized = true;
  }

  Future<String?> getOrCreateFcmToken() async {
    final messaging = FirebaseMessaging.instance;
    return messaging.getToken();
  }

  Future<void> getTokenStream() async {
    final messaging = FirebaseMessaging.instance;
    messaging.onTokenRefresh.listen((token) {
      onTokenRefreshed?.call(token);
    });
  }

  void Function(String token)? onTokenRefreshed;

  Future<void> requestPermissions() async {
    if (!_initialized) await init();
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    final canScheduleExact = await androidImpl?.canScheduleExactNotifications();
    if (canScheduleExact == false) {
      await androidImpl?.requestExactAlarmsPermission();
    }
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  void _onResponse(NotificationResponse response) {
    if (response.payload == null) return;
    _tapNotifier.value = response.payload;
  }

  Future<void> scheduleDailyReminders(
    List<Medication> medications, {
    required String patientId,
  }) async {
    if (!_initialized) return;

    var scheduleMode = AndroidScheduleMode.exactAllowWhileIdle;
    final canScheduleExact = await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.canScheduleExactNotifications();
    if (canScheduleExact == false) {
      scheduleMode = AndroidScheduleMode.inexactAllowWhileIdle;
    }

    final now = tz.TZDateTime.now(tz.local);
    var id = 0;
    for (final med in medications) {
      if (med.patientId != patientId) continue;
      final scheduled = med.scheduledDateTime;
      if (scheduled == null) continue;

      var next = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        scheduled.hour,
        scheduled.minute,
      );
      if (!next.isAfter(now)) {
        next = next.add(const Duration(days: 1));
      }

      await _plugin.zonedSchedule(
        id: id++,
        title: 'Medication Reminder',
        body: 'Time to take ${med.name} (${med.dosage})',
        scheduledDate: next,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'medication_reminders',
            'Medication Reminders',
            channelDescription: 'Reminders to take your medication on time',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBanner: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: scheduleMode,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: med.id,
      );
    }
  }

  Future<void> cancelAll() => _plugin.cancelAll();

  /// Unique, stable notification id for a snoozed medication, so rescheduling
  /// replaces the previous snooze and cancel() can find it again.
  int _snoozeNotificationId(String medId) =>
      500000 + (medId.hashCode & 0xFFFF);

  /// One-shot system notification at [when] (typically now + 10 min) so a
  /// snoozed medication still reminds the patient even when the app is in the
  /// background or closed during the snooze window. Tapping it opens the
  /// Reminders tab.
  Future<void> scheduleSnoozeReminder({
    required String medId,
    required String medName,
    String? dosage,
    required DateTime when,
  }) async {
    if (!_initialized) await init();
    final scheduled = tz.TZDateTime.from(when, tz.local);
    var scheduleMode = AndroidScheduleMode.exactAllowWhileIdle;
    final canScheduleExact = await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.canScheduleExactNotifications();
    if (canScheduleExact == false) {
      scheduleMode = AndroidScheduleMode.inexactAllowWhileIdle;
    }
    await _plugin.zonedSchedule(
      id: _snoozeNotificationId(medId),
      title: 'Medication Reminder',
      body:
          'Time to take $medName${dosage != null && dosage.isNotEmpty ? ' ($dosage)' : ''}',
      scheduledDate: scheduled,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'medication_reminders',
          'Medication Reminders',
          channelDescription: 'Reminders to take your medication on time',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: scheduleMode,
      payload: medId,
    );
  }

  /// Cancel a pending snooze reminder (e.g. the medicine was taken or skipped
  /// before the 10-minute window elapsed).
  Future<void> cancelSnoozeReminder(String medId) =>
      _plugin.cancel(id: _snoozeNotificationId(medId));

  Future<void> showImmediateNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
if (!_initialized) await init();
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationService.sosAlertsChannel,
          'SOS Alerts',
          channelDescription: 'Immediate emergency alerts from linked patients',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
          // Play the bundled alarm tone (res/raw/sos_alarm.wav) instead of the
          // default chime, and present it full-screen with the emergency
          // alarm sound even when the app is in the background.
          playSound: true,
          sound: NotificationService.sosSound,
          fullScreenIntent: true,
          color: NotificationService.sosColor,
          visibility: NotificationVisibility.public,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentSound: true,
          sound: 'sos_alarm.wav',
        ),
      ),
      payload: payload,
    );
  }

  Future<void> scheduleAppointmentReminders(List<Appointment> appointments) async {
    if (!_initialized) return;

    var scheduleMode = AndroidScheduleMode.exactAllowWhileIdle;
    final canScheduleExact = await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.canScheduleExactNotifications();
    if (canScheduleExact == false) {
      scheduleMode = AndroidScheduleMode.inexactAllowWhileIdle;
    }

    final now = tz.TZDateTime.now(tz.local);
    var id = 10000;

    for (final apt in appointments) {
      final normalizedDate = apt.date.replaceAll('/', '-');
      final aptDate = DateTime.tryParse(normalizedDate);
      if (aptDate == null) continue;

      final timeParts = apt.time.split(':');
      if (timeParts.length != 2) continue;
      final hour = int.tryParse(timeParts[0]) ?? 0;
      final minute = int.tryParse(timeParts[1]) ?? 0;

      var next = tz.TZDateTime(
        tz.local,
        aptDate.year,
        aptDate.month,
        aptDate.day,
        hour,
        minute,
      );
      next = next.subtract(Duration(minutes: apt.remindBefore.clamp(0, 24 * 60)));

      if (!next.isAfter(now)) continue;

      final diff = next.difference(now);
      if (diff.inDays > 0) continue;

      await _plugin.zonedSchedule(
        id: id++,
        title: 'Appointment Reminder',
        body: '${apt.title} at ${apt.time}${apt.location.isNotEmpty ? ' - ${apt.location}' : ''}',
        scheduledDate: next,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'appointment_reminders',
            'Appointment Reminders',
            channelDescription: 'Reminders for upcoming appointments',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBanner: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: scheduleMode,
        payload: 'appointment:${apt.id}',
      );
    }
  }

  /// Show an in-app chat notification (used when the app is in the foreground).
  Future<void> showChatNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) await init();
    final id = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationService.chatChannel,
          'Chat Messages',
          channelDescription: 'New messages from your healthcare circle',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }
}
