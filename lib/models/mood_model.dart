class DailyMood {
  final String id;
  final String patientId;
  final int moodIndex;
  final String moodLabel;
  final String emoji;
  final String date;
  final int timestamp;

  DailyMood({
    required this.id,
    required this.patientId,
    required this.moodIndex,
    required this.moodLabel,
    required this.emoji,
    required this.date,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'patientId': patientId,
    'moodIndex': moodIndex,
    'moodLabel': moodLabel,
    'emoji': emoji,
    'date': date,
    'timestamp': timestamp,
  };

  factory DailyMood.fromMap(String id, Map<String, dynamic> map) => DailyMood(
    id: map['id'] as String? ?? id,
    patientId: map['patientId'] as String,
    moodIndex: (map['moodIndex'] as num).toInt(),
    moodLabel: map['moodLabel'] as String,
    emoji: map['emoji'] as String,
    date: map['date'] as String,
    timestamp: (map['timestamp'] as num).toInt(),
  );
}
