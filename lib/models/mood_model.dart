import '../services/cloud_record_fields.dart';

/// Stores a patient's daily mood check-in details.
class DailyMood {
  /// Stores the patient information and selected mood.
  final String id;
  final String patientId;
  final int moodIndex;
  final String moodLabel;
  final String emoji;

  /// Stores the selected date and the time the mood was recorded.
  final String date;
  final int timestamp;

  /// Creates a daily mood record with the required details.
  DailyMood({
    required this.id,
    required this.patientId,
    required this.moodIndex,
    required this.moodLabel,
    required this.emoji,
    required this.date,
    required this.timestamp,
  });

  /// Converts mood details into a map for Firebase Firestore.
  Map<String, dynamic> toMap() => {
    'patientId': patientId,
    'moodIndex': moodIndex,
    'moodLabel': moodLabel,
    'emoji': emoji,
    'date': date,
    'timestamp': timestamp,
  };

  /// Converts stored data into a DailyMood object.
  factory DailyMood.fromMap(String id, Map<String, dynamic> map) => DailyMood(
    id: id,
    patientId: CloudRecordFields.patientUid(map),
    moodIndex: (map['moodIndex'] as num).toInt(),
    moodLabel: map['moodLabel'] as String,
    emoji: map['emoji'] as String,
    date: map['date'] as String,
    timestamp: (map['timestamp'] as num).toInt(),
  );
}
