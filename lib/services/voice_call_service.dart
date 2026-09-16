import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'frame_safe_notifier.dart';

/// One audio-only call per signed-in device. Firestore carries signaling only;
/// WebRTC transports encrypted audio directly or through the configured TURN relay.
class VoiceCallService extends FrameSafeNotifier<int> {
  VoiceCallService._() : super(0);
  static final instance = VoiceCallService._();
  final _db = FirebaseFirestore.instance;
  final _api = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
  final _ringer = AudioPlayer();
  static const _native = MethodChannel('medicare/voice_call');
  StreamSubscription? _auth, _incoming, _call, _ice;
  RTCPeerConnection? _peer;
  MediaStream? _media;
  final List<RTCIceCandidate> _remoteCandidates = [];
  bool _remoteReady = false, _answering = false, _ending = false;
  int _generation = 0;
  Future<void> _events = Future.value();
  Timer? _clock, _heartbeat, _connectTimeout;
  String? id, uid, error;
  Map<String, dynamic>? data;
  String status = '';
  bool busy = false, muted = false, speaker = false;
  DateTime? connectedAt;
  bool get incoming => data?['calleeId'] == uid;
  bool get ringing => data?['state'] == 'ringing' && connectedAt == null;
  bool get visible => id != null || busy || error != null;
  String get name =>
      (data?[incoming ? 'callerName' : 'calleeName'] as String?) ??
      'MediCare call';
  void _changed() => value++;

  void initialize() {
    _auth ??= FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (uid == user?.uid) return;
      await _incoming?.cancel();
      await _release();
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
                error = null;
                id = calls.first.id;
                data = calls.first.data();
                status = 'Incoming voice call';
                _watch();
                _ring();
                _changed();
              }
            },
            onError: (Object e) {
              // The normal app remains usable before the new rules are deployed.
            },
          );
    });
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

  Future<void> start(String chatId) async {
    if (id != null || busy || _ending) return;
    busy = true;
    error = null;
    status = 'Starting call…';
    _changed();
    final startingGeneration = _generation;
    try {
      final result = await _request('start', {'chatId': chatId});
      if (startingGeneration != _generation) return;
      id = result['callId'] as String;
      final generation = _generation;
      data = (await _db.collection('calls').doc(id).get()).data();
      if (generation != _generation) return;
      _watch();
      await _prepare(result['iceServers'] as List, generation);
      if (generation != _generation) return;
      final offer = await _peer!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      await _peer!.setLocalDescription(offer);
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

  Future<void> _prepare(List servers, int generation) async {
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
        await _native.invokeMethod('stop');
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
    for (final t in media.getTracks()) {
      await peer.addTrack(t, media);
      if (generation != _generation) return;
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
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        unawaited(
          _fail(
            'Could not connect the audio. Check your connection or relay configuration.',
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
    await Helper.setSpeakerphoneOn(false);
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
    if (generation != _generation) return;
    _remoteReady = true;
    for (final c in _remoteCandidates) {
      await _peer!.addCandidate(c);
    }
    _remoteCandidates.clear();
  }

  void _watch() {
    final generation = _generation;
    _call = _db
        .collection('calls')
        .doc(id)
        .snapshots()
        .listen(
          (snapshot) {
            _events = _events
                .then((_) async {
                  if (generation != _generation || !snapshot.exists) return;
                  data = snapshot.data();
                  final state = data!['state'];
                  if (!['preparing', 'ringing', 'accepted'].contains(state)) {
                    await _release();
                    status = state == 'rejected'
                        ? 'Call declined'
                        : 'Call ended';
                    error = status;
                    _changed();
                    return;
                  }
                  if (state == 'accepted') {
                    await _ringer.stop();
                    if (incoming && !_answering && _peer == null) {
                      await _release();
                      return;
                    }
                    if (!incoming) await _remote(data!['answer'] as Map);
                    status = connectedAt == null ? 'Connecting…' : 'Connected';
                    _heartbeat ??= Timer.periodic(
                      const Duration(seconds: 25),
                      (_) => _request('heartbeat').catchError((Object e) {
                        if (generation == _generation) unawaited(_fail(e));
                        return <String, dynamic>{};
                      }),
                    );
                    _connectTimeout ??= Timer(const Duration(seconds: 35), () {
                      if (connectedAt == null) {
                        unawaited(
                          _fail(
                            'The call could not connect. Please try again.',
                          ),
                        );
                      }
                    });
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
      if ((data?['expiresAt'] as num? ?? double.infinity) <=
          DateTime.now().millisecondsSinceEpoch) {
        unawaited(end());
      } else {
        _changed();
      }
    });
  }

  Future<void> _ring() async {
    final generation = _generation;
    try {
      await _ringer.setReleaseMode(ReleaseMode.loop);
      if (generation != _generation) return;
      await _ringer.play(AssetSource('sounds/incoming_call.wav'));
      if (generation != _generation) await _ringer.stop();
    } catch (_) {}
  }

  Future<void> accept() async {
    if (busy || !incoming || !ringing) return;
    busy = true;
    _answering = true;
    status = 'Connecting…';
    _changed();
    final generation = _generation;
    try {
      await _ringer.stop();
      final result = await _request('ice');
      await _prepare(result['iceServers'] as List, generation);
      if (generation != _generation) return;
      await _remote(data!['offer'] as Map);
      final answer = await _peer!.createAnswer();
      await _peer!.setLocalDescription(answer);
      await _request('accept', {'answer': answer.toMap()});
    } on FirebaseFunctionsException catch (e) {
      if (generation != _generation) return;
      if (e.code == 'failed-precondition') {
        await _release();
        error = 'This call was answered elsewhere or has ended.';
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
    await _release();
    await completion;
    _ending = false;
  }

  Future<void> _fail(Object e) async {
    await end();
    error = e is FirebaseFunctionsException
        ? e.message ?? 'Calling is unavailable.'
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
      await Helper.setSpeakerphoneOn(!speaker);
      speaker = !speaker;
      _changed();
    } catch (_) {}
  }

  Future<void> _release() async {
    _generation++;
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
    speaker = false;
    busy = false;
    _changed();
    // Detach first so racing signaling callbacks cannot reuse released media.
    for (final subscription in subscriptions) {
      try {
        await subscription?.cancel();
      } catch (_) {}
    }
    try {
      await _ringer.stop();
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
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _native.invokeMethod('stop');
      } catch (_) {}
    }
  }
}
