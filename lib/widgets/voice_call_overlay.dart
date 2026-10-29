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
                      builder: (context, constraints) {
                        final horizontalPadding = constraints.maxWidth < 400
                            ? 16.0
                            : 32.0;
                        final content = Column(
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
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                alignment: WrapAlignment.center,
                                children: [
                                  FilledButton.tonalIcon(
                                    key: const Key('call-camera-toggle'),
                                    style: _videoControlStyle,
                                    onPressed: call.videoBusy
                                        ? null
                                        : call.toggleCamera,
                                    icon: Icon(
                                      call.cameraEnabled
                                          ? Icons.videocam_off
                                          : Icons.videocam,
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
                                        call.videoBusy || !call.cameraEnabled
                                        ? null
                                        : call.switchCamera,
                                    icon: const Icon(Icons.cameraswitch),
                                    label: const Text('Switch camera'),
                                  ),
                                ],
                              ),
                            ],
                            if (call.mediaError != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: _CallMediaNotice(call: call),
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
                        );
                        final actions = _CallActions(call: call);
                        // Only video needs a separate scrollable area. Voice
                        // details and actions stay together in a centered group.
                        final canPinControls =
                            call.videoMode &&
                            constraints.maxHeight >=
                                MediaQuery.textScalerOf(context).scale(14) *
                                        2.4 +
                                    240;
                        if (!canPinControls) {
                          return SingleChildScrollView(
                            padding: EdgeInsets.symmetric(
                              horizontal: horizontalPadding,
                              vertical: 24,
                            ),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: call.videoMode
                                      ? double.infinity
                                      : 480,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    content,
                                    const SizedBox(height: 32),
                                    actions,
                                  ],
                                ),
                              ),
                            ),
                          );
                        }
                        return Column(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                padding: EdgeInsets.fromLTRB(
                                  horizontalPadding,
                                  32,
                                  horizontalPadding,
                                  16,
                                ),
                                child: content,
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                horizontalPadding,
                                16,
                                horizontalPadding,
                                24,
                              ),
                              child: actions,
                            ),
                          ],
                        );
                      },
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

class _CallActions extends StatelessWidget {
  const _CallActions({required this.call});

  final VoiceCallService call;

  @override
  Widget build(BuildContext context) {
    if (call.error != null && call.id == null) {
      return FilledButton(onPressed: call.dismiss, child: const Text('Close'));
    }
    final showAccept = call.incoming && call.ringing && !call.busy;
    final actionStyle = FilledButton.styleFrom(
      foregroundColor: Colors.white,
      iconColor: Colors.white,
      minimumSize: const Size(160, 56),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (call.connectedAt != null) _CallPrimaryControls(call: call),
        if (showAccept)
          FilledButton.icon(
            key: const Key('call-accept'),
            style: actionStyle.copyWith(
              backgroundColor: const WidgetStatePropertyAll(Colors.green),
            ),
            onPressed: call.accept,
            icon: const Icon(Icons.call),
            label: const Text('Accept'),
          ),
        if (!call.busy || call.id != null)
          Padding(
            padding: EdgeInsets.only(
              top: call.connectedAt != null || showAccept ? 16 : 0,
            ),
            child: Center(
              child: FilledButton.icon(
                key: const Key('call-end'),
                style: actionStyle.copyWith(
                  backgroundColor: const WidgetStatePropertyAll(
                    Color(0xFFD32F2F),
                  ),
                ),
                onPressed: () =>
                    call.end(reject: call.incoming && call.ringing),
                icon: const Icon(Icons.call_end),
                label: Text(
                  call.incoming && call.ringing ? 'Reject' : 'End Call',
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CallPrimaryControls extends StatelessWidget {
  const _CallPrimaryControls({required this.call});

  final VoiceCallService call;

  @override
  Widget build(BuildContext context) => Row(
    key: const Key('call-primary-controls'),
    children: [
      Expanded(
        child: _CallControl(
          buttonKey: const Key('call-voice-only'),
          label: 'Voice Call',
          icon: Icons.call,
          selected: !call.videoMode,
          onPressed: call.videoBusy ? null : call.switchToVoice,
          tooltip: 'Switch to voice-only mode',
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _CallControl(
          buttonKey: const Key('call-enable-video'),
          label: 'Video Call',
          icon: Icons.videocam,
          selected: call.videoMode,
          onPressed: call.videoBusy ? null : call.enableVideo,
          tooltip: 'Enable video and your camera',
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _CallControl(
          buttonKey: const Key('call-mute-toggle'),
          label: call.muted ? 'Unmute' : 'Mute',
          icon: call.muted ? Icons.mic_off : Icons.mic,
          selected: call.muted,
          onPressed: call.toggleMute,
          tooltip: call.muted ? 'Unmute microphone' : 'Mute microphone',
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _CallControl(
          buttonKey: const Key('call-speaker-toggle'),
          label: call.speaker ? 'Speaker' : 'Normal',
          icon: call.speaker ? Icons.volume_up : Icons.hearing,
          selected: call.speaker,
          onPressed: call.toggleSpeaker,
          tooltip: call.speaker ? 'Use normal earpiece' : 'Use loudspeaker',
        ),
      ),
    ],
  );
}

class _CallControl extends StatelessWidget {
  const _CallControl({
    required this.buttonKey,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
    required this.tooltip,
  });

  final Key buttonKey;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: Tooltip(
      message: tooltip,
      child: FilledButton(
        key: buttonKey,
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: selected
              ? const Color(0xFF2F55F4)
              : const Color(0xFF334E70),
          foregroundColor: Colors.white,
          iconColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF526580),
          disabledForegroundColor: const Color(0xFFE0E7F1),
          disabledIconColor: const Color(0xFFE0E7F1),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          minimumSize: const Size(0, 88),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          side: BorderSide(
            color: selected ? Colors.white : Colors.white38,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28),
            const SizedBox(height: 8),
            SizedBox(
              height: MediaQuery.textScalerOf(context).scale(14) * 2.4,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label.replaceAll(' ', '\n'),
                  semanticsLabel: label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
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
