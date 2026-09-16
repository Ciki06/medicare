import 'package:flutter/material.dart';
import '../models/user_model.dart';
import 'date_range_filter.dart';

class MedicationActivityCriteria {
  const MedicationActivityCriteria({
    this.patientId,
    this.status,
    this.name = '',
    this.range,
  });
  final String? patientId, status;
  final String name;
  final DateTimeRange? range;
}

class MedicationActivityFilter extends StatefulWidget {
  const MedicationActivityFilter({
    super.key,
    required this.patients,
    required this.onChanged,
    this.onReport,
  });
  final List<UserModel> patients;
  final ValueChanged<MedicationActivityCriteria> onChanged;
  final VoidCallback? onReport;
  @override
  State<MedicationActivityFilter> createState() =>
      _MedicationActivityFilterState();
}

class _MedicationActivityFilterState extends State<MedicationActivityFilter> {
  bool _open = false;
  String? _patient, _status;
  String _name = '';
  DateTimeRange? _range;
  void _change(VoidCallback change) {
    setState(change);
    widget.onChanged(
      MedicationActivityCriteria(
        patientId: _patient,
        status: _status,
        name: _name,
        range: _range,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              'Recent Medication Activity',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
          ),
          IconButton(
            tooltip: _open
                ? 'Close medication filters'
                : 'Filter medication activity',
            icon: Icon(_open ? Icons.close : Icons.filter_list),
            onPressed: () => setState(() => _open = !_open),
          ),
          if (widget.onReport != null)
            IconButton(
              tooltip: 'Weekly / monthly report',
              icon: const Icon(Icons.assessment_outlined),
              onPressed: widget.onReport,
            ),
        ],
      ),
      if (_open) ...[
        DateRangeFilter(
          value: _range,
          onChanged: (v) => _change(() => _range = v),
        ),
        DropdownButtonFormField<String>(
          initialValue: _patient ?? '',
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Patient'),
          items: [
            const DropdownMenuItem(value: '', child: Text('All patients')),
            ...widget.patients.map(
              (p) => DropdownMenuItem(value: p.uid, child: Text(p.name)),
            ),
          ],
          onChanged: (v) => _change(() => _patient = v == '' ? null : v),
        ),
        DropdownButtonFormField<String>(
          initialValue: _status ?? '',
          decoration: const InputDecoration(labelText: 'Medication status'),
          items: const [
            DropdownMenuItem(value: '', child: Text('All statuses')),
            DropdownMenuItem(value: 'taken', child: Text('Taken')),
            DropdownMenuItem(value: 'missed', child: Text('Missed')),
            DropdownMenuItem(value: 'snoozed', child: Text('Snoozed')),
          ],
          onChanged: (v) => _change(() => _status = v == '' ? null : v),
        ),
        TextFormField(
          initialValue: _name,
          decoration: const InputDecoration(labelText: 'Medication name'),
          onChanged: (v) => _change(() => _name = v),
        ),
        const SizedBox(height: 12),
      ],
    ],
  );
}
