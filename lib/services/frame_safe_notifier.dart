import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Values change synchronously; UI listeners run outside build/dispose locks.
class FrameSafeNotifier<T> extends ValueNotifier<T> {
  FrameSafeNotifier(super.value);
  bool _queued = false, _disposed = false;
  @override
  void notifyListeners() {
    if (_queued || _disposed) return;
    _queued = true;
    scheduleMicrotask(() {
      if (_disposed) return;
      final scheduler = SchedulerBinding.instance;
      if (scheduler.schedulerPhase == SchedulerPhase.idle ||
          scheduler.schedulerPhase == SchedulerPhase.postFrameCallbacks) {
        _publish();
      } else {
        scheduler.addPostFrameCallback((_) => _publish());
        scheduler.ensureVisualUpdate();
      }
    });
  }

  void _publish() {
    _queued = false;
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
