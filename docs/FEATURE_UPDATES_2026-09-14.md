> Follow-up: homepage placement, filters, family access and calling were revised in [FOLLOWUP_UPDATES_2026-09-15.md](FOLLOWUP_UPDATES_2026-09-15.md). Calling now stays inside MediCare; the dialer references below describe the earlier implementation.

# MediCare feature updates — 14 September 2026

## Scope and release status

This change implements the eleven requested feature areas in the Flutter app, Android/iOS configuration, and Firebase backend/rules. **Nothing has been deployed to Firebase.** The existing project is `medicare-348a1`.

The active platform projects are `android/` and `ios/`. The nested legacy copies `android/android/` and `ios/ios/` are not build targets and were not edited.

## 1. SOS, location sharing, alarm, and duplicate notifications

### Requirement

Share the patient's current location with the linked caregiver and family in chat; sound a continuous local locator alarm until manually stopped; use the SOS sound in background notifications; show one recipient notification per SOS.

### Implementation

- `lib/services/firestore_service.dart`: creates the SOS immediately with `locationStatus: pending`. Location acquisition is independent of dispatch, so denied permissions or slow GPS cannot hold up the alert. The SOS write is queued locally if offline.
- `lib/services/sos_location_service.dart`: requests foreground location permission and captures a high-accuracy GPS snapshot with a 12-second acquisition timeout. Stores latitude, longitude, accuracy in metres, and capture time. Disabled GPS, denial and acquisition failures are explicit states; no coordinates are fabricated.
- `functions/index.js`: the existing `sendSosNotification` resolves recipients from the patient's caregiver and linked family, including the legacy family relationship. New `syncSosLocationToChats` creates one deterministic `sos_<alertId>` message in each patient/contact chat, then updates that same message when GPS completes. A transaction reads the latest SOS state to prevent stale trigger invocations overwriting a captured location. It preserves newer ordinary-chat previews and increments unread counts only once.
- Chat messages include a map link, accuracy, and capture time. The location is **a snapshot at the SOS**, not continuous background movement tracking. `chat_room_page.dart` supplies an Open location button.
- `lib/services/patient_alarm_service.dart`: starts the patient locator alarm separately from the countdown. Its lifecycle is independent of navigating between app tabs. `app_shell.dart` displays **Stop SOS alarm**. `patient_home_page.dart` starts it when the countdown completes and clearly distinguishes a saved/queued SOS from confirmed delivery.
- Android `PatientAlarmService.kt`: a media-playback foreground service loops `res/raw/sos_alarm.wav` on the alarm audio stream, holds a playback wake lock, and offers a **Stop alarm** notification action. Backgrounding or swiping the task away does not intentionally stop the service. Manual stop removes the notification and releases the player.
- iOS: the looping player uses a playback audio session, and `Info.plist` enables background audio.
- `sos_background_handler.dart`: handles **Android only**. iOS already renders `aps.alert` and its bundled sound; posting another local notification there was a duplicate path.
- `notification_identity.dart`: stable per-alert Android notification IDs, `onlyAlertOnce`, and a bounded persistent list of 200 displayed SOS IDs suppress repeat delivery, including across process restarts. In-app FCM/Firestore presentation continues to share the existing deduplication policy. Opening an SOS cancels its Android tray notification.
- SOS chat entries do **not** cause ordinary chat pushes. APNs uses the alert ID as its collapse ID. A completed backend dispatch is skipped when an event is retried. Ordinary chat pushes explicitly use `chat_messages`, and the Android default FCM channel is also changed to chat so chat cannot inherit the SOS sound.
- SOS channel is versioned to `sos_alarm_v2`, with alarm audio usage, because Android channel sound settings cannot be changed after creation.

### Platform limits to verify on phones

