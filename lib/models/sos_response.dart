import 'package:cloud_firestore/cloud_firestore.dart';

/// Stores responses sent by caregivers or family members to a patient's SOS alert.
class SosResponse {
  final String id;

  /// Stores responses sent by caregivers or family members to a patient's SOS alert.
  final String alertId;
  final String senderId;
  final String senderName;
  final String senderRole;
  final String message;
  final DateTime createdAt;

  /// Keeps SOS responses visible for five minutes after being sent.
  DateTime get expiresAt => createdAt.add(const Duration(minutes: 5));
  // Checks whether the SOS response is still within the display period.
  bool isCurrentAt(DateTime now) => now.isBefore(expiresAt);

  /// Creates an SOS response with the required details.
  SosResponse({
    required this.id,
    required this.alertId,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.message,
    required this.createdAt,
  });

  /// Converts SOS response details into a map for cloud storage.
  Map<String, dynamic> toMap() => {
    'senderId': senderId,
    'senderName': senderName,
    'senderRole': senderRole,
    'message': message,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  /// Converts stored data into an SosResponse object.
  factory SosResponse.fromMap(String id, Map<String, dynamic> map) =>
      SosResponse(
        id: id,
        alertId: map['alertId'] as String? ?? '',
        senderId: map['senderId'] as String? ?? '',
        senderName: map['senderName'] as String? ?? 'Someone',
        senderRole: map['senderRole'] as String? ?? 'helper',
        message: map['message'] as String? ?? '',
        // Supports both Firestore timestamps and stored millisecond values.
        createdAt: map['createdAt'] is Timestamp
            ? (map['createdAt'] as Timestamp).toDate()
            : DateTime.fromMillisecondsSinceEpoch(
                (map['createdAt'] as num?)?.toInt() ??
                    DateTime.now().millisecondsSinceEpoch,
              ),
      );

  /// Converts the sender's role into a readable label.
  String get senderRoleLabel => switch (senderRole) {
    'caregiver' => 'Caregiver',
    'family' => 'Family',
    _ => 'Helper',
  };
}
