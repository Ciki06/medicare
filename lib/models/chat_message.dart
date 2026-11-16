import 'location_coordinates.dart';

/// One chat entry, such as a text, attachment, location or call record.
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
  final String? callId, callerId, callerName, calleeId, calleeName, callStatus;
  final String? callType;
  final int? acceptedAt, endedAt;

  /// Location messages can include the saved point and details about its capture.
  final double? latitude, longitude, locationAccuracy;
  final String? locationName, locationStatus;
  final int? locationCapturedAt;

  bool get isVideoCall =>
      callType == 'video' ||
      (callType == null && type == 'call' && text.startsWith('Video call:'));

  /// Shows the call direction, type, and status for the current user.
  String callLabel(String uid) {
    final direction = callerId == uid ? 'Outgoing' : 'Incoming';
    final status = switch (callStatus) {
      'preparing' => 'Starting',
      'ringing' => 'Ringing',
      'accepted' => 'Accepted',
      'ended' => acceptedAt == null ? 'Ended' : 'Accepted · Ended',
      'rejected' => 'Rejected',
      'missed' => 'Missed',
      'cancelled' => 'Cancelled',
      _ => 'Ended',
    };
    final kind = isVideoCall ? 'video' : 'voice';
    return '$direction $kind call · $status';
  }

  /// Look for supported map links in the map field and the message text.
  Iterable<Uri> get _mapUris sync* {
    final candidates = [
      if (mapUrl != null) mapUrl!.trim(),
      ...RegExp(r'https?://[^\s<>]+').allMatches(text).map((m) => m.group(0)!),
    ];
    for (final value in candidates) {
      final uri = Uri.tryParse(value);
      if (uri == null ||
          !['https', 'http'].contains(uri.scheme) ||
          uri.host.isEmpty) {
        continue;
      }
      final isMap =
          uri.host == 'maps.google.com' ||
          uri.host == 'maps.apple.com' ||
          uri.host == 'maps.app.goo.gl' ||
          ((uri.host == 'www.google.com' || uri.host == 'google.com') &&
              uri.path.startsWith('/maps'));

      /// Open supported map links over HTTPS.
      if (isMap) yield uri.replace(scheme: 'https');
    }
  }

  /// Returns the saved point when a location is available.
  LocationCoordinates? get locationCoordinates {
    if (type == 'sos_location' &&
        locationStatus != null &&
        locationStatus != 'available') {
      return null;
    }
    final snapshot = LocationCoordinates.fromValues(latitude, longitude);
    if (snapshot != null) return snapshot;

    /// Stop if an SOS entry has invalid or incomplete saved coordinates.
    if (type == 'sos_location' && (latitude != null || longitude != null)) {
      return null;
    }

    /// Older SOS messages saved a link. Read the exact coordinates from it.
    for (final uri in _mapUris) {
      final point =
          LocationCoordinates.fromQuery(
            uri.queryParameters['query'] ?? uri.queryParameters['q'],
          ) ??
          (uri.host == 'maps.apple.com'
              ? LocationCoordinates.fromQuery(uri.queryParameters['ll'])
              : null);
      if (point != null) return point;
    }
    return null;
  }

  /// Builds a web map link for the saved location.
  Uri? get locationUri {
    if (type == 'sos_location' &&
        locationStatus != null &&
        locationStatus != 'available') {
      return null;
    }
    if (type == 'sos_location') return locationCoordinates?.webUri;
    // Regular map messages can also open a supported link from the text.
    return locationCoordinates?.webUri ?? _mapUris.firstOrNull;
  }

  /// Lists links for the device's map app and the web map.
  List<Uri> locationTargets({bool android = false, bool ios = false}) {
    final point = locationCoordinates;
    return [
      if (point != null && android) point.androidUri(label: locationName),
      if (point != null && ios) point.appleUri(label: locationName),
      ?locationUri,
    ];
  }

  /// Returns the text shown in the chat bubble.
  String get displayText {
    // Voice messages have a player. Images show a caption when one is saved.
    if (type == 'voice') return '';
    if (type == 'image') return caption ?? (text == 'Image' ? '' : text);
    return text;
  }

  /// Creates a text message by default. Other types can include extra fields.
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
    this.callId,
    this.callerId,
    this.callerName,
    this.calleeId,
    this.calleeName,
    this.callStatus,
    this.callType,
    this.acceptedAt,
    this.endedAt,
    this.latitude,
    this.longitude,
    this.locationAccuracy,
    this.locationName,
    this.locationStatus,
    this.locationCapturedAt,
  });

  /// Reads a Firestore message and uses the write status supplied by the caller.
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
    callId: map['callId'] as String?,
    callerId: map['callerId'] as String?,
    callerName: map['callerName'] as String?,
    calleeId: map['calleeId'] as String?,
    calleeName: map['calleeName'] as String?,
    callStatus: map['callStatus'] as String?,
    callType: map['callType'] as String?,
    acceptedAt: (map['acceptedAt'] as num?)?.toInt(),
    endedAt: (map['endedAt'] as num?)?.toInt(),
    latitude: (map['latitude'] as num?)?.toDouble(),
    longitude: (map['longitude'] as num?)?.toDouble(),
    locationAccuracy: (map['locationAccuracy'] as num?)?.toDouble(),
    locationName: map['locationName'] as String?,
    locationStatus: map['locationStatus'] as String?,
    locationCapturedAt: (map['locationCapturedAt'] as num?)?.toInt(),
  );

  /// Builds the message data sent to Firestore. The server writes call history.
  Map<String, dynamic> toMap() => {
    'senderId': senderId,
    'senderName': senderName,
    'text': text,
    'createdAt': createdAt,
    'type': type,
    if (mediaUrl != null) 'mediaUrl': mediaUrl,
    if (mapUrl != null) 'mapUrl': mapUrl,
    if (caption != null) 'caption': caption,
    if (durationSeconds != null) 'durationSeconds': durationSeconds,
    if (forwarded) 'forwarded': true,
    if (latitude != null) 'latitude': latitude,
    if (longitude != null) 'longitude': longitude,
    if (locationName != null) 'locationName': locationName,
    if (locationStatus != null) 'locationStatus': locationStatus,
    if (locationAccuracy != null) 'locationAccuracy': locationAccuracy,
    if (locationCapturedAt != null) 'locationCapturedAt': locationCapturedAt,
  };
}
