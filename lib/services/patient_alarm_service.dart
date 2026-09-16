import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PatientAlarmService {
  static final active = ValueNotifier(false);
  static const _channel = MethodChannel('medicare/patient_alarm');
  static final _player = AudioPlayer();
  static Future<void> start() async {
    if (active.value) return;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _channel.invokeMethod<void>('start');
    } else {
      await _player.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {AVAudioSessionOptions.mixWithOthers},
          ),
        ),
      );
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource('sounds/sos_alarm.wav'), volume: 1);
    }
    active.value = true;
  }

  static Future<void> refresh() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      active.value = await _channel.invokeMethod<bool>('isActive') ?? false;
    }
  }

  static Future<void> stop() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _channel.invokeMethod<void>('stop');
    } else {
      await _player.stop();
    }
    active.value = false;
  }
}
