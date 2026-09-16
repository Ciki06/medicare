import 'package:flutter/material.dart';
import '../models/mood_model.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';

class DailyMoodSection extends StatefulWidget {
  const DailyMoodSection({super.key, required this.patients});
  final List<UserModel> patients;
  @override
  State<DailyMoodSection> createState() => _DailyMoodSectionState();
}

class _DailyMoodSectionState extends State<DailyMoodSection> {
  late Stream<List<DailyMood>> _stream;
  String get _ids => widget.patients.map((p) => p.uid).join(',');
  late String _key;
  void _subscribe() {
    _key = _ids;
    _stream = FirestoreService().getMoodHistory(
      widget.patients.map((p) => p.uid).toList(),
    );
  }

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant DailyMoodSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_ids != _key) _subscribe();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'Daily Mood Check-In',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
      ),
      StreamBuilder<List<DailyMood>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Text(
              'Mood history could not load. Check your connection and linked patient access.',
            );
          }
          if (!snapshot.hasData) return const LinearProgressIndicator();
          if (snapshot.data!.isEmpty) {
            return const ListTile(title: Text('No mood records yet.'));
          }
          return Column(
            children: snapshot.data!
                .map(
                  (m) => Card(
                    child: ListTile(
                      leading: Text(
                        m.emoji,
                        style: const TextStyle(fontSize: 30),
                      ),
                      title: Text(
                        '${widget.patients.where((p) => p.uid == m.patientId).firstOrNull?.name ?? 'Patient'} • ${m.moodLabel}',
                      ),
                      subtitle: Text(
                        '${m.date} • ${TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(m.timestamp)).format(context)}',
                      ),
                    ),
                  ),
                )
                .toList(),
          );
        },
      ),
    ],
  );
}
