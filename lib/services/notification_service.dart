import 'dart:ui' show Color;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/medication_model.dart';
import '../models/medication_action.dart';
import 'notification_identity.dart';
import 'schedule_time.dart';
import 'reminder_plan.dart';
import 'reminder_audio_service.dart';
import 'reminder_speech.dart';
import 'appointment_notification_policy.dart';
import 'reminder_notification_settings.dart';
import 'snooze_notification_migration.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  /// Android notification channel for SOS emergencies.
  ///
  /// IMPORTANT: Android 8+ freezes a channel's sound after its first creation,
  /// so this channel id must never be reused if the installed sound changes.
  /// The alarm sound ships as `res/raw/sos_alarm.wav` and is baked in when this
  /// channel is created fresh.
  static const String sosAlertsChannel = 'sos_alarm_v2';
  static const RawResourceAndroidNotificationSound sosSound =
      RawResourceAndroidNotificationSound('sos_alarm');
  static const Color sosColor = Color(0xFFE85B61);

  static const String chatChannel = 'chat_messages';
  static const String incomingCallChannel = 'voice_calls_v3';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final ValueNotifier<String?> _tapNotifier = ValueNotifier<String?>(null);
  bool _initialized = false;
  bool _fcmInitialized = false;
  bool _tokenListening = false;

  Future<bool> wasSosOpened(String uid, String id) async =>
      (await SharedPreferencesAsync().getStringList('opened_sos_$uid') ?? [])
          .contains(id);

  Future<void> markSosOpened(String uid, String id) async {
    final prefs = SharedPreferencesAsync();
    final ids = await prefs.getStringList('opened_sos_$uid') ?? [];
    if (!ids.contains(id)) {
      await prefs.setStringList('opened_sos_$uid', [...ids, id]);
    }
  }

  void clearSessionCallbacks() {
    _tapNotifier.value = null;
    onForegroundSos = null;
    onSosOpened = null;
    onForegroundChat = null;
    onChatOpened = null;
    onTokenRefreshed = null;
  }

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

    tz.setLocalLocation(ScheduleTime.location);

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
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            incomingCallChannel,
            'Incoming voice calls',
            description: 'Incoming calls inside MediCare',
            importance: Importance.max,
            playSound: true,
            // Alarm usage keeps the normal incoming ringtone independent of
            // the ringer's Silent mode. DND, channel settings and alarm volume
            // remain under the patient's control.
            audioAttributesUsage: AudioAttributesUsage.alarm,
            enableVibration: true,
            sound: UriAndroidNotificationSound(
              'content://settings/system/ringtone',
            ),
          ),
        );
    for (final channel in ReminderNotificationSettings.channels) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }
    await _plugin
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
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
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
    await messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );
    // Forward foreground SOS messages to the app so it can show the
    // full-screen red emergency screen instantly.
    FirebaseMessaging.onMessage.listen((message) {
      if (message.data['type'] == 'sos') {
        onForegroundSos?.call(message.data);
      } else if (message.data['type'] == 'chat') {
        onForegroundChat?.call(message.data);
      } else if (message.data['type'] == 'call_ended') {
        final callId = message.data['callId'] as String?;
        if (callId != null) cancelIncomingCall(callId);
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
    if (_tokenListening) return;
    _tokenListening = true;
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
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImpl?.requestNotificationsPermission();
    final canScheduleExact = await androidImpl?.canScheduleExactNotifications();
    if (canScheduleExact == false) {
      await androidImpl?.requestExactAlarmsPermission();
    }
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
          critical: const bool.fromEnvironment('MEDICARE_CRITICAL_ALERTS'),
        );
  }

  void _onResponse(NotificationResponse response) {
    if (response.payload == null) return;
    final payload = response.payload!;
    if (payload.startsWith('appointment:')) {
      // Stop the matching voice immediately; the app persists viewed state.
      cancelAppointmentReminder(payload.substring('appointment:'.length));
    }
    // Taps are events, including a second reminder for the same appointment
    // after its schedule was edited. ValueNotifier otherwise suppresses it.
    _tapNotifier.value = null;
    _tapNotifier.value = response.payload;
  }

  List<Medication> _scheduledMedications = [];
  List<Appointment> _scheduledAppointments = [];
  List<MedicationAction> _restoredSnoozeActions = [];
  final _migratedSnoozes = <(int, int)>{};
  final _cancelledSnoozes = <int>{};
  Future<void> _scheduleQueue = Future.value();
  int _scheduleGeneration = 0;
  String? _patientId;
  bool _medicationsLoaded = false, _appointmentsLoaded = false;
  final scheduleNotice = ValueNotifier<String?>(null);

  void beginPatientSession(String patientId) {
    if (_patientId != patientId) {
      _scheduleGeneration++;
      _medicationsLoaded = false;
      _appointmentsLoaded = false;
      _scheduledMedications = [];
      _scheduledAppointments = [];
      _restoredSnoozeActions = [];
      _migratedSnoozes.clear();
      _cancelledSnoozes.clear();
    }
    _patientId = patientId;
  }

  Future<void> scheduleDailyReminders(
    List<Medication> medications, {
    required String patientId,
  }) {
    if (patientId != _patientId) return Future.value();
    _medicationsLoaded = true;
    _scheduledMedications = medications
        .where((m) => m.patientId == patientId)
        .toList();
    return refreshReminders();
  }

  Future<void> scheduleAppointmentReminders(List<Appointment> appointments) {
    if (_patientId == null) return Future.value();
    _appointmentsLoaded = true;
    _scheduledAppointments = appointments
        .where((a) => a.patientId == _patientId)
        .toList();
    return refreshReminders();
  }

  /// Reuse the persisted snooze expiry when migrating an installed app's
  /// pending notifications. This never creates an alert from history alone.
  Future<void> restoreSnoozeReminders(
    List<MedicationAction> actions, {
    required String patientId,
  }) {
    if (patientId != _patientId) return Future.value();
    _restoredSnoozeActions = actions
        .where((action) => action.patientId == patientId)
        .toList();
    return refreshReminders();
  }

  Future<void> refreshReminders() {
    // Each Firestore stream can arrive independently. Do not block appointment
    // alarms while the medication query is still loading (or has failed).
    if (_patientId == null || (!_medicationsLoaded && !_appointmentsLoaded)) {
      return Future.value();
    }
    final generation = _scheduleGeneration;
    _scheduleQueue = _scheduleQueue.catchError((Object _) {}).then((_) async {
      if (generation != _scheduleGeneration) return;
      try {
        await _reconcileReminders(generation);
      } catch (error, stackTrace) {
        debugPrint('Reminder reconciliation failed: $error\n$stackTrace');
        scheduleNotice.value = 'Reminders could not be scheduled: $error';
      }
    });
    return _scheduleQueue;
  }

  Future<void> _reconcileReminders(int generation) async {
    if (!_initialized) await init();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final exact = await android?.canScheduleExactNotifications();
    final plan = planReminders(
      _scheduledMedications,
      _scheduledAppointments,
      ScheduleTime.now(),
    );
    final needsStartDate = _scheduledMedications.any(
      (m) =>
          m.startDate == null &&
          m.days.any(
            (d) => [
              'once',
              'weekly',
              'monthly',
              'every x days',
            ].contains(d.toLowerCase()),
          ),
    );
    final pending = await _plugin.pendingNotificationRequests();
    final prefs = SharedPreferencesAsync();
    final oldIds = (await prefs.getStringList('scheduled_reminder_ids') ?? [])
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
    // Migrate the old list-position IDs without touching snoozes or chat alerts.
    oldIds.addAll(pending.where((p) => p.id < 500000).map((p) => p.id));
    final unmanaged = pending.where((p) => !oldIds.contains(p.id)).length;
    final capacity = defaultTargetPlatform == TargetPlatform.iOS
        ? (60 - unmanaged).clamp(0, 60)
        : 200; // Speech alarms and visible notifications share Android's alarm quota.
    final selected = plan.take(capacity).toList();
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final critical =
        (await ios?.checkPermissions())?.isCriticalEnabled ?? false;
    var nativeSpeech = false;
    var nativeAppointmentAlarm = false;
    if (ReminderAudioService.android) {
      try {
        // Inexact alarms cannot reliably start foreground audio on Android 12+.
        nativeSpeech = true;
        if (_medicationsLoaded) {
          nativeSpeech = await ReminderAudioService.reconcile(
            exact == false
                ? []
                : selected.where((item) => item.medication).toList(),
            group: 'medications',
          );
        }
        if (_appointmentsLoaded) {
          final appointmentSpeech = await ReminderAudioService.reconcile(
            exact == false
                ? []
                : selected.where((item) => !item.medication).toList(),
            group: 'appointments',
            retainedAppointments: [
              for (final appointment in _scheduledAppointments)
                if (appointment.status == 'scheduled' &&
                    !appointment.reminderViewed &&
                    appointment.reminderAt != null)
                  {
                    'id': notificationId(
                      'apt:${appointment.patientId}:${appointment.id}',
                    ),
                    'at': appointment.reminderAt!.millisecondsSinceEpoch,
                    'payload': 'appointment:${appointment.id}',
                    'patientId': appointment.patientId,
                    'scheduleKey': appointment.reminderKey,
                  },
            ],
          );
          nativeAppointmentAlarm = appointmentSpeech && exact != false;
        }
        if (_medicationsLoaded && _appointmentsLoaded) {
          // Migrate the original shared group only after both streams have
          // loaded. An early medication snapshot must not erase appointment
          // speech while the appointment query is still starting.
          await ReminderAudioService.reconcile([], group: 'main');
        }
        nativeSpeech = nativeSpeech && exact != false;
      } catch (e) {
        debugPrint('Native reminder audio unavailable: $e');
      }
    }
    final ids = selected.map((p) => p.id).toSet();
    // A fired appointment leaves the future plan. Keep its delivered tray
    // notification until it is viewed/completed, instead of treating it as a
    // removed schedule during the next Firestore refresh. Do not re-post it.
    ids.addAll(
      retainedAppointmentNotificationIds(
        _scheduledAppointments,
        ScheduleTime.now(),
      ),
    );
    if (!_appointmentsLoaded) {
      ids.addAll(
        pending
            .where((item) => item.payload?.startsWith('appointment:') ?? false)
            .map((item) => item.id),
      );
      // A delivered alert is absent from pendingNotificationRequests. Retain
      // it during initial loading until its viewed/completed state is known.
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS)) {
        final active = await _plugin.getActiveNotifications();
        ids.addAll(
          active
              .where((item) => item.title == 'Appointment Reminder')
              .map((item) => item.id)
              .whereType<int>(),
        );
      }
    }
    var usedInexactFallback = false;
    if (generation != _scheduleGeneration) return;
    for (final id in oldIds.difference(ids)) {
      await _plugin.cancel(id: id);
      if (_appointmentsLoaded &&
          pending.any(
            (request) =>
                request.id == id &&
                (request.payload?.startsWith('appointment:') ?? false),
          )) {
        await ReminderAudioService.cancel(id);
      }
    }
    for (final item in selected) {
      if (generation != _scheduleGeneration) return;
      if (!item.medication && nativeAppointmentAlarm) {
        // The foreground alarm service owns this appointment's notification,
        // looping ringtone and manual stop control, including while closed.
        // Cancel only the previous future plugin schedule during migration;
        // delivered/unviewed appointment alarms are retained above.
        if (pending.any((request) => request.id == item.id)) {
          await _plugin.cancel(id: item.id);
        }
        continue;
      }
      final spokenSound = await ReminderAudioService.sound(item);
      if (generation != _scheduleGeneration) return;
      final details = NotificationDetails(
        android: ReminderNotificationSettings.androidDetails(
          nativeSpeech: item.medication ? nativeSpeech : false,
          medication: item.medication,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentSound: true,
          sound:
              spokenSound ?? (item.medication ? 'medication_voice.wav' : null),
          interruptionLevel: critical
              ? InterruptionLevel.critical
              : InterruptionLevel.timeSensitive,
          criticalSoundVolume: critical ? 1.0 : null,
        ),
      );

      Future<void> schedule(AndroidScheduleMode mode) => _plugin.zonedSchedule(
        id: item.id,
        title: item.title,
        body: item.body,
        scheduledDate: item.at,
        payload: item.payload,
        androidScheduleMode: mode,
        matchDateTimeComponents: item.repeat,
        notificationDetails: details,
      );

      final scheduleMode = exact == false
          ? AndroidScheduleMode.inexactAllowWhileIdle
          : AndroidScheduleMode.exactAllowWhileIdle;
      try {
        await schedule(scheduleMode);
      } catch (error, stackTrace) {
        if (defaultTargetPlatform != TargetPlatform.android || exact == false) {
          rethrow;
        }
        debugPrint(
          'Exact alarm scheduling failed for ${item.payload}; retrying inexact: '
          '$error\n$stackTrace',
        );
        await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
        usedInexactFallback = true;
      }
    }
    if (generation != _scheduleGeneration) return;
    await prefs.setStringList(
      'scheduled_reminder_ids',
      ids.map((id) => id.toString()).toList(),
    );
    await _migratePendingSnoozes(generation);
    if (generation != _scheduleGeneration) return;
    scheduleNotice.value = needsStartDate
        ? 'A medication needs a start date. Ask your caregiver to open Edit Medication and save its frequency and start date.'
        : plan.length > selected.length
        ? 'The nearest ${selected.length} reminders are scheduled. Open MediCare regularly to schedule later doses.'
        : usedInexactFallback
        ? 'Exact alarm access was unavailable. Reminders are scheduled with Android inexact alarms.'
        : ReminderAudioService.ios && !critical
        ? 'Silent-mode reminder audio requires Critical Alerts, Apple approval, and permission in Settings. Normal reminders are scheduled.'
        : exact == false
        ? 'Enable Alarms & reminders in system settings for on-time spoken alerts, including in Silent mode.'
        : ReminderAudioService.android && !nativeSpeech
        ? 'Spoken alarms could not be enabled. Reopen the updated app and check Alarms & reminders permission.'
        : null;
  }

  Future<void> _migratePendingSnoozes(int generation) async {
    final patientId = _patientId;
    if (!ReminderAudioService.android ||
        !_medicationsLoaded ||
        patientId == null) {
      return;
    }
    bool active() =>
        _patientId == patientId && generation == _scheduleGeneration;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      if (!active()) return;
      final candidates = pendingSnoozeMigrations(
        medications: _scheduledMedications,
        actions: _restoredSnoozeActions,
        pending: pending,
        patientId: patientId,
        now: ScheduleTime.now(),
      );
      for (final candidate in candidates) {
        if (!active()) return;
        if (_migratedSnoozes.contains(candidate.key)) continue;
        final currentPending = await _plugin.pendingNotificationRequests();
        bool stillCurrent() =>
            active() &&
            !_migratedSnoozes.contains(candidate.key) &&
            !_cancelledSnoozes.contains(candidate.id) &&
            pendingSnoozeMigrations(
              medications: _scheduledMedications,
              actions: _restoredSnoozeActions,
              pending: currentPending,
              patientId: patientId,
              now: ScheduleTime.now(),
            ).any((current) => current.key == candidate.key);
        if (!stillCurrent()) continue;
        final medication = candidate.medication;
        final scheduled = await _scheduleSnoozeReminder(
          medId: medication.id,
          medName: medication.name,
          dosage: medication.dosage,
          medicationType: medication.type,
          when: candidate.when,
          stillCurrent: stillCurrent,
        );
        if (scheduled && active()) _migratedSnoozes.add(candidate.key);
      }
    } catch (error) {
      // A failed migration leaves the existing notification intact for retry.
      debugPrint(
        'Pending snooze tone migration deferred (${error.runtimeType}).',
      );
    }
  }

  Future<void> cancelSosNotification(String alertId) =>
      _plugin.cancel(id: notificationId('sos:$alertId'));

  /// Dismiss only this patient's appointment alert and its spoken alarm.
  Future<void> cancelAppointmentReminder(String appointmentId) async {
    final patientId = _patientId;
    if (patientId == null) return;
    final id = notificationId('apt:$patientId:$appointmentId');
    await _plugin.cancel(id: id);
    await ReminderAudioService.cancel(id);
  }

  Future<void> cancelIncomingCall(String callId) async {
    if (ReminderAudioService.ios) {
      await ReminderAudioService.channel.invokeMethod('cancelIncomingCall', {
        'callId': callId,
      });
    } else {
      await _plugin.cancel(id: 0, tag: callId);
    }
  }

  /// Share the foreground delivery record with the background isolate, so a
  /// retried FCM event does not sound again after the app is backgrounded.
  Future<void> rememberSosAlert(String alertId) async {
    final preferences = SharedPreferencesAsync();
    final seen = await preferences.getStringList('shown_sos_alerts') ?? [];
    if (seen.contains(alertId)) return;
    await preferences.setStringList('shown_sos_alerts', [
      ...seen.skip(seen.length > 199 ? seen.length - 199 : 0),
      alertId,
    ]);
  }

  Future<void> cancelAll() async {
    _patientId = null;
    _scheduleGeneration++;
    _scheduledMedications = [];
    _scheduledAppointments = [];
    _restoredSnoozeActions = [];
    _migratedSnoozes.clear();
    _cancelledSnoozes.clear();
    await _scheduleQueue.catchError((Object _) {});
    await _plugin.cancelAll();
    await ReminderAudioService.cancelAll();
    await SharedPreferencesAsync().remove('scheduled_reminder_ids');
    scheduleNotice.value = null;
  }

  /// Unique, stable notification id for a snoozed medication, so rescheduling
  /// replaces the previous snooze and cancel() can find it again.
  int _snoozeNotificationId(String medId) => notificationId('snooze:$medId');

  /// One-shot system notification at [when] (typically now + 10 min) so a
  /// snoozed medication still reminds the patient even when the app is in the
  /// background or closed during the snooze window. Tapping it opens the
  /// Reminders tab.
  Future<void> scheduleSnoozeReminder({
    required String medId,
    required String medName,
    String? dosage,
    String? medicationType,
    required DateTime when,
  }) async {
    final generation = _scheduleGeneration;
    _cancelledSnoozes.remove(_snoozeNotificationId(medId));
    await _scheduleSnoozeReminder(
      medId: medId,
      medName: medName,
      dosage: dosage,
      medicationType: medicationType,
      when: when,
    );
    if (generation == _scheduleGeneration) {
      _migratedSnoozes.add((
        _snoozeNotificationId(medId),
        when.millisecondsSinceEpoch,
      ));
    }
  }

  Future<bool> _scheduleSnoozeReminder({
    required String medId,
    required String medName,
    String? dosage,
    String? medicationType,
    required DateTime when,
    bool Function()? stillCurrent,
  }) async {
    if (stillCurrent != null && !stillCurrent()) return false;
    if (!_initialized) await init();
    if (stillCurrent != null && !stillCurrent()) return false;
    final scheduled = tz.TZDateTime.from(when, tz.local);
    var scheduleMode = AndroidScheduleMode.exactAllowWhileIdle;
    final canScheduleExact = await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.canScheduleExactNotifications();
    if (canScheduleExact == false) {
      scheduleMode = AndroidScheduleMode.inexactAllowWhileIdle;
    }
    final item = PlannedReminder(
      'snooze:$medId',
      scheduled,
      'Medication Reminder',
      'Time to take $medName${dosage != null && dosage.isNotEmpty ? ' ($dosage)' : ''}',
      medId,
      speech: medicationReminderSpeech(
        name: medName,
        dosage: dosage,
        medicationType: medicationType,
      ),
    );
    if (stillCurrent != null && !stillCurrent()) return false;
    var nativeSpeech = false;
    if (ReminderAudioService.android && canScheduleExact != false) {
      try {
        nativeSpeech = await ReminderAudioService.reconcile([
          item,
        ], group: 'snooze:$medId');
      } catch (e) {
        debugPrint('Snooze speech unavailable: $e');
      }
    }
    final spokenSound = await ReminderAudioService.sound(item);
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final critical =
        (await ios?.checkPermissions())?.isCriticalEnabled ?? false;
    if (stillCurrent != null && !stillCurrent()) return false;
    await _plugin.zonedSchedule(
      id: _snoozeNotificationId(medId),
      title: 'Medication Reminder',
      body:
          'Time to take $medName${dosage != null && dosage.isNotEmpty ? ' ($dosage)' : ''}',
      scheduledDate: scheduled,
      notificationDetails: NotificationDetails(
        android: ReminderNotificationSettings.androidDetails(
          nativeSpeech: nativeSpeech,
          medication: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentSound: true,
          sound: spokenSound ?? 'medication_voice.wav',
          interruptionLevel: critical
              ? InterruptionLevel.critical
              : InterruptionLevel.timeSensitive,
          criticalSoundVolume: critical ? 1.0 : null,
        ),
      ),
      androidScheduleMode: scheduleMode,
      payload: medId,
    );
    return true;
  }

  /// Cancel a pending snooze reminder (e.g. the medicine was taken or skipped
  /// before the 10-minute window elapsed).
  Future<void> cancelSnoozeReminder(String medId) async {
    _cancelledSnoozes.add(_snoozeNotificationId(medId));
    await _plugin.cancel(id: _snoozeNotificationId(medId));
    await ReminderAudioService.cancel(_snoozeNotificationId(medId));
  }

  /// Stop the confirmed dose's audio and snooze. Future repeating doses stay
  /// scheduled; completed Once prescriptions are removed by reconciliation.
  Future<void> cancelMedicationReminder(String medId) async {
    await cancelSnoozeReminder(medId);
    await ReminderAudioService.stopSpeech(medId);
  }

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
