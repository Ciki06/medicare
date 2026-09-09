import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../models/user_role.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import 'chat_room_page.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key, required this.me});

  final UserModel me;

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  final _firestore = FirestoreService();
  List<UserModel> _contacts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final contacts = await _firestore.getChatContacts(widget.me.uid);
      if (!mounted) return;
      setState(() {
        _contacts = contacts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _openChat(UserModel other) async {
    String roomId;
    try {
      roomId = await _firestore.findOrCreateChatRoom(
        widget.me.uid,
        other.uid,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open chat: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatRoomPage(
          me: widget.me,
          other: other,
          roomId: roomId,
        ),
      ),
    );
    _loadContacts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.paleBlue,
      appBar: AppBar(
        backgroundColor: AppTheme.navy,
        foregroundColor: Colors.white,
        title: const Text('Chat'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Text(
              'Select someone to chat with',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.muted,
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Color(0xFFE85B61),
                                size: 40,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Could not load contacts: $_error',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppTheme.muted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: _loadContacts,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _contacts.isEmpty
                        ? const Center(
                            child: Text(
                              'No linked accounts to chat with.',
                              style: TextStyle(color: AppTheme.muted),
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                            children: _contacts
                                .map(
                                  (c) => _ContactTile(
                                    contact: c,
                                    onTap: () => _openChat(c),
                                  ),
                                )
                                .toList(),
                          ),
          ),
        ],
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.contact, required this.onTap});

  final UserModel contact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFBFC2C5)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: contact.role.color.withValues(alpha: .15),
              child: Icon(
                _roleIcon(contact.role),
                color: contact.role.color,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    contact.role.label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.muted),
          ],
        ),
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
