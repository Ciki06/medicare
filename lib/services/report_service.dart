import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/medication_action.dart';
import '../models/user_model.dart';
import 'history_filter.dart';
import 'schedule_time.dart';

class ReportService {
  static const _navy = PdfColor.fromInt(0xFF193B64);
  static const _teal = PdfColor.fromInt(0xFF087F83);
  static const _ink = PdfColor.fromInt(0xFF26384B);
  static const _muted = PdfColor.fromInt(0xFF637487);
  static const _line = PdfColor.fromInt(0xFFE1E8EF);
  static const _pale = PdfColor.fromInt(0xFFF4F7FA);
  static const _green = PdfColor.fromInt(0xFF18754D);
  static const _red = PdfColor.fromInt(0xFFAC4247);
  static const _amber = PdfColor.fromInt(0xFF956214);

  static pw.Text _text(
    String value, {
    double size = 10,
    PdfColor color = _ink,
    bool bold = false,
  }) => pw.Text(
    value,
    style: pw.TextStyle(
      fontSize: size,
      color: color,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    ),
  );

  static pw.Widget _metric(
    String label,
    int count,
    PdfColor color,
    PdfColor background,
  ) => pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        color: background,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _text(label.toUpperCase(), size: 9, color: color),
          pw.SizedBox(height: 5),
          _text('$count', size: 28, color: color, bold: true),
          _text('recorded actions', size: 8, color: color),
        ],
      ),
    ),
  );

  static pw.Widget _heading(String title, String subtitle) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 22, bottom: 10),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _text(title, size: 15, color: _navy, bold: true),
        pw.SizedBox(height: 3),
        _text(subtitle, size: 9, color: _muted),
      ],
    ),
  );

  static pw.Widget _table(
    List<String> headers,
    List<List<pw.Widget>> rows,
    Map<int, pw.TableColumnWidth> widths,
  ) => pw.Table(
    columnWidths: widths,
    defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
    children: [
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: _navy),
        children: headers
            .map(
              (h) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                child: _text(h, size: 9, color: PdfColors.white),
              ),
            )
            .toList(),
      ),
      for (var i = 0; i < rows.length; i++)
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: i.isEven ? _pale : PdfColors.white,
            border: const pw.Border(
              bottom: pw.BorderSide(color: _line, width: .5),
            ),
          ),
          children: rows[i]
              .map(
                (cell) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  child: cell,
                ),
              )
              .toList(),
        ),
    ],
  );

  static pw.Widget _status(String action) {
    final status = medicationStatus(action);
    final color = switch (status) {
      'taken' => _green,
      'missed' => _red,
      'snoozed' => _amber,
      _ => _muted,
    };
    return _text(
      status.isEmpty ? '-' : '${status[0].toUpperCase()}${status.substring(1)}',
      size: 9,
      color: color,
    );
  }

  static Future<Uint8List> build({
    required List<MedicationAction> actions,
    required List<UserModel> patients,
    required DateTime start,
    required DateTime end,
    required String period,
    Set<DateTime>? months,
  }) async {
    final rows = filterMedicationActions(
      actions,
      start: start,
      end: end,
      months: months,
    );
    final totals = medicationTotals(rows);
    final names = {for (final p in patients) p.uid: p.name};
    final pdf = pw.Document(
      title: 'MediCare - $period medication report',
      author: 'MediCare',
    );
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final dateRange = months == null
        ? '${shortDate(start)} - ${shortDate(end)}'
        : selectedMonthsLabel(months);
    pdf.addPage(
      pw.MultiPage(
        maxPages: rows.length + patients.length + 10,
        theme: pw.ThemeData.withFont(base: font, bold: pw.Font.helveticaBold()),
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 32),
        header: (context) => context.pageNumber == 1
            ? pw.SizedBox()
            : pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 16),
                padding: const pw.EdgeInsets.only(bottom: 8),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: _line)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _text(
                      'MediCare / $period medication report',
                      size: 9,
                      color: _navy,
                    ),
                    _text(
                      months == null
                          ? dateRange
                          : '${months.length} selected months',
                      size: 8,
                      color: _muted,
                    ),
                  ],
                ),
              ),
        footer: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 16),
          padding: const pw.EdgeInsets.only(top: 9),
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: _line)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _text(
                'MediCare  |  Private health information',
                size: 8,
                color: _muted,
              ),
              _text(
                '${context.pageNumber} / ${context.pagesCount}',
                size: 8,
                color: _muted,
              ),
            ],
          ),
        ),
        build: (_) => [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(22),
            decoration: pw.BoxDecoration(
              color: _navy,
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _text('MediCare', size: 13, color: PdfColors.white, bold: true),
                pw.SizedBox(height: 18),
                _text(
                  '$period medication report',
                  size: 24,
                  color: PdfColors.white,
                  bold: true,
                ),
                pw.SizedBox(height: 9),
                _text(
                  months == null
                      ? '$dateRange  |  Inclusive dates'
                      : 'Selected months: $dateRange',
                  size: 10,
                  color: PdfColor.fromInt(0xFFD2E5F2),
                ),
              ],
            ),
          ),
          pw.Container(
            height: 3,
            margin: const pw.EdgeInsets.only(top: 8, bottom: 18),
            color: _teal,
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _text('ACTIVITY OVERVIEW', size: 9, color: _muted),
              _text(
                '${patients.length} ${patients.length == 1 ? 'patient' : 'patients'}  /  ${rows.length} recorded actions',
                size: 9,
                color: _muted,
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            children: [
              _metric(
                'Taken',
                totals.taken,
                _green,
                const PdfColor.fromInt(0xFFEDF6F0),
              ),
              pw.SizedBox(width: 10),
              _metric(
                'Missed',
                totals.missed,
                _red,
                const PdfColor.fromInt(0xFFFBEEEE),
              ),
              pw.SizedBox(width: 10),
              _metric(
                'Snoozed',
                totals.snoozed,
                _amber,
                const PdfColor.fromInt(0xFFFFF6E6),
              ),
            ],
          ),
          _heading(
            'Patient summary',
            'Recorded medication actions for each patient in this period.',
          ),
          if (patients.isEmpty) _text('No patients selected.', color: _muted),
          if (patients.isNotEmpty)
            _table(
              ['Patient', 'Taken', 'Missed', 'Snoozed'],
              patients.map((p) {
                final t = medicationTotals(
                  rows.where((a) => a.patientId == p.uid),
                );
                return [
                  _text(p.name),
                  _text('${t.taken}', color: _green),
                  _text('${t.missed}', color: _red),
                  _text('${t.snoozed}', color: _amber),
                ];
              }).toList(),
              {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FlexColumnWidth(1),
                3: const pw.FlexColumnWidth(1),
              },
            ),
          _heading(
            'Medication activity',
            'Most recent first. Times shown in Malaysia time (UTC+08:00).',
          ),
          if (rows.isEmpty)
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(18),
              color: _pale,
              child: _text(
                'No recorded medication activity in this period.',
                color: _muted,
              ),
            ),
          if (rows.isNotEmpty)
            _table(
              ['Patient', 'Medication', 'Status', 'Date / time'],
              rows.map((a) {
                final d = DateTime.fromMillisecondsSinceEpoch(
                  a.timestamp,
                  isUtc: true,
                ).add(const Duration(hours: 8));
                return [
                  _text(names[a.patientId] ?? a.patientId, size: 9),
                  _text(a.medicationName, size: 9),
                  _status(a.action),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _text(shortDate(d), size: 9),
                      _text(
                        ScheduleTime.display(
                          '${d.hour}:${d.minute.toString().padLeft(2, '0')}',
                        ),
                        size: 8,
                        color: _muted,
                      ),
                    ],
                  ),
                ];
              }).toList(),
              {
                0: const pw.FlexColumnWidth(1.4),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(1),
                3: const pw.FlexColumnWidth(1.3),
              },
            ),
        ],
      ),
    );
    return pdf.save();
  }
}
