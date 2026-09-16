import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/medication_action.dart';
import '../models/user_model.dart';
import 'history_filter.dart';

class ReportService {
  static Future<Uint8List> build({
    required List<MedicationAction> actions,
    required List<UserModel> patients,
    required DateTime start,
    required DateTime end,
    required String period,
  }) async {
    final rows = filterMedicationActions(actions, start: start, end: end);
    final totals = medicationTotals(rows);
    final pdf = pw.Document();
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    pdf.addPage(
      pw.MultiPage(
        maxPages: rows.length + patients.length + 10,
        theme: pw.ThemeData.withFont(base: font, bold: font),
        pageFormat: PdfPageFormat.a4,
        footer: (context) => pw.Text(
          'Page ${context.pageNumber} / ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 9),
        ),
        build: (_) => [
          pw.Header(level: 0, text: 'MediCare | $period medication report'),
          pw.Text('${shortDate(start)} - ${shortDate(end)} (inclusive)'),
          pw.SizedBox(height: 16),
          pw.Text(
            'Total Taken: ${totals.taken}    Total Missed: ${totals.missed}    Total Snoozed: ${totals.snoozed}',
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Counts are recorded actions. Missed includes legacy Skipped records; unrecorded doses are not inferred. Snoozes are events, not unique doses. Offline exports include only cached records.',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 18),
          pw.TableHelper.fromTextArray(
            headers: ['Patient', 'Taken', 'Missed', 'Snoozed'],
            data: patients.map((p) {
              final t = medicationTotals(
                rows.where((a) => a.patientId == p.uid),
              );
              return [p.name, '${t.taken}', '${t.missed}', '${t.snoozed}'];
            }).toList(),
            cellStyle: const pw.TextStyle(fontSize: 10),
          ),
          pw.SizedBox(height: 18),
          pw.Header(level: 1, text: 'Medication activity by patient'),
          if (rows.isEmpty)
            pw.Text('No recorded medication activity in this period.'),
          if (rows.isNotEmpty)
            pw.TableHelper.fromTextArray(
              headers: ['Patient', 'Medicine', 'Status', 'Date / time'],
              data: rows.map((a) {
                final names = patients.where((p) => p.uid == a.patientId);
                final d = DateTime.fromMillisecondsSinceEpoch(a.timestamp);
                return [
                  names.isEmpty ? a.patientId : names.first.name,
                  a.medicationName,
                  medicationStatus(a.action),
                  '${shortDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
                ];
              }).toList(),
              cellStyle: const pw.TextStyle(fontSize: 9),
            ),
        ],
      ),
    );
    return pdf.save();
  }
}
