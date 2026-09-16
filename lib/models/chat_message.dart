class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final int createdAt;
  final String type;
  final String? mediaUrl;
  final bool pending;
  final String? mapUrl;
  final String? caption;
  final int? durationSeconds;
  final bool forwarded;

  String get displayText {
    if (type == 'voice') return '';
    if (type == 'image') return caption ?? (text == 'Image' ? '' : text);
    return text;
  }

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.createdAt,
    this.type = 'text',
    this.mediaUrl,
    this.mapUrl,
    this.pending = false,
    this.caption,
    this.durationSeconds,
    this.forwarded = false,
  });

  factory ChatMessage.fromMap(
    String id,
    Map<String, dynamic> map, {
    bool pending = false,
  }) => ChatMessage(
    id: id,
    senderId: map['senderId'] as String? ?? '',
    senderName: map['senderName'] as String? ?? '',
    text: map['text'] as String? ?? '',
    createdAt: map['createdAt'] as int? ?? 0,
    type: map['type'] as String? ?? 'text',
    mediaUrl: map['mediaUrl'] as String?,
    pending: pending,
    mapUrl: map['mapUrl'] as String?,
    caption: map['caption'] as String?,
    durationSeconds: (map['durationSeconds'] as num?)?.toInt(),
    forwarded: map['forwarded'] == true,
  );

  Map<String, dynamic> toMap() => {
    'senderId': senderId,
    'senderName': senderName,
    'text': text,
    'createdAt': createdAt,
    'type': type,
    if (mediaUrl != null) 'mediaUrl': mediaUrl,
    if (caption != null) 'caption': caption,
    if (durationSeconds != null) 'durationSeconds': durationSeconds,
    if (forwarded) 'forwarded': true,
  };
}