Notifications still depend on notification permission, network connectivity, OS battery restrictions, device volume, Focus/DND, and vendor behaviour. Android force-stop disables FCM delivery until the app is reopened. No app can guarantee a continuous process after a user/OS force-stop or a reboot. iOS notification sounds are finite (under 30 seconds); the patient's already-running audio session provides continuous playback while backgrounded, but cannot survive a force-quit. The code does not override the user's system volume or request Apple's critical-alert entitlement.

An SOS saved without internet cannot reach contacts until it syncs. GPS sharing also requires permission; the chat explicitly explains unavailable location. A process killed before location capture finishes may leave the location pending. Actual delivery and sound must be validated on the target phones before release.

## 2. Chat improvements

Files: `lib/screens/home/chat_room_page.dart`, `lib/models/chat_message.dart`, `lib/services/firestore_service.dart`, `lib/services/storage_service.dart`, `firestore.rules`, `storage.rules`.

- **Read status:** pending clock while Firestore has uncommitted writes, ✓ Sent after acknowledgement, ✓✓ Seen after the other participant reads through that message. A message is marked read when the chat route is current, the app is foregrounded, and the newest messages are visible. Background or covered chat routes do not mark messages read.
- **Typing…:** throttled updates with a six-second expiry, cleared on inactivity, backgrounding and disposal. This avoids stuck typing indicators after a lost connection.
- **Date/time:** calendar-day separators and local time on every message.
- **Call:** top-right phone button opens the device dialler using the contact's saved phone number. This is a telephone call, not an in-app VoIP service. Missing numbers and unavailable diallers produce a clear message.
- **Images:** gallery picker, attachment preview, removal before send, compression/resizing, 10 MB limit, persistent display cache, and tap-to-enlarge viewer. The original text draft and attachment remain available in the current chat if sending fails.
- **Voice:** microphone permission, start/stop recording, 60-second automatic recording limit, explicit send, attachment removal, and play/stop controls. AAC/M4A uploads use an audio content type. Backgrounding ends the current recording and retains its draft while the page remains alive.
- Text is limited to 1,000 characters. Message creation, room preview and unread increment commit together in a Firestore batch.
- Old text-only messages remain compatible; absent `type` means `text`.
- New `chats/{chatId}/presence/{uid}` documents hold `readThrough` and `typingAt`. Rules permit each participant to write only their own presence document.
- `chat_media/{chatId}/{senderId}/{fileName}` storage is restricted to chat participants, the authenticated sender's upload folder, permitted content types and size. Client messages cannot impersonate a system `sos_location` message.

Media upload and initial creation of a new chat require internet. Existing cached chat messages and queued text messages work offline. Voice playback requires network access; only images are persistently cached in this change. Unsent attachment drafts are not promised to survive process termination.

## 3. Offline functionality

Files: `lib/services/offline_service.dart`, `lib/widgets/offline_banner.dart`, `lib/widgets/offline_image.dart`, `lib/main.dart`, `lib/services/auth_service.dart`, and the image consumers under `lib/screens/home/` and `lib/widgets/notification_overlay.dart`.

- Enables Firestore persistence before use. An existing authenticated session can load its cached profile on restart.
- Uses cached Firestore snapshots for medication schedules, actions, appointments, moods and chats already loaded on the device.
- Medication action logs, stock updates, mood save/delete, SOS writes and chat batches use a queue-aware write wrapper. The UI waits at most two seconds for server acknowledgement, then continues while Firestore retains the write. Later server rejection is shown in a visible sync-error banner.
- The banner reports lack of a network interface and pending writes tracked in the current process. Wi-Fi availability alone does not prove internet reachability; waiting for server confirmation is displayed independently. The pending counter restarts with the process; Firestore's native queue persists independently of that counter.
- Network images and profile-image providers now use the same disk cache, including medicine pictures in the reminder notification overlay. The cache allows up to 2,000 objects with a 365-day stale period. Previously loaded pictures remain viewable offline as long as the OS/cache has not evicted them. Missing images show a fallback.
- Scheduled medication/snooze notifications, the local reminder service and patient SOS sound run locally after setup. PDF creation uses a bundled font and does not need to download fonts.

