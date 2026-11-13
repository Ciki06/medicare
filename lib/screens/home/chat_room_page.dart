import '../../widgets/chat_message_layout.dart';
import '../../widgets/chat_call_event.dart';
import '../../widgets/chat_message_list.dart';
import '../../widgets/sos_location_message.dart';
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
import '../../widgets/profile_picture.dart';
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
  static const _maxPhotos = 10;
  final _firestore = FirestoreService();
  late final _otherProfile = _firestore.watchUserById(widget.other.uid);
  final _controller = TextEditingController();
  final _scroll = ScrollController(keepScrollOffset: false);
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  final _subscriptions = <StreamSubscription>[];
  List<ChatMessage> _messages = [];
  Map<String, dynamic> _presence = {};
  bool _sending = false,
      _recording = false,
      _loaded = false,
      _foreground = true;
  final _attachments = <Uint8List>[];
  final _uploadedPhotos = Expando<String>();
  bool _pickingPhotos = false;
  bool _voiceBusy = false;
  bool get _composerBusy => _sending || _pickingPhotos || _voiceBusy;
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
    unawaited(
      VoiceCallService.instance.syncHistory(widget.roomId).catchError((
        Object error,
      ) {
        debugPrint('Previous call history could not sync: $error');
      }),
    );
    _scroll.addListener(_markRead);
    _subscriptions.add(
      _firestore
          .streamMessages(widget.roomId)
          .listen(
            (messages) {
              if (!mounted) return;
              setState(() {
                _messages = messages;
                _loaded = true;
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
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
        _scroll.position.extentBefore > 30 ||
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
    await _startCall(video: false);
  }

  Future<void> _videoCall() async {
    await _startCall(video: true);
  }

  Future<void> _startCall({required bool video}) async {
    if (_recording) {
      _notice('Finish your voice message before calling.');
      return;
    }
    await _player.stop();
    await VoiceCallService.instance.start(widget.roomId, video: video);
  }

  Future<void> _pickPhotos() async {
    if (_composerBusy || _recording) return;
    final remaining = _maxPhotos - (_voice ? 0 : _attachments.length);
    if (remaining == 0) {
      _notice('You can attach up to $_maxPhotos photos.');
      return;
    }
    setState(() => _pickingPhotos = true);
    try {
      final files = await ImagePicker().pickMultiImage(
        imageQuality: 85,
        maxWidth: 2048,
        limit: remaining,
      );
      if (files.isEmpty || !mounted) return;
      final photos = <Uint8List>[];
      var oversized = false;
      for (final file in files.take(remaining)) {
        if (await file.length() > 10 * 1024 * 1024) {
          oversized = true;
        } else {
          photos.add(await file.readAsBytes());
        }
        if (!mounted) return;
      }
      if (photos.isNotEmpty) {
        setState(() {
          if (_voice) _attachments.clear();
          _voice = false;
          _attachments.addAll(photos);
        });
      }
      if (oversized) _notice('Each photo must be 10 MB or smaller.');
      if (files.length > remaining) {
        _notice('You can attach up to $_maxPhotos photos.');
      }
    } catch (_) {
      _notice('Photo access failed. Check the app permissions.');
    } finally {
      if (mounted) setState(() => _pickingPhotos = false);
    }
  }

  Future<void> _startRecording() async {
    if (_composerBusy || _recording) return;
    setState(() => _voiceBusy = true);
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
    } finally {
      if (mounted) setState(() => _voiceBusy = false);
    }
  }

  Future<void> _stopRecording() async {
    _recordLimit?.cancel();
    if (!_recording) return;
    setState(() {
      _recording = false;
      _voiceBusy = true;
    });
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
          _attachments
            ..clear()
            ..add(bytes);
          _voice = true;
        });
      }
    } catch (e) {
      _notice('Could not save voice message: $e');
    } finally {
      if (mounted) setState(() => _voiceBusy = false);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (_composerBusy || _recording || (text.isEmpty && _attachments.isEmpty)) {
      return;
    }
    setState(() => _sending = true);
    try {
      if (_attachments.isNotEmpty && !_voice) {
        await _sendPhotos(text);
      } else {
        await _sendDraftMessage(text, _attachments.firstOrNull);
      }
      if (!mounted) return;
      _controller.clear();
      _typing('');
      setState(_attachments.clear);
    } catch (e) {
      _notice('Message could not send: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendPhotos(String caption) async {
    final urls = await Future.wait(
      _attachments.map((bytes) async {
        final uploaded = _uploadedPhotos[bytes];
        if (uploaded != null) return uploaded;
        final url = await _uploadAttachment(bytes, voice: false);
        _uploadedPhotos[bytes] = url;
        return url;
      }),
    );
    await _firestore.sendChatPhotos(
      chatId: widget.roomId,
      senderId: widget.me.uid,
      senderName: widget.me.name,
      recipientId: widget.other.uid,
      photoUrls: urls,
      caption: caption,
    );
  }

  Future<String> _uploadAttachment(Uint8List bytes, {required bool voice}) {
    if (OfflineService.offline.value) {
      throw Exception(
        'Reconnect to upload the attachment. Your draft is still here.',
      );
    }
    final imageType = bytes.length > 4 && bytes[0] == 137 && bytes[1] == 80
        ? 'image/png'
        : 'image/jpeg';
    return StorageService().uploadChatMedia(
      widget.roomId,
      widget.me.uid,
      bytes,
      voice: voice,
      imageType: imageType,
    );
  }

  Future<void> _sendDraftMessage(String text, Uint8List? bytes) async {
    final url = bytes == null
        ? null
        : await _uploadAttachment(bytes, voice: true);
    await _firestore.sendMessage(
      chatId: widget.roomId,
      senderId: widget.me.uid,
      senderName: widget.me.name,
      recipientId: widget.other.uid,
      text: text,
      type: bytes == null ? 'text' : 'voice',
      mediaUrl: url,
      durationSeconds: bytes != null ? _voiceDuration : null,
    );
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
    final targets = message.locationTargets(
      android: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
      ios: !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS,
    );
    if (targets.isEmpty) {
      _notice(
        'This message has no available location yet. Ask the sender to share their location again.',
      );
      return;
    }
    for (final uri in targets) {
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
                          leading: ProfilePicture(
                            user: user,
                            size: 36,
                            backgroundColor: user.role.color.withValues(
                              alpha: .15,
                            ),
                            iconColor: user.role.color,
                            fallbackIcon: _roleIcon(user.role),
                          ),
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
          ? '${message.text}${message.locationUri == null ? '' : '\n${message.locationUri}'}'
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
        title: Row(
          children: [
            ProfilePicture(
              user: widget.other,
              size: 32,
              iconSize: 20,
              profileStream: _otherProfile,
              backgroundColor: Colors.white,
              iconColor: widget.other.role.color,
              fallbackIcon: _roleIcon(widget.other.role),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.other.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17),
                  ),
                  Text(
                    typing ? 'Typing…' : widget.other.role.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Call',
            onPressed: _call,
            icon: const Icon(Icons.call),
          ),
          IconButton(
            key: const Key('chat-video-call'),
            tooltip: 'Video call',
            onPressed: _videoCall,
            icon: const Icon(Icons.videocam),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            OfflineBanner(
              patientUid: widget.me.role == UserRole.patient
                  ? widget.me.uid
                  : null,
            ),
            Expanded(
              child: _error != null
                  ? Center(child: Text(_error!))
                  : !_loaded
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                  ? const Center(child: Text('No messages yet. Say hello!'))
                  : ChatMessageList(
                      messages: _messages,
                      controller: _scroll,
                      onAtLatest: _markRead,
                      itemBuilder: (context, i) {
                        final m = _messages[i];
                        if (m.type == 'call') {
                          return ChatCallEvent(
                            message: m,
                            userId: widget.me.uid,
                          );
                        }
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
                                      if (m.type == 'sos_location')
                                        SosLocationMessage(message: m)
                                      else
                                        SelectableText(m.displayText),
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
            if (_attachments.isNotEmpty && _voice)
              ListTile(
                leading: const Icon(Icons.mic),
                title: const Text('Voice message ready to send'),
                trailing: IconButton(
                  tooltip: 'Remove attachment',
                  onPressed: _composerBusy
                      ? null
                      : () => setState(_attachments.clear),
                  icon: const Icon(Icons.close),
                ),
              ),
            if (_attachments.isNotEmpty && !_voice)
              SizedBox(
                height: 76,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  scrollDirection: Axis.horizontal,
                  itemCount: _attachments.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) => Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          _attachments[index],
                          width: 76,
                          height: 76,
                          cacheWidth: 228,
                          fit: BoxFit.cover,
                        ),
                      ),
                      PositionedDirectional(
                        top: 0,
                        end: 0,
                        child: IconButton(
                          tooltip: 'Remove photo ${index + 1}',
                          onPressed: _composerBusy
                              ? null
                              : () => setState(
                                  () => _attachments.removeAt(index),
                                ),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black54,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.close, size: 16),
                        ),
                      ),
                    ],
                  ),
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
                    tooltip: 'Add photos',
                    onPressed: _composerBusy || _recording ? null : _pickPhotos,
                    icon: const Icon(Icons.image),
                  ),
                  IconButton(
                    tooltip: _recording
                        ? 'Stop recording'
                        : 'Record voice message',
                    onPressed: _composerBusy
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
                    onPressed: _composerBusy || _recording ? null : _send,
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

  IconData _roleIcon(UserRole role) => switch (role) {
    UserRole.patient => Icons.person,
    UserRole.caregiver => Icons.health_and_safety,
    UserRole.family => Icons.people,
    UserRole.pharmacist => Icons.medical_services,
  };
}
