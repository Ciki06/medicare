import 'package:flutter/material.dart';
import '../services/voice_call_service.dart';

class VoiceCallOverlay extends StatelessWidget {
  const VoiceCallOverlay({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final call = VoiceCallService.instance;
    return ListenableBuilder(
      listenable: call,
      builder: (context, _) => Stack(
        children: [
          child,
          if (call.visible)
            Positioned.fill(
              child: Material(
                color: const Color(0xFF142D4E),
                child: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.call, color: Colors.white, size: 64),
                          const SizedBox(height: 24),
                          Text(
                            call.name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            call.error ?? call.status,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                            ),
                          ),
                          if (call.connectedAt != null)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                _duration(
                                  DateTime.now().difference(call.connectedAt!),
                                ),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                ),
                              ),
                            ),
                          const SizedBox(height: 32),
                          if (call.error != null && call.id == null)
                            FilledButton(
                              onPressed: call.dismiss,
                              child: const Text('Close'),
                            )
                          else
                            Wrap(
                              spacing: 20,
                              runSpacing: 20,
                              alignment: WrapAlignment.center,
                              children: [
                                if (call.incoming && call.ringing && !call.busy)
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.green,
                                    ),
                                    onPressed: call.accept,
                                    icon: const Icon(Icons.call),
                                    label: const Text('Accept'),
                                  ),
                                if (call.connectedAt != null) ...[
                                  FilledButton.tonalIcon(
                                    onPressed: call.toggleMute,
                                    icon: Icon(
                                      call.muted ? Icons.mic_off : Icons.mic,
                                    ),
                                    label: Text(call.muted ? 'Unmute' : 'Mute'),
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: call.toggleSpeaker,
                                    icon: Icon(
                                      call.speaker
                                          ? Icons.volume_up
                                          : Icons.hearing,
                                    ),
                                    label: Text(
                                      call.speaker ? 'Speaker on' : 'Earpiece',
                                    ),
                                  ),
                                ],
                                if (!call.busy || call.id != null)
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.red,
                                    ),
                                    onPressed: () => call.end(
                                      reject: call.incoming && call.ringing,
                                    ),
                                    icon: const Icon(Icons.call_end),
                                    label: Text(
                                      call.incoming && call.ringing
                                          ? 'Reject'
                                          : 'End call',
                                    ),
                                  ),
                              ],
                            ),
                          if (call.busy)
                            const Padding(
                              padding: EdgeInsets.all(20),
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _duration(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}
