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
              // This panel sits above the Navigator, so its tooltips need
              // their own Overlay without changing the call layout.
              child: Overlay.wrap(
                child: Material(
                  color: const Color(0xFF142D4E),
                  child: SafeArea(
                    child: Center(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          if (call.videoMode) {
                            return _VideoCallLayout(call: call);
                          }
                          final horizontalPadding = constraints.maxWidth < 400
                              ? 16.0
                              : 32.0;
                          final content = Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.call, color: Colors.white, size: 64),
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
                          return SingleChildScrollView(
                            padding: EdgeInsets.symmetric(
                              horizontal: horizontalPadding,
                              vertical: 24,
                            ),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 480,
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
                        },
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

/// The video gets the space left after its controls, rather than imposing a
/// minimum video height that pushes camera actions into a scrolling viewport.
class _VideoCallLayout extends StatelessWidget {
  const _VideoCallLayout({required this.call});

  final VoiceCallService call;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final landscape = constraints.maxWidth > constraints.maxHeight;
      final short = constraints.maxHeight < 400;
      final padding = short ? 8.0 : 12.0;
      final controls = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CallCameraControls(call: call),
          const SizedBox(height: 6),
          _CallActions(call: call, compact: true),
        ],
      );
      final stage = LayoutBuilder(
        builder: (context, stageConstraints) => Stack(
          children: [
            _CallVideoStage(call: call, height: stageConstraints.maxHeight),
            if (call.mediaError != null)
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: _CallMediaNotice(call: call, compact: true),
              )
            else if (!call.cameraEnabled)
              const Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Text(
                  'Your camera is off',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
          ],
        ),
      );
      return Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          children: [
            _VideoCallHeader(call: call, compact: short),
            const SizedBox(height: 8),
            Expanded(
              child: landscape && constraints.maxWidth >= 520
                  ? Row(
                      children: [
                        Expanded(child: stage),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: (constraints.maxWidth * .46).clamp(260, 320),
                          child: Center(child: controls),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Expanded(child: stage),
                        const SizedBox(height: 8),
                        controls,
                      ],
                    ),
            ),
          ],
        ),
      );
    },
  );
}

class _VideoCallHeader extends StatelessWidget {
  const _VideoCallHeader({required this.call, required this.compact});

  final VoiceCallService call;
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(Icons.videocam, size: compact ? 24 : 28, color: Colors.white),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              call.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 16 : 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              call.error ?? call.status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white70,
                fontSize: compact ? 12 : 14,
              ),
            ),
          ],
        ),
      ),
      if (call.busy || call.videoBusy) ...[
        const SizedBox(width: 8),
        Semantics(
          label: 'Updating call video',
          child: const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2,
            ),
          ),
        ),
      ],
      if (call.connectedAt != null) ...[
        const SizedBox(width: 12),
        Text(
          _formatCallDuration(DateTime.now().difference(call.connectedAt!)),
          style: TextStyle(color: Colors.white, fontSize: compact ? 14 : 16),
        ),
      ],
    ],
  );
}

class _CallCameraControls extends StatelessWidget {
  const _CallCameraControls({required this.call});

  final VoiceCallService call;

