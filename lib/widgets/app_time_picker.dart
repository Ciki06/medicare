import 'package:flutter/material.dart';

/// Formats a selected time with an explicit AM/PM period.
///
/// Storage and scheduling continue to use their existing 24-hour format.
String formatAppTime(TimeOfDay time) => const DefaultMaterialLocalizations()
    .formatTimeOfDay(time, alwaysUse24HourFormat: false);

/// Shows a twelve-hour clock with AM/PM beside the selected time.
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
    builder: (context, child) => Localizations.override(
      context: context,
      // Some regional formats remain 24-hour even when Android's preference is
      // disabled. Override only this dialog so AM/PM is always available.
      locale: const Locale('en', 'US'),
      delegates: const [DefaultMaterialLocalizations.delegate],
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          alwaysUse24HourFormat: false,
          textScaler: MediaQuery.textScalerOf(
            context,
          ).clamp(minScaleFactor: 1.0),
        ),
        child: child!,
      ),
    ),
  );
}
