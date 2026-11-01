import '../models/medication_action.dart';
import '../models/user_model.dart';
import 'history_filter.dart';

typedef ReportActionCounts = ({int taken, int missed, int snoozed});

class ReportChartBucket {
  const ReportChartBucket({required this.date, required this.counts});

  final DateTime date;
  final ReportActionCounts counts;
}

class ReportChartData {
  ReportChartData._({
    required this.rows,
    required this.totals,
    required this.buckets,
    required this.monthly,
  });

  final List<MedicationAction> rows;
  final ReportActionCounts totals;
  final List<ReportChartBucket> buckets;
  final bool monthly;

  static DateTime malaysiaDate(int timestamp) {
    final wallTime = DateTime.fromMillisecondsSinceEpoch(
      timestamp,
      isUtc: true,
    ).add(const Duration(hours: 8));
    return DateTime.utc(wallTime.year, wallTime.month, wallTime.day);
  }

  static DateTime _day(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day);

  factory ReportChartData.fromRecords({
    required Iterable<MedicationAction> actions,
    required Iterable<UserModel> patients,
    required DateTime start,
    required DateTime end,
    Set<DateTime>? months,
  }) {
    final first = _day(start);
    final last = _day(end);
    if (last.isBefore(first)) {
      throw ArgumentError('The report end date precedes its start date.');
    }
    final selectedMonths = months
        ?.map((date) => DateTime.utc(date.year, date.month))
        .toSet();
    if (selectedMonths != null && selectedMonths.isEmpty) {
      throw ArgumentError('Select at least one report month.');
    }
    final patientIds = patients.map((patient) => patient.uid).toSet();
    final rows = actions.where((action) {
      if (!patientIds.contains(action.patientId)) return false;
      final date = malaysiaDate(action.timestamp);
      return !date.isBefore(first) &&
          !date.isAfter(last) &&
          (selectedMonths == null ||
              selectedMonths.contains(DateTime.utc(date.year, date.month)));
    }).toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final grouped = <DateTime, List<MedicationAction>>{};
    if (selectedMonths != null) {
      final sorted = selectedMonths.toList()..sort();
      for (final month in sorted) {
        grouped[month] = [];
      }
    } else {
      for (
        var date = first;
        !date.isAfter(last);
        date = date.add(const Duration(days: 1))
      ) {
        grouped[date] = [];
      }
    }
    for (final action in rows) {
      final date = malaysiaDate(action.timestamp);
      final key = selectedMonths == null
          ? date
          : DateTime.utc(date.year, date.month);
      grouped[key]!.add(action);
    }
    return ReportChartData._(
      rows: List.unmodifiable(rows),
      totals: medicationTotals(rows),
      buckets: List.unmodifiable([
        for (final entry in grouped.entries)
          ReportChartBucket(
            date: entry.key,
            counts: medicationTotals(entry.value),
          ),
      ]),
      monthly: selectedMonths != null,
    );
  }

  // Small groups keep month/date labels readable on an A4 page.
  Iterable<List<ReportChartBucket>> get trendChunks sync* {
    for (var offset = 0; offset < buckets.length; offset += 8) {
      yield buckets.sublist(
        offset,
        offset + 8 < buckets.length ? offset + 8 : buckets.length,
      );
    }
  }
}
