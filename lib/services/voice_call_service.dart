import 'dart:async';
import 'package:audioplayers/audioplayers.dart' hide Source;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' hide AndroidAudioMode;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'notification_service.dart';
import 'call_tone_controller.dart';
import 'call_video_media.dart';
import 'frame_safe_notifier.dart';
import 'call_audio_route.dart';
import 'incoming_call_bridge.dart';
import 'incoming_call_controller.dart';

/// One live call per signed-in device. Firestore carries signaling only;
/// WebRTC transports encrypted audio/video through the existing peer connection.
class VoiceCallService extends FrameSafeNotifier<int>
    with WidgetsBindingObserver {
  VoiceCallService._() : super(0);
  static final instance = VoiceCallService._();
  final _db = FirebaseFirestore.instance;
  final _api = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
  final _ringer = AudioPlayer();
  final _ringback = AudioPlayer();
  late final _audioRoute = CallAudioRoute(
    apply: Helper.setSpeakerphoneOn,
    onChanged: _changed,
  );
  final _initialSession = Completer<void>();
  Future<void> _authEvents = Future.value();
  int _authEpoch = 0, _releasesInFlight = 0;
  bool _authReconciling = true;
  String? _pendingNativeAccept;
  late final _incomingActions = IncomingCallController(
    currentUserId: () async {
      if (!await _waitForState(() => !_authReconciling)) return null;
      return uid == FirebaseAuth.instance.currentUser?.uid ? uid : null;
    },
    loadCall: (callId) async =>
        (await _db
                .collection('calls')
                .doc(callId)
                .get(const GetOptions(source: Source.server))
                .timeout(const Duration(seconds: 8)))
            .data(),
    activeCallId: () => id,
    waitUntilReady: _waitUntilNativeReady,
    present: (callId, record) async {
      if (!await _presentIncoming(callId, record)) {
        throw StateError('The incoming call is no longer available.');
      }
    },
    accept: (callId) async {
      if (id == callId) await accept();
    },
    dismiss: (callId) =>
        NotificationService.instance.cancelIncomingCall(callId),
    onError: (error) => debugPrint('Incoming call action failed: $error'),
  );
  late final _tones = CallToneController(
    play: _playTone,
    stop: () async {
      // Always stop both players, even if one audio route has already failed.
      await Future.wait([_ringer.stop(), _ringback.stop()]);
    },
    onError: (error) => debugPrint('Call tone failed: $error'),
  );
  bool _observing = false, _foreground = true;
  static const _native = MethodChannel('medicare/voice_call');
  StreamSubscription? _auth, _incoming, _call, _ice;
  RTCPeerConnection? _peer;
  MediaStream? _media;
  MediaStream? _camera, _remoteVideo, _remoteVideoWrapper;
  RTCRtpSender? _videoSender;
  RTCVideoRenderer? localRenderer, remoteRenderer;
  Future<void> _videoEvents = Future.value();
  Future<bool>? _videoRegistration;
  bool _videoRegistrationAttempted = false;
  bool _startWithVideo = false;
  final Map<String, bool> _videoCapabilities = {};
  int _mediaRevision = -1;
  bool videoMode = false, cameraEnabled = false, remoteCameraEnabled = false;
  bool videoBusy = false, frontCamera = true;
  bool _cameraRequested = false;
  String? mediaError;
  bool get videoAvailable =>
      connectedAt != null &&
      _videoSender != null &&
      _videoCapabilities[uid] == true &&
      _videoCapabilities[_otherUid] == true;
  String? get _otherUid => data?[incoming ? 'callerId' : 'calleeId'] as String?;
  final List<RTCIceCandidate> _remoteCandidates = [];
  bool _remoteReady = false, _answering = false, _ending = false;
  int _generation = 0;
  Future<void> _events = Future.value();
  Timer? _clock, _heartbeat, _connectTimeout;
  String? id, uid, error;
  Map<String, dynamic>? data;
  String status = '';
  bool busy = false, muted = false;
  bool get speaker => _audioRoute.speaker;
  DateTime? connectedAt;
  bool get incoming => data?['calleeId'] == uid;
  bool get ringing => data?['state'] == 'ringing' && connectedAt == null;
  bool get visible => id != null || busy || error != null;
  String get name =>
      (data?[incoming ? 'callerName' : 'calleeName'] as String?) ??
      'MediCare call';
  String? get photoUrl =>
      data?[incoming ? 'callerPhotoUrl' : 'calleePhotoUrl'] as String?;
  void _changed() => value++;

  void initialize() {
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
    }
    _auth ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      final epoch = ++_authEpoch;
      _authReconciling = true;
      _incomingActions.resetSession();
      _changed();
      final reconciliation = _authEvents.then((_) async {
        if (epoch != _authEpoch) return;
        if (uid == user?.uid && (uid == null || _incoming != null)) return;
        final incoming = _incoming;
        _incoming = null;
        await incoming?.cancel();
        if (epoch != _authEpoch) return;
        await _release();
        if (epoch != _authEpoch) return;
        uid = user?.uid;
        error = null;
        if (uid == null) return;
        _incoming = _db
            .collection('calls')
            .where('calleeId', isEqualTo: uid)
            .where('state', isEqualTo: 'ringing')
            .snapshots()
            .listen(
              (snapshot) {
                if (id != null || busy || _ending) return;
                final calls =
                    snapshot.docs
                        .where(
                          (d) =>
                              (d.data()['expiresAt'] as num? ?? 0) >
                              DateTime.now().millisecondsSinceEpoch,
                        )
                        .toList()
                      ..sort(
                        (a, b) => (b.data()['createdAt'] as num).compareTo(
                          a.data()['createdAt'] as num,
                        ),
                      );
                if (calls.isNotEmpty) {
                  unawaited(
                    _presentIncoming(
                      calls.first.id,
                      calls.first.data(),
                    ).then<void>((_) {}),
                  );
                }
              },
              onError: (Object e) {
                // The normal app remains usable before the new rules are deployed.
              },
            );
      });
      _authEvents = reconciliation.catchError((Object error) {
        debugPrint('Call session reconciliation failed: $error');
      });
      unawaited(
        _authEvents.whenComplete(() {
          if (epoch != _authEpoch) return;
          _authReconciling = false;
          if (!_initialSession.isCompleted) _initialSession.complete();
          _changed();
        }),
      );
    });
    NotificationService.instance.onCallEnded = _handleRemoteCallEnded;
    unawaited(
      IncomingCallBridge.instance.initialize((action) async {
        if (action.action == 'accept') _pendingNativeAccept = action.callId;
        try {
          await _initialSession.future;
          await _incomingActions.handle(action);
        } finally {
          if (_pendingNativeAccept == action.callId) {
            _pendingNativeAccept = null;
          }
        }
      }, onEnded: _handleRemoteCallEnded),
    );
  }

  Future<void> _handleRemoteCallEnded(String callId, String? state) async {
    _incomingActions.invalidate(callId);
    final terminal = const {
      'ended',
      'rejected',
      'cancelled',
      'missed',
      'expired',
      'failed',
      'busy',
    }.contains(state);
    final answeredElsewhere =
        state == 'accepted' && !_answering && connectedAt == null;
    if (id == callId && (terminal || answeredElsewhere)) {
      final incomingWaiting = incoming && connectedAt == null;
      final releasedGeneration = _generation + 1;
      await _release();
      if (_generation == releasedGeneration && id == null) {
        status = state == 'rejected' ? 'Call declined' : 'Call ended';
        error = incomingWaiting ? null : status;
        _changed();
      }
    }
    await NotificationService.instance.cancelIncomingCall(callId);
  }

  Future<bool> _waitForState(bool Function() ready, {int? expiresAt}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final deadline = expiresAt ?? now + 45000;
    if (deadline <= now) return false;
    if (ready()) return true;
    final completion = Completer<bool>();
    void check() {
      if (!completion.isCompleted && ready()) completion.complete(true);
    }

    final timer = Timer(
      Duration(milliseconds: (deadline - now).clamp(1, 45000)),
      () {
        if (!completion.isCompleted) completion.complete(false);
      },
    );
    addListener(check);
    check();
    try {
      return await completion.future;
    } finally {
      timer.cancel();
      removeListener(check);
    }
  }

  Future<bool> _waitUntilNativeReady(int? expiresAt) => _waitForState(
    () => !_authReconciling && !busy && !_ending && _releasesInFlight == 0,
    expiresAt: expiresAt,
  );

  Future<bool> _presentIncoming(
    String callId,
    Map<String, dynamic> record,
  ) async {
    final expiry = record['expiresAt'];
    do {
      if (!await _waitUntilNativeReady(expiry is num ? expiry.toInt() : null)) {
        return false;
      }
    } while (_authReconciling || busy || _ending || _releasesInFlight > 0);
    if (_incomingActions.isInvalidated(callId) ||
        uid == null ||
        uid != FirebaseAuth.instance.currentUser?.uid ||
        record['calleeId'] != uid ||
        record['state'] != 'ringing' ||
        expiry is! num ||
        expiry <= DateTime.now().millisecondsSinceEpoch ||
        (id != null && id != callId)) {
      return false;
    }
    if (id == callId) {
      data = record;
      _changed();
      return true;
    }
    _generation++;
    error = null;
    id = callId;
    data = record;
    status = 'Incoming call';
    _watch();
    _changed();
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A system notification supplies the background incoming sound. Running
    // both players would produce two ringtones on the receiver's phone.
    _foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.paused && cameraEnabled) {
      // Do not keep capturing a patient's camera after leaving the app. Audio
      // continues on the microphone foreground service; camera restart is opt-in.
      for (final track in _camera?.getVideoTracks() ?? <MediaStreamTrack>[]) {
        track.enabled = false;
      }
      unawaited(_cameraOff(allowBusy: true));
    }
    if (incoming && ringing && !_answering) {
      unawaited(_updateRingingTone());
    }
  }

  Future<Map<String, dynamic>> _request(
    String action, [
    Map<String, dynamic> extra = const {},
  ]) async {
    final result = await _api.httpsCallable('voiceCall').call({
      'action': action,
      'callId': id,
      ...extra,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<void> start(String chatId, {bool video = false}) async {
    if (id != null ||
        busy ||
        _ending ||
        _authReconciling ||
        _releasesInFlight > 0) {
      return;
    }
    busy = true;
    error = null;
    _startWithVideo = video;
    status = 'Starting call…';
    _changed();
    final startingGeneration = ++_generation;
    try {
      final result = await _request('start', {
        'chatId': chatId,
        'supportsVideo': true,
      });
      if (startingGeneration != _generation) return;
      id = result['callId'] as String;
      final generation = _generation;
      data = (await _db.collection('calls').doc(id).get()).data();
      if (generation != _generation) return;
      _watch();
      await _prepare(result['iceServers'] as List, generation);
      if (generation != _generation) return;
      final peer = _peer;
      if (peer == null) return;
      final offer = await peer.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      });
      if (generation != _generation || !identical(peer, _peer)) return;
      await peer.setLocalDescription(offer);
      if (generation != _generation || !identical(peer, _peer)) return;
      await _request('offer', {'offer': offer.toMap()});
      if (generation != _generation) return;
      status = 'Calling…';
    } catch (e) {
      if (startingGeneration == _generation) await _fail(e);
    } finally {
      if (startingGeneration == _generation) {
        busy = false;
        _changed();
      }
    }
  }

  Future<void> syncHistory(String chatId) async {
    await _request('history', {'chatId': chatId});
  }

  Future<void> _prepare(List servers, int generation) async {
    if (generation != _generation || _ending) return;
    final media = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
    if (generation != _generation) {
      for (final t in media.getTracks()) {
        await t.stop();
      }
      await media.dispose();
      return;
    }
    _media = media;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _native.invokeMethod('start');
      if (generation != _generation) {
        if (id == null && !busy) await _native.invokeMethod('stop');
        return;
      }
    }
    final peer = await createPeerConnection({
      'iceServers': servers,
      'sdpSemantics': 'unified-plan',
    });
    if (generation != _generation) {
      await peer.close();
      await peer.dispose();
      return;
    }
    _peer = peer;
    peer.onTrack = (event) {
      if (generation != _generation || event.track.kind != 'video') return;
      unawaited(
        _receiveRemoteVideo(event, generation).catchError((Object _) {
          if (generation == _generation) {
            mediaError =
                'Could not display video. You can continue using voice.';
            _changed();
          }
        }),
      );
    };
    for (final t in media.getTracks()) {
      await peer.addTrack(t, media);
      if (generation != _generation) return;
    }
    // Reserve the video m-line while both cameras are still off. replaceTrack
    // later changes only video, so neither audio nor the call needs restarting.
    // Only the caller creates this transceiver. The receiver must use the
    // transceiver associated with the received offer, not a separate sender.
    if (!incoming) {
      final sender = await reserveCallVideo(peer, media);
      if (generation != _generation) return;
      _videoSender = sender;
    }
    final callId = id!;
    peer.onIceCandidate = (candidate) {
      if (generation != _generation ||
          candidate.candidate == null ||
          candidate.candidate!.isEmpty) {
        return;
      }
      _db
          .collection('calls')
          .doc(callId)
          .collection('candidates')
          .add({'senderId': uid, ...candidate.toMap()})
          .catchError((Object e) {
            if (generation == _generation && !_ending) unawaited(_fail(e));
            throw e;
          })
          .then<void>((_) {}, onError: (_) {});
    };
    peer.onConnectionState = (state) {
      if (generation != _generation) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        connectedAt ??= DateTime.now();
        status = 'Connected';
        _connectTimeout?.cancel();
        _changed();
        if (_startWithVideo && !incoming && !videoMode && !videoBusy) {
          _startWithVideo = false;
          unawaited(enableVideo());
        }
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        unawaited(
          _fail(
            'Could not connect the call. Check your connection or relay configuration.',
          ),
        );
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        status = 'Reconnecting…';
        _changed();
        _connectTimeout?.cancel();
        _connectTimeout = Timer(
          const Duration(seconds: 20),
          () => _fail('The audio connection was lost.'),
        );
      }
    };
    _ice = _db
        .collection('calls')
        .doc(callId)
        .collection('candidates')
        .snapshots()
        .listen(
          (snapshot) {
            for (final change in snapshot.docChanges) {
              final d = change.doc.data();
              if (change.type != DocumentChangeType.added ||
                  d == null ||
                  d['senderId'] == uid) {
                continue;
              }
              final candidate = RTCIceCandidate(
                d['candidate'] as String?,
                d['sdpMid'] as String?,
                d['sdpMLineIndex'] as int?,
              );
              if (_remoteReady) {
                peer.addCandidate(candidate).catchError((Object e) {
                  if (generation == _generation) unawaited(_fail(e));
                });
              } else {
                _remoteCandidates.add(candidate);
              }
            }
          },
          onError: (Object e) {
            if (generation == _generation) unawaited(_fail(e));
          },
        );
    await _audioRoute.reset();
  }

  Future<void> _remote(Map description) async {
    if (_remoteReady || _peer == null) return;
    final generation = _generation;
    final peer = _peer!;
    await peer.setRemoteDescription(
      RTCSessionDescription(
        description['sdp'] as String?,
        description['type'] as String?,
      ),
    );
    if (generation != _generation || !identical(peer, _peer)) return;
    if (incoming && description['type'] == 'offer') {
      try {
        final sender = await answerCallVideo(
          peer,
          description['sdp'] as String,
          _media!,
        );
        if (generation != _generation || !identical(peer, _peer)) return;
        _videoSender = sender;
      } catch (_) {
        if (generation != _generation) return;
        _videoSender = null;
        mediaError =
            'Video could not be prepared on this phone. '
            'Your voice call can continue.';
      }
    }
    if (generation != _generation || !identical(peer, _peer)) return;
    _remoteReady = true;
    final candidates = List<RTCIceCandidate>.of(_remoteCandidates);
    _remoteCandidates.clear();
    for (final candidate in candidates) {
      if (generation != _generation || !identical(peer, _peer)) return;
      await peer.addCandidate(candidate);
      if (generation != _generation || !identical(peer, _peer)) return;
    }
  }

  Future<void> _receiveRemoteVideo(RTCTrackEvent event, int generation) async {
    MediaStream? wrapper;
    final MediaStream stream;
    if (event.streams.isNotEmpty) {
      stream = event.streams.first;
    } else {
      // Unified Plan also permits streamless tracks. Wrap the real remote
      // track for the renderer instead of showing a permanently empty view.
      wrapper = await createLocalMediaStream('call-remote-$generation');
      try {
        await wrapper.addTrack(event.track);
      } catch (_) {
        await wrapper.dispose();
        rethrow;
      }
      stream = wrapper;
    }
    if (generation != _generation) {
      await wrapper?.dispose();
      return;
    }
    final previousWrapper = _remoteVideoWrapper;
    _remoteVideoWrapper = wrapper;
    _remoteVideo = stream;
    remoteRenderer?.srcObject = stream;
    _changed();
    await previousWrapper?.dispose();
  }

  void _watch() {
    final generation = _generation;
    final watchedCallId = id;
    if (watchedCallId == null) return;
    bool current() => generation == _generation && id == watchedCallId;
    _call = _db
        .collection('calls')
        .doc(watchedCallId)
        .snapshots()
        .listen(
          (snapshot) {
            _events = _events
                .then((_) async {
                  if (!current() || !snapshot.exists) return;
                  data = snapshot.data();
                  _observeVideoCapabilities(data!['videoCapabilities']);
                  _applyMedia(data!['media']);
                  final state = data!['state'];
                  if (!['preparing', 'ringing', 'accepted'].contains(state)) {
                    final incomingWaiting = incoming && connectedAt == null;
                    final releasedGeneration = _generation + 1;
                    await _release();
                    if (_generation != releasedGeneration || id != null) return;
                    status = state == 'rejected'
                        ? 'Call declined'
                        : 'Call ended';
                    error = incomingWaiting ? null : status;
                    _changed();
                    return;
                  }
                  if (state == 'accepted') {
                    await _setTone(null);
                    if (!current()) return;
                    await NotificationService.instance.cancelIncomingCall(
                      watchedCallId,
                    );
                    if (!current()) return;
                    if (incoming && !_answering && _peer == null) {
                      await _release();
                      return;
                    }
                    if (!incoming) await _remote(data!['answer'] as Map);
                    if (!current()) return;
                    if (_remoteReady &&
                        _videoSender != null &&
                        !_videoRegistrationAttempted) {
                      _videoRegistrationAttempted = true;
                      unawaited(_refreshVideoCapabilities());
                    }
                    status = connectedAt == null ? 'Connecting…' : 'Connected';
                    _heartbeat ??= Timer.periodic(const Duration(seconds: 25), (
                      _,
                    ) {
                      if (!current()) return;
                      unawaited(
                        _request('heartbeat').catchError((Object e) {
                          if (generation == _generation) unawaited(_fail(e));
                          return <String, dynamic>{};
                        }),
                      );
                    });
                    _connectTimeout ??= Timer(const Duration(seconds: 35), () {
                      if (current() && connectedAt == null) {
                        unawaited(
                          _fail(
                            'The call could not connect. Please try again.',
                          ),
                        );
                      }
                    });
                  } else if (state == 'ringing' && !_answering) {
                    await _updateRingingTone();
                  }
                  _changed();
                })
                .catchError((Object e) {
                  if (generation == _generation) unawaited(_fail(e));
                });
          },
          onError: (Object e) {
            if (generation == _generation) unawaited(_fail(e));
          },
        );
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!current()) return;
      if ((data?['expiresAt'] as num? ?? double.infinity) <=
          DateTime.now().millisecondsSinceEpoch) {
        unawaited(end());
      } else {
        _changed();
      }
    });
  }

  Future<void> _setTone(String? tone) {
    return _tones.set(tone);
  }

  Future<void> _updateRingingTone() async {
    if (!ringing || _answering) return;
    final generation = _generation;
    final callId = id;
    if (callId == null) return;
    if (!incoming) {
      await _setTone('ringback');
      return;
    }
    if (IncomingCallBridge.instance.supported) {
      await _setTone(null);
      if (generation != _generation ||
          id != callId ||
          !incoming ||
          !ringing ||
          _answering ||
          _pendingNativeAccept == callId) {
        return;
      }
      await IncomingCallBridge.instance.show({
        'callId': callId,
        'callerId': data?['callerId'],
        'calleeId': data?['calleeId'],
        'callerName': data?['callerName'],
        'callerPhotoUrl': data?['callerPhotoUrl'],
        'createdAt': data?['createdAt'],
        'expiresAt': data?['expiresAt'],
      });
      return;
    }
    if (!_foreground) {
      await _setTone(null);
      return;
    }
    // Taking ownership from Android's background notification first prevents
    // its ringtone from overlapping the in-app player on resume.
    try {
      await NotificationService.instance.cancelIncomingCall(callId);
    } catch (error) {
      debugPrint('Incoming notification could not be cleared: $error');
    }
    if (generation != _generation ||
        id != callId ||
        !_foreground ||
        !incoming ||
        !ringing ||
        _answering) {
      return;
    }
    await _setTone('incoming');
  }

  Future<void> _playTone(String tone) async {
    final player = tone == 'incoming' ? _ringer : _ringback;
    await player.setAudioContext(
      callToneAudioContext(incoming: tone == 'incoming'),
    );
    await player.setReleaseMode(ReleaseMode.loop);
    await player.play(
      AssetSource(
        'sounds/${tone == 'incoming' ? 'incoming_call' : 'ringback'}.wav',
      ),
    );
  }

  Future<void> accept() async {
    if (busy || !incoming || !ringing) return;
    final acceptedCallId = id;
    if (acceptedCallId == null) return;
    busy = true;
    _answering = true;
    status = 'Connecting…';
    _changed();
    final generation = _generation;
    bool current() =>
        generation == _generation && id == acceptedCallId && !_ending;
    try {
      await _setTone(null);
      if (!current()) return;
      await NotificationService.instance.cancelIncomingCall(acceptedCallId);
      if (!current()) return;
      final result = await _request('ice');
      if (!current()) return;
      await _prepare(result['iceServers'] as List, generation);
      if (generation != _generation) return;
      final peer = _peer;
      if (peer == null) return;
      await _remote(data!['offer'] as Map);
      if (generation != _generation || !identical(peer, _peer)) return;
      final answer = await peer.createAnswer();
      if (generation != _generation || !identical(peer, _peer)) return;
      await peer.setLocalDescription(answer);
      if (generation != _generation || !identical(peer, _peer)) return;
      await _request('accept', {
        'answer': answer.toMap(),
        'supportsVideo': _videoSender != null,
      });
    } on FirebaseFunctionsException catch (e) {
      if (generation != _generation) return;
      if (e.code == 'failed-precondition') {
        final releasedGeneration = _generation + 1;
        await _release();
        if (_generation == releasedGeneration && id == null) {
          error = 'This call was answered elsewhere or has ended.';
          _changed();
        }
      } else {
        await _fail(e);
      }
    } catch (e) {
      if (generation == _generation) await _fail(e);
    } finally {
      if (generation == _generation) {
        busy = false;
        _changed();
      }
    }
  }

  Future<void> end({bool reject = false}) async {
    if (_ending) return;
    _ending = true;
    final request = id == null
        ? Future.value(<String, dynamic>{})
        : _request(reject ? 'reject' : 'end');
    final completion = request
        .timeout(const Duration(seconds: 4))
        .then<void>((_) {}, onError: (_) {});
    try {
      await _release();
      await completion;
    } finally {
      _ending = false;
      _changed();
    }
  }

  Future<void> _fail(Object e) async {
    final releasedGeneration = _generation + 1;
    await end();
    if (_generation != releasedGeneration || id != null) return;
    final text = '$e'.toLowerCase();
    error = e is FirebaseFunctionsException
        ? e.message ?? 'Calling is unavailable.'
        : text.contains('permission') || text.contains('notallowed')
        ? 'Microphone access is required for calls. Allow Microphone in '
              'Settings > Apps > MediCare > Permissions, then try again.'
        : '$e';
    _changed();
  }

  void dismiss() {
    error = null;
    _changed();
  }

  void toggleMute() {
    muted = !muted;
    for (final t in _media?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !muted;
    }
    _changed();
  }

  Future<void> toggleSpeaker() async {
    try {
      await _audioRoute.toggle();
    } catch (_) {
      mediaError = 'Could not change the audio output. Please try again.';
      _changed();
    }
  }

  void clearMediaError() {
    mediaError = null;
    _changed();
  }

  void _observeVideoCapabilities(dynamic raw) {
    if (raw is! Map) return;
    // Registrations are monotonic within one call. An older Firestore snapshot
    // must not undo the authoritative callable response and disable video.
    for (final participant in [uid, _otherUid]) {
      if (participant != null && raw[participant] == true) {
        _videoCapabilities[participant] = true;
      }
    }
  }

  Future<bool> _refreshVideoCapabilities() async {
    final pending = _videoRegistration;
    if (pending != null) return pending;
    if (id == null || !_remoteReady || _videoSender == null) return false;
    final generation = _generation;
    final registration = () async {
      try {
        final result = await _request('videoReady');
        if (generation != _generation) return false;
        _observeVideoCapabilities(result['videoCapabilities']);
        _applyMedia(result['media']);
        _changed();
        return videoAvailable;
      } on FirebaseFunctionsException catch (e) {
        if (generation != _generation) return false;
        // Existing capable calls remain usable with the previous video server
        // release; a refresh failure never terminates an established voice call.
        if (!videoAvailable) {
          mediaError =
              e.code == 'failed-precondition' &&
                  e.message?.toLowerCase().contains('video') == true
              ? e.message
              : 'Video could not be prepared. Your voice call continues. '
                    'Please retry; the calling service may need updating.';
          _changed();
        }
        return videoAvailable;
      } catch (_) {
        if (generation == _generation && !videoAvailable) {
          mediaError =
              'Could not check video availability. '
              'Your voice call continues. Check your connection and retry.';
          _changed();
        }
        return generation == _generation && videoAvailable;
      }
    }();
    _videoRegistration = registration;
    try {
      return await registration;
    } finally {
      if (identical(_videoRegistration, registration)) {
        _videoRegistration = null;
      }
    }
  }

  void _applyMedia(dynamic raw) {
    if (raw is! Map || raw['revision'] is! num) return;
    final revision = (raw['revision'] as num).toInt();
    if (revision <= _mediaRevision) return;
    _mediaRevision = revision;
    videoMode = raw['mode'] == 'video';
    final cameras = raw['cameras'];
    _cameraRequested = videoMode && cameras is Map && cameras[uid] == true;
    remoteCameraEnabled =
        videoMode && cameras is Map && cameras[_otherUid] == true;
    if (videoMode && remoteRenderer == null) {
      final generation = _generation;
      _videoEvents = _videoEvents
          .then((_) async {
            if (generation == _generation && videoMode) {
              await _ensureVideoRenderers(generation);
              _changed();
            }
          })
          .catchError((Object _) {
            if (generation == _generation) {
              mediaError =
                  'Could not display video. You can continue using voice.';
              _changed();
            }
          });
    }
    if (!_cameraRequested && _camera != null) {
      for (final track in _camera!.getVideoTracks()) {
        track.enabled = false;
      }
      cameraEnabled = false;
      final generation = _generation;
      _videoEvents = _videoEvents
          .then((_) async {
            if (generation == _generation && !_cameraRequested) {
              await _stopCamera();
              _changed();
            }
          })
          .catchError((Object e) {
            if (generation == _generation) {
              mediaError = 'Could not stop the camera. Please end the call.';
              _changed();
            }
          });
    }
    _changed();
  }

  Future<void> _videoAction(
    Future<void> Function(int) action, {
    bool allowBusy = false,
  }) async {
    if ((videoBusy && !allowBusy) ||
        id == null ||
        connectedAt == null ||
        _ending) {
      return;
    }
    final generation = _generation;
    videoBusy = true;
    mediaError = null;
    _changed();
    final operation = _videoEvents.then((_) async {
      if (generation == _generation) await action(generation);
    });
    _videoEvents = operation.catchError((Object _) {});
    try {
      await operation;
    } catch (e) {
      if (generation == _generation) {
        mediaError = e is FirebaseFunctionsException
            ? e.message ?? 'Video could not be changed. Please try again.'
            : _cameraError(e);
      }
    } finally {
      if (generation == _generation) {
        videoBusy = false;
        _changed();
      }
    }
  }

  String _cameraError(Object error) {
    final text = '$error'.toLowerCase();
    if (text.contains('permission') ||
        text.contains('denied') ||
        text.contains('notallowed')) {
      return 'Camera access was not allowed. Voice calling continues. '
          'Allow Camera in Settings > Apps > MediCare > Permissions, then retry.';
    }
    if (error is PlatformException &&
        [
          'call_not_visible',
          'call_service_failed',
          'call_service_inactive',
          'camera_service_failed',
        ].contains(error.code)) {
      return '${error.message ?? 'The camera service could not start.'} '
          'Your voice call continues. Return to MediCare and try again.';
    }
    return 'Camera unavailable. Voice calling continues. '
        'Close other apps using the camera and try again.';
  }

  Future<void> _ensureVideoRenderers(int generation) async {
    if (localRenderer != null && remoteRenderer != null) return;
    final local = RTCVideoRenderer();
    final remote = RTCVideoRenderer();
    try {
      await local.initialize();
      await remote.initialize();
      if (generation != _generation) return;
      localRenderer = local;
      remoteRenderer = remote;
      remote.srcObject = _remoteVideo;
    } finally {
      if (localRenderer != local) await local.dispose();
      if (remoteRenderer != remote) await remote.dispose();
    }
  }

  Future<void> enableVideo() => _videoAction((generation) async {
    if (!videoAvailable) {
      await _refreshVideoCapabilities();
      if (generation != _generation) return;
      if (!videoAvailable) {
        mediaError ??= _videoSender == null
            ? 'This call was connected in voice-only mode. '
                  'Update MediCare on both phones and start a new call for video.'
            : 'Waiting for the other phone to support video. '
                  'Both users need the updated app. Your voice call continues; '
                  'please try Video call again once both phones are ready.';
        return;
      }
    }
    if (cameraEnabled) return;
    if (!_foreground) {
      mediaError = 'Open MediCare to turn on your camera.';
      return;
    }
    final revision = _mediaRevision;
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    MediaStream? capture;
    var attached = false;
    try {
      if (android) {
        final granted = await _native.invokeMethod<bool>('cameraPermission');
        if (generation != _generation) return;
        if (granted != true) throw StateError('Camera permission denied');
        await _native.invokeMethod('camera', {'enabled': true});
        if (generation != _generation) return;
      }
      capture = await openCallCamera();
      if (generation != _generation || !_foreground) return;
      if (capture.getVideoTracks().isEmpty) throw StateError('No camera found');
      await _ensureVideoRenderers(generation);
      if (generation != _generation || !_foreground) return;
      final result = await _request('media', {
        'mode': 'video',
        'videoEnabled': true,
        'expectedRevision': revision,
      });
      if (generation != _generation) return;
      _applyMedia(result['media']);
      if (!_cameraRequested || !_foreground) return;
      await _videoSender!.replaceTrack(capture.getVideoTracks().first);
      if (generation != _generation || !_cameraRequested || !_foreground) {
        if (generation == _generation) await _videoSender?.replaceTrack(null);
        return;
      }
      _camera = capture;
      localRenderer!.srcObject = capture;
      cameraEnabled = true;
      frontCamera = true;
      attached = true;
      _changed();
      try {
        // Camera acquisition must not override a manually selected audio route.
        await _audioRoute.restore();
      } catch (_) {
        if (generation == _generation) {
          mediaError =
              'Could not restore the audio output. Check the speaker control.';
        }
      }
    } finally {
      if (!attached) {
        if (generation == _generation) {
          try {
            await _videoSender?.replaceTrack(null);
          } catch (_) {}
        }
        for (final track in capture?.getTracks() ?? <MediaStreamTrack>[]) {
          try {
            await track.stop();
          } catch (_) {}
        }
        try {
          await capture?.dispose();
        } catch (_) {}
        if (generation == _generation) {
          if (android) {
            try {
              await _native.invokeMethod('camera', {'enabled': false});
            } catch (_) {}
          }
          // A permission/media failure must never end the ongoing voice call.
          if (_cameraRequested) {
            try {
              final result = await _request('media', {'videoEnabled': false});
              if (generation == _generation) _applyMedia(result['media']);
            } catch (_) {}
          }
        }
      }
    }
  });

  Future<void> toggleCamera() => cameraEnabled ? _cameraOff() : enableVideo();

  Future<void> _cameraOff({bool allowBusy = false}) =>
      _videoAction((generation) async {
        // Stop capture before network I/O, including when the phone is offline.
        await _stopCamera();
        if (generation != _generation) return;
        final result = await _request('media', {'videoEnabled': false});
        if (generation == _generation) _applyMedia(result['media']);
      }, allowBusy: allowBusy);

  Future<void> switchToVoice() => _videoAction((generation) async {
    await _stopCamera();
    if (generation != _generation) return;
    final result = await _request('media', {
      'mode': 'voice',
      'videoEnabled': false,
    });
    if (generation == _generation) _applyMedia(result['media']);
  });

  Future<void> switchCamera() => _videoAction((generation) async {
    final tracks = _camera?.getVideoTracks();
    if (!cameraEnabled || tracks == null || tracks.isEmpty) return;
    final isFront = await Helper.switchCamera(tracks.first);
    if (generation == _generation) frontCamera = isFront;
  });

  Future<void> _stopCamera() async {
    final generation = _generation;
    final stream = _camera;
    final sender = _videoSender;
    final renderer = localRenderer;
    _camera = null;
    cameraEnabled = false;
    for (final track in stream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = false;
    }
    _changed();
    // Detach before capture is stopped; keep the negotiated sender for reuse.
    try {
      await sender?.replaceTrack(null);
    } catch (_) {}
    try {
      renderer?.srcObject = null;
    } catch (_) {}
    for (final track in stream?.getTracks() ?? <MediaStreamTrack>[]) {
      try {
        await track.stop();
      } catch (_) {}
    }
    try {
      await stream?.dispose();
    } catch (_) {}
    if (generation == _generation &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _native.invokeMethod('camera', {'enabled': false});
      } catch (_) {}
    }
    _changed();
  }

  Future<void> _release() async {
    _releasesInFlight++;
    try {
      _generation++;
      final releaseGeneration = _generation;
      _videoEvents = Future.value();
      _videoRegistration = null;
      _videoRegistrationAttempted = false;
      _videoCapabilities.clear();
      final camera = _camera;
      for (final track in camera?.getVideoTracks() ?? <MediaStreamTrack>[]) {
        track.enabled = false;
      }
      _camera = null;
      final localVideo = localRenderer;
      final remoteVideo = remoteRenderer;
      final remoteWrapper = _remoteVideoWrapper;
      _remoteVideoWrapper = null;
      localRenderer = null;
      remoteRenderer = null;
      _remoteVideo = null;
      _videoSender = null;
      _mediaRevision = -1;
      _cameraRequested = false;
      videoMode = cameraEnabled = remoteCameraEnabled = videoBusy = false;
      _startWithVideo = false;
      frontCamera = true;
      mediaError = null;
      final stopTones = _setTone(null);
      if (id != null) {
        _incomingActions.invalidate(id!);
        unawaited(
          NotificationService.instance
              .cancelIncomingCall(id!)
              .catchError((_) {}),
        );
      }
      _clock?.cancel();
      _clock = null;
      _heartbeat?.cancel();
      _heartbeat = null;
      _connectTimeout?.cancel();
      _connectTimeout = null;
      final subscriptions = [_call, _ice];
      _call = null;
      _ice = null;
      final media = _media;
      _media = null;
      final peer = _peer;
      _peer = null;
      _remoteCandidates.clear();
      _remoteReady = false;
      _answering = false;
      id = null;
      data = null;
      connectedAt = null;
      muted = false;
      unawaited(_audioRoute.reset().catchError((Object _) {}));
      busy = false;
      _changed();
      // Detach first so racing signaling callbacks cannot reuse released media.
      for (final subscription in subscriptions) {
        try {
          await subscription?.cancel();
        } catch (_) {}
      }
      try {
        await stopTones;
      } catch (_) {}
      for (final track in camera?.getTracks() ?? <MediaStreamTrack>[]) {
        try {
          await track.stop();
        } catch (_) {}
      }
      try {
        localVideo?.srcObject = null;
        await localVideo?.dispose();
      } catch (_) {}
      try {
        remoteVideo?.srcObject = null;
        await remoteVideo?.dispose();
      } catch (_) {}
      try {
        await remoteWrapper?.dispose();
      } catch (_) {}
      try {
        await camera?.dispose();
      } catch (_) {}
      for (final t in media?.getTracks() ?? <MediaStreamTrack>[]) {
        try {
          await t.stop();
        } catch (_) {}
      }
      try {
        await media?.dispose();
      } catch (_) {}
      try {
        await peer?.close();
      } catch (_) {}
      try {
        await peer?.dispose();
      } catch (_) {}
      if (releaseGeneration == _generation &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android) {
        try {
          await _native.invokeMethod('stop');
        } catch (_) {}
      }
    } finally {
      _releasesInFlight--;
      _changed();
    }
  }
}
