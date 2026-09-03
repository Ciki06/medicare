import 'dart:async';

/// Counts elapsed hold ticks independently of the last rendered progress value.
class SosHoldController {
  SosHoldController({required this.onChanged, required this.onComplete});

  final void Function(bool holding, double progress) onChanged;
  final void Function() onComplete;
  Timer? _timer;

  void start() {
    if (_timer != null) return;
    onChanged(true, 0);
    var ticks = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      ticks++;
      if (ticks >= 40) {
        _timer?.cancel();
        _timer = null;
        onChanged(false, 0);
        onComplete();
      } else {
        onChanged(true, ticks / 40);
      }
    });
  }

  void cancel() {
    if (_timer == null) return;
    _timer?.cancel();
    _timer = null;
    onChanged(false, 0);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
