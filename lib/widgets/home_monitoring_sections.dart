import 'package:flutter/material.dart';
import '../models/mood_model.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import 'filter_panel.dart';
import 'mood_face_art.dart';

class DailyMoodSection extends StatefulWidget {
  const DailyMoodSection({super.key, required this.patients, this.moodStream});
  final List<UserModel> patients;
  final Stream<List<DailyMood>>? moodStream;
  @override
  State<DailyMoodSection> createState() => _DailyMoodSectionState();
}

class _DailyMoodSectionState extends State<DailyMoodSection> {
  late Stream<List<DailyMood>> _stream;
  String get _ids => widget.patients.map((p) => p.uid).join(',');
  late String _key;
  bool _filtersOpen = false, _showAll = false;
  final Set<int> _moods = {};
  void _subscribe() {
    _key = _ids;
    _stream =
        widget.moodStream ??
        FirestoreService().getMoodHistory(
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
    if (_ids != _key || oldWidget.moodStream != widget.moodStream) {
      _subscribe();
      _showAll = false;
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Daily Mood Check-In',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: Colors.black,
                ),
              ),
            ),
            IconButton(
              tooltip: _filtersOpen ? 'Close mood filters' : 'Filter moods',
              icon: Icon(_filtersOpen ? Icons.close : Icons.filter_list),
              color: _moods.isEmpty ? null : AppTheme.navy,
              onPressed: () => setState(() => _filtersOpen = !_filtersOpen),
            ),
          ],
        ),
      ),
      if (_filtersOpen)
        FilterPanel(
          onClear: () => setState(() {
            _moods.clear();
            _showAll = false;
          }),
          children: [
            const Text(
              'Choose one or more moods. No selection shows all moods.',
              style: TextStyle(fontSize: 12, color: AppTheme.muted),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(
                MoodFaceArt.moods.length,
                (i) => FilterChip(
                  avatar: MoodFaceArt(moodIndex: i, size: 26),
                  label: Text(MoodFaceArt.moods[i].$2),
                  selected: _moods.contains(i),
                  showCheckmark: false,
                  selectedColor: AppTheme.lightBlue,
                  onSelected: (selected) => setState(() {
                    selected ? _moods.add(i) : _moods.remove(i);
                    _showAll = false;
                  }),
                ),
              ),
            ),
          ],
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
          final rows =
              snapshot.data!
                  .where((m) => _moods.isEmpty || _moods.contains(m.moodIndex))
                  .toList()
                ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
          if (rows.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(12),
              child: Text('No mood records match these filters.'),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...(_showAll ? rows : rows.take(5)).map(
                (m) => Card(
                  child: ListTile(
                    leading: MoodFaceArt(moodIndex: m.moodIndex, size: 40),
                    title: Text(
                      '${widget.patients.where((p) => p.uid == m.patientId).firstOrNull?.name ?? 'Patient'} • ${m.moodLabel}',
                    ),
                    subtitle: Text(
                      '${m.date} • ${TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(m.timestamp)).format(context)}',
                    ),
                  ),
                ),
              ),
              if (rows.length > 5)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton(
                    onPressed: () => setState(() => _showAll = !_showAll),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.navy,
                      side: const BorderSide(color: AppTheme.navy),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Text(
                      _showAll ? 'Show Less' : 'View More',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}
