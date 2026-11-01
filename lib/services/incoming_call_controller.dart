import 'dart:async';

/// Opening an alert and accepting a call are intentionally separate actions.
class IncomingCallAction {
  const IncomingCallAction._(this.callId, this.action);

  final String callId;
  final String action;

  static IncomingCallAction? parse(dynamic value) {
    if (value is! Map) return null;
    final id = value['callId'];
    final action = value['action'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 200 ||
        id.trim() != id ||
        id.contains('/') ||
        (action != 'open' && action != 'accept')) {
      return null;
    }
    return IncomingCallAction._(id, action as String);
  }
}

/// Revalidates native call actions against the authenticated server record
/// before the existing call service is allowed to prepare media.
class IncomingCallController {
  IncomingCallController({
    required this.currentUserId,
    required this.loadCall,
    required this.activeCallId,
    required this.present,
    required this.accept,
    required this.dismiss,
    this.waitUntilReady,
    int Function()? now,
    this.onError,
  }) : now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Future<String?> Function() currentUserId;
  final Future<Map<String, dynamic>?> Function(String) loadCall;
  final String? Function() activeCallId;
  final Future<void> Function(String, Map<String, dynamic>) present;
  final Future<void> Function(String) accept;
  final Future<void> Function(String) dismiss;
  final Future<bool> Function(int? expiresAt)? waitUntilReady;
  final int Function() now;
  final void Function(Object)? onError;
  final Set<String> _cancelled = {};
  final Set<String> _accepted = {};
  Future<void> _pending = Future.value();
  int _session = 0;
  String? _waitingId;
  Completer<bool>? _readinessAbort;

  void _remember(Set<String> values, String id) {
    values.add(id);
    while (values.length > 100) {
      values.remove(values.first);
    }
  }

  bool isInvalidated(String callId) => _cancelled.contains(callId);

  void invalidate(String callId) {
    _remember(_cancelled, callId);
    if (_waitingId == callId) _abortReadiness();
  }

  void _abortReadiness() {
    final abort = _readinessAbort;
    if (abort != null && !abort.isCompleted) abort.complete(false);
  }

  void resetSession() {
    _session++;
    _abortReadiness();
    _cancelled.clear();
    _accepted.clear();
  }

  Future<bool> _ready(
    IncomingCallAction action,
    int session, [
    int? expiry,
  ]) async {
    final wait = waitUntilReady;
    if (wait == null) return true;
    if (session != _session || isInvalidated(action.callId)) return false;
    final abort = Completer<bool>();
    _waitingId = action.callId;
    _readinessAbort = abort;
    try {
      return await Future.any([wait(expiry), abort.future]);
    } finally {
      if (identical(_readinessAbort, abort)) {
        _readinessAbort = null;
        _waitingId = null;
      }
    }
  }

  Future<void> handle(IncomingCallAction action) {
    final session = _session;
    final result = _pending.then((_) => _handle(action, session));
    _pending = result.catchError((Object error) => onError?.call(error));
    return result;
  }

  Future<void> _handle(IncomingCallAction action, int session) async {
    final id = action.callId;
    bool current() => session == _session && !_cancelled.contains(id);
    try {
      if (!current() || _accepted.contains(id)) return;
      if (!await _ready(action, session)) {
        if (current()) await dismiss(id);
        return;
      }
      if (!current()) return;
      final uid = await currentUserId();
      if (!current()) return;
      final record = uid == null ? null : await loadCall(id);
      if (!current()) return;
      final expiry = record?['expiresAt'];
      if (!await _ready(
            action,
            session,
            expiry is num ? expiry.toInt() : null,
          ) ||
          !current()) {
        if (current()) await dismiss(id);
        return;
      }
      final active = activeCallId();
      final eligible =
          uid != null &&
          record != null &&
          record['calleeId'] == uid &&
          record['participants'] is List &&
          (record['participants'] as List).contains(uid) &&
          record['state'] == 'ringing' &&
          record['expiresAt'] is num &&
          (record['expiresAt'] as num) > now() &&
          (active == null || active == id);
      if (!current()) return;
      if (!eligible) {
        await dismiss(id);
        return;
      }
      final currentUid = await currentUserId();
      if (!current()) return;
      if (currentUid != uid) {
        await dismiss(id);
        return;
      }
      await present(id, record);
      if (!current()) return;
      if (action.action == 'accept') {
        _remember(_accepted, id);
        await accept(id);
      }
    } catch (error) {
      onError?.call(error);
      if (current()) await dismiss(id);
    }
  }
}
