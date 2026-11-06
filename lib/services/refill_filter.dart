import '../models/refill_request.dart';
import 'history_filter.dart';

class RefillFilterCriteria {
  const RefillFilterCriteria({
    this.patientId,
    this.status,
    this.medicationName = '',
    this.start,
    this.end,
  });

  final String? patientId;
  final String? status;
  final String medicationName;
  final DateTime? start;
  final DateTime? end;

  bool get isActive =>
      patientId != null ||
      status != null ||
      medicationName.trim().isNotEmpty ||
      start != null ||
      end != null;
}

/// Filters the already authorized records without changing their source order.
/// Dates refer to when a request was made, including the entire final day.
List<RefillRequest> filterRefillRequests(
  Iterable<RefillRequest> requests, {
  RefillFilterCriteria criteria = const RefillFilterCriteria(),
}) {
  final name = criteria.medicationName.trim().toLowerCase();
  return requests
      .where(
        (request) =>
            (criteria.patientId == null ||
                request.patientId == criteria.patientId) &&
            (criteria.status == null || request.status == criteria.status) &&
            request.medicationName.toLowerCase().contains(name) &&
            withinDates(
              DateTime.fromMillisecondsSinceEpoch(request.requestedAt),
              criteria.start,
              criteria.end,
            ),
      )
      .toList();
}
