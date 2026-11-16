import 'package:flutter/material.dart';

import '../models/mood_model.dart';
import 'mood_face_art.dart';

/// Displays a recorded mood and its associated date.
class DailyMoodRecordCard extends StatelessWidget {
  const DailyMoodRecordCard({super.key, required this.mood, required this.patientName});

  final DailyMood mood;
  final String patientName;

  /// Use the supplied mood record to build the card shown in history.
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: MoodFaceArt(moodIndex: mood.moodIndex, size: 40),
      title: Text('$patientName • ${mood.moodLabel}'),
      subtitle: Text(
        '${mood.date} • ${TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(mood.timestamp)).format(context)}',
      ),
    ),
  );
}
