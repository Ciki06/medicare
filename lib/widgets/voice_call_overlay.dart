import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/voice_call_service.dart';

class VoiceCallOverlay extends StatelessWidget {
  const VoiceCallOverlay({super.key, required this.child, this.service});
  final Widget child;
  final VoiceCallService? service;

  static final _videoControlStyle = FilledButton.styleFrom(
    backgroundColor: const Color(0xFF2F55F4),
    foregroundColor: Colors.white,
    iconColor: Colors.white,
    disabledBackgroundColor: const Color(0xFF526580),
    disabledForegroundColor: const Color(0xFFE0E7F1),
    disabledIconColor: const Color(0xFFE0E7F1),
  );

  @override
  Widget build(BuildContext context) {
    final call = service ?? VoiceCallService.instance;
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
                    child: LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              call.videoMode ? Icons.videocam : Icons.call,
                              color: Colors.white,
                              size: call.videoMode ? 40 : 64,
                            ),
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
                                    DateTime.now().difference(
                                      call.connectedAt!,
                                    ),
                                  ),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                  ),
                                ),
                              ),
                            if (call.videoMode) ...[
                              const SizedBox(height: 12),
                              _CallVideoStage(
                                call: call,
                                height: (constraints.maxHeight * .5).clamp(
                                  200.0,
                                  480.0,
                                ),
                              ),
                              if (!call.cameraEnabled)
                                const Padding(
                                  padding: EdgeInsets.only(top: 12),
                                  child: Text(
                                    'Your camera is off. Turn it on to share your video.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                ),
                            ],
                            if (call.mediaError != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: _CallMediaNotice(call: call),
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
                                  if (call.incoming &&
                                      call.ringing &&
                                      !call.busy)
                                    FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.green,
                                      ),
                                      onPressed: call.accept,
                                      icon: const Icon(Icons.call),
                                      label: const Text('Accept'),
                                    ),
                                  if (call.connectedAt != null) ...[
                                    if (call.videoMode) ...[
                                      FilledButton.tonalIcon(
                                        key: const Key('call-camera-toggle'),
                                        style: _videoControlStyle,
                                        onPressed: call.videoBusy
                                            ? null
                                            : call.toggleCamera,
                                        icon: Icon(
                                          call.cameraEnabled
                                              ? Icons.videocam
                                              : Icons.videocam_off,
                                        ),
                                        label: Text(
                                          call.cameraEnabled
                                              ? 'Turn camera off'
                                              : 'Turn camera on',
                                        ),
                                      ),
                                      FilledButton.tonalIcon(
                                        key: const Key('call-switch-camera'),
                                        style: _videoControlStyle,
                                        onPressed:
                                            call.videoBusy ||
                                                !call.cameraEnabled
                                            ? null
                                            : call.switchCamera,
                                        icon: const Icon(Icons.cameraswitch),
                                        label: const Text('Switch camera'),
                                      ),
                                      FilledButton.tonalIcon(
                                        key: const Key('call-voice-only'),
                                        style: _videoControlStyle,
                                        onPressed: call.videoBusy
                                            ? null
                                            : call.switchToVoice,
                                        icon: const Icon(Icons.call),
                                        label: const Text('Voice only'),
                                      ),
                                    ] else
                                      Tooltip(
                                        message: call.videoBusy
                                            ? 'Updating call video…'
                                            : 'Turn on your camera for this call',
                                        child: FilledButton.tonalIcon(
                                          key: const Key('call-enable-video'),
                                          style: _videoControlStyle,
                                          onPressed: call.videoBusy
                                              ? null
                                              : call.enableVideo,
                                          icon: const Icon(Icons.videocam),
                                          label: const Text('Video call'),
                                        ),
                                      ),
                                    FilledButton.tonalIcon(
                                      onPressed: call.toggleMute,
                                      icon: Icon(
                                        call.muted ? Icons.mic_off : Icons.mic,
                                      ),
                                      label: Text(
                                        call.muted ? 'Unmute' : 'Mute',
                                      ),
                                    ),
                                    FilledButton.tonalIcon(
                                      onPressed: call.toggleSpeaker,
                                      icon: Icon(
                                        call.speaker
                                            ? Icons.volume_up
                                            : Icons.hearing,
                                      ),
                                      label: Text(
                                        call.speaker
                                            ? 'Speaker on'
                                            : 'Earpiece',
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
                            if (call.videoBusy && !call.busy)
                              Padding(
                                padding: const EdgeInsets.all(20),
                                child: Semantics(
                                  label: 'Updating call video',
                                  child: const CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
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
        ],
      ),
    );
  }

  String _duration(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

/// The renderers contain the actual WebRTC streams maintained by the call
/// service. A missing renderer always shows an explicit loading/off state.
class _CallVideoStage extends StatelessWidget {
  const _CallVideoStage({required this.call, required this.height});

  final VoiceCallService call;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const Key('call-video-stage'),
    height: height,
    width: double.infinity,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ColoredBox(
        color: const Color(0xFF09182C),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final localWidth = (constraints.maxWidth * .3).clamp(80.0, 128.0);
            final remote = call.remoteRenderer;
            final local = call.localRenderer;
            return Stack(
              children: [
                Positioned.fill(
                  child: Semantics(
                    label: '${call.name} video',
                    child: call.remoteCameraEnabled && remote != null
                        ? RTCVideoView(
                            remote,
                            key: const Key('call-remote-video'),
                            objectFit: RTCVideoViewObjectFit
                                .RTCVideoViewObjectFitContain,
                            placeholderBuilder: (_) => const _VideoPlaceholder(
                              message: 'Connecting video…',
                            ),
                          )
                        : _VideoPlaceholder(
                            message: call.remoteCameraEnabled
                                ? 'Connecting video…'
                                : 'Camera off',
                          ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: SizedBox(
                    key: const Key('call-local-preview'),
                    width: localWidth,
                    height: localWidth * 1.3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ColoredBox(
                        color: const Color(0xFF314760),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (call.cameraEnabled && local != null)
                              Semantics(
                                label: 'Your camera preview',
                                child: RTCVideoView(
                                  local,
                                  key: const Key('call-local-video'),
                                  mirror: call.frontCamera,
                                  objectFit: RTCVideoViewObjectFit
                                      .RTCVideoViewObjectFitCover,
                                ),
                              )
                            else
                              Icon(
                                call.cameraEnabled
                                    ? Icons.videocam
                                    : Icons.videocam_off,
                                color: Colors.white70,
                              ),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                width: double.infinity,
                                color: Colors.black54,
                                padding: const EdgeInsets.all(4),
                                child: const Text(
                                  'You',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_off, size: 40, color: Colors.white70),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ],
      ),
    ),
  );
}

class _CallMediaNotice extends StatelessWidget {
  const _CallMediaNotice({required this.call});
  final VoiceCallService call;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      key: const Key('call-media-notice'),
      padding: const EdgeInsets.only(left: 12, top: 8, bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              call.mediaError!,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss notice',
            onPressed: call.clearMediaError,
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
    ),
  );
}
