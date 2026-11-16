import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../services/history_filter.dart';
import '../theme/app_theme.dart';

/// Displays a call in the chat timeline using its direction, type, and outcome.
class ChatCallEvent extends StatelessWidget {
  const ChatCallEvent({super.key, required this.message, required this.userId});
  final ChatMessage message;
  final String userId;

  @override
  Widget build(BuildContext context) {
    /// The caller owns the shared event, even when its final status was written
    /// by the receiver or the server. Older events may only have senderId.
    final mine = (message.callerId ?? message.senderId) == userId;
    final failed = [
      'rejected',
      'missed',
      'cancelled',
    ].contains(message.callStatus);
    final color = failed ? const Color(0xFFBA4148) : AppTheme.navy;
    /// Choose a camera icon for video calls and use the outcome to style failed calls.
    final icon = message.isVideoCall
        ? Icons.videocam
        : (failed ? Icons.phone_missed : Icons.call);
    final date = DateTime.fromMillisecondsSinceEpoch(message.createdAt);
    /// Use the saved duration to display how long an answered call lasted.
    final duration = message.durationSeconds ?? 0;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        key: ValueKey(message.callId),
        constraints: const BoxConstraints(maxWidth: 290),
        margin: const EdgeInsets.symmetric(vertical: 7),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: mine ? const Color(0xFFD4E8FF) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: .25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.callLabel(userId),
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${message.callerName ?? 'Contact'} → ${message.calleeName ?? 'Contact'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    '${shortDate(date)} · ${TimeOfDay.fromDateTime(date).format(context)}'
                    '${message.endedAt != null && message.acceptedAt != null ? ' · ${duration ~/ 60}m ${duration % 60}s' : ''}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
