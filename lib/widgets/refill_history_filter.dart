import 'package:flutter/material.dart';

import '../models/refill_request.dart';
import '../services/refill_filter.dart';
import '../theme/app_theme.dart';
import 'date_range_filter.dart';
import 'filter_panel.dart';

/// Filters the refill history already available to the signed-in care team.
class RefillHistoryFilter extends StatefulWidget {
  const RefillHistoryFilter({
    super.key,
    required this.requests,
    required this.onChanged,
  });

  final List<RefillRequest> requests;
  final ValueChanged<RefillFilterCriteria> onChanged;

  @override
  State<RefillHistoryFilter> createState() => _RefillHistoryFilterState();
}

class _RefillHistoryFilterState extends State<RefillHistoryFilter> {
  final _medicationController = TextEditingController();
  bool _expanded = false;
  String? _patientId;
  String? _selectedPatientName;
  String? _status;
  DateTimeRange? _range;

  RefillFilterCriteria get _criteria => RefillFilterCriteria(
    patientId: _patientId,
    status: _status,
    medicationName: _medicationController.text,
    start: _range?.start,
    end: _range?.end,
  );

  @override
  void didUpdateWidget(covariant RefillHistoryFilter oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final request in widget.requests) {
      if (request.patientId == _patientId) {
        _selectedPatientName = request.patientName;
        break;
      }
    }
  }

  @override
  void dispose() {
    _medicationController.dispose();
    super.dispose();
  }

  void _change(VoidCallback change) {
    setState(change);
    widget.onChanged(_criteria);
  }

  void _clear() => _change(() {
    _patientId = null;
    _selectedPatientName = null;
    _status = null;
    _range = null;
    _medicationController.clear();
  });

  Widget _field(String label, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: AppTheme.navy,
          ),
        ),
      ),
      Semantics(label: label, child: child),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final patients = <String, String>{
      for (final request in widget.requests)
        if (request.patientId.isNotEmpty)
          request.patientId: request.patientName,
    };
    // Keep the active choice visible if a live update removes its last record.
    if (_patientId != null) {
      patients.putIfAbsent(
        _patientId!,
        () => _selectedPatientName ?? 'Selected patient',
      );
    }
    final patientOptions = patients.entries.toList()
      ..sort((a, b) {
        final byName = a.value.toLowerCase().compareTo(b.value.toLowerCase());
        return byName == 0 ? a.key.compareTo(b.key) : byName;
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Medication Refill Status',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.navy,
                ),
              ),
            ),
            IconButton(
              tooltip: _expanded ? 'Hide filters' : 'Show filters',
              isSelected: _expanded,
              color: AppTheme.navy,
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _criteria.isActive
                    ? Icons.filter_alt
                    : Icons.filter_alt_outlined,
              ),
            ),
          ],
        ),
        if (_expanded)
          FilterPanel(
            onClear: _clear,
            children: [
              _field(
                'Patient',
                DropdownButtonFormField<String>(
                  key: ValueKey(('refill-patient', _patientId)),
                  initialValue: _patientId ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('All patients'),
                    ),
                    for (final patient in patientOptions)
                      DropdownMenuItem(
                        value: patient.key,
                        child: Text(
                          patient.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => _change(() {
                    _patientId = value == '' ? null : value;
                    _selectedPatientName = patients[value];
                  }),
                ),
              ),
              _field(
                'Refill status',
                DropdownButtonFormField<String>(
                  key: ValueKey(('refill-status', _status)),
                  initialValue: _status ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('All statuses')),
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(
                      value: 'ready_for_pickup',
                      child: Text(
                        'Ready for Pickup',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'collected',
                      child: Text('Completed'),
                    ),
                    DropdownMenuItem(
                      value: 'rejected',
                      child: Text('Rejected'),
                    ),
                  ],
                  onChanged: (value) =>
                      _change(() => _status = value == '' ? null : value),
                ),
              ),
              _field(
                'Request date',
                DateRangeFilter(
                  value: _range,
                  onChanged: (value) => _change(() => _range = value),
                ),
              ),
              _field(
                'Medication name',
                TextField(
                  controller: _medicationController,
                  decoration: const InputDecoration(
                    hintText: 'Search medication',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => _change(() {}),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
