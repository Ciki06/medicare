import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/local_database_overview_service.dart';
import '../../theme/app_theme.dart';

class LocalDatabaseOverviewPage extends StatefulWidget {
  const LocalDatabaseOverviewPage({
    super.key,
    required this.firebaseUid,
    this.service,
  });
  final String firebaseUid;
  final LocalDatabaseOverviewService? service;

  @override
  State<LocalDatabaseOverviewPage> createState() =>
      _LocalDatabaseOverviewPageState();
}

class _LocalDatabaseOverviewPageState extends State<LocalDatabaseOverviewPage> {
  late final _service = widget.service ?? LocalDatabaseOverviewService();
  StreamSubscription<String?>? _session;
  final _search = TextEditingController();
  LocalDatabaseOverview? _overview;
  String? _selected;
  String? _error;
  bool _loading = true;
  bool _authorized = true;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _session = _service.uidChanges.listen((uid) {
      if (uid != widget.firebaseUid) _lock();
    }, onError: (Object _) => _lock());
    _load();
  }

  void _lock() {
    if (!mounted) return;
    ++_request;
    _search.clear();
    setState(() {
      _authorized = false;
      _loading = false;
      _overview = null;
      _error =
          'Your account changed. Return to Profile to open the database again.';
    });
  }

  Future<void> _load() async {
    if (!_authorized) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _overview = null;
    });
    try {
      final overview = await _service.load(widget.firebaseUid);
      if (!mounted || !_authorized || request != _request) return;
      setState(() {
        _overview = overview;
        if (!overview.tables.any((table) => table.name == _selected)) {
          _selected = overview.tables.firstOrNull?.name;
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted || !_authorized || request != _request) return;
      setState(() {
        _loading = false;
        _error =
            'Could not read the local database. Check that you are signed in and try refreshing.';
      });
    }
  }

  @override
  void dispose() {
    ++_request;
    _session?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overview = _overview;
    final table = overview?.tables
        .where((table) => table.name == _selected)
        .firstOrNull;
    final query = _search.text.trim().toLowerCase();
    final rows =
        table?.rows
            .where(
              (row) =>
                  query.isEmpty ||
                  row.values.any(
                    (value) =>
                        value != null &&
                        value.toString().toLowerCase().contains(query),
                  ),
            )
            .toList() ??
        [];
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Local database',
          style: TextStyle(color: AppTheme.navy, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh database',
            onPressed: !_authorized || _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.navy,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.storage_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'On this device',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'All saved records, organized by table.',
                        style: TextStyle(color: Colors.white, height: 1.5),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          _badge(
                            _countLabel(overview?.tables.length ?? 0, 'table'),
                          ),
                          _badge(
                            _countLabel(overview?.recordCount ?? 0, 'record'),
                          ),
                          _badge('Read only'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Includes all accounts saved on this phone. Firebase remains the source of truth.',
                  style: TextStyle(color: AppTheme.muted, height: 1.4),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Choose a table',
                  style: TextStyle(
                    color: AppTheme.navy,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item
                        in overview?.tables ?? <LocalDatabaseTable>[])
                      ChoiceChip(
                        label: Text('${item.title} (${item.rows.length})'),
                        selected: item.name == _selected,
                        onSelected: (_) => setState(() {
                          _selected = item.name;
                          _search.clear();
                        }),
                      ),
                  ],
                ),
                if (table == null) ...[
                  const SizedBox(height: 24),
                  const Text('No application tables are available yet.'),
                ] else ...[
                  const SizedBox(height: 20),
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Search ${table.title.toLowerCase()}',
                      hintText: 'Name, ID or any saved value',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(_search.clear),
                            ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '${rows.length} of ${_countLabel(table.rows.length, 'record')}',
                    style: const TextStyle(color: AppTheme.muted),
                  ),
                  const SizedBox(height: 10),
                  if (rows.isEmpty)
                    _empty(
                      table.rows.isEmpty
                          ? 'No saved records in this table yet. Account profiles and Patient medication schedules are saved after successful account creation or sign-in on this device. Refresh to see newly saved records.'
                          : 'No records match your search. Try another name or ID.',
                    ),
                  for (final row in rows) _recordCard(table, row),
                  const SizedBox(height: 12),
                  Card(
                    elevation: 0,
                    color: Colors.white,
                    child: ExpansionTile(
                      key: ValueKey('schema-${table.name}'),
                      leading: const Icon(
                        Icons.schema_outlined,
                        color: AppTheme.navy,
                      ),
                      title: const Text('Table fields'),
                      subtitle: Text(
                        '${table.name} • ${table.columns.length} fields',
                        style: const TextStyle(fontSize: 12),
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        for (final column in table.columns)
                          _schemaField(column),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  'medicare_local.db • Schema version ${overview?.version ?? "—"}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
              ],
            ),
    );
  }

  String _countLabel(int count, String noun) =>
      '$count $noun${count == 1 ? '' : 's'}';

  Widget _badge(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
    ),
  );

  Widget _empty(String message) => Card(
    color: AppTheme.lightBlue,
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Icon(Icons.inbox_outlined, color: AppTheme.navy, size: 32),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.5),
          ),
        ],
      ),
    ),
  );

  Widget _recordCard(LocalDatabaseTable table, Map<String, Object?> row) {
    final primaryKey = table.columns
        .where((column) => column.primaryKey)
        .firstOrNull;
    final id = primaryKey == null ? null : row[primaryKey.name];
    final title =
        row['name'] ?? row['medical_history'] ?? '${table.title} record';
    final subtitle = <String>[
      if (id != null) '${localDatabaseFieldLabel(primaryKey!.name)} $id',
      if (table.name == 'patient_medical_history')
        'Patient ID ${row['patient_id']}',
      if (row['email'] != null) row['email'].toString(),
    ].join(' • ');
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppTheme.lightBlue),
      ),
      child: ExpansionTile(
        key: ValueKey('record-${table.name}-${id ?? table.rows.indexOf(row)}'),
        title: Text(
          title.toString(),
          style: const TextStyle(
            color: AppTheme.navy,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: subtitle.isEmpty
            ? null
            : Text(subtitle, style: const TextStyle(fontSize: 12, height: 1.5)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          for (final column in table.columns)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localDatabaseFieldLabel(column.name),
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      _value(column.name, row[column.name]),
                      style: const TextStyle(height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _value(String field, Object? value) {
    if (value == null || value == '') return 'Not provided';
    if (value is List<int>) return 'Binary data (${value.length} bytes)';
    if ((field == 'created_at' || field == 'updated_at') && value is String) {
      final date = DateTime.tryParse(value)?.toLocal();
      if (date != null) {
        final labels = MaterialLocalizations.of(context);
        return '${labels.formatMediumDate(date)}, ${date.year} • ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(date))} (local time)';
      }
    }
    return value.toString();
  }

  Widget _schemaField(LocalDatabaseColumn column) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      column.primaryKey
          ? Icons.key
          : column.references != null
          ? Icons.link
          : Icons.notes,
      size: 20,
      color: AppTheme.navy,
    ),
    title: Text(
      localDatabaseFieldLabel(column.name),
      style: const TextStyle(fontSize: 14),
    ),
    subtitle: Text(
      [
        '${column.name} • ${column.type}',
        column.primaryKey
            ? 'Primary key'
            : column.requiredValue
            ? 'Required'
            : 'Optional',
        if (column.references != null) 'Links to ${column.references}',
      ].join('\n'),
      style: const TextStyle(fontSize: 12, height: 1.5),
    ),
  );
}
