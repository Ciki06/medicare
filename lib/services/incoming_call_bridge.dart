import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'incoming_call_controller.dart';

/// Android owns incoming presentation and ringing without starting a Flutter
/// isolate. Only explicit native Accept actions enter the media acceptance path.
class IncomingCallBridge {
  IncomingCallBridge._();
  static final instance = IncomingCallBridge._();
  static const channel = MethodChannel('medicare/incoming_call');

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool _initialized = false;
  bool _nativeReady = false;
  bool get ready => supported && _nativeReady;

  Future<void> initialize(
    Future<void> Function(IncomingCallAction) onAction, {
    Future<void> Function(String callId, String? state)? onEnded,
  }) async {
    if (!supported || _initialized) return;
    _initialized = true;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'callAction') {
        final action = IncomingCallAction.parse(call.arguments);
        if (action != null) await onAction(action);
      } else if (call.method == 'callEnded' && call.arguments is Map) {
        final args = call.arguments as Map;
        final action = IncomingCallAction.parse({
          'callId': args['callId'],
          'action': 'open',
        });
        if (action != null && onEnded != null) {
          await onEnded(
            action.callId,
            args['state'] is String ? args['state'] as String : null,
          );
        }
      }
    });
    try {
      await channel.invokeMethod<void>('initialize');
      _nativeReady = true;
      final action = IncomingCallAction.parse(
        await channel.invokeMethod<dynamic>('getPendingAction'),
      );
      if (action != null) await onAction(action);
    } on MissingPluginException {
      // Unit tests and non-Android hosts have no native incoming-call bridge.
    } on PlatformException catch (error) {
      debugPrint('Incoming call bridge could not initialize: ${error.code}');
    }
  }

  Future<void> show(Map<String, dynamic> payload) async {
    if (!supported) return;
    try {
      await channel.invokeMethod<void>('showIncoming', payload);
    } on MissingPluginException {
      // Allows isolated Dart tests without requiring an Android process.
    }
  }

  Future<void> dismiss(String callId) async {
    if (!supported) return;
    try {
      await channel.invokeMethod<void>('dismiss', {'callId': callId});
    } on MissingPluginException {
      // No native presentation exists on test/desktop hosts.
    }
  }

  Future<Map<String, dynamic>> permissions() async {
    if (!supported) return {};
    try {
      final value = await channel.invokeMapMethod<String, dynamic>(
        'permissions',
      );
      return value ?? {};
    } on MissingPluginException {
      return {};
    }
  }

  Future<void> openFullScreenSettings() =>
      channel.invokeMethod<void>('openFullScreenSettings');

  Future<void> openNotificationSettings() =>
      channel.invokeMethod<void>('openNotificationSettings');
}
