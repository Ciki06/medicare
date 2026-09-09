/// A message a caregiver / family member sends to the patient after they
/// receive an SOS alert (e.g. "I'm on the way!"), showing the patient who is
/// coming to help.
class SosResponse {
  final String id;
  final String alertId;
  final String senderId;
  final String senderName;
  final String senderRole;
  final String message;
  final DateTime createdAt;

  SosResponse({
    required this.id,
    required this.alertId,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.message,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'senderId': senderId,
        'senderName': senderName,
        'senderRole': senderRole,
        'message': message,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory SosResponse.fromMap(String id, Map<String, dynamic> map) =>
      SosResponse(
        id: id,
        alertId: map['alertId'] as String? ?? '',
        senderId: map['senderId'] as String? ?? '',
        senderName: map['senderName'] as String? ?? 'Someone',
        senderRole: map['senderRole'] as String? ?? 'helper',
        message: map['message'] as String? ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['createdAt'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch,
        ),
      );

  /// Human-friendly label for the sender's role, e.g. 'Caregiver' / 'Family'.
  String get senderRoleLabel => switch (senderRole) {
        'caregiver' => 'Caregiver',
        'family' => 'Family',
        _ => 'Helper',
      };
}