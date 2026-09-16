# MediCare follow-up changes — 2026-09-15

This document describes the follow-up request and supersedes the homepage layout and phone-dialer calling behavior in `FEATURE_UPDATES_2026-09-14.md`. No Firebase deployment or production-data changes were performed.

## Requirements and implementation locations

| Requirement | Result | Main files |
| --- | --- | --- |
| Caregiver/family mood below Patient Schedule | Daily Mood Check-In now follows the patient schedule, with every recorded mood for the displayed patients, newest first, including patient, date and time. No seven-record homepage cutoff. | `lib/screens/home/medication_page.dart`, `lib/widgets/home_monitoring_sections.dart` |
| Completed Appointment filters and previous design | Section header shows a filter icon while collapsed and a close icon while expanded. Controls filter date/range, time text, location, patient and appointment title/type. Closing retains filters. Homepage cards use the original green bordered `_AppointmentCard`, with its completed icon, patient, date/time and location. | `lib/widgets/completed_appointments_section.dart`, `lib/screens/home/medication_page.dart` |
| Recent Medication Activity filters | Icons sit beside the section title. Date/range, status, patient and medication-name criteria combine on both homepages. View More/Show Less apply to the filtered rows. Filters stay selected when collapsed. | `lib/widgets/medication_activity_filter.dart`, `lib/services/history_filter.dart`, `lib/screens/home/medication_page.dart` |
| Caregiver Report icon | The report icon sits next to the medication filter icon and opens the weekly/monthly report, with per-patient medication events, Taken/Missed/Snoozed totals and PDF export. | `lib/screens/home/medication_page.dart`, existing `lib/screens/home/history_page.dart`, `lib/services/report_service.dart` |
| Family History permission error | Rules explicitly authorize family profiles linked through `linkedPatientIds` or legacy `linkedPatientId`, even without `caregiverId`. Family schedule queries now use linked patient IDs. History streams query individual patients to avoid exceeding Firestore's cross-document rule-read budget when a caregiver has many patients. | `firestore.rules`, `lib/services/firestore_service.dart`, `lib/screens/home/medication_page.dart` |
| Offline pending crash | Pending values change synchronously but listener notifications are deferred outside widget build/dispose locks and coalesced. Late acknowledgements and rejections update the count safely; queued-write failures remain visible. | `lib/services/frame_safe_notifier.dart`, `lib/services/offline_service.dart` |
| Readable SOS location in chat | Native reverse geocoding adds a real place/address name. The trusted Function updates one deterministic SOS message per linked chat. Numeric coordinates remain in a separate map URL, while message text displays the name. Old coordinate-containing messages also get readable fallback text. | `lib/services/sos_location_service.dart`, `functions/index.js`, `firestore.rules`, `lib/models/chat_message.dart`, `lib/screens/home/chat_room_page.dart` |
| SOS sound to both caregiver and family | Existing trusted recipient fanout, high-priority Android data delivery, custom alarm channel, iOS APNs custom sound and per-alert deduplication are retained and regression-tested. SOS location chat messages never send a second push. | `functions/index.js`, `lib/services/sos_background_handler.dart`, `lib/services/notification_service.dart`, `lib/services/sos_notification_policy.dart` |
| Spoken medication reminder, including silent mode where possible | Scheduled and snoozed reminders use the bundled “It's time to take your medicine” sound on Android's alarm audio usage. iOS reminders now request time-sensitive interruption, with the same spoken sound. | `lib/services/notification_service.dart`, existing `android/app/src/main/res/raw/medication_voice.wav`, `ios/Runner/medication_voice.wav` |
| Actual in-app voice calls | Chat Call starts audio-only WebRTC; a global MediCare overlay displays outgoing/incoming calls, Accept, Reject, End call, mute, speaker and duration. It does not launch `tel:` or the normal dialer. | `lib/services/voice_call_service.dart`, `lib/widgets/voice_call_overlay.dart`, `lib/main.dart`, `lib/screens/home/chat_room_page.dart` |
| Call backend and background notification | Authenticated callable Function validates chat membership and call state, reserves both users atomically, exchanges offer/answer and issues temporary TURN credentials. Rules protect ICE candidates and forbid direct call-state mutations. Incoming push opens MediCare to answer. Android uses a microphone foreground service during active media capture. | `functions/calls.js`, `functions/index.js`, `firestore.rules`, `firestore.indexes.json`, `android/app/src/main/kotlin/com/example/medicare/VoiceCallForegroundService.kt`, `MainActivity.kt`, `AndroidManifest.xml`, `ios/Runner/Info.plist` |

