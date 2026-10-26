# medicare

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Patient reminders, SOS, chat and calls

For video-call setup, TURN configuration, permissions and two-device testing, see
[Voice and video calling](VIDEO_CALLING.md).

Deploy the matching Firestore rules/indexes and Cloud Functions before releasing
the updated mobile build. The linked-family lookup uses `users` in Firestore
with both `role == family` and `linkedPatientIds array-contains patientUid`.
It does not query a caregiver's device-local SQLite database.

```powershell
firebase deploy --only firestore:rules,firestore:indexes,functions:voiceCall,functions:sendIncomingCall,functions:expireVoiceCalls,functions:sendChatNotification,functions:syncSosLocationToChats
```

`expireVoiceCalls` uses Cloud Scheduler every minute to finalize calls after a
phone disconnects. `voiceCall` writes one server-owned `call_<callId>` message
at initiation and updates that event in the same transaction as call state.
Opening a conversation also restores events for older calls in that chat.
Clients cannot create or edit call events. Existing TURN configuration is still
required for reliable audio across restrictive networks.

Android spoken reminders use persisted exact alarms and a short foreground
speech service, with alarm audio independent of the ringer's Silent setting.
Allow notifications and **Alarms & reminders**, keep alarm volume audible, and
install an English text-to-speech voice. If speech is unavailable, the service
plays the system alarm sound. It queues simultaneous reminders and stops audio
on completion or the notification's **Stop voice** action. Calls and the SOS
locator siren take priority over reminder speech. Alarm permissions are checked
again on resume; without exact access, visible inexact notifications remain and
the app explains the limitation. It does not change global volume or DND policy.

iOS generates each spoken reminder into `Library/Sounds` before scheduling it,
so playback does not need a running Flutter process. To play through Silent/Focus,
obtain Apple's [Critical Alerts entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.usernotifications.critical-alerts),
add `com.apple.developer.usernotifications.critical-alerts = true` to the signed
Runner entitlements/provisioning profile, and build with
`--dart-define=MEDICARE_CRITICAL_ALERTS=true`. Users must also grant Critical Alerts
permission. The default build uses ordinary spoken/time-sensitive notifications
and displays the Silent-mode limitation; adding an unsigned entitlement alone
cannot bypass it. Validate the Swift integration on a macOS/iOS build host.

SOS is submitted before location acquisition. GPS falls back to Android's device
provider if fused location fails; a cached fix is accepted only within two minutes
and with accuracy at most 200 m. Reverse-geocoding failure does not discard valid
coordinates. Permission denial, permanently blocked permission, disabled services
and timeouts produce actionable patient feedback and specific shared-chat messages.

SOS chat entries store the latitude, longitude, address, accuracy and capture time
from one GPS snapshot. The address is labelled approximate; the map target always
uses the saved coordinates. Android opens a `geo:` pin labelled with the saved
place name (the first non-empty address component), and iOS uses that same name
in Apple Maps. The full address remains in the chat message. If no name was
captured, the label shows the coordinates. The browser fallback uses Google's
[coordinate Maps URL](https://developers.google.com/maps/documentation/urls/get-started).
Older SOS messages with only `maps.google.com/?q=lat,lng` are normalized by the
updated client. Address names and nearby business listings never replace the point.

## Verification

```powershell
flutter analyze --no-pub
flutter test --no-pub
node --test functions/call_history.test.js
# Set JAVA_HOME to a Java 21+ runtime for the Firebase CLI.
firebase emulators:exec --only firestore --project demo-medicare --config firebase.emulators.json "node --test functions/firestore_access.test.js"
flutter build apk --debug --no-pub
```

Before release, verify two real phones: caller ringback versus receiver ringtone;
accept/reject/cancel/timeout and background/foreground transitions; persistent
history on reopening; edited/deleted/completed and midnight-crossing appointment
reminders; Silent-mode speech with the app closed and after reboot; and SOS with
GPS available, services disabled, permission denied, and internet unavailable.

## Reminder and patient accessibility updates

Once medications become completed from their existing durable Taken history,
including patient actions waiting in the SQLite outbox. Completion is projected
into schedule streams rather than adding another medication-status collection or
changing the SQLite schema. Completed Once medications remain available for review.
Foreground reminders compare full timestamps and set a timer for the next due
boundary, avoiding the negative-minute truncation that previously fired early.

Spoken medication reminders start with “It is time to take your medicine” and
include the name, dosage and type. Dosage units and decimal digits are expanded
only in spoken text; prescription data and medicine names remain unchanged.
Android prefers an installed offline English voice and a slower speech rate.
Medication vibration and incoming call audio use alarm attributes, subject to
notification permission, channel settings, alarm volume and the device's DND
policy. The app does not change global volume or the ringer mode.

Appointment notifications remain until viewed or completed. The optional
`appointments.reminderViewedFor` field acknowledges `date|HH:mm|remindBefore` so
editing the schedule can re-arm the reminder. Existing records remain compatible.
Rules restrict the new acknowledgement to the owning patient and the current
schedule; they do not grant patients permission to edit appointment details.
A device acknowledgement also protects startup from the older SQLite schedule
cache; no SQL migration is needed. Passing the appointment time alone does not
mark an appointment completed. Patient reminder cards open the details and allow
later completion after the reminder has been viewed.

Patient typography applies above the Navigator, including dialogs and chat, with
a readable minimum and larger system text preserved. Buttons, profile details,
mood choices and SOS/call overlays adapt to narrow screens and large fonts.
Call events use participant-aligned bubbles. Chat anchors its newest message at
offset zero and returns there on new messages without reacting to read receipts.

The incoming-call channel is `voice_calls_v3`; release the matching `voiceCall`
function and Firestore rules with the updated Android build. Targeted permission
regressions are in `functions/appointment_reminder_rules.test.js` and must run
against a local demo-project Firestore emulator rather than production data.
