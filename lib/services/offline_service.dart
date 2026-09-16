import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'frame_safe_notifier.dart';

class OfflineService {
  static final offline = FrameSafeNotifier(false);
  static final pending = FrameSafeNotifier(0);
  static final error = FrameSafeNotifier<String?>(null);
  static Future<void> initialize() async {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );
    void update(List<ConnectivityResult> state) =>
        offline.value = state.contains(ConnectivityResult.none);
    try {
      update(await Connectivity().checkConnectivity());
    } catch (_) {}
    Connectivity().onConnectivityChanged.listen(update);
  }

  /// Firestore queues this write durably. Do not leave local UI waiting for a
  /// server acknowledgement while offline. Later rejections remain visible.
  static Future<void> save(Future<void> write) async {
    pending.value++;
    final completion = write.then(
      (_) {
        pending.value--;
      },
      onError: (Object e, StackTrace s) {
        pending.value--;
        error.value =
            'A saved change could not sync. Please review and retry: $e';
        Error.throwWithStackTrace(e, s);
      },
    );
    await completion.timeout(const Duration(seconds: 2), onTimeout: () {});
  }
}
