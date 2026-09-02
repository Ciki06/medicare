import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Full-screen overlay shown after the patient completes the press-and-hold
/// gesture. Plays the system alarm tone and counts down 3 -> 2 -> 1 before the
/// SOS alert is actually broadcast, giving the patient a final chance to abort.
class SosCountdownOverlay extends StatefulWidget {
  const SosCountdownOverlay({
    super.key,
    required this.onComplete,
    this.onCancel,
  });

  /// Called after the countdown finishes (3..1) — the SOS is sent here.
  final VoidCallback onComplete;

  /// Optional callback when the patient taps "Cancel" to abort the SOS.
  final VoidCallback? onCancel;

  @override
  State<SosCountdownOverlay> createState() => _SosCountdownOverlayState();
}

class _SosCountdownOverlayState extends State<SosCountdownOverlay>
    with SingleTickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  int _count = 3;
  Timer? _ticker;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..repeat(reverse: true);
    // Play the alarm once (the 3s siren spans the whole countdown) rather than
    // re-triggering play() each second — re-playing while the previous
    // playback is mid-flight can fail silently on the player.
    _configureAudio();
    _playAlarm();
    _vibrate();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_count <= 1) {
        timer.cancel();
        _stopAudio();
        widget.onComplete();
      } else {
        setState(() => _count--);
        _vibrate();
      }
    });
  }

  /// Route playback through the system's alarm stream so the SOS sound is
  /// audible even when the device's media volume is low or silenced. This is
  /// essential for an emergency alarm.
  Future<void> _configureAudio() async {
    try {
      await _player.setAudioContext(
        AudioContext(
          android: AudioContextAndroid(
            usageType: AndroidUsageType.alarm,
            contentType: AndroidContentType.sonification,
            audioFocus: AndroidAudioFocus.gainTransient,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {AVAudioSessionOptions.mixWithOthers},
          ),
        ),
      );
    } catch (e) {
      debugPrint('SOS alarm: audio context setup failed: $e');
    }
  }

  Future<void> _playAlarm() async {
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setVolume(1.0);
      await _player.play(
        AssetSource('sounds/sos_alarm.wav'),
        mode: PlayerMode.mediaPlayer,
      );
      debugPrint('SOS alarm: playback started');
    } catch (e) {
      debugPrint('SOS alarm: playback failed: $e');
    }
  }

  void _stopAudio() {
    try {
      _player.stop();
    } catch (_) {
      // Ignore.
    }
  }

  void _vibrate() {
    HapticFeedback.heavyImpact();
    HapticFeedback.vibrate();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pulse.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x99000000),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: Tween<double>(begin: 1.1, end: 1.0).animate(_pulse),
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE85B61),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: Text(
                      '$_count',
                      key: ValueKey(_count),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 72,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Sending SOS in...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Release to cancel',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 24),
              if (widget.onCancel != null)
                TextButton(
                  onPressed: () {
                    _ticker?.cancel();
                    _stopAudio();
                    widget.onCancel!.call();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white24,
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
