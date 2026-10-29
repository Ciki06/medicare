import '../services/cloud_record_fields.dart';
import '../services/reminder_speech.dart';
import '../services/schedule_time.dart';

class Medication {
  final String id;
  final String name;
  final String dosage;
  final String time;
  final List<String> days;
  final String patientId;
  final String patientName;
  final String caregiverId;
  final String type;
  final int currentStock;
  final String? imageUrl;
  final bool remindRefill;
  final int remindThreshold;
  final String? startDate;
  final int intervalDays;
  final String timeZone;

  /// Completion is projected from immutable medication-action history. It is
  /// intentionally not written into the schedule or a second local schema.
  final int? completedAt;

  Medication({
    required this.id,
    required this.name,
    required this.dosage,
    required this.time,
    required this.days,
    required this.patientId,
    required this.patientName,
    required this.caregiverId,
    this.type = 'Pill',
    this.currentStock = 0,
    this.imageUrl,
    this.remindRefill = true,
    this.remindThreshold = 5,
    this.startDate,
    this.intervalDays = 1,
    String? timeZone,
    this.completedAt,
  }) : timeZone = timeZone ?? ScheduleTime.zone;

  bool get isOnce => days.any((day) => day.trim().toLowerCase() == 'once');
  bool get isCompleted => isOnce && completedAt != null;
  String get status => isCompleted ? 'completed' : 'scheduled';

  Medication withCompletion(int? timestamp) => Medication(
    id: id,
    name: name,
    dosage: dosage,
    time: time,
    days: days,
    patientId: patientId,
    patientName: patientName,
    caregiverId: caregiverId,
    type: type,
    currentStock: currentStock,
    imageUrl: imageUrl,
    remindRefill: remindRefill,
    remindThreshold: remindThreshold,
    startDate: startDate,
    intervalDays: intervalDays,
    timeZone: timeZone,
    completedAt: isOnce ? timestamp : null,
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'dosage': dosage,
    'time': ScheduleTime.normalize(time),
    'timeZone': timeZone,
    if (startDate != null) 'startDate': startDate,
    'intervalDays': intervalDays,
    'days': days,
    'patientId': patientId,
    'patientName': patientName,
    'caregiverId': caregiverId,
    'type': type,
    'currentStock': currentStock,
    'remindRefill': remindRefill,
    if (remindRefill) 'remindThreshold': remindThreshold,
    if (imageUrl != null) 'imageUrl': imageUrl,
  };

  factory Medication.fromMap(String id, Map<String, dynamic> map) => Medication(
    id: id,
    name: map['name'] as String,
    dosage: map['dosage'] as String,
    time: map['time'] as String,
    days: List<String>.from(map['days'] as List),
    patientId: CloudRecordFields.patientUid(map),
    patientName: map['patientName'] as String,
    caregiverId: CloudRecordFields.caregiverUid(map),
    type: (map['type'] as String?) ?? 'Pill',
    currentStock: (map['currentStock'] as int?) ?? 0,
    imageUrl: map['imageUrl'] as String?,
    remindRefill: (map['remindRefill'] as bool?) ?? true,
    remindThreshold: (map['remindThreshold'] as int?) ?? 5,
    startDate: map['startDate'] as String?,
    intervalDays: (map['intervalDays'] as num?)?.toInt() ?? 1,
    timeZone: map['timeZone'] as String?,
  );

