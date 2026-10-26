import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Medication channels retain their existing message sound and vibration.
/// Appointment alarm channels are separate because Android freezes each
/// channel's initial sound configuration.
class ReminderNotificationSettings {
  static const nativeChannel = 'reminder_messages_v3';
  static const fallbackChannel = 'reminder_messages_fallback_v3';
  static const channelName = 'Medication and appointment reminders';
  static const sound = UriAndroidNotificationSound(
    'content://settings/system/notification_sound',
  );
  static const appointmentNativeChannel = 'appointment_alarm_service_v1';
  static const appointmentFallbackChannel = 'appointment_alarm_fallback_v4';
  static const appointmentSound = UriAndroidNotificationSound(
    'content://settings/system/alarm_alert',
  );
  static final vibration = Int64List.fromList([0, 600, 250, 600, 250, 900]);

  static Iterable<AndroidNotificationChannel> get channels sync* {
    for (final nativeSpeech in [true, false]) {
      yield AndroidNotificationChannel(
        nativeSpeech ? nativeChannel : fallbackChannel,
        channelName,
        description: 'Scheduled medication and appointment reminders',
        importance: Importance.max,
        playSound: true,
        sound: sound,
        audioAttributesUsage: AudioAttributesUsage.notification,
        // The native speech service owns vibration in the exact-alarm path,
        // including Silent mode. The notification owns it in the fallback.
        enableVibration: !nativeSpeech,
        vibrationPattern: nativeSpeech ? null : vibration,
      );
    }
    yield const AndroidNotificationChannel(
      appointmentNativeChannel,
      'Appointment alarms',
      description: 'Appointment alarms with a manual stop control',
      importance: Importance.high,
      playSound: false,
      enableVibration: false,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );
    yield AndroidNotificationChannel(
      appointmentFallbackChannel,
      'Appointment alarm notifications',
      description: 'Appointment alarms when background playback is restricted',
      importance: Importance.max,
      sound: appointmentSound,
      playSound: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      enableVibration: true,
      vibrationPattern: vibration,
    );
  }

  static AndroidNotificationDetails androidDetails({
    required bool nativeSpeech,
    required bool medication,
  }) {
    if (!medication) {
      return AndroidNotificationDetails(
        nativeSpeech ? appointmentNativeChannel : appointmentFallbackChannel,
        nativeSpeech ? 'Appointment alarms' : 'Appointment alarm notifications',
        channelDescription: nativeSpeech
            ? 'Appointment alarms with a manual stop control'
            : 'Appointment alarms when background playback is restricted',
        sound: nativeSpeech ? null : appointmentSound,
        playSound: !nativeSpeech,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableVibration: !nativeSpeech,
        vibrationPattern: nativeSpeech ? null : vibration,
        additionalFlags: nativeSpeech ? null : Int32List.fromList([4]),
        ongoing: false,
        autoCancel: true,
        category: AndroidNotificationCategory.alarm,
        importance: Importance.max,
        priority: Priority.high,
      );
    }
    return AndroidNotificationDetails(
      nativeSpeech ? nativeChannel : fallbackChannel,
      channelName,
      channelDescription: 'Scheduled medication and appointment reminders',
      sound: sound,
      playSound: true,
      audioAttributesUsage: AudioAttributesUsage.notification,
      enableVibration: !nativeSpeech,
      vibrationPattern: nativeSpeech ? null : vibration,
      ongoing: !medication,
      autoCancel: true,
      category: AndroidNotificationCategory.reminder,
      importance: Importance.max,
      priority: Priority.high,
    );
  }
}
