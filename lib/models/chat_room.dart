/// A conversation and the details shown in the chat list.
/// Stores the details of a chat room and its latest message.
class ChatRoom {
  final String id;

  /// List of users involved in the conversation.
  final List<String> participants;
  final String lastMessage;
  final String lastMessageSender;
  final int lastMessageAt;

  /// Stores the number of unread messages for each user.
  final Map<String, int> unreadCount;

  /// Creates a chat room with the required details and default values.
  ChatRoom({
    required this.id,
    required this.participants,
    this.lastMessage = '',
    this.lastMessageSender = '',
    this.lastMessageAt = 0,
    this.unreadCount = const {},
  });

  /// Converts data from Firestore into a ChatRoom object.
  factory ChatRoom.fromMap(String id, Map<String, dynamic> map) => ChatRoom(
    id: id,
    participants: (map['participants'] as List?)?.cast<String>() ?? [],
    lastMessage: map['lastMessage'] as String? ?? '',
    lastMessageSender: map['lastMessageSender'] as String? ?? '',
    lastMessageAt: map['lastMessageAt'] as int? ?? 0,
    unreadCount:
        (map['unreadCount'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, (v as num).toInt()),
        ) ??
        {},
  );

  /// Converts the chat room details into a map for storing in Firestore.
  Map<String, dynamic> toMap() => {
    'participants': participants,
    'lastMessage': lastMessage,
    'lastMessageSender': lastMessageSender,
    'lastMessageAt': lastMessageAt,
    'unreadCount': unreadCount,
  };

  /// Finds the other participant's user ID in the conversation.
  String otherUserId(String myId) =>
      participants.firstWhere((p) => p != myId, orElse: () => '');
}