**Offline scope:** first login, account creation, uploading media, contacting other devices, fetching never-loaded records and opening external map data require a connection. Offline reports describe only the cached records. Web image persistence depends on the browser; the disk-cache behaviour above targets Android/iOS. The existing medication recurrence and stock business rules remain in place.

## 4. Caregiver reports

Files: `lib/screens/home/history_page.dart`, `lib/services/report_service.dart`, `lib/services/history_filter.dart`, `lib/screens/home/medication_page.dart`, `assets/fonts/`.

Open **Report** at the top of the caregiver schedule screen.

- Select Weekly or Monthly and any historical anchor date.
- Weekly means Monday through Sunday; monthly means the calendar month. Current periods include records available so far.
- Select all linked patients or one patient.
- Displays Total Taken, Total Missed and Total Snoozed, plus each patient's totals and individual medication activity.
- **Export PDF** opens the platform share/save sheet with the same selected period and patients. The PDF contains its inclusive date range, summary, per-patient table, medication names, status, date/time, repeated table headings and page numbers. It supports multiple pages without limiting records to the visible history preview.
- Noto Sans is bundled under its OFL licence for offline export and accented Latin names. Additional script-specific fonts may be needed for names outside this font's coverage.

### Counting definitions

Counts are **recorded medication actions**, not inferred prescriptions or unique doses. Legacy `skipped` records are shown/count as **Missed**; `missed` is also understood by filters. Each recorded snooze is counted. A snoozed medicine later taken contributes one snooze event and one taken event. No automatic missed record is invented merely because a dose has no logged action. These definitions appear in the screen and PDF to avoid misleading adherence statistics.

## 5–6. Family history expansion and medication filters

Files: `history_page.dart`, `medication_page.dart`, `history_filter.dart`, `date_range_filter.dart`.

- Family accounts now see the recent medication activity section on the main schedule screen with **View More / Show Less**, as caregivers already did.
- The dedicated History screen begins with five records. **View More** adds up to twenty more at a time; **Show Less** returns to five. Filtering resets the preview size. The full fetched set is used for totals, regardless of visible count.
- Open **History, Mood & Filters** from either account's schedule screen, or the family's History tab.
- Combine patient, inclusive date/date range, Taken/Missed/Snoozed status and case-insensitive medication-name filters.
- Empty results are explained and dates can be cleared. The caregiver lookup uses the caregiver's own UID.
- `getMedicationActionsByPatients`, `getMoodHistory` and `getAppointmentsByPatients` merge **all** Firestore chunks of up to thirty IDs, replacing the previous silent first-thirty-patients limit.

## 7. Patient voice medication notifications

Files: `notification_service.dart`, `assets/sounds/medication_voice.wav`, `android/app/src/main/res/raw/medication_voice.wav`, `ios/Runner/medication_voice.wav`, and the iOS Xcode resource list.

- Both daily and snoozed medication notifications use a bundled spoken recording: **“It's time to take your medicine. Please check your medicine and dosage.”**
- Android uses the new `medication_voice_v1` channel, high importance and alarm audio usage. Versioning avoids preserving the old normal-chime channel sound on upgraded installations.
- iOS scheduled notifications reference the bundled WAV sound.
- The voice is generated locally from Windows speech synthesis and bundled, so runtime TTS services/internet are unnecessary. The existing medicine name and dosage remain visible in the notification body.
- Audibility depends on the phone's notification permissions and system sound settings. Notification sound timing requires real-device verification, especially with battery restrictions or exact-alarm permission denied.

## 8. Enlarged medicine image

Files: `reminder_page.dart`, `notification_overlay.dart`, `offline_image.dart`.

