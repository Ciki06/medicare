import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import '../../models/user_model.dart';
import '../../models/user_role.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';

class ChatRoomPage extends StatefulWidget {
  const ChatRoomPage({
    super.key,
    required this.me,
    required this.other,
    required this.roomId,
  });

  final UserModel me;
  final UserModel other;
  final String roomId;

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final _firestore = FirestoreService();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  bool _initialScrollDone = false;

  @override
  void initState() {
    super.initState();
    _firestore.markChatRead(widget.roomId, widget.me.uid).catchError((_) {});
    _firestore.streamMessages(widget.roomId).listen((messages) {
      if (!mounted) return;
      if (messages.any((m) => m.senderId != widget.me.uid)) {
        _firestore.markChatRead(widget.roomId, widget.me.uid).catchError((_) {});
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _firestore.sendMessage(
        chatId: widget.roomId,
        senderId: widget.me.uid,
        senderName: widget.me.name,
        text: text,
      );
      await _firestore.incrementUnread(widget.roomId, widget.other.uid);
      _controller.clear();
      _scrollToBottom(animate: true, force: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom({bool animate = false, bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (!force &&
          position.maxScrollExtent - position.pixels > 120) {
        return;
      }
      if (animate) {
        _scrollController.animateTo(
          position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final other = widget.other;
    return Scaffold(
      backgroundColor: AppTheme.paleBlue,
      appBar: AppBar(
        backgroundColor: AppTheme.navy,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: other.role.color.withValues(alpha: .3),
              child: Icon(
                _roleIcon(other.role),
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  other.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                Text(
                  other.role.label,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _firestore.streamMessages(widget.roomId),
              builder: (context, snap) {
                final messages = snap.data ?? [];
                final initialLoad =
                    !_initialScrollDone && messages.isNotEmpty;
                if (initialLoad) _initialScrollDone = true;
                _scrollToBottom(force: initialLoad);
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'No messages yet.\nSay hello!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.muted),
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) => _MessageBubble(
                    message: messages[index],
                    isMine: messages[index].senderId == widget.me.uid,
                  ),
                );
              },
            ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                hintText: 'Type a message...',
                filled: true,
                fillColor: Color(0xFFF2F2F2),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(22)),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _sending ? null : _send,
            icon: const Icon(Icons.send, color: Colors.white),
            style: IconButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
          ),
        ],
      ),
    );
  }

  IconData _roleIcon(UserRole role) => switch (role) {
        UserRole.patient => Icons.person,
        UserRole.caregiver => Icons.health_and_safety,
        UserRole.family => Icons.people,
        UserRole.pharmacist => Icons.medical_services,
      };
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMine});

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final t = DateTime.fromMillisecondsSinceEpoch(message.createdAt).toLocal();
    final timeText =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isMine ? AppTheme.primaryBlue : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isMine ? 14 : 2),
            bottomRight: Radius.circular(isMine ? 2 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMine)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  message.senderName,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.muted,
                  ),
                ),
              ),
            Text(
              message.text,
              style: TextStyle(
                fontSize: 14,
                color: isMine ? Colors.white : AppTheme.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              timeText,
              style: TextStyle(
                fontSize: 9,
                color: isMine ? Colors.white70 : AppTheme.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
