import 'package:flutter/material.dart';
import '../models/chat_message.dart';

/// Anchors the latest message at offset zero rather than an estimated, lazily
/// laid out maxScrollExtent. Images, large text and keyboard changes therefore
/// cannot leave the initial viewport partway through the history.
class ChatMessageList extends StatefulWidget {
  const ChatMessageList({
    super.key,
    required this.messages,
    required this.controller,
    required this.itemBuilder,
    this.onAtLatest,
  });

  /// Messages arrive in ascending chronological order from Firestore.
  final List<ChatMessage> messages;
  final ScrollController controller;
  final IndexedWidgetBuilder itemBuilder;
  final VoidCallback? onAtLatest;

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  bool _scrollScheduled = false;

  @override
  void initState() {
    super.initState();
    _showLatest();
  }

  @override
  void didUpdateWidget(ChatMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.messages;
    final current = widget.messages;
    if (identical(previous, current)) return;
    final previousIds = previous.map((m) => m.id).toSet();
    // Older history inserted before the first visible record is not a new
    // arrival. Metadata/read receipts and call-status updates also retain the
    // user's position while they read earlier messages.
    final newArrival = current.any(
      (m) =>
          !previousIds.contains(m.id) &&
          (previous.isEmpty || m.createdAt >= previous.first.createdAt),
    );
    if (newArrival) _showLatest();
  }

  void _showLatest() {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !widget.controller.hasClients) return;
      widget.controller.jumpTo(widget.controller.position.minScrollExtent);
      widget.onAtLatest?.call();
    });
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
    controller: widget.controller,
    reverse: true,
    padding: const EdgeInsets.all(12),
    itemCount: widget.messages.length,
    findChildIndexCallback: (key) {
      if (key is! ValueKey<String>) return null;
      final index = widget.messages.indexWhere((m) => m.id == key.value);
      return index == -1 ? null : widget.messages.length - 1 - index;
    },
    itemBuilder: (context, reversedIndex) {
      final index = widget.messages.length - 1 - reversedIndex;
      return KeyedSubtree(
        key: ValueKey(widget.messages[index].id),
        child: widget.itemBuilder(context, index),
      );
    },
  );
}
