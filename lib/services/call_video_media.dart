import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Negotiate video without opening a camera or changing the audio sender.
/// Keeping a sendrecv video m-line lets either participant start or stop their
/// camera with replaceTrack, without ending or renegotiating the live call.
Future<RTCRtpSender> reserveCallVideo(
  RTCPeerConnection peer,
  MediaStream audio,
) async {
  final transceiver = await peer.addTransceiver(
    kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
    init: RTCRtpTransceiverInit(
      direction: TransceiverDirection.SendRecv,
      streams: [audio],
    ),
  );
  return transceiver.sender;
}

/// Use the video transceiver associated when the callee applies the offer.
/// A transceiver added before setRemoteDescription remains unassociated under
/// Unified Plan and cannot send on the offered video section in this answer.
/// This changes negotiation only; opening the camera remains explicit.
Future<RTCRtpSender?> answerCallVideo(
  RTCPeerConnection peer,
  String offerSdp,
  MediaStream audio,
) async {
  final mids = _twoWayVideoMids(offerSdp);
  if (mids.isEmpty) return null;
  for (final transceiver in await peer.getTransceivers()) {
    if (transceiver.stoped ||
        transceiver.mid.isEmpty ||
        !mids.contains(transceiver.mid) ||
        transceiver.receiver.track?.kind != 'video') {
      continue;
    }
    await transceiver.setDirection(TransceiverDirection.SendRecv);
    final sender = transceiver.sender;
    try {
      await sender.setStreams([audio]);
    } catch (_) {
      // Some platform versions cannot set stream IDs on a track-null sender.
      // The receiver can still render its track through a streamless wrapper.
    }
    return sender;
  }
  return null;
}

Set<String> _twoWayVideoMids(String sdp) {
  if (!sdp.startsWith('v=0') || sdp.length > 100000) return {};
  var sessionDirection = 'sendrecv';
  final sections =
      <({String kind, int port, Map<String, String> attributes})>[];
  for (final raw in sdp.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.startsWith('m=')) {
      final parts = line.substring(2).split(RegExp(r'\s+'));
      final port =
          parts.length > 1 && RegExp(r'^\d+(?:/\d+)?$').hasMatch(parts[1])
          ? int.tryParse(parts[1].split('/').first) ?? 0
          : 0;
      sections.add((kind: parts.first, port: port, attributes: {}));
    } else if (RegExp(
      r'^a=(sendrecv|sendonly|recvonly|inactive)$',
    ).hasMatch(line)) {
      if (sections.isEmpty) {
        sessionDirection = line.substring(2);
      } else {
        sections.last.attributes['direction'] = line.substring(2);
      }
    } else if (sections.isNotEmpty && line.startsWith('a=mid:')) {
      sections.last.attributes['mid'] = line.substring(6).trim();
    }
  }
  return {
    for (final section in sections)
      if (section.kind == 'video' &&
          section.port > 0 &&
          section.port <= 65535 &&
          (section.attributes['direction'] ?? sessionDirection) == 'sendrecv' &&
          (section.attributes['mid']?.isNotEmpty ?? false))
        section.attributes['mid']!,
  };
}

/// Capture video only; the existing microphone track stays untouched. Android
/// callers must first obtain permission and upgrade the call foreground service.
Future<MediaStream> openCallCamera() => navigator.mediaDevices.getUserMedia({
  'audio': false,
  'video': {'facingMode': 'user', 'width': 640, 'height': 480, 'frameRate': 24},
});
