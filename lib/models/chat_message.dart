import 'location_coordinates.dart';

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
  final int? acceptedAt, endedAt;
  final double? latitude, longitude, locationAccuracy;
  final String? locationName, locationStatus;
  final int? locationCapturedAt;

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
    return '$direction voice call · $status';
  }

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
      if (isMap) yield uri.replace(scheme: 'https');
    }
  }

  LocationCoordinates? get locationCoordinates {
    if (type == 'sos_location' &&
        locationStatus != null &&
        locationStatus != 'available') {
      return null;
    }
    final snapshot = LocationCoordinates.fromValues(latitude, longitude);
    if (snapshot != null) return snapshot;
    if (type == 'sos_location' && (latitude != null || longitude != null)) {
      return null;
    }
    // Older SOS events only stored a URL. Recover its exact point without
    // resolving the address to a different building or a nearby business.
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

  Uri? get locationUri {
    if (type == 'sos_location' &&
        locationStatus != null &&
        locationStatus != 'available') {
      return null;
    }
    if (type == 'sos_location') return locationCoordinates?.webUri;
    return locationCoordinates?.webUri ?? _mapUris.firstOrNull;
  }

  /// Label the saved point with its captured address, without searching by name.
  List<Uri> locationTargets({bool android = false, bool ios = false}) {
    final point = locationCoordinates;
    return [
      if (point != null && android) point.androidUri(label: locationName),
      if (point != null && ios) point.appleUri(label: locationName),
      ?locationUri,
    ];
  }

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
    this.callId,
    this.callerId,
    this.callerName,
    this.calleeId,
    this.calleeName,
    this.callStatus,
    this.acceptedAt,
    this.endedAt,
    this.latitude,
    this.longitude,
    this.locationAccuracy,
    this.locationName,
    this.locationStatus,
    this.locationCapturedAt,
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
    callId: map['callId'] as String?,
    callerId: map['callerId'] as String?,
    callerName: map['callerName'] as String?,
    calleeId: map['calleeId'] as String?,
    calleeName: map['calleeName'] as String?,
    callStatus: map['callStatus'] as String?,
    acceptedAt: (map['acceptedAt'] as num?)?.toInt(),
    endedAt: (map['endedAt'] as num?)?.toInt(),
    latitude: (map['latitude'] as num?)?.toDouble(),
    longitude: (map['longitude'] as num?)?.toDouble(),
    locationAccuracy: (map['locationAccuracy'] as num?)?.toDouble(),
    locationName: map['locationName'] as String?,
    locationStatus: map['locationStatus'] as String?,
    locationCapturedAt: (map['locationCapturedAt'] as num?)?.toInt(),
  );

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