  bool isScheduledForDate(DateTime date) {
    if (isCompleted) return false;
    // Count repeats in whole calendar days, without local clock offsets.
    final day = DateTime.utc(date.year, date.month, date.day);
    final anchor = startDate == null
        ? null
        : DateTime.tryParse('${startDate}T00:00:00Z');
    if (anchor != null && day.isBefore(anchor)) return false;
    final dayList = days.map((d) => d.toLowerCase()).toList();
    if (dayList.contains('daily') || dayList.isEmpty) return true;
    if (anchor != null) {
      final elapsed = day.difference(anchor).inDays;
      if (dayList.contains('once')) return elapsed == 0;
      if (dayList.contains('weekly')) return elapsed % 7 == 0;
      if (dayList.contains('monthly')) {
        return day.day == anchor.day;
      }
      if (dayList.contains('every x days')) {
        return intervalDays > 0 && elapsed % intervalDays == 0;
      }
    }
    const weekdayNames = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];
    final todayName = weekdayNames[date.weekday - 1];
    if (dayList.any((d) => d == todayName)) return true;
    return false;
  }

  static String formatTodayDate() {
    final now = ScheduleTime.now();
    const months = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[now.month]} ${now.day}, ${now.year}';
  }

  static String todayIso() => ScheduleTime.today();
  DateTime? get scheduledDateTime =>
      ScheduleTime.onDate(time, ScheduleTime.now());
  String get time24h => ScheduleTime.normalize(time);
  String get displayTime => ScheduleTime.display(time);

  int get _sortMinutes {
    final dt = scheduledDateTime;
    if (dt == null) return 9999;
    return dt.hour * 60 + dt.minute;
  }

  static int compareByTime(Medication a, Medication b) {
    return a._sortMinutes.compareTo(b._sortMinutes);
  }
}

class Appointment {
  String get displayTime => ScheduleTime.display(time);
  DateTime? get scheduledAt {
    final day = DateTime.tryParse(date.replaceAll('/', '-'));
    return day == null ? null : ScheduleTime.onDate(time, day);
  }

  DateTime? get reminderAt =>
      scheduledAt?.subtract(Duration(minutes: remindBefore.clamp(0, 1440)));

  /// A viewed reminder stays acknowledged until its schedule changes.
  String get reminderKey =>
      '$date|${ScheduleTime.normalize(time)}|${remindBefore.clamp(0, 1440)}';
  bool get reminderViewed => reminderViewedFor == reminderKey;

  String get voiceReminder => appointmentReminderPhrase;

  static int compareChronologically(Appointment a, Appointment b) {
    final first = a.scheduledAt, second = b.scheduledAt;
    if (first == null) return second == null ? a.id.compareTo(b.id) : 1;
    if (second == null) return -1;
    final order = first.compareTo(second);
    return order == 0 ? a.id.compareTo(b.id) : order;
  }

  static int newestFirst(Appointment a, Appointment b) {
    if (a.scheduledAt == null || b.scheduledAt == null) {
      return compareChronologically(a, b);
    }
    return compareChronologically(b, a);
  }

  final String id;
  final String title;
  final String date;
  final String time;
  final String location;
  final String patientId;
  final String patientName;
  final String caregiverId;
  final String status;
  final int remindBefore;
  final String? reminderViewedFor;

  Appointment({
    required this.id,
    required this.title,
    required this.date,
    required this.time,
    required this.location,
    required this.patientId,
    required this.patientName,
    required this.caregiverId,
    this.status = 'scheduled',
    this.remindBefore = 0,
    this.reminderViewedFor,
  });

  Map<String, dynamic> toMap() => {
    'title': title,
    'date': date,
    'time': ScheduleTime.normalize(time),
    'location': location,
    'patientId': patientId,
    'patientName': patientName,
    'caregiverId': caregiverId,
    'status': status,
    'remindBefore': remindBefore,
    if (reminderViewedFor != null) 'reminderViewedFor': reminderViewedFor,
  };

  factory Appointment.fromMap(String id, Map<String, dynamic> map) =>
      Appointment(
        id: id,
        title: map['title'] as String,
        date: map['date'] as String,
        time: map['time'] as String,
        location: map['location'] as String,
        patientId: CloudRecordFields.patientUid(map),
        patientName: map['patientName'] as String,
        caregiverId: CloudRecordFields.caregiverUid(map),
        status: (map['status'] as String?) ?? 'scheduled',
        remindBefore: (map['remindBefore'] as num?)?.toInt() ?? 0,
        reminderViewedFor: map['reminderViewedFor'] as String?,
      );
}
