import '../../widgets/medication_activity_card.dart';
import '../../widgets/medication_totals_cards.dart';
import '../../widgets/report_week_picker.dart';
import '../../widgets/report_month_picker.dart';
import '../../widgets/mood_face_art.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../models/medication_action.dart';
import '../../models/medication_model.dart';
import '../../models/mood_model.dart';
import '../../models/user_model.dart';
import '../../models/user_role.dart';
import '../../services/firestore_service.dart';
import '../../services/history_filter.dart';
import '../../services/report_service.dart';
import '../../widgets/date_range_filter.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.user, this.report = false});
  final UserModel user;
  final bool report;
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _firestore = FirestoreService();
  final _subscriptions = <StreamSubscription>[];
  List<UserModel> _patients = [];
  List<MedicationAction> _actions = [];
  List<DailyMood> _moods = [];
  List<Appointment> _appointments = [];
  String? _patientId, _status, _error;
  String _name = '', _type = '', _location = '';
  DateTimeRange? _range, _appointmentRange;
  bool _loaded = false, _exporting = false;
  int _visible = 5, _moodsVisible = 7;
  String _period = 'Weekly';
  DateTime _anchor = DateTime.now();
  Set<DateTime> _months = {DateTime(DateTime.now().year, DateTime.now().month)};

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _failed(Object e) {
    if (mounted) setState(() => _error = 'Unable to load records: $e');
  }

  Future<void> _load() async {
    try {
      final patients = widget.user.role == UserRole.family
          ? await _firestore.getPatientsByIds(widget.user.linkedPatientIds)
          : await _firestore.getPatientsByCaregiver(widget.user.uid).first;
      if (!mounted) return;
      setState(() => _patients = patients);
      final ids = patients.map((p) => p.uid).toList();
      _subscriptions.add(
        _firestore.getMedicationActionsByPatients(ids).listen((rows) {
          if (mounted) {
            setState(() {
              _actions = rows;
              _loaded = true;
            });
          }
        }, onError: _failed),
      );
      _subscriptions.add(
        _firestore.getMoodHistory(ids).listen((rows) {
          if (mounted) setState(() => _moods = rows);
        }, onError: _failed),
      );
      _subscriptions.add(
        (widget.user.role == UserRole.family
                ? _firestore.getAppointmentsByPatients(ids)
                : _firestore.getAppointmentsByCaregiver(widget.user.uid))
            .listen((rows) {
              if (mounted) setState(() => _appointments = rows);
            }, onError: _failed),
      );
    } catch (e) {
      _failed(e);
    }
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }

  DateTimeRange get _reportRange {
    if (_period == 'Monthly' && _months.isNotEmpty) {
      final sorted = _months.toList()..sort();
      return DateTimeRange(
        start: sorted.first,
        end: DateTime(sorted.last.year, sorted.last.month + 1, 0),
      );
    }
    final day = DateTime(_anchor.year, _anchor.month, _anchor.day);
    final start = _period == 'Weekly'
        ? day.subtract(Duration(days: day.weekday - 1))
        : DateTime(day.year, day.month);
    return DateTimeRange(
      start: start,
      end: _period == 'Weekly'
          ? start.add(const Duration(days: 6))
          : DateTime(day.year, day.month + 1, 0),
    );
  }

  String _patientName(String id) =>
      _patients.where((p) => p.uid == id).firstOrNull?.name ?? 'Patient';
  void _filter(VoidCallback change) => setState(() {
    change();
    _visible = 5;
    _moodsVisible = 7;
  });
  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final range = _reportRange;
      final patients = _patients
          .where((p) => _patientId == null || p.uid == _patientId)
          .toList();
      final bytes = await ReportService.build(
        actions: _actions
            .where((a) => _patientId == null || a.patientId == _patientId)
            .toList(),
        patients: patients,
        start: range.start,
        end: range.end,
        period: _period,
        months: _period == 'Monthly' ? _months : null,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'MediCare_${_period}_${range.start.toIso8601String().substring(0, 10)}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('PDF export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _heading(String text, {Color? color}) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(
      text,
      style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: color),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!)),
      );
    }
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (_patients.isEmpty) {
      return const Center(child: Text('No patients linked yet.'));
    }
    final range = widget.report ? _reportRange : _range;
    final rows = filterMedicationActions(
      _actions,
      patientId: _patientId,
      status: widget.report ? null : _status,
      name: widget.report ? '' : _name,
      start: range?.start,
      end: range?.end,
      months: widget.report && _period == 'Monthly' ? _months : null,
    );
    final total = medicationTotals(rows);
    final moods = _moods
        .where(
          (m) =>
              (_patientId == null || m.patientId == _patientId) &&
              withinDates(
                DateTime.tryParse(m.date) ??
                    DateTime.fromMillisecondsSinceEpoch(m.timestamp),
                range?.start,
                range?.end,
              ),
        )
        .toList();
    final completed =
        _appointments.where((a) {
          final date = DateTime.tryParse(a.date.replaceAll('/', '-'));
          return a.status == 'completed' &&
              (_patientId == null || a.patientId == _patientId) &&
              a.title.toLowerCase().contains(_type.toLowerCase().trim()) &&
              a.location.toLowerCase().contains(
                _location.toLowerCase().trim(),
              ) &&
              (date == null
                  ? _appointmentRange == null
                  : withinDates(
                      date,
                      _appointmentRange?.start,
                      _appointmentRange?.end,
                    ));
        }).toList()..sort(
          (a, b) => '${b.date} ${b.time}'.compareTo('${a.date} ${a.time}'),
        );
    return ListView(
      padding: EdgeInsets.fromLTRB(16, widget.report ? 8 : 20, 16, 20),
      children: [
        if (!widget.report) _heading('Patient History & Health'),
        DropdownButtonFormField<String>(
          initialValue: _patientId ?? '',
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Patient'),
          items: [
            const DropdownMenuItem(
              value: '',
              child: Text('All linked patients'),
            ),
            ..._patients.map(
              (p) => DropdownMenuItem(value: p.uid, child: Text(p.name)),
            ),
          ],
          onChanged: (v) => _filter(() => _patientId = v == '' ? null : v),
        ),
        if (widget.report) ...[
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Weekly', label: Text('Weekly')),
              ButtonSegment(value: 'Monthly', label: Text('Monthly')),
            ],
            selected: {_period},
            onSelectionChanged: (v) => _filter(() => _period = v.first),
          ),
          if (_period == 'Monthly')
            ReportMonthPicker(
              selected: _months,
              onChanged: (v) => _filter(() => _months = v),
            )
          else
            ReportWeekPicker(
              selected: _anchor,
              onChanged: (v) => _filter(() => _anchor = v),
            ),
        ] else ...[
          DateRangeFilter(
            value: _range,
            onChanged: (v) => _filter(() => _range = v),
          ),
          DropdownButtonFormField<String>(
            initialValue: '',
            decoration: const InputDecoration(labelText: 'Medication status'),
            items: const [
              DropdownMenuItem(value: '', child: Text('All statuses')),
              DropdownMenuItem(value: 'taken', child: Text('Taken')),
              DropdownMenuItem(value: 'missed', child: Text('Missed')),
              DropdownMenuItem(value: 'snoozed', child: Text('Snoozed')),
            ],
            onChanged: (v) => _filter(() => _status = v == '' ? null : v),
          ),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Medication name',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => _filter(() => _name = v),
          ),
        ],
        _heading('Medication totals'),
        MedicationTotalsCards(
          taken: total.taken,
          missed: total.missed,
          snoozed: total.snoozed,
        ),
        if (widget.report) _heading('Patient summary'),
        if (widget.report)
          ..._patients
              .where((p) => _patientId == null || p.uid == _patientId)
              .map((p) {
                final t = medicationTotals(
                  rows.where((a) => a.patientId == p.uid),
                );
                return PatientMedicationSummary(
                  name: p.name,
                  taken: t.taken,
                  missed: t.missed,
                  snoozed: t.snoozed,
                );
              }),
        _heading('Medication History'),
        if (rows.isEmpty)
          const Text('No medication records match these filters.'),
        ...rows
            .take(_visible)
            .map(
              (a) => MedicationActivityCard(
                action: a,
                patientName: _patientName(a.patientId),
                showDate: true,
              ),
            ),
        if (rows.length > _visible)
          TextButton(
            onPressed: () => setState(() => _visible += 20),
            child: Text('View More (${rows.length - _visible} remaining)'),
          ),
        if (_visible > 5)
          TextButton(
            onPressed: () => setState(() => _visible = 5),
            child: const Text('Show Less'),
          ),
        if (!widget.report) ...[
          _heading('Patient Health (Daily Mood)'),
          const Text(
            'Uses the patient and date filters above. Compare these dates with medication history.',
          ),
          if (moods.isEmpty)
            const ListTile(title: Text('No mood recorded in this period.')),
          ...moods
              .take(_moodsVisible)
              .map(
                (m) => Card(
                  child: ListTile(
                    leading: MoodFaceArt(moodIndex: m.moodIndex, size: 40),
                    title: Text(
                      '${_patientName(m.patientId)} • ${m.moodLabel}',
                    ),
                    subtitle: Text(m.date),
                  ),
                ),
              ),
          if (moods.length > _moodsVisible)
            TextButton(
              onPressed: () => setState(() => _moodsVisible += 20),
              child: const Text('View More Moods'),
            ),
          if (_moodsVisible > 7)
            TextButton(
              onPressed: () => setState(() => _moodsVisible = 7),
              child: const Text('Show Less Moods'),
            ),
          _heading('Completed Appointments', color: Colors.black),
          DateRangeFilter(
            value: _appointmentRange,
            onChanged: (v) => _filter(() => _appointmentRange = v),
          ),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Appointment type / title',
            ),
            onChanged: (v) => setState(() => _type = v),
          ),
          TextField(
            decoration: const InputDecoration(labelText: 'Location'),
            onChanged: (v) => setState(() => _location = v),
          ),
          if (completed.isEmpty)
            const ListTile(
              title: Text('No completed appointments match these filters.'),
            ),
          ...completed.map(
            (a) => Card(
              child: ListTile(
                leading: const Icon(Icons.event_available),
                title: Text(a.title),
                subtitle: Text(
                  '${_patientName(a.patientId)}\n${a.date} ${a.displayTime}\n${a.location}',
                ),
              ),
            ),
          ),
        ],
        if (widget.report) ...[
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _exporting || (_period == 'Monthly' && _months.isEmpty)
                ? null
                : _export,
            icon: const Icon(Icons.picture_as_pdf),
            label: Text(_exporting ? 'Exporting…' : 'Export PDF'),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
