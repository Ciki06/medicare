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

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final ValueNotifier<String?> _tapNotifier = ValueNotifier<String?>(null);
  bool _initialized = false;
  bool _fcmInitialized = false;

  /// Called with (title, body, patientName) when an FCM SOS message arrives
  /// while the app is in the foreground.
  void Function(String patientName)? onForegroundSos;

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
            'sos_alerts',
            'SOS Alerts',
            description: 'Immediate emergency alerts from linked patients',
            importance: Importance.max,
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
    if (status != AuthorizationStatus.authorized &&
        status != AuthorizationStatus.provisional) {
      return;
    }
    // Show a local notification when an FCM message arrives while the app is
    // foregrounded (SOS foreground alerts are surfaced via the in-app banner
    // through the Firestore stream to avoid duplicate notifications).
    FirebaseMessaging.onMessage.listen((message) {
      if (message.data['type'] == 'sos') {
        final patientName =
            message.data['patientName'] as String? ?? 'Patient';
        onForegroundSos?.call(patientName);
      }
    });
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
          'sos_alerts',
          'SOS Alerts',
          channelDescription: 'Immediate emergency alerts from linked patients',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          color: const Color(0xFFE85B61),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentSound: true,
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
}
