import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridges Android/iOS home-screen SOS widget deep links into Flutter.
///
/// Native code accepts the `medicare://sos/trigger` URL and queues a cold-start
/// link until Flutter is ready. This service deliberately treats every link as
/// untrusted input and exposes only the one supported SOS action.
class SosLaunchService {
  SosLaunchService._();

  static final SosLaunchService instance = SosLaunchService._();

  static const MethodChannel _channel = MethodChannel('medicare/deeplinks');

  VoidCallback? onSosRequested;
  bool _initialized = false;
  bool _hasPendingSosRequest = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleNativeCall);

    try {
      final initialLink = await _channel.invokeMethod<String>(
        'consumeInitialDeepLink',
      );
      if (initialLink != null) _acceptLink(initialLink);
    } on MissingPluginException {
      // Desktop platforms do not provide the mobile deep-link bridge.
    } on PlatformException catch (error) {
      debugPrint('Unable to read initial SOS deep link: $error');
    }
  }

  bool consumePendingSosRequest() {
    if (!_hasPendingSosRequest) return false;
    _hasPendingSosRequest = false;
    return true;
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'onDeepLink' || call.arguments is! String) return;
    _acceptLink(call.arguments as String);
  }

  void _acceptLink(String link) {
    final uri = Uri.tryParse(link);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'medicare' ||
        uri.host.toLowerCase() != 'sos' ||
        uri.path != '/trigger') {
      return;
    }

    final callback = onSosRequested;
    if (callback == null) {
      _hasPendingSosRequest = true;
    } else {
      callback();
    }
  }
}