Tap the medicine picture on the reminder card, medicine detail view or medication banner to open a full-screen, aspect-preserving image viewer with pinch zoom and a back button. It uses the same cache as the thumbnail, so an already-loaded image can also be enlarged offline. Accessibility semantics identify the image as an enlarge button.

## 9. Patient Health (Daily Mood)

Files: `history_page.dart`, `firestore_service.dart`.

The caregiver/family history screen includes **Patient Health (Daily Mood)** with patient name, mood, emoji and recorded date. Patient and date filters are shared with medication history, placing both histories in one view. Mood history begins with seven entries and can be expanded/collapsed. Missing mood records are explicitly shown as missing, not treated as a neutral mood.

## 10. Completed appointment filters

Files: `lib/widgets/completed_appointments_section.dart`, `medication_page.dart`, `history_page.dart`.

Both caregiver and family accounts can filter completed appointments on the schedule screen and in History. Combine patient, inclusive date range, appointment type/title text and location text. Results are newest first, and only appointments with stored `status: completed` appear. The existing schema stores appointment descriptions in `title`, so the type control searches that field; no new type taxonomy or migration is introduced.

## 11. Clipped launch logo

Files: `android/app/src/main/res/drawable/splash_logo_safe.xml`, `res/values-v31/styles.xml`, `res/mipmap-anydpi-v26/ic_launcher.xml`.

Android 12+ applies a system-controlled splash mask. The launch logo now sits in a centred **128 dp square inside a 288 dp canvas**, so its corners fit within the system's 192 dp safe circle. Adaptive launcher foregrounds also receive an inset. This preserves the full square artwork on circular-mask phones. The launcher controls the final outer icon shape; the app cannot force every launcher to display a square. Existing iOS launch images were not circle-masked and are unchanged.

## Dependencies and native configuration

`pubspec.yaml` / `pubspec.lock` add geolocator, cached_network_image, flutter_cache_manager, record, path_provider, url_launcher, pdf, printing, connectivity_plus and shared_preferences. Generated desktop plugin registrants are updated by Flutter.

Android declares foreground location, microphone, internet, foreground playback and wake-lock permissions, plus the patient alarm service. iOS declares location, photo-library and microphone usage descriptions, background audio, telephone query support and the bundled voice sound. A **full native rebuild/reinstall** is needed; hot reload alone does not install these changes.

Firebase rules are backward-compatible with existing text messages and SOS creation that omitted `locationStatus`. Existing stored actions do not need rewriting.

## Verification

- Flutter tests: **8 passed**, including inclusive end-date/leap-day filters, event totals, stable notification identities, completed-appointment combined filters, report generation and existing SOS countdown cancellation/completion.
- Replaced an obsolete placeholder login test that assumed login without Firebase setup with a real appointment-filter widget test.
- Export QA: generated a synthetic 100-row report using the app's actual export code, confirmed 34 Taken / 33 Missed / 33 Snoozed and all 100 rows by PDF extraction, and visually inspected all four rendered pages. Table headings, accented text, row wrapping and pagination were clear.
- Firebase emulator checks: **7 passed** against the **demo-medicare** emulator project, not production, including access rules, notification helpers, SOS chat retry idempotency and out-of-order GPS updates preserving newer chat previews.
- Static analysis: no compilation errors in the latest completed run; three pre-existing unused private declarations remain in `medication_page.dart`.
- Android ARM64 debug APK: **build passed** (`flutter build apk --debug --target-platform android-arm64 --no-pub`). Output: `build/app/outputs/flutter-apk/app-debug.apk` (about 108 MiB). Verified the packaged spoken reminder, PDF font and safe splash drawable. The first build attempt exhausted disk space; after space became available, the complete native build succeeded. This is a debug build, not a signed production release.
- iOS compilation, device GPS, permission dialogs, phone calls, actual microphone recordings, cross-device read status, background push delivery/sound and launcher masks need the physical-device acceptance checks below.

## Commands to run locally

From the repository root:

