import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'reminder_plan.dart';

class ReminderAudioService {
  static const channel = MethodChannel('medicare/reminder_audio');
  static bool get android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<bool> reconcile(
    List<PlannedReminder> reminders, {
    String group = 'main',
    List<Map<String, Object?>>? retainedAppointments,
  }) async {
    if (!android) return false;
    return await channel.invokeMethod<bool>('reconcile', {
          'group': group,
          'retain': ?retainedAppointments,
          'items': reminders
              .map(
                (item) => {
                  'id': item.id,
                  'at': item.at.millisecondsSinceEpoch,
                  'title': item.title,
                  'payload': item.payload,
                  'medication': item.medication,
                  'speech': item.spokenText,
                  'repeat': item.repeat?.name ?? '',
                  if (!item.medication) ...{
                    'patientId': item.patientId,
                    'scheduleKey': item.scheduleKey,
                    'body': item.body,
                  },
                },
              )
              .toList(),
        }) ??
        false;
  }

  static Future<String?> sound(PlannedReminder reminder) async {
    if (!ios) return null;
    try {
      return await channel
          .invokeMethod<String>('sound', {'speech': reminder.spokenText})
          .timeout(const Duration(seconds: 35));
    } catch (e) {
      debugPrint('Spoken reminder sound could not be prepared: $e');
      return null;
    }
  }

  static Future<void> cancel(int id) async {
    if (android) await channel.invokeMethod('cancel', {'id': id});
  }

  static Future<List<Map<String, dynamic>>> dismissedAppointments() async {
    if (!android) return [];
    final records = await channel.invokeListMethod<dynamic>(
      'dismissedAppointments',
    );
    return [
      for (final record in records ?? const [])
        if (record is Map) Map<String, dynamic>.from(record),
    ];
  }

  static Future<void> cancelAll() async {
    if (android) await channel.invokeMethod('cancelAll');
  }

  static Future<void> stopSpeech(String payload) async {
    if (android) {
      await channel.invokeMethod('stopSpeech', {'payload': payload});
    }
  }
}
