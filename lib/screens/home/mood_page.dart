import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/mood_face_art.dart';

class MoodPage extends StatefulWidget {
  const MoodPage({super.key, required this.user});

  final UserModel user;

  @override
  State<MoodPage> createState() => _MoodPageState();
}

class _MoodPageState extends State<MoodPage> {
  int _selected = 4;
  DateTime _date = DateTime.now();
  bool _saving = false;
  final _firestore = FirestoreService();

  static const moods = [
    ('😠', 'Angry', Color(0xFFF2A98D)),
    ('🙂', 'Calm', Color(0xFFFFD49C)),
    ('😊', 'Happy', Color(0xFFFFF0A7)),
    ('😍', 'Lovely', Color(0xFFF4B7B5)),
    ('😐', 'Neutral', Color(0xFFE8D8B9)),
    ('😆', 'Joyful', Color(0xFFDDE99B)),
    ('☹️', 'Sad', Color(0xFFE4D6E8)),
    ('😢', 'Crying', Color(0xFFC7D8E5)),
    ('😮', 'Anxious', Color(0xFFCDE4C8)),
  ];

  String get _dateStr =>
      '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _loadSavedMood();
  }

  Future<void> _loadSavedMood() async {
    final saved = await _firestore.getMoodByDate(widget.user.uid, _dateStr);
    if (!mounted) return;
    setState(() {
      _selected = saved?.moodIndex ?? 4;
    });
  }

  Future<void> _chooseDate() async {
    final selected = await showDialog<DateTime>(
      context: context,
      builder: (context) => _CalendarDialog(initialDate: _date),
    );
    if (selected != null) {
      setState(() => _date = selected);
      _loadSavedMood();
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final isToday =
        _date.year == today.year &&
        _date.month == today.month &&
        _date.day == today.day;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How do you feel?',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 13),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .72),
              borderRadius: BorderRadius.circular(28),
            ),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: moods.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 9,
                childAspectRatio: 0.95,
              ),
              itemBuilder: (context, index) {
                final mood = moods[index];
                final active = _selected == index;
                return InkWell(
                  key: Key('mood-$index'),
                  borderRadius: BorderRadius.circular(50),
                  onTap: () => setState(() => _selected = index),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 65,
                        height: 65,
                        decoration: BoxDecoration(
                          color: mood.$3,
                          shape: BoxShape.circle,
                          border: active
                              ? Border.all(color: AppTheme.navy, width: 3)
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: MoodFaceArt(
                          size: 65,
                          moodIndex: index,
                          color: mood.$3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(mood.$2, style: const TextStyle(fontSize: 9)),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            key: const Key('mood-date'),
            borderRadius: BorderRadius.circular(28),
            onTap: _chooseDate,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Row(
                children: [
                  const Text('Date', style: TextStyle(fontSize: 12)),
                  const Spacer(),
                  Text(
                    isToday
                        ? 'Today'
                        : '${_date.day}/${_date.month}/${_date.year}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: FilledButton(
              onPressed: _saving
                  ? null
                  : () async {
                      setState(() => _saving = true);
                      final mood = moods[_selected];
                      final messenger = ScaffoldMessenger.of(context);
                      await _firestore.saveMood(
                        patientId: widget.user.uid,
                        moodIndex: _selected,
                        moodLabel: mood.$2,
                        emoji: mood.$1,
                        date: _dateStr,
                      );
                      if (!mounted) return;
                      setState(() => _saving = false);
                      messenger.showSnackBar(
                        SnackBar(content: Text('${mood.$2} mood saved')),
                      );
                    },
              style: FilledButton.styleFrom(backgroundColor: AppTheme.navy),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Save My Mood',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarDialog extends StatefulWidget {
  const _CalendarDialog({required this.initialDate});

  final DateTime initialDate;

  @override
  State<_CalendarDialog> createState() => _CalendarDialogState();
}

class _CalendarDialogState extends State<_CalendarDialog> {
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDate;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: 320,
        child: CalendarDatePicker(
          initialDate: _selected,
          firstDate: DateTime(2020),
          lastDate: DateTime(2035),
          onDateChanged: (value) {
            _selected = value;
            Navigator.of(context).pop(value);
          },
        ),
      ),
    );
  }
}