```powershell
flutter pub get
flutter analyze --no-fatal-warnings --no-fatal-infos
flutter test --concurrency=1
npm --prefix functions ci
npm --prefix functions test
```

The ordinary Node test run skips emulator-only cases. For full rules/backend checks, use Java 21+ (set JAVA_HOME and put its bin directory on PATH) and Firebase CLI:

```powershell
firebase emulators:exec --config firebase.test.json --project demo-medicare --only firestore,storage "npm --prefix functions test"
```

Build/run after freeing sufficient disk space:

```powershell
flutter run
flutter build apk --debug --target-platform android-arm64
flutter build appbundle --release
```

The repository still uses its existing debug signing configuration for Android release builds. Configure your release signing before distributing. On macOS with Xcode configured, run `flutter build ios --no-codesign` for an iOS compile check, then sign/archive normally for device distribution.

### Firebase deployment — run yourself when ready

**These commands were not executed.** Deploy the rules and Functions together before exercising the new features against production. Storage's Firestore-backed chat membership rules may prompt the Firebase CLI to enable the required cross-service permissions on first deployment.

```powershell
firebase login --reauth
npm --prefix functions ci
firebase deploy --project medicare-348a1 --only "firestore:rules,firestore:indexes,storage,functions"
```

The Functions package retains its existing Node 20 runtime declaration. Match the supported runtime/tooling used for your deployment environment and review Firebase CLI runtime notices. No hosting deployment is needed for these phone-app changes.

## Physical-device acceptance checklist

1. Rebuild/install on patient, caregiver and family phones. Test fresh install and upgrade over the old notification channels.
2. Trigger SOS while granting GPS: confirm one chat entry per linked recipient with a valid captured location, and one SOS notification per recipient. Repeat with denied permission and disabled GPS; SOS must still dispatch with clear unavailable-location text.
3. Background and swipe away the patient app while its siren is sounding; check it continues where the OS permits. Stop from both the app and Android notification action. Verify no alarm is stopped merely by changing tabs.
4. Background/close caregiver and family apps, trigger SOS and verify the custom sound. Repeat duplicate delivery of the same alert ID; no second chat entry or tray notification should appear. Repeat on iOS to verify APNs alone displays the background notification.
5. Open a chat on two phones: check pending/sent/seen, typing expiry, day separators, image preview/zoom, voice recording/playback and phone-dialler launch. Leave a chat backgrounded and confirm it does not mark new messages seen.
6. Load data and images online, then enable airplane mode. Reopen with the existing session, view cached pictures, record a medication action/mood and snooze a reminder. Reconnect and confirm the entries sync once; any rejected write must be visible.
7. Compare weekly/monthly report totals with known taken/skipped/snoozed events for multiple patients, including a last-day late-night entry. Export and save/share the PDF. Verify an offline export is understood as cached data only.
8. Exercise View More/Show Less and combined patient/date/status/name filters on both account roles. Compare mood dates beside medication history and completed appointment patient/date/type-title/location filters.
9. Schedule a medication and snooze notification a few minutes ahead, background the patient phone, and verify the spoken message. Check actual device volume/Focus settings and exact-alarm permission.
10. Check splash/launcher appearance on Android 12+ phones with circular and square launcher masks, plus older Android and iOS.

## Reference documentation

- [Firebase Flutter foreground/background message behaviour](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages)
- [Android foreground-service declaration](https://developer.android.com/develop/background-work/services/fgs/declare)
- [Android splash safe-area dimensions](https://developer.android.com/develop/ui/views/launch/splash-screen)
- [Apple custom notification sounds](https://developer.apple.com/documentation/usernotifications/unnotificationsound)
- [Geolocator API](https://pub.dev/packages/geolocator)
- [Cached Network Image](https://pub.dev/packages/cached_network_image)
- [AudioRecorder API](https://pub.dev/documentation/record/latest/record/AudioRecorder-class.html)
- [Dart PDF package](https://pub.dev/packages/pdf)
