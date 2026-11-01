import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/medication_action.dart';
import '../models/user_model.dart';
import 'history_filter.dart';
import 'report_chart_data.dart';
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

  static List<int> _ticks(int maximum) {
    final target = math.max(1, (maximum / 4).ceil());
    final scale = math.pow(10, (math.log(target) / math.ln10).floor()).toInt();
    final ratio = target / scale;
    final step =
        (ratio <= 1
            ? 1
            : ratio <= 2
            ? 2
            : ratio <= 5
            ? 5
            : 10) *
        scale;
    final top = ((maximum / step).ceil() + 1) * step;
    return [for (var value = 0; value <= top; value += step) value];
  }

  static pw.Widget _legend() => pw.Wrap(
    spacing: 18,
    children: [
      for (final item in [
        (label: 'Taken', color: _green),
        (label: 'Missed', color: _red),
        (label: 'Snoozed', color: _amber),
      ])
        pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Container(width: 9, height: 9, color: item.color),
            pw.SizedBox(width: 5),
            _text(item.label, size: 9),
          ],
        ),
    ],
  );

  static pw.FixedAxis<int> _countAxis(int maximum) => pw.FixedAxis<int>(
    _ticks(maximum),
    textStyle: const pw.TextStyle(fontSize: 8, color: _muted),
    format: (value) => value.toInt().toString(),
    color: _line,
    width: .7,
    divisions: true,
    divisionsColor: _line,
    divisionsWidth: .5,
  );

  static pw.Widget _chartBlock(
    String title,
    String dates,
    pw.Widget chart,
    String caption,
  ) => pw.Inseparable(
    child: pw.Container(
      margin: const pw.EdgeInsets.only(top: 22),
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _text(title, size: 14, color: _navy, bold: true),
          pw.SizedBox(height: 4),
          _text(dates, size: 8, color: _muted),
          pw.SizedBox(height: 10),
          _text('Recorded actions (count)', size: 8, color: _muted),
          pw.SizedBox(height: 8),
          pw.SizedBox(height: 170, child: chart),
          pw.SizedBox(height: 12),
          _legend(),
          pw.SizedBox(height: 8),
          _text(caption, size: 8, color: _muted),
        ],
      ),
    ),
  );

  static pw.Widget _statusChart(ReportChartData data, String dateRange) {
    final counts = [data.totals.taken, data.totals.missed, data.totals.snoozed];
    final colors = [_green, _red, _amber];
    return _chartBlock(
      'Recorded medication responses',
      '$dateRange | Malaysia time (UTC+08:00)',
      pw.Chart(
        grid: pw.CartesianGrid(
          xAxis: pw.FixedAxis.fromStrings(
            ['Taken', 'Missed', 'Snoozed'],
            textStyle: const pw.TextStyle(fontSize: 9, color: _ink),
            marginStart: 46,
            marginEnd: 46,
            color: _line,
          ),
          yAxis: _countAxis(counts.reduce(math.max)),
        ),
        datasets: [
          for (var index = 0; index < counts.length; index++)
            pw.BarDataSet<pw.PointChartValue>(
              data: [
                pw.PointChartValue(index.toDouble(), counts[index].toDouble()),
              ],
              color: colors[index],
              width: 42,
              valuePosition: pw.ValuePosition.top,
              buildValue: (_, value) => _text(
                value.y.toInt().toString(),
                size: 10,
                color: colors[index],
                bold: true,
              ),
            ),
        ],
      ),
      'Counts of saved responses, not prescribed doses or an adherence percentage.',
    );
  }

  static pw.Widget _trendChart(
    ReportChartData data,
    List<ReportChartBucket> buckets,
  ) {
    final labels = buckets.map((bucket) {
      final date = bucket.date;
      return data.monthly
          ? '${reportMonthNames[date.month - 1]}\n${date.year}'
          : '${date.day} ${reportMonthNames[date.month - 1]}';
    }).toList();
    final maximum = buckets.fold<int>(
      0,
      (value, bucket) => math.max(
        value,
        math.max(
          bucket.counts.taken,
          math.max(bucket.counts.missed, bucket.counts.snoozed),
        ),
      ),
    );
    final series = [
      (color: _green, values: buckets.map((b) => b.counts.taken).toList()),
      (color: _red, values: buckets.map((b) => b.counts.missed).toList()),
      (color: _amber, values: buckets.map((b) => b.counts.snoozed).toList()),
    ];
    final dates = data.monthly
        ? buckets
              .map(
                (b) => '${reportMonthNames[b.date.month - 1]} ${b.date.year}',
              )
              .join(', ')
        : '${shortDate(buckets.first.date)} - ${shortDate(buckets.last.date)}';
    return _chartBlock(
      data.monthly ? 'Monthly response comparison' : 'Daily response trend',
      '$dates | Malaysia time (UTC+08:00)',
      pw.Chart(
        grid: pw.CartesianGrid(
          xAxis: pw.FixedAxis<double>(
            [
              -.5,
              for (var index = 0; index < buckets.length; index++)
                index.toDouble(),
              buckets.length - .5,
            ],
            buildLabel: (value) =>
                value == value.roundToDouble() &&
                    value >= 0 &&
                    value < labels.length
                ? _text(labels[value.toInt()], size: 8)
                : pw.SizedBox(),
            color: _line,
          ),
          yAxis: _countAxis(maximum),
        ),
        datasets: [
          for (var index = 0; index < series.length; index++)
            if (data.monthly)
              pw.BarDataSet<pw.PointChartValue>(
                data: [
                  for (var point = 0; point < buckets.length; point++)
                    pw.PointChartValue(
                      point + (index - 1) * .24,
                      series[index].values[point].toDouble(),
                    ),
                ],
                color: series[index].color,
                width: buckets.length <= 4 ? 18 : 10,
              )
            else
              pw.LineDataSet<pw.PointChartValue>(
                data: [
                  for (var point = 0; point < buckets.length; point++)
                    pw.PointChartValue(
                      point.toDouble(),
                      series[index].values[point].toDouble(),
                    ),
                ],
                color: series[index].color,
                pointSize: 2.5,
                lineWidth: 1.6,
                isCurved: false,
              ),
        ],
      ),
      data.monthly
          ? 'Selected months only. Unselected months are omitted; no continuous trend is implied.'
          : 'Zero means no saved response of that type on the date; it does not imply a missed dose.',
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
    final charts = ReportChartData.fromRecords(
      actions: actions,
      patients: patients,
      start: start,
      end: end,
      months: months,
    );
    final rows = charts.rows;
    final totals = charts.totals;
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
    final chartRange = months == null || months.length <= 8
        ? dateRange
        : '${shortDate(start)} - ${shortDate(end)} | ${months.length} selected months';
    final trendChunks = charts.trendChunks.toList();
    pdf.addPage(
      pw.MultiPage(
        maxPages: rows.length + patients.length + trendChunks.length + 20,
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
                      : 'Selected months: $chartRange',
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
          if (months != null && months.length > 8)
            for (final chunk in trendChunks)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: _text(
                  chunk
                      .map(
                        (b) =>
                            '${reportMonthNames[b.date.month - 1]} ${b.date.year}',
                      )
                      .join(', '),
                  size: 9,
                  color: _muted,
                ),
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
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 12),
            child: _text(
              'Missed represents a recorded Skip action. Snoozes may be followed by later responses. '
              'Charts count Taken, Missed and Snoozed events, not unique doses or a prescribed-dose adherence rate.',
              size: 8,
              color: _muted,
            ),
          ),
          if (rows.isNotEmpty) ...[
            _statusChart(charts, chartRange),
            for (final chunk in trendChunks) _trendChart(charts, chunk),
          ] else
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 16),
              padding: const pw.EdgeInsets.all(14),
              color: _pale,
              child: _text(
                'Charts are not plotted because there are no recorded actions in the selected period.',
                size: 9,
                color: _muted,
              ),
            ),
          pw.NewPage(freeSpace: 150),
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
          pw.NewPage(freeSpace: 150),
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