## Behavior and limits

### Location and reports

- Reverse geocoding returns the OS mapping provider's actual place/address. A specific building name is only shown if the provider supplies it. The app never invents “Nursing Home Main Building.” When geocoding fails, the saved GPS fix still opens a map with the label “Location shared — open map.” If GPS/permission fails, SOS still dispatches and explains that location is unavailable.
- Location is a timestamped SOS snapshot, not continuous movement tracking. SOS creation/notification does not wait for the geocoder.
- Time filtering currently matches appointment time text (for example `09:30` or `AM`); date filtering supports a single-day range or multiple dates.
- Reports count recorded medication actions: legacy `skipped` is displayed/counts as Missed, and repeated snoozes count as events. Unrecorded doses are not inferred as missed. Offline reports contain available cached records.
- The Family History production error will only be resolved after the updated rules are deployed. App-only installation cannot change server permissions.

### Alarm behavior

- Android medication sounds use alarm audio usage so normal ringer silent/vibrate mode does not select the notification stream. The phone's alarm volume, notification-channel settings, Do Not Disturb policy and manufacturer restrictions still control audibility. This does not forcibly raise system volume or change the user's DND settings. [Android audio attributes](https://developer.android.com/reference/android/media/AudioAttributes)
- iOS time-sensitive notifications are not critical alerts: they do not guarantee sound through the mute switch. Bypassing mute/DND for this notification implementation requires Apple's critical-alert entitlement and user authorization, neither of which this repository has. [Apple critical alert authorization](https://developer.apple.com/documentation/usernotifications/unnotificationsettings/criticalalertsetting)
- SOS custom notifications work through the background paths already implemented. Notification permission, network delivery and normal OS background execution are required. Android Settings → Force stop prevents FCM delivery until the app is reopened; no app code can guarantee delivery in that state. [Firebase background delivery prerequisites](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages)

### Calling

- Calls require online access, microphone permission, deployed Functions/rules/indexes and two signed-in users in the chat. No microphone is acquired merely because an incoming call rings; acquisition starts when the recipient presses Accept.
- Signaling records live in `calls/{id}` and `calls/{id}/candidates/{id}`. Server-only `call_sessions/{uid}` documents prevent simultaneous calls. Preparing expires in 30 seconds, ringing in 45 seconds; accepted sessions use 25-second heartbeats and bounded leases. A dead peer cannot keep the other user busy indefinitely. Calls answered on another device close locally.
- Call audio is carried by WebRTC, not stored in Firestore or recorded. TURN credentials expire after one hour. STUN is available by default; reliable calls across carrier/restrictive NAT networks require a deployed TURN relay.
- Incoming background/closed-app pushes display a notification; tapping it opens the in-app Accept/Reject screen if the call is still ringing. This implementation does not use iOS CallKit/PushKit or present native lock-screen call controls. Android keeps active microphone use visible through a foreground notification; ending releases tracks and the service even if the network is unavailable.
- The native mobile implementation was compiled for Android. iOS compilation and two-phone audio/notification behavior need device testing. Web/desktop voice-call support has not been validated.

## TURN configuration

Use an existing coturn-compatible service with `use-auth-secret` enabled. Configure its `static-auth-secret`, public address, TLS certificate, UDP/TCP listener ports and relay UDP port range. Use your actual public host in the following environment file. Credentials remain server-side; authenticated clients receive temporary HMAC credentials.

```powershell
Copy-Item functions/.env.example functions/.env.medicare-348a1
```

Edit the copied file before deployment:

```dotenv
TURN_URLS=turn:YOUR_PUBLIC_TURN_HOST:3478,turns:YOUR_PUBLIC_TURN_HOST:5349
TURN_SHARED_SECRET=THE_SAME_STRONG_SECRET_CONFIGURED_ON_YOUR_TURN_SERVER
```

The real `.env` files are gitignored. Do not put the shared secret in Dart, source control or documentation. Merely copying the example does not provision a relay. Without TURN configuration the app still attempts STUN-only calls, which may fail between different mobile networks. [WebRTC connection API](https://flutter-webrtc.org/docs/flutter-webrtc/api-docs/rtc-peerconnection/)

## Verification

- Flutter regression suite: **11 tests passed**. Checks report export, history filters, SOS countdown, offline disposal/late errors, collapsed appointment controls and homepage medication filters/report action.
- Firebase emulator suite: **12 tests passed, none skipped**. Verifies family/legacy patient links without caregiverId, unauthorized history access, call state/signaling rules, busy/accept/end behavior, recipient fanout, custom SOS payload and repeat suppression. Messaging is stubbed in dispatch tests; no real notifications are sent.
- Static analysis: no errors; three existing unused members remain in `medication_page.dart` (`_showMedicationDetail`, `_showAppointmentDetail`, `_RefillStatusCard`).
- Android ARM64 debug APK compile: **passed**, `build/app/outputs/flutter-apk/app-debug.apk` (149,440,594 bytes; approximately 142.5 MiB). No iOS build or physical-device audio/FCM test was performed on this Windows host.

## Commands to run

From the repository root:

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub --concurrency=1
npm --prefix functions ci
```

Emulator checks require Java 21+ on PATH (the Android build can keep its existing Java 17 toolchain):

```powershell
firebase emulators:exec --config firebase.test.json --project demo-medicare --only firestore,storage "npm --prefix functions test"
```

Build/install:

```powershell
flutter run
flutter build apk --debug --target-platform android-arm64
```

Run these yourself when signed in to the correct Firebase account. **They were not run in this session.** Configure TURN first for dependable calls, and wait for the new Firestore index to finish building before testing incoming calls.

```powershell
firebase login --reauth
firebase deploy --project medicare-348a1 --only "firestore:rules,firestore:indexes,storage,functions"
```

No Firebase Hosting deployment is needed. For iOS, use macOS/Xcode to run `flutter build ios --no-codesign`, then sign/install for physical-device checks. Keep the existing APNs/Firebase setup valid.

## Phone acceptance checks

1. On caregiver and family homepages, verify schedule → all daily moods → completed appointments → recent medication activity. Expand/collapse both filter icons. Combine patient/date/status/name filters and verify View More/Show Less.
2. Confirm completed cards match the prior green bordered design. Filter by date, time, location, patient and title.
3. Link a family account without `caregiverId`; check all history sections after deploying rules. Verify an unrelated family account cannot query those records.
4. Export weekly and monthly reports, comparing each patient's totals with known events.
5. Queue a medication action offline, navigate away immediately, reconnect, and confirm the pending count reaches zero without a widget-lock exception. Repeat with a server-rejected write.
6. Trigger SOS and check the caregiver and family each receive one alarm notification and one named-location chat entry. Deny GPS and disable network/geocoding in separate tests; alert creation must continue.
7. Test SOS and scheduled/snoozed voice reminders with each recipient app foreground/background/closed, normal ringer/silent mode, alarm volume, DND and notification permissions. Test Android and iOS separately.
8. Call between two real phones: accept, reject, end from either side, mute/unmute, earpiece/speaker, background the accepted call, ring timeout, concurrent caller/busy, microphone denial, disconnect, sign-out and multi-device acceptance. Verify the microphone indicator and foreground notification stop after ending.
9. Repeat calls over different Wi-Fi networks and Wi-Fi ↔ cellular with TURN configured. Test an incoming push while the recipient app is closed; answer inside MediCare before expiry. Confirm old notification taps never resurrect ended calls.
