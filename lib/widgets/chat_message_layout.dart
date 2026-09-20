import 'package:flutter/material.dart';

/// Keeps message actions outside the bubble, on its inward-facing side.
class ChatMessageLayout extends StatelessWidget {
  const ChatMessageLayout({
    super.key,
    required this.mine,
    required this.bubble,
    required this.onForward,
  });
  final bool mine;
  final Widget bubble;
  final VoidCallback? onForward;
  @override
  Widget build(BuildContext context) {
    final forward = IconButton(
      tooltip: 'Forward message',
      icon: const Icon(Icons.shortcut_rounded, size: 23),
      color: const Color(0xFF687987),
      onPressed: onForward,
    );
    return Row(
      mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (mine) forward,
        Flexible(child: bubble),
        if (!mine) forward,
      ],
    );
  }
}
