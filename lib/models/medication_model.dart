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
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'dosage': dosage,
    'time': time,
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

  factory Medication.fromMap(String id, Map<String, dynamic> map) =>
      Medication(
        id: id,
        name: map['name'] as String,
        dosage: map['dosage'] as String,
        time: map['time'] as String,
        days: List<String>.from(map['days'] as List),
        patientId: map['patientId'] as String,
        patientName: map['patientName'] as String,
        caregiverId: map['caregiverId'] as String,
        type: (map['type'] as String?) ?? 'Pill',
        currentStock: (map['currentStock'] as int?) ?? 0,
        imageUrl: map['imageUrl'] as String?,
        remindRefill: (map['remindRefill'] as bool?) ?? true,
        remindThreshold: (map['remindThreshold'] as int?) ?? 5,
      );

  bool isScheduledForDate(DateTime date) {
    final dayList = days.map((d) => d.toLowerCase()).toList();
    if (dayList.contains('daily') || dayList.isEmpty) return true;
    const weekdayNames = [
      'monday', 'tuesday', 'wednesday', 'thursday',
      'friday', 'saturday', 'sunday',
    ];
    final todayName = weekdayNames[date.weekday - 1];
    if (dayList.any((d) => d == todayName)) return true;
    if (dayList.any((d) => d.startsWith('every'))) return true;
    return false;
  }

  static String formatTodayDate() {
    final now = DateTime.now();
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[now.month]} ${now.day}, ${now.year}';
  }

  static String todayIso() => DateTime.now().toString().substring(0, 10);

  DateTime? get scheduledDateTime {
    try {
      final cleaned = time.trim();
      final isPM = cleaned.toUpperCase().contains('PM');
      final isAM = cleaned.toUpperCase().contains('AM');
      final withoutAmPm = cleaned.replaceAll(RegExp(r'[AaPp][Mm]'), '').trim();
      final parts = withoutAmPm.split(':');
      if (parts.length != 2) return null;
      var hour = int.parse(parts[0].trim());
      final minute = int.parse(parts[1].trim());
      if (isPM && hour != 12) hour += 12;
      if (isAM && hour == 12) hour = 0;
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day, hour, minute);
    } catch (_) {
      return null;
    }
  }

  String get time24h {
    try {
      final cleaned = time.trim();
      final isPM = cleaned.toUpperCase().contains('PM');
      final isAM = cleaned.toUpperCase().contains('AM');
      final withoutAmPm = cleaned.replaceAll(RegExp(r'[AaPp][Mm]'), '').trim();
      final parts = withoutAmPm.split(':');
      if (parts.length != 2) return time;
      var hour = int.parse(parts[0].trim());
      final minute = int.parse(parts[1].trim());
      if (isPM && hour != 12) hour += 12;
      if (isAM && hour == 12) hour = 0;
      return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return time;
    }
  }

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
  final String id;
  final String title;
  final String date;
  final String time;
  final String location;
  final String patientId;
  final String patientName;
  final String caregiverId;

  Appointment({
    required this.id,
    required this.title,
    required this.date,
    required this.time,
    required this.location,
    required this.patientId,
    required this.patientName,
    required this.caregiverId,
  });

  Map<String, dynamic> toMap() => {
    'title': title,
    'date': date,
    'time': time,
    'location': location,
    'patientId': patientId,
    'patientName': patientName,
    'caregiverId': caregiverId,
  };

  factory Appointment.fromMap(String id, Map<String, dynamic> map) =>
      Appointment(
        id: id,
        title: map['title'] as String,
        date: map['date'] as String,
        time: map['time'] as String,
        location: map['location'] as String,
        patientId: map['patientId'] as String,
        patientName: map['patientName'] as String,
        caregiverId: map['caregiverId'] as String,
      );
}
