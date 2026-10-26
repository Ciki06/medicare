import 'package:flutter/material.dart';

/// Shows the time picker with a safe minimum text scale for its dialog layout.
///
/// Flutter's input mode keeps a fixed minimum height while scaling its maximum
/// height with text size. Smaller system fonts can otherwise make the maximum
/// height less than the minimum. Keep this adjustment local to the picker and
/// preserve larger accessibility text settings.
Future<TimeOfDay?> showAppTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  TimePickerEntryMode initialEntryMode = TimePickerEntryMode.dial,
}) {
  return showTimePicker(
    context: context,
    initialTime: initialTime,
    initialEntryMode: initialEntryMode,
    builder: (context, child) =>
        MediaQuery.withClampedTextScaling(minScaleFactor: 1.0, child: child!),
  );
}
