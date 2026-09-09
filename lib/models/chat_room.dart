class ChatRoom {
  final String id;
  final List<String> participants;
  final String lastMessage;
  final String lastMessageSender;
  final int lastMessageAt;
  final Map<String, int> unreadCount;

  ChatRoom({
    required this.id,
    required this.participants,
    this.lastMessage = '',
    this.lastMessageSender = '',
    this.lastMessageAt = 0,
    this.unreadCount = const {},
  });

  factory ChatRoom.fromMap(String id, Map<String, dynamic> map) => ChatRoom(
        id: id,
        participants: (map['participants'] as List?)?.cast<String>() ?? [],
        lastMessage: map['lastMessage'] as String? ?? '',
        lastMessageSender: map['lastMessageSender'] as String? ?? '',
        lastMessageAt: map['lastMessageAt'] as int? ?? 0,
        unreadCount: (map['unreadCount'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, (v as num).toInt())) ??
            {},
      );

  Map<String, dynamic> toMap() => {
        'participants': participants,
        'lastMessage': lastMessage,
        'lastMessageSender': lastMessageSender,
        'lastMessageAt': lastMessageAt,
        'unreadCount': unreadCount,
      };

  String otherUserId(String myId) =>
      participants.firstWhere((p) => p != myId, orElse: () => '');
}
