class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final int createdAt;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.createdAt,
  });

  factory ChatMessage.fromMap(String id, Map<String, dynamic> map) =>
      ChatMessage(
        id: id,
        senderId: map['senderId'] as String? ?? '',
        senderName: map['senderName'] as String? ?? '',
        text: map['text'] as String? ?? '',
        createdAt: map['createdAt'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'senderId': senderId,
        'senderName': senderName,
        'text': text,
        'createdAt': createdAt,
      };
}
