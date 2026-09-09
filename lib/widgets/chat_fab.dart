import 'dart:async';

import 'package:flutter/material.dart';

import '../models/chat_room.dart';
import '../models/user_model.dart';
import '../screens/home/chat_list_page.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

class ChatFab extends StatefulWidget {
  const ChatFab({
    super.key,
    required this.user,
    required this.maxWidth,
    required this.maxHeight,
  });

  final UserModel user;
  final double maxWidth;
  final double maxHeight;

  @override
  State<ChatFab> createState() => _ChatFabState();
}

class _ChatFabState extends State<ChatFab> {
  static const _fabSize = 56.0;
  static const _sideMargin = 16.0;

  final _firestore = FirestoreService();
  int _totalUnread = 0;
  StreamSubscription<List<ChatRoom>>? _sub;
  double _left = _sideMargin;
  double? _top;

  double get _initialTop => widget.maxHeight - _fabSize - 80;

  @override
  void initState() {
    super.initState();
    _sub = _firestore.streamChatRooms(widget.user.uid).listen((rooms) {
      if (!mounted) return;
      var total = 0;
      for (final room in rooms) {
        total += room.unreadCount[widget.user.uid] ?? 0;
      }
      setState(() => _totalUnread = total);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final left = _left + details.delta.dx;
    final top = (_top ?? _initialTop) + details.delta.dy;
    setState(() {
      _left = left.clamp(0.0, widget.maxWidth - _fabSize);
      _top = top.clamp(0.0, widget.maxHeight - _fabSize);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    final top = _top ?? _initialTop;
    final snapLeft = _left + _fabSize / 2 < widget.maxWidth / 2
        ? _sideMargin
        : widget.maxWidth - _fabSize - _sideMargin;
    final snapTop = top.clamp(0.0, widget.maxHeight - _fabSize);
    setState(() {
      _left = snapLeft;
      _top = snapTop;
    });
  }

  void _open() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatListPage(me: widget.user),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _left,
      top: _top ?? _initialTop,
      child: GestureDetector(
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            FloatingActionButton(
              backgroundColor: AppTheme.primaryBlue,
              onPressed: _open,
              child: const Icon(
                Icons.chat_bubble,
                color: Colors.white,
                size: 28,
              ),
            ),
            if (_totalUnread > 0)
              Positioned(
                top: -6,
                right: -6,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(
                    color: Color(0xFFE85B61),
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 20,
                    minHeight: 20,
                  ),
                  child: Text(
                    _totalUnread > 99 ? '99+' : '$_totalUnread',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}