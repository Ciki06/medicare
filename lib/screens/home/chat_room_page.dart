import '../../widgets/chat_message_layout.dart';
import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/chat_message.dart';
import '../../models/user_model.dart';
import '../../models/user_role.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../services/voice_call_service.dart';
import '../../services/offline_service.dart';
import '../../services/history_filter.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/offline_image.dart';
import '../../theme/app_theme.dart';

class ChatRoomPage extends StatefulWidget {
  const ChatRoomPage({
    super.key,
    required this.me,
    required this.other,
    required this.roomId,
  });
  final UserModel me, other;
  final String roomId;
  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage>
    with WidgetsBindingObserver {
  final _firestore = FirestoreService();
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  final _subscriptions = <StreamSubscription>[];
  List<ChatMessage> _messages = [];
  Map<String, dynamic> _presence = {};
  bool _sending = false,
      _recording = false,
      _loaded = false,
      _foreground = true;
  Uint8List? _attachment;
  bool _voice = false;
  String? _playing, _error;
  Timer? _typingTimer, _clock, _recordLimit;
  int _lastTyping = 0, _lastRead = 0;
  final _recordWatch = Stopwatch();
  int? _voiceDuration;
  final Map<String, int> _durations = {};
  final Map<String, Future<int?>> _durationReads = {};
  bool _forwarding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_markRead);
    _subscriptions.add(
      _firestore
          .streamMessages(widget.roomId)
          .listen(
            (messages) {
              if (!mounted) return;
              final atBottom =
                  !_scroll.hasClients || _scroll.position.extentAfter < 80;
              setState(() {
                _messages = messages;
                _loaded = true;
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                if (atBottom && _scroll.hasClients) {
                  _scroll.jumpTo(_scroll.position.maxScrollExtent);
                }
                _markRead();
              });
            },
            onError: (Object e) {
              if (mounted) setState(() => _error = 'Chat could not load: $e');
            },
          ),
    );
    _subscriptions.add(
      _firestore.chatPresence(widget.roomId).listen((p) {
        if (mounted) setState(() => _presence = p);
      }, onError: (_) {}),
    );
    _subscriptions.add(
      _player.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _playing = null);
      }),
    );
    _subscriptions.add(
      _player.onDurationChanged.listen((duration) {
        final id = _playing;
        if (mounted && id != null) {
          setState(
            () => _durations[id] = (duration.inMilliseconds / 1000).ceil(),
          );
        }
      }),
    );
    _clock = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        setState(() {});
        _markRead();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _firestore
          .setTyping(widget.roomId, widget.me.uid, false)
          .catchError((_) {});
      _player.stop();
      _playing = null;
      if (_recording) _stopRecording();
    } else {
      _markRead();
    }
  }

  void _markRead() {
    if (!_foreground ||
        !mounted ||
        !(ModalRoute.of(context)?.isCurrent ?? false) ||
        !_scroll.hasClients ||
        _scroll.position.extentAfter > 30 ||
        _messages.isEmpty) {
      return;
    }
    final incoming = _messages.where(
      (m) => m.senderId != widget.me.uid && !m.pending,
    );
    if (incoming.isEmpty) return;
    final through = incoming.last.createdAt;
    if (through <= _lastRead) return;
    _lastRead = through;
    _firestore
        .markChatRead(widget.roomId, widget.me.uid, through: through)
        .catchError((_) {
          _lastRead = 0;
        });
  }

  void _typing(String text) {
    _typingTimer?.cancel();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastTyping > 2000 || text.isEmpty) {
      _lastTyping = now;
      _firestore
          .setTyping(widget.roomId, widget.me.uid, text.isNotEmpty)
          .catchError((_) {});
    }
    _typingTimer = Timer(
      const Duration(seconds: 4),
      () => _firestore
          .setTyping(widget.roomId, widget.me.uid, false)
          .catchError((_) {}),
    );
  }

  void _notice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _call() async {
    if (_recording) {
      _notice('Finish your voice message before calling.');
      return;
    }
    await _player.stop();
    await VoiceCallService.instance.start(widget.roomId);
  }

  Future<void> _pickImage() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2048,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        _notice('Choose an image under 10 MB.');
        return;
      }
      if (mounted) {
        setState(() {
          _attachment = bytes;
          _voice = false;
        });
      }
    } catch (_) {
      _notice('Photo access failed. Check the app permissions.');
    }
  }

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        _notice('Microphone permission is required for voice messages.');
        return;
      }
      final path = kIsWeb
          ? ''
          : '${(await getTemporaryDirectory()).path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      if (!mounted) {
        await _recorder.cancel();
        return;
      }
      setState(() => _recording = true);
      _recordWatch
        ..reset()
        ..start();
      _recordLimit = Timer(const Duration(seconds: 60), _stopRecording);
    } catch (e) {
      _notice('Recording could not start: $e');
    }
  }

  Future<void> _stopRecording() async {
    _recordLimit?.cancel();
    if (!_recording) return;
    setState(() => _recording = false);
    _recordWatch.stop();
    _voiceDuration = (_recordWatch.elapsedMilliseconds / 1000).ceil().clamp(
      1,
      61,
    );
    try {
      final path = await _recorder.stop();
      if (path == null) return;
      final bytes = await XFile(path).readAsBytes();
      if (mounted) {
        setState(() {
          _attachment = bytes;
          _voice = true;
        });
      }
    } catch (e) {
      _notice('Could not save voice message: $e');
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (_sending || _recording || (text.isEmpty && _attachment == null)) return;
    setState(() => _sending = true);
    try {
      String? url;
      final bytes = _attachment;
      if (bytes != null) {
        if (OfflineService.offline.value) {
          throw Exception(
            'Reconnect to upload the attachment. Your draft is still here.',
          );
        }
        final imageType = bytes.length > 4 && bytes[0] == 137 && bytes[1] == 80
            ? 'image/png'
            : 'image/jpeg';
        url = await StorageService().uploadChatMedia(
          widget.roomId,
          widget.me.uid,
          bytes,
          voice: _voice,
          imageType: imageType,
        );
      }
      await _firestore.sendMessage(
        chatId: widget.roomId,
        senderId: widget.me.uid,
        senderName: widget.me.name,
        recipientId: widget.other.uid,
        text: text,
        type: bytes == null
            ? 'text'
            : _voice
            ? 'voice'
            : 'image',
        mediaUrl: url,
        caption: bytes != null && !_voice ? text : null,
        durationSeconds: bytes != null && _voice ? _voiceDuration : null,
      );
      _controller.clear();
      _typing('');
      if (mounted) setState(() => _attachment = null);
    } catch (e) {
      _notice('Message could not send: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _play(ChatMessage m) async {
    try {
      if (_playing == m.id) {
        await _player.stop();
        if (mounted) setState(() => _playing = null);
        return;
      }
      await _player.stop();
      if (mounted) setState(() => _playing = m.id);
      await _player.play(UrlSource(m.mediaUrl!));
      if (mounted) setState(() => _playing = m.id);
    } catch (_) {
      if (mounted) setState(() => _playing = null);
      _notice('Voice message unavailable. Check your connection.');
    }
  }

  Future<void> _openLocation(ChatMessage message) async {
    final uri = message.locationUri;
    if (uri == null) {
      _notice(
        'This message has no available location yet. Ask the sender to share their location again.',
      );
      return;
    }
    for (final mode in [
      LaunchMode.externalApplication,
      LaunchMode.platformDefault,
    ]) {
      try {
        if (await launchUrl(uri, mode: mode)) return;
      } catch (_) {
        // Try the browser fallback when no external map app can handle the link.
      }
    }
    _notice(
      'Could not open the location. Check that a browser or maps app is installed.',
    );
  }

  Future<void> _forward(ChatMessage message) async {
    if (_forwarding || message.pending) return;
    setState(() => _forwarding = true);
    try {
      final contacts = {
        for (final user in await _firestore.getChatContacts(widget.me.uid))
          user.uid: user,
      };
      final rooms = await _firestore.streamChatRooms(widget.me.uid).first;
      for (final room in rooms) {
        for (final uid in room.participants) {
          if (uid == widget.me.uid || contacts.containsKey(uid)) continue;
          final user = await _firestore.getUserById(uid);
          if (user != null) contacts[uid] = user;
        }
      }
      contacts.remove(widget.me.uid);
      if (!mounted) return;
      final recipient = await showModalBottomSheet<UserModel>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('Forward to another chat')),
              if (contacts.isEmpty)
                const ListTile(title: Text('No available chats')),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: contacts.values
                      .map(
                        (user) => ListTile(
                          leading: const Icon(Icons.person_outline),
                          title: Text(user.name),
                          subtitle: Text(user.role.label),
                          trailing: const Icon(Icons.shortcut_rounded),
                          onTap: () => Navigator.pop(context, user),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      );
      if (recipient == null) return;
      final destination = await _firestore.findOrCreateChatRoom(
        widget.me.uid,
        recipient.uid,
      );
      String? url;
      final attachment = ['image', 'voice'].contains(message.type);
      if (attachment && message.mediaUrl != null) {
        url = await StorageService().copyChatMedia(
          message.mediaUrl!,
          destination,
          widget.me.uid,
          voice: message.type == 'voice',
        );
      }
      final text = message.type == 'sos_location'
          ? '${message.text}${message.mapUrl == null ? '' : '\n${message.mapUrl}'}'
          : message.type == 'image'
          ? message.displayText
          : message.text;
      await _firestore.sendMessage(
        chatId: destination,
        senderId: widget.me.uid,
        senderName: widget.me.name,
        recipientId: recipient.uid,
        text: text,
        type: attachment ? message.type : 'text',
        mediaUrl: url,
        caption: message.type == 'image' ? message.displayText : null,
        durationSeconds: message.durationSeconds ?? _durations[message.id],
        forwarded: true,
      );
      _notice('Forwarded to ${recipient.name}.');
    } catch (_) {
      _notice(
        'Could not forward the message. Check your connection and chat access.',
      );
    } finally {
      if (mounted) setState(() => _forwarding = false);
    }
  }

  Future<int?> _readVoiceDuration(String url) async {
    final reader = AudioPlayer();
    try {
      await reader.setSourceUrl(url).timeout(const Duration(seconds: 10));
      final duration = await reader.getDuration();
      return duration == null ? null : (duration.inMilliseconds / 1000).ceil();
    } catch (_) {
      return null;
    } finally {
      await reader.dispose();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _typingTimer?.cancel();
    _clock?.cancel();
    _recordLimit?.cancel();
    _firestore
        .setTyping(widget.roomId, widget.me.uid, false)
        .catchError((_) {});
    for (final s in _subscriptions) {
      s.cancel();
    }
    _recorder.dispose();
    _player.dispose();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final otherPresence =
        _presence[widget.other.uid] as Map<String, dynamic>? ?? {};
    final age =
        DateTime.now().millisecondsSinceEpoch -
        ((otherPresence['typingAt'] as num?)?.toInt() ?? 0);
    final typing = age >= 0 && age < 6000;
    final readThrough = (otherPresence['readThrough'] as num?)?.toInt() ?? 0;
    return Scaffold(
      backgroundColor: AppTheme.paleBlue,
      appBar: AppBar(
        backgroundColor: AppTheme.navy,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.other.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17),
            ),
            Text(
              typing ? 'Typing…' : widget.other.role.label,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Call',
            onPressed: _call,
            icon: const Icon(Icons.call),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const OfflineBanner(),
            Expanded(
              child: _error != null
                  ? Center(child: Text(_error!))
                  : !_loaded
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                  ? const Center(child: Text('No messages yet. Say hello!'))
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: _messages.length,
                      itemBuilder: (context, i) {
                        final m = _messages[i];
                        final mine = m.senderId == widget.me.uid;
                        final date = DateTime.fromMillisecondsSinceEpoch(
                          m.createdAt,
                        );
                        final separator =
                            i == 0 ||
                            shortDate(date) !=
                                shortDate(
                                  DateTime.fromMillisecondsSinceEpoch(
                                    _messages[i - 1].createdAt,
                                  ),
                                );
                        return Column(
                          children: [
                            if (separator)
                              Padding(
                                padding: const EdgeInsets.all(10),
                                child: Text(shortDate(date)),
                              ),
                            ChatMessageLayout(
                              mine: mine,
                              onForward: m.pending || _forwarding
                                  ? null
                                  : () => _forward(m),
                              bubble: Container(
                                constraints: const BoxConstraints(
                                  maxWidth: 290,
                                ),
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                decoration: BoxDecoration(
                                  color: mine
                                      ? const Color(0xFFD4E8FF)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (m.forwarded)
                                      const Text(
                                        'Forwarded',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.muted,
                                        ),
                                      ),
                                    if (m.type == 'image' && m.mediaUrl != null)
                                      InkWell(
                                        onTap: () => showImageViewer(
                                          context,
                                          m.mediaUrl!,
                                        ),
                                        child: OfflineImage(
                                          m.mediaUrl!,
                                          width: 240,
                                          height: 180,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    if (m.type == 'voice' && m.mediaUrl != null)
                                      TextButton.icon(
                                        onPressed: () => _play(m),
                                        icon: Icon(
                                          _playing == m.id
                                              ? Icons.stop
                                              : Icons.play_arrow,
                                        ),
                                        label: m.durationSeconds != null
                                            ? Text('${m.durationSeconds} s')
                                            : FutureBuilder<int?>(
                                                future: _durationReads
                                                    .putIfAbsent(
                                                      m.id,
                                                      () => _readVoiceDuration(
                                                        m.mediaUrl!,
                                                      ),
                                                    ),
                                                builder: (_, snapshot) => Text(
                                                  '${_durations[m.id] ?? snapshot.data ?? '—'} s',
                                                ),
                                              ),
                                      ),
                                    if (m.displayText.isNotEmpty)
                                      SelectableText(
                                        m.type == 'sos_location'
                                            ? m.text.replaceAll(
                                                RegExp(
                                                  r'https://maps\.google\.com/\?q=[\d.,-]+',
                                                ),
                                                'Location shared — open map',
                                              )
                                            : m.displayText,
                                      ),
                                    if (m.type == 'sos_location')
                                      TextButton.icon(
                                        icon: const Icon(Icons.location_on),
                                        label: const Text('Open location'),
                                        onPressed: () => _openLocation(m),
                                      ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          TimeOfDay.fromDateTime(
                                            date,
                                          ).format(context),
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: AppTheme.muted,
                                          ),
                                        ),
                                        if (mine)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              left: 6,
                                            ),
                                            child: Tooltip(
                                              message: m.pending
                                                  ? 'Pending'
                                                  : m.createdAt <= readThrough
                                                  ? 'Seen'
                                                  : 'Sent',
                                              child: Icon(
                                                m.pending
                                                    ? Icons.schedule
                                                    : m.createdAt <= readThrough
                                                    ? Icons.done_all
                                                    : Icons.done,
                                                size: 16,
                                                color:
                                                    !m.pending &&
                                                        m.createdAt <=
                                                            readThrough
                                                    ? AppTheme.navy
                                                    : Colors.grey,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
            if (_attachment != null)
              ListTile(
                leading: _voice
                    ? const Icon(Icons.mic)
                    : Image.memory(
                        _attachment!,
                        width: 42,
                        height: 42,
                        fit: BoxFit.cover,
                      ),
                title: Text(
                  _voice
                      ? 'Voice message ready to send'
                      : 'Image ready to send',
                ),
                trailing: IconButton(
                  tooltip: 'Remove attachment',
                  onPressed: _sending
                      ? null
                      : () => setState(() => _attachment = null),
                  icon: const Icon(Icons.close),
                ),
              ),
            if (_recording)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'Recording… Tap stop when finished (maximum 60 seconds).',
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Send image',
                    onPressed: _sending || _recording ? null : _pickImage,
                    icon: const Icon(Icons.image),
                  ),
                  IconButton(
                    tooltip: _recording
                        ? 'Stop recording'
                        : 'Record voice message',
                    onPressed: _sending
                        ? null
                        : _recording
                        ? _stopRecording
                        : _startRecording,
                    icon: Icon(
                      _recording ? Icons.stop_circle : Icons.mic,
                      color: _recording ? Colors.red : null,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_sending,
                      maxLength: 1000,
                      minLines: 1,
                      maxLines: 4,
                      onChanged: _typing,
                      decoration: const InputDecoration(
                        hintText: 'Message…',
                        counterText: '',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Send',
                    onPressed: _sending || _recording ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(),
                          )
                        : const Icon(Icons.send),
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
