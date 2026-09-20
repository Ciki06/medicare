import 'filter_panel.dart';
import 'package:flutter/material.dart';
import '../models/medication_model.dart';
import '../models/user_model.dart';
import '../services/history_filter.dart';
import 'date_range_filter.dart';
import '../theme/app_theme.dart';

class CompletedAppointmentsSection extends StatefulWidget {
  const CompletedAppointmentsSection({
    super.key,
    required this.appointments,
    required this.patients,
    this.cardBuilder,
  });
  final Widget Function(Appointment)? cardBuilder;
  final List<Appointment> appointments;
  final List<UserModel> patients;
  @override
  State<CompletedAppointmentsSection> createState() =>
      _CompletedAppointmentsSectionState();
}

class _CompletedAppointmentsSectionState
    extends State<CompletedAppointmentsSection> {
  DateTimeRange? _range;
  String _patient = '', _type = '', _location = '', _time = '';
  bool _open = false, _showAll = false;
  int _reset = 0;
  void _filter(VoidCallback change) => setState(() {
    change();
    _showAll = false;
  });
  @override
  Widget build(BuildContext context) {
    final rows =
        widget.appointments.where((a) {
          final day = DateTime.tryParse(a.date.replaceAll('/', '-'));
          return a.status == 'completed' &&
              a.displayTime.toLowerCase().contains(
                _time.trim().toLowerCase(),
              ) &&
              (_patient.isEmpty || a.patientId == _patient) &&
              a.title.toLowerCase().contains(_type.trim().toLowerCase()) &&
              a.location.toLowerCase().contains(
                _location.trim().toLowerCase(),
              ) &&
              (day == null
                  ? _range == null
                  : withinDates(day, _range?.start, _range?.end));
        }).toList()..sort(
          (a, b) => '${b.date} ${b.time}'.compareTo('${a.date} ${a.time}'),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Completed Appointment',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                ),
              ),
            ),
            IconButton(
              tooltip: _open
                  ? 'Close appointment filters'
                  : 'Filter completed appointments',
              icon: Icon(_open ? Icons.close : Icons.filter_list),
              onPressed: () => setState(() => _open = !_open),
            ),
          ],
        ),
        if (_open)
          FilterPanel(
            key: ValueKey(_reset),
            onClear: () => _filter(() {
              _patient = '';
              _type = '';
              _location = '';
              _time = '';
              _range = null;
              _reset++;
            }),
            children: [
              DateRangeFilter(
                value: _range,
                onChanged: (v) => _filter(() => _range = v),
              ),
              DropdownButtonFormField<String>(
                initialValue: _patient,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Patient'),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('All patients'),
                  ),
                  ...widget.patients.map(
                    (p) => DropdownMenuItem(value: p.uid, child: Text(p.name)),
                  ),
                ],
                onChanged: (v) => _filter(() => _patient = v ?? ''),
              ),
              TextFormField(
                initialValue: _type,
                decoration: const InputDecoration(
                  labelText: 'Appointment type / title',
                ),
                onChanged: (v) => _filter(() => _type = v),
              ),
              TextFormField(
                initialValue: _location,
                decoration: const InputDecoration(labelText: 'Location'),
                onChanged: (v) => _filter(() => _location = v),
              ),
              TextFormField(
                initialValue: _time,
                decoration: const InputDecoration(
                  labelText: 'Time',
                  hintText: 'e.g. 9:30 AM',
                ),
                onChanged: (v) => _filter(() => _time = v),
              ),
            ],
          ),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('No completed appointments match these filters.'),
          ),
        ...(_showAll ? rows : rows.take(5)).map(
          (a) =>
              widget.cardBuilder?.call(a) ??
              Card(
                child: ListTile(
                  leading: const Icon(Icons.event_available),
                  title: Text(a.title),
                  subtitle: Text(
                    '${a.patientName}\n${a.date} ${a.displayTime}\n${a.location}',
                  ),
                ),
              ),
        ),
        if (rows.length > 5)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SizedBox(
              width: double.infinity,
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
          ),
      ],
    );
  }
}
