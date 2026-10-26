import 'package:audioplayers/audioplayers.dart';

/// Serializes playback so a slow start cannot outlive an accept/end request.
class CallToneController {
  CallToneController({required this.play, required this.stop, this.onError});
  final Future<void> Function(String) play;
  final Future<void> Function() stop;
  final void Function(Object)? onError;
  Future<void> _events = Future.value();
  String? _desired;
  int _version = 0;

  Future<void> set(String? tone) {
    if (_desired == tone) return _events;
    _desired = tone;
    final version = ++_version;
    _events = _events
        .catchError((Object _) {})
        .then((_) async {
          await stop();
          if (version != _version || tone == null) return;
          await play(tone);
          if (version != _version) await stop();
        })
        .catchError((Object error) async {
          // A failed old request must not erase a newer desired state.
          if (version == _version) _desired = null;
          try {
            await stop();
          } catch (_) {}
          onError?.call(error);
        });
    return _events;
  }
}

/// Incoming calls are urgent alarms in MediCare, so silent ringer mode does not
/// mute the app's foreground ringtone. Android still controls alarm volume,
/// audio focus and Do Not Disturb. Outgoing progress uses the call audio route.
AudioContext callToneAudioContext({required bool incoming}) => AudioContext(
  android: AudioContextAndroid(
    usageType: incoming
        ? AndroidUsageType.alarm
        : AndroidUsageType.voiceCommunicationSignalling,
    contentType: AndroidContentType.sonification,
    audioFocus: AndroidAudioFocus.gainTransient,
    audioMode: incoming
        ? AndroidAudioMode.normal
        : AndroidAudioMode.inCommunication,
    isSpeakerphoneOn: incoming,
  ),
  iOS: AudioContextIOS(
    category: incoming
        ? AVAudioSessionCategory.soloAmbient
        : AVAudioSessionCategory.playAndRecord,
  ),
);
