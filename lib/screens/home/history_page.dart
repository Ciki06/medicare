import '../../widgets/filter_panel.dart';
import '../../widgets/mood_face_art.dart';
import '../../widgets/daily_mood_record_card.dart';
import '../../widgets/medication_activity_card.dart';
import '../../widgets/medication_totals_cards.dart';
import '../../widgets/report_week_picker.dart';
import '../../widgets/report_month_picker.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/medication_action.dart';
import '../../models/medication_model.dart';
import '../../models/mood_model.dart';
import '../../models/user_model.dart';
import '../../models/user_role.dart';
import '../../services/firestore_service.dart';
import '../../services/history_filter.dart';
import '../../services/report_service.dart';
import '../../services/report_chart_data.dart';
import '../../theme/app_theme.dart';
import '../../widgets/date_range_filter.dart';
import '../../widgets/completed_appointment_card.dart';
import '../../widgets/completed_appointments_section.dart';
import 'report_preview_page.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    required this.user,
    this.report = false,
    this.initialPatientId,
    this.medicationId,
  });
  final UserModel user;
  final bool report;
  final String? initialPatientId;
  final String? medicationId;
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
  int _visible = 5, _moodsVisible = 5;
  bool get _familyHistory =>
      widget.user.role == UserRole.family && !widget.report;
  bool _moodFiltersOpen = false;
  final Set<int> _selectedMoods = {};
  String _period = 'Weekly';
  DateTime _anchor = DateTime.now();
  Set<DateTime> _months = {DateTime(DateTime.now().year, DateTime.now().month)};

  @override
  void initState() {
    super.initState();
    _patientId = widget.initialPatientId;
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
      final scopedPatients = widget.medicationId == null
          ? patients
          : patients.where((p) => p.uid == widget.initialPatientId).toList();
      setState(() => _patients = scopedPatients);
      final ids = scopedPatients.map((p) => p.uid).toList();
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
      if (widget.medicationId != null) return;
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
    _moodsVisible = 5;
  });
  Future<void> _export() async {
    if (_exporting || !_loaded) return;
    setState(() => _exporting = true);
    try {
      final range = _reportRange;
      final period = _period;
      final months = period == 'Monthly' ? Set<DateTime>.of(_months) : null;
      final patients = _patients
          .where((p) => _patientId == null || p.uid == _patientId)
          .toList();
      final actions = _actions
          .where((a) => _patientId == null || a.patientId == _patientId)
          .toList();
      final firstDate = range.start.toIso8601String().substring(0, 10);
      final lastDate = range.end.toIso8601String().substring(0, 10);
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ReportPreviewPage.generate(
            generatePdf: () => ReportService.build(
              actions: actions,
              patients: patients,
              start: range.start,
              end: range.end,
              period: period,
              months: months,
            ),
            filename: 'MediCare_${period}_${firstDate}_$lastDate.pdf',
          ),
        ),
      );
    } catch (e) {
      debugPrint('PDF preparation failed (${e.runtimeType}).');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not prepare the PDF. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _heading(String text, {Color? color, double topPadding = 20}) =>
      Padding(
        padding: EdgeInsets.only(top: topPadding, bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      );

  Widget _filterLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );

  Widget _historyMoreButton(String label, VoidCallback onPressed) {
    if (!_familyHistory) {
      return TextButton(onPressed: onPressed, child: Text(label));
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.navy,
            side: const BorderSide(color: AppTheme.navy),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

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
    final externalFilterLabels = _familyHistory;
    final range = widget.report ? _reportRange : _range;
    final rows = widget.report
        ? (_period == 'Monthly' && _months.isEmpty
              ? <MedicationAction>[]
              : ReportChartData.fromRecords(
                  actions: _actions,
                  patients: _patients.where(
                    (p) => _patientId == null || p.uid == _patientId,
                  ),
                  start: range!.start,
                  end: range.end,
                  months: _period == 'Monthly' ? _months : null,
                ).rows)
        : filterMedicationActions(
            _actions
                .where(
                  (action) =>
                      widget.medicationId == null ||
                      action.medicationId == widget.medicationId,
                )
                .toList(),
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
              (_selectedMoods.isEmpty || _selectedMoods.contains(m.moodIndex)) &&
              withinDates(
                DateTime.tryParse(m.date) ??
                    DateTime.fromMillisecondsSinceEpoch(m.timestamp),
                range?.start,
                range?.end,
              ),
        )
        .toList();
    final completed = _appointments.where((a) {
      final date = DateTime.tryParse(a.date.replaceAll('/', '-'));
      return a.status == 'completed' &&
          (_patientId == null || a.patientId == _patientId) &&
          a.title.toLowerCase().contains(_type.toLowerCase().trim()) &&
          a.location.toLowerCase().contains(_location.toLowerCase().trim()) &&
          (date == null
              ? _appointmentRange == null
              : withinDates(
                  date,
                  _appointmentRange?.start,
                  _appointmentRange?.end,
                ));
    }).toList()..sort(Appointment.newestFirst);
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        widget.report || _familyHistory ? 8 : 20,
        16,
        20,
      ),
      children: [
        if (!widget.report)
          _heading(
            widget.medicationId == null
                ? 'Patient History & Health'
                : 'Medication History',
            topPadding: _familyHistory ? 0 : 20,
          ),
        if (widget.medicationId == null) ...[
          if (externalFilterLabels) _filterLabel('Patient'),
          Semantics(
            label: externalFilterLabels ? 'Patient' : null,
            child: DropdownButtonFormField<String>(
              initialValue: _patientId ?? '',
              isExpanded: true,
              decoration: InputDecoration(
                labelText: externalFilterLabels ? null : 'Patient',
              ),
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
          ),
          if (externalFilterLabels) const SizedBox(height: 8),
        ],
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
          if (externalFilterLabels) ...[
            const SizedBox(height: 16),
            _filterLabel('Medication status'),
          ],
          Semantics(
            label: externalFilterLabels ? 'Medication status' : null,
            child: DropdownButtonFormField<String>(
              initialValue: '',
              decoration: InputDecoration(
                labelText: externalFilterLabels ? null : 'Medication status',
              ),
              items: const [
                DropdownMenuItem(value: '', child: Text('All statuses')),
                DropdownMenuItem(value: 'taken', child: Text('Taken')),
                DropdownMenuItem(value: 'missed', child: Text('Missed')),
                DropdownMenuItem(value: 'snoozed', child: Text('Snoozed')),
              ],
              onChanged: (v) => _filter(() => _status = v == '' ? null : v),
            ),
          ),
          if (externalFilterLabels) const SizedBox(height: 8),
          if (widget.medicationId == null)
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
                showDate: !_familyHistory,
              ),
            ),
        if (rows.length > _visible)
          _historyMoreButton(
            'View More',
            () => setState(() => _visible += 20),
          ),
        if (_visible > 5)
          _historyMoreButton('Show Less', () => setState(() => _visible = 5)),
        if (!widget.report && widget.medicationId == null) ...[
          Row(
            children: [
              Expanded(
                child: _heading(_familyHistory
                    ? 'Daily Mood Check-In'
                    : 'Patient Health (Daily Mood)'),
              ),
              IconButton(
                tooltip: _moodFiltersOpen ? 'Close mood filters' : 'Filter moods',
                icon: Icon(_moodFiltersOpen ? Icons.close : Icons.filter_list),
                color: _selectedMoods.isEmpty ? null : AppTheme.navy,
                onPressed: () => setState(() => _moodFiltersOpen = !_moodFiltersOpen),
              ),
            ],
          ),
          if (_moodFiltersOpen)
            FilterPanel(
              onClear: () => setState(() {
                _selectedMoods.clear();
                _moodsVisible = 5;
              }),
              children: [
                const Text(
                  'Choose one or more moods. No selection shows all moods.',
                  style: TextStyle(fontSize: 12, color: AppTheme.muted),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(MoodFaceArt.moods.length, (i) => FilterChip(
                    avatar: MoodFaceArt(moodIndex: i, size: 26),
                    label: Text(MoodFaceArt.moods[i].$2),
                    selected: _selectedMoods.contains(i),
                    showCheckmark: false,
                    selectedColor: AppTheme.lightBlue,
                    onSelected: (selected) => setState(() {
                      selected ? _selectedMoods.add(i) : _selectedMoods.remove(i);
                      _moodsVisible = 5;
                    }),
                  )),
                ),
              ],
            ),
          if (!_familyHistory)
            const Text(
              'Uses the patient and date filters above. Compare these dates with medication history.',
            ),
          if (moods.isEmpty)
            const ListTile(title: Text('No mood recorded in this period.')),
          ...moods
              .take(_moodsVisible)
              .map(
                (m) => DailyMoodRecordCard(
                  mood: m,
                  patientName: _patientName(m.patientId),
                ),
              ),
          if (moods.length > _moodsVisible)
            _historyMoreButton(
              _familyHistory ? 'View More' : 'View More Moods',
              () => setState(() => _moodsVisible = _familyHistory ? moods.length : _moodsVisible + 20),
            ),
          if (_moodsVisible > 5)
            _historyMoreButton(
              _familyHistory ? 'Show Less' : 'Show Less Moods',
              () => setState(() => _moodsVisible = 5),
            ),
          if (_familyHistory) ...[
            const SizedBox(height: 20),
            CompletedAppointmentsSection(
              key: ValueKey(_patientId),
              appointments: _appointments
                  .where((a) => _patientId == null || a.patientId == _patientId)
                  .toList(),
              patients: _patients
                  .where((p) => _patientId == null || p.uid == _patientId)
                  .toList(),
              cardBuilder: (a) => CompletedAppointmentCard(
                appointment: a,
                patientName: _patientName(a.patientId),
              ),
            ),
          ] else ...[
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
        ],
        if (widget.report) ...[
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _exporting || (_period == 'Monthly' && _months.isEmpty)
                ? null
                : _export,
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Export PDF'),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