  @override
  Widget build(BuildContext context) {
    final style = VoiceCallOverlay._videoControlStyle.copyWith(
      minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
      maximumSize: const WidgetStatePropertyAll(Size(double.infinity, 48)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    );
    return Row(
      children: [
        Expanded(
          child: Tooltip(
            message: call.cameraEnabled ? 'Turn camera off' : 'Turn camera on',
            child: Semantics(
              toggled: call.cameraEnabled,
              child: FilledButton.tonalIcon(
                key: const Key('call-camera-toggle'),
                style: style.copyWith(
                  backgroundColor: WidgetStatePropertyAll(
                    call.cameraEnabled
                        ? const Color(0xFF167D54)
                        : const Color(0xFFB53640),
                  ),
                ),
                onPressed: call.videoBusy ? null : call.toggleCamera,
                icon: Icon(
                  call.cameraEnabled ? Icons.videocam : Icons.videocam_off,
                  size: 20,
                ),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(call.cameraEnabled ? 'Camera ON' : 'Camera OFF'),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Tooltip(
            message: call.frontCamera
                ? 'Switch to rear camera'
                : 'Switch to front camera',
            child: FilledButton.tonalIcon(
              key: const Key('call-switch-camera'),
              style: style,
              onPressed: call.videoBusy || !call.cameraEnabled
                  ? null
                  : call.switchCamera,
              icon: const Icon(Icons.cameraswitch, size: 20),
              label: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Switch camera'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _formatCallDuration(Duration duration) =>
    '${duration.inMinutes.toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

class _CallActions extends StatelessWidget {
  const _CallActions({required this.call, this.compact = false});

  final VoiceCallService call;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (call.error != null && call.id == null) {
      return FilledButton(onPressed: call.dismiss, child: const Text('Close'));
    }
    final showAccept = call.incoming && call.ringing && !call.busy;
    final actionStyle = FilledButton.styleFrom(
      foregroundColor: Colors.white,
      iconColor: Colors.white,
      minimumSize: Size(160, compact ? 48 : 56),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 24,
        vertical: compact ? 8 : 16,
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (call.connectedAt != null)
          _CallPrimaryControls(call: call, compact: compact),
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
              top: call.connectedAt != null || showAccept
                  ? (compact ? 6 : 16)
                  : 0,
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
  const _CallPrimaryControls({required this.call, this.compact = false});

  final VoiceCallService call;
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    key: const Key('call-primary-controls'),
    children: [
      Expanded(
        child: _CallControl(
          buttonKey: const Key('call-voice-only'),
          compact: compact,
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
          compact: compact,
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
          compact: compact,
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
          compact: compact,
          label: call.speaker ? 'Speaker ON' : 'Speaker OFF',
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
    this.compact = false,
  });

  final Key buttonKey;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onPressed;
  final String tooltip;
  final bool compact;

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
          padding: EdgeInsets.symmetric(
            horizontal: 4,
            vertical: compact ? 4 : 12,
          ),
          minimumSize: Size(0, compact ? 64 : 88),
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
            Icon(icon, size: compact ? 20 : 28),
            SizedBox(height: compact ? 4 : 8),
            SizedBox(
              height:
                  MediaQuery.textScalerOf(context).scale(compact ? 12 : 14) *
                  (compact ? 2.2 : 2.4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label.replaceAll(' ', '\n'),
                  semanticsLabel: label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: compact ? 12 : 14,
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
            final inset = constraints.maxHeight < 180 ? 8.0 : 12.0;
            final localWidth = (constraints.maxWidth * .28)
                .clamp(64.0, 120.0)
                .clamp(
                  0.0,
                  (constraints.maxWidth - inset * 2).clamp(
                    0.0,
                    double.infinity,
                  ),
                )
                .clamp(
                  0.0,
                  (constraints.maxHeight - inset * 2).clamp(
                        0.0,
                        double.infinity,
                      ) /
                      1.3,
                );
            final remote = call.remoteRenderer;
            final local = call.localRenderer;
            Widget placeholder(String message) => Padding(
              // In a short stage the preview shares the placeholder's centre.
              // Leave its column clear so camera-off/loading text stays readable.
              padding: EdgeInsets.only(
                right: constraints.maxHeight < 260 ? localWidth + inset : 0,
              ),
              child: _VideoPlaceholder(message: message),
            );
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
                            placeholderBuilder: (_) =>
                                placeholder('Connecting video…'),
                          )
                        : placeholder(
                            call.remoteCameraEnabled
                                ? 'Connecting video…'
                                : 'Camera off',
                          ),
                  ),
                ),
                Positioned(
                  top: inset,
                  right: inset,
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
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) => FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: constraints.maxWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_off, size: 32, color: Colors.white70),
                const SizedBox(height: 8),
                Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _CallMediaNotice extends StatelessWidget {
  const _CallMediaNotice({required this.call, this.compact = false});
  final VoiceCallService call;
  final bool compact;

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
              maxLines: compact ? 2 : null,
              overflow: compact ? TextOverflow.ellipsis : null,
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 12 : 16,
              ),
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
