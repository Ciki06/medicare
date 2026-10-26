/// Spoken prompts stay independent of the details shown in reminder cards.
const medicationReminderPhrase = "It's time to take your medicine.";
const appointmentReminderPhrase = "It's time to go to your appointment.";

/// Retain the named arguments used by scheduled and snoozed reminders, while
/// speaking only the requested prompt. Prescription details remain in the UI.
String medicationReminderSpeech({
  required String name,
  String? dosage,
  String? medicationType,
}) => medicationReminderPhrase;
