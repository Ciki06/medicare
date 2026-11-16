import '../services/cloud_record_fields.dart';
import '../services/reminder_speech.dart';
import '../services/schedule_time.dart';
import 'medication_dosage.dart';

/// Stores medication details, schedules, stock, and refill reminders.
class Medication {
  /// Stores the medication and patient information.
  final String id;
  final String name;
  final String dosage;
  final String? mealTiming;
  final String time;
  final List<String> days;
  final String patientId;
  final String patientName;
  final String caregiverId;
  final String type;

  /// Stores medication stock and refill reminder settings.
  final int currentStock;
  final String? imageUrl;
  final bool remindRefill;
  final int remindThreshold;

  /// Stores the medication start date and repeat schedule.
  final String? startDate;
  final int intervalDays;
  final String timeZone;

  /// Stores the completion time for a one-time medication.
  final int? completedAt;

  /// Creates a medication record with its schedule and reminder settings.
  Medication({
    required this.id,
    required this.name,
    required this.dosage,
    this.mealTiming,
    required this.time,
    required this.days,
    required this.patientId,
    required this.patientName,
    required this.caregiverId,
    String type = 'Pill',
    this.currentStock = 0,
    this.imageUrl,
    this.remindRefill = true,
    this.remindThreshold = 5,
    this.startDate,
    this.intervalDays = 1,
    String? timeZone,
    this.completedAt,
  }) : type = MedicationDosage.canonicalType(type) ?? 'Pill',
       timeZone = timeZone ?? ScheduleTime.zone;

  /// Checks whether the medication is scheduled only once.
  bool get isOnce => days.any((day) => day.trim().toLowerCase() == 'once');

  /// Formats the dosage for display.
  String get displayDosage => MedicationDosage.display(dosage, type);

  /// Converts the medication frequency into readable text.
  String get displayFrequency {
    final entries = days
        .map((day) => day.trim())
        .where((day) => day.isNotEmpty);
    if (entries.isEmpty) return 'Daily';
    return entries
        .map((day) {
          final normalized = day.toLowerCase();
          // Displays the interval for medications taken every few days.
          if (normalized == 'every x days') {
            return intervalDays == 1 ? 'Every day' : 'Every $intervalDays days';
          }
          return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
        })
        .join(', ');
  }

  /// Checks whether a one-time medication has been completed.
  bool get isCompleted => isOnce && completedAt != null;
  // Returns the current medication schedule status.
  String get status => isCompleted ? 'completed' : 'scheduled';

  /// Creates a copy of the medication with updated completion details.
  Medication withCompletion(int? timestamp) => Medication(
    id: id,
    name: name,
    dosage: dosage,
    mealTiming: mealTiming,
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

  /// Converts medication details into a map for cloud storage.
  Map<String, dynamic> toMap() => {
    'name': name,
    'dosage': dosage,
    if (mealTiming != null) 'mealTiming': mealTiming,
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

  /// Converts stored data into a Medication object.
  factory Medication.fromMap(String id, Map<String, dynamic> map) => Medication(
    id: id,
    name: map['name'] as String,
    dosage: map['dosage'] as String,
    mealTiming: map['mealTiming'] as String?,
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

  /// Checks whether the medication should be taken on the selected date.
  bool isScheduledForDate(DateTime date) {
    if (isCompleted) return false;

    /// Uses calendar dates to calculate repeat schedules.
    final day = DateTime.utc(date.year, date.month, date.day);
    final anchor = startDate == null
        ? null
        : DateTime.tryParse('${startDate}T00:00:00Z');

    /// Prevents scheduling medication before its start date.
    if (anchor != null && day.isBefore(anchor)) return false;
    final dayList = days.map((d) => d.toLowerCase()).toList();

    /// Handles daily medication schedules.
    if (dayList.contains('daily') || dayList.isEmpty) return true;
    if (anchor != null) {
      final elapsed = day.difference(anchor).inDays;

      /// Checks one-time, weekly, monthly, and interval schedules.
      if (dayList.contains('once')) return elapsed == 0;
      if (dayList.contains('weekly')) return elapsed % 7 == 0;
      if (dayList.contains('monthly')) {
        return day.day == anchor.day;
      }
      if (dayList.contains('every x days')) {
        return intervalDays > 0 && elapsed % intervalDays == 0;
      }
    }

    /// List of weekdays used to check selected medication days.
    const weekdayNames = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];
    // Checks whether the selected date matches a scheduled weekday.
    final todayName = weekdayNames[date.weekday - 1];
    if (dayList.any((d) => d == todayName)) return true;
    return false;
  }

  /// Returns today's date in a readable format.
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

  /// Returns today's date in ISO format.
  static String todayIso() => ScheduleTime.today();

  /// Gets the medication time for the current date.
  DateTime? get scheduledDateTime =>
      ScheduleTime.onDate(time, ScheduleTime.now());
  // Formats the medication time for storage and display.
  String get time24h => ScheduleTime.normalize(time);
  String get displayTime => ScheduleTime.display(time);

  /// Converts the medication time into minutes for sorting.
  int get _sortMinutes {
    final dt = scheduledDateTime;
    if (dt == null) return 9999;
    return dt.hour * 60 + dt.minute;
  }

  /// Sorts medications according to their scheduled time.
  static int compareByTime(Medication a, Medication b) {
    return a._sortMinutes.compareTo(b._sortMinutes);
  }
}

/// Stores patient appointment details and reminder settings.
class Appointment {
  /// Formats the appointment time for display.
  String get displayTime => ScheduleTime.display(time);

  /// Combines the appointment date and time.
  DateTime? get scheduledAt {
    final day = DateTime.tryParse(date.replaceAll('/', '-'));
    return day == null ? null : ScheduleTime.onDate(time, day);
  }

  /// Calculates when the appointment reminder should appear.
  DateTime? get reminderAt =>
      scheduledAt?.subtract(Duration(minutes: remindBefore.clamp(0, 1440)));

  /// Creates a unique key based on the appointment reminder settings.
  String get reminderKey =>
      '$date|${ScheduleTime.normalize(time)}|${remindBefore.clamp(0, 1440)}';

  /// Checks whether the current reminder has already been viewed.
  bool get reminderViewed => reminderViewedFor == reminderKey;
  // Gets the voice message used for appointment reminders.
  String get voiceReminder => appointmentReminderPhrase;

  /// Sorts appointments from earliest to latest.
  static int compareChronologically(Appointment a, Appointment b) {
    final first = a.scheduledAt, second = b.scheduledAt;
    if (first == null) return second == null ? a.id.compareTo(b.id) : 1;
    if (second == null) return -1;
    final order = first.compareTo(second);
    return order == 0 ? a.id.compareTo(b.id) : order;
  }

  /// Sorts appointments from latest to earliest.
  static int newestFirst(Appointment a, Appointment b) {
    if (a.scheduledAt == null || b.scheduledAt == null) {
      return compareChronologically(a, b);
    }
    return compareChronologically(b, a);
  }

  /// Stores the appointment and patient information.
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

  /// Creates an appointment with its details and reminder settings.
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

  /// Converts appointment details into a map for cloud storage.
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

  /// Converts stored data into an Appointment object.
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
