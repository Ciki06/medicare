import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/mood_face_art.dart';

class MoodPage extends StatefulWidget {
  const MoodPage({super.key, required this.user, this.onSaved});

  final UserModel user;
  final VoidCallback? onSaved;

  @override
  State<MoodPage> createState() => _MoodPageState();
}

class _MoodPageState extends State<MoodPage> {
  int _selected = 4;
  DateTime _date = DateTime.now();
  bool _saving = false;
  final _firestore = FirestoreService();

  static const moods = MoodFaceArt.moods;

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
            child: MoodChoiceGrid(
              selected: _selected,
              onSelected: (index) => setState(() => _selected = index),
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
                      try {
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
                        widget.onSaved?.call();
                      } catch (e) {
                        if (!mounted) return;
                        setState(() => _saving = false);
                        messenger.showSnackBar(
                          SnackBar(content: Text('Unable to save mood: $e')),
                        );
                      }
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

class MoodChoiceGrid extends StatelessWidget {
  const MoodChoiceGrid({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: MoodFaceArt.moods.length,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      mainAxisSpacing: 12,
      crossAxisSpacing: 9,
      childAspectRatio: 0.95,
    ),
    itemBuilder: (context, index) => InkWell(
      key: Key('mood-$index'),
      borderRadius: BorderRadius.circular(50),
      onTap: () => onSelected(index),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 65,
            height: 65,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: selected == index
                  ? Border.all(color: AppTheme.navy, width: 3)
                  : null,
            ),
            alignment: Alignment.center,
            child: MoodFaceArt(size: 65, moodIndex: index),
          ),
          const SizedBox(height: 2),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                MoodFaceArt.moods[index].$2,
                maxLines: 1,
                style: const TextStyle(fontSize: 9),
              ),
            ),
          ),
        ],
      ),
    ),
  );
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
