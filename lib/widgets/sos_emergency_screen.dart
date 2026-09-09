import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/firestore_service.dart';

/// Full-screen red emergency screen shown to a caregiver / family member when
/// a linked patient triggers an SOS alert. Plays the same alarm sound the
/// patient hears, pulses a large red SOS, and offers a single "I'll help"
/// action that acknowledges the alert.
///
/// It can be pushed as a route (in-app, foreground) or provided directly as
/// `home` after a cold start so it also covers the screen when the app is
/// launched from a background notification.
class SosEmergencyScreen extends StatefulWidget {
  const SosEmergencyScreen({
    super.key,
    required this.alertId,
    required this.patientName,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    this.onAcknowledge,
  });

  final String alertId;
  final String patientName;

  /// Identity of the person seeing this screen (the caregiver / family member).
  /// Used to sign the "on the way" reply so the patient knows who is coming.
  final String senderId;
  final String senderName;
  final String senderRole;

  /// Invoked after the alert is acknowledged and the screen is ready to close.
  /// When omitted, the widget pops itself (useful when pushed as a route).
  final VoidCallback? onAcknowledge;

  @override
  State<SosEmergencyScreen> createState() => _SosEmergencyScreenState();
}

class _SosEmergencyScreenState extends State<SosEmergencyScreen>
    with SingleTickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  late final AnimationController _pulse;
  bool _sending = false;

  bool get _hasAlertId => widget.alertId.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
    unawaited(_startAlarm());
    _vibrate();
  }

  Future<void> _startAlarm() async {
    await _configureAudio();
    if (!mounted) return;
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);
      await _player.play(
        AssetSource('sounds/sos_alarm.wav'),
        mode: PlayerMode.mediaPlayer,
      );
    } catch (e) {
      debugPrint('SOS emergency: alarm playback failed: $e');
    }
  }

  /// Route playback through the system's alarm stream so the SOS sound is
  /// audible even when the device's media volume is low or silenced.
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
      debugPrint('SOS emergency: audio context setup failed: $e');
    }
  }

  void _vibrate() {
    HapticFeedback.heavyImpact();
    HapticFeedback.vibrate();
  }

  /// Acknowledge the alert so it doesn't re-appear, then close the screen.
  Future<void> _close() async {
    if (_hasAlertId) {
      try {
        await FirestoreService().acknowledgeSos(widget.alertId);
      } catch (e) {
        debugPrint('SOS emergency: acknowledge failed: $e');
      }
    }
    if (!mounted) return;
    final onAcknowledge = widget.onAcknowledge;
    if (onAcknowledge != null) {
      onAcknowledge();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).maybePop();
    }
  }

  /// Send an "on the way"-style reply to the patient, then close the screen.
  /// Firestore rules only allow recipients of the active alert to write, so any
  /// legitimate user here is authorized.
  Future<void> _sendResponse(String message) async {
    final text = message.trim();
    if (text.isEmpty || _sending || !_hasAlertId) return;
    setState(() => _sending = true);
    try {
      await FirestoreService().sendSosResponse(
        alertId: widget.alertId,
        senderId: widget.senderId,
        senderName: widget.senderName,
        senderRole: widget.senderRole,
        message: text,
      );
    } catch (e) {
      debugPrint('SOS emergency: send response failed: $e');
    }
    if (!mounted) return;
    await _close();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE85B61),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ScaleTransition(
                        scale: Tween<double>(begin: 1.12, end: 1.0)
                            .animate(_pulse),
                        child: GestureDetector(
                          onTap: _vibrate,
                          child: Container(
                            width: 130,
                            height: 130,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'SOS',
                                  style: TextStyle(
                                    color: Color(0xFFE85B61),
                                    fontSize: 36,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2,
                                  ),
                                ),
                                Text(
                                  'EMERGENCY',
                                  style: TextStyle(
                                    color: Color(0xFFE85B61),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        '🚨 SOS Alert',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${widget.patientName} sent an SOS and needs help '
                        'immediately!',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _sending
                            ? null
                            : () => _sendResponse('I\'m on the way!'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFFE85B61),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                          minimumSize: const Size(double.infinity, 0),
                        ),
                        icon: const Icon(Icons.directions_car),
                        label: const Text(
                          "I'm On The Way",
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Notifies ${widget.patientName} that you are coming.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
