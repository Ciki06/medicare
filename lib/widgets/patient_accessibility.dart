import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/frame_safe_notifier.dart';

/// Applied above the Navigator, so patient dialogs and pushed pages share the
/// same readable typography. Other account roles retain their existing sizes.
class PatientAccessibility extends StatelessWidget {
  const PatientAccessibility({
    super.key,
    required this.enabled,
    required this.child,
  });

  static final patientSession = FrameSafeNotifier(false);
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final media = MediaQuery.of(context);
    final original = media.textScaler;
    return MediaQuery(
      data: media.copyWith(
        textScaler: original is PatientTextScaler
            ? original
            : PatientTextScaler(original),
      ),
      child: child,
    );
  }
}

/// Adds two logical pixels to patient text without changing component geometry
/// or reducing the user's system text settings.
@immutable
class PatientTextScaler extends TextScaler {
  const PatientTextScaler(this.system);

  final TextScaler system;

  @override
  double scale(double fontSize) {
    if (fontSize == 0) return 0;
    final readable = fontSize + 2.0;
    return math.max(readable, system.scale(fontSize));
  }

  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  bool operator ==(Object other) =>
      other is PatientTextScaler && other.system == system;

  @override
  int get hashCode => system.hashCode;
}
