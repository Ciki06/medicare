import 'package:flutter/foundation.dart';

/// Applies audio routes in order. Camera changes restore the user's route;
/// only an explicit toggle enables the speaker.
class CallAudioRoute {
  CallAudioRoute({required this.apply, this.onChanged});

  final Future<void> Function(bool enabled) apply;
  final VoidCallback? onChanged;
  bool _speaker = false;
  int _generation = 0;
  Future<void> _pending = Future.value();

  bool get speaker => _speaker;

  Future<void> _enqueue(Future<void> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.catchError((Object _) {});
    return result;
  }

  Future<void> reset() {
    final generation = ++_generation;
    return _enqueue(() async {
      if (generation != _generation) return;
      await apply(false);
      if (generation != _generation) return;
      _speaker = false;
      onChanged?.call();
    });
  }

  Future<void> toggle() {
    final generation = _generation;
    return _enqueue(() async {
      if (generation != _generation) return;
      final next = !_speaker;
      await apply(next);
      if (generation != _generation) return;
      _speaker = next;
      onChanged?.call();
    });
  }

  Future<void> restore() {
    final generation = _generation;
    return _enqueue(() async {
      if (generation == _generation) await apply(_speaker);
    });
  }
}
