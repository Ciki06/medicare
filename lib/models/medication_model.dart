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
