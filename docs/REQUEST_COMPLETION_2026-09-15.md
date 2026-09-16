# Homepage, SOS, medication and chat updates

## Source changes

The working tree already contained the homepage filters, report/PDF export, named SOS locations, family-history rules and WebRTC calling described in [FOLLOWUP_UPDATES_2026-09-15.md](FOLLOWUP_UPDATES_2026-09-15.md). This pass preserved those changes and completed the remaining behavior:

- Caregiver and family use the shared schedule → full mood history → completed appointments → medication activity layout. Completed cards retain the green bordered design; filters combine date, time and location. Medication filters combine patient, date/range, status and name. The caregiver report icon opens weekly/monthly totals and PDF export.
- Patient SOS state now rebuilds on status changes to the same alert. Response creation and acknowledgement commit atomically. New responses use server timestamps; legacy numeric timestamps remain readable. A timer removes responses after five minutes and checks again when the patient returns to the app.
- Every foreground/background SOS opening validates the current account, role, recipient list, age and active server status. Account-specific opened IDs prevent repeats. Account changes clear notification payloads, pending reminders, callback ownership and the patient alarm. The patient’s in-app Stop SOS action also marks active alerts stopped. Android's notification action silences the locator sound only.
- SOS Functions check current status before dispatch and set a five-minute delivery lifetime. The active screen closes when a stream reports that the alert has been stopped or acknowledged.
- Sent chat ticks are grey; seen ticks are dark blue. Images show only captions, including an explicitly entered caption of “Image.” Voice bubbles show a play/stop control and seconds. New recordings persist duration; old recordings try to load audio metadata, showing a dash if unavailable.
- Each message has a forwarding action. The user selects another contact/chat, and attachments are copied to that chat's Storage path. Forwarded messages carry the current sender and a Forwarded label; forwarding an SOS location produces an ordinary message, not a new emergency alert. Attachment notifications still send when there is no caption.
- Add and Edit Medication share recurrence fields: Once, Daily, Weekly, Monthly, Every X days, start date and interval. Edit uses the clock picker. Add now actually saves the selected frequency; it previously always saved Daily. Existing weekday lists are preserved when editing.
- Schedule parsing, display, date boundaries and reminder instants use **Asia/Kuala_Lumpur, UTC+08:00** across roles. Times display as `20:00 (8:00 PM)`. Legacy AM/PM values are parsed consistently.
- OS reminders have stable IDs, serialized reconciliation and stale-ID cancellation. They respect recurrence, schedule appointments beyond the next day, refresh after permissions/settings changes, and stop rescheduling after logout. Daily, weekday/weekly and monthly schedules use OS repetition. Future-start and custom-interval schedules use dated occurrences.

## Release requirements and practical limits

No Firebase rules, indexes, Storage rules or Functions were deployed, and no production records were migrated. Deploy those together using the existing instructions in the follow-up document. The live permission errors require the updated server rules; installing the app alone cannot change them. TURN must be configured for reliable voice calls across restrictive networks.

Legacy non-daily medications without a start date require the caregiver to open Edit Medication and save the schedule. The patient sees a setup notice. Monthly schedules on the 29th–31st skip months lacking that date; the form explains this behavior.

The scheduler reserves space below iOS's 64-pending-notification limit and schedules the nearest occurrences first. It shows a notice when more reminders remain. Custom intervals and future-start regimens must be replenished by opening the app regularly; the planner covers up to 400 days, subject to OS capacity. A regimen edited remotely while the patient's app is terminated takes effect when the patient's app next synchronizes. Existing scheduled reminders run without keeping Flutter open.

Android spoken reminders use the alarm audio stream. Alarm volume, DND and notification settings still apply. iOS mute/DND bypass needs Apple's critical-alert entitlement and user permission; this repository uses ordinary time-sensitive notifications. Force-stop, denied permissions and OS/vendor restrictions cannot be overridden by these app changes. See [Firebase background prerequisites](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages), [local notification scheduling limits](https://pub.dev/packages/flutter_local_notifications), and [Apple critical alerts](https://developer.apple.com/documentation/usernotifications/unauthorizationoptions/criticalalert).

## Validation

- Flutter regression suite: **20 passed**.
- Firebase Firestore/Storage emulator suite: **13 passed, none skipped**. Messaging was stubbed; no real push notifications were sent.
- Android ARM64 debug APK: compiled successfully. Build output is `build/app/outputs/flutter-apk/app-debug.apk`.
- Whole-app static analysis: no errors; three pre-existing unused private declarations in `medication_page.dart`. The remaining new brace-style diagnostic was corrected and checked separately.

Regression tests cover filters, report/PDF generation, recurrence and timezone handling, stable reminder IDs, future appointments, response expiry, server/legacy response timestamps, SOS recipient/status checks and chat metadata. Firebase emulator tests cover location/history permissions, atomic responses, invalid forwarded-message metadata, call signaling/lifecycle and stopped-alert dispatch suppression.

Before release, test two phones for in-app calling (including TURN), live SOS response/expiry, account switching, named locations, forwarding attachments and actual reminder audio in foreground/background/closed states. iOS compilation and device notification behavior require macOS/Xcode and an iPhone.
