import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/medication_model.dart';
import '../../models/sos_alert.dart';
import '../../models/user_model.dart';
import '../../models/user_role.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';
import '../../services/reminder_service.dart';
import '../../services/sos_launch_service.dart';
import '../../services/sos_notification_policy.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/bottom_navigation.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/phone_frame.dart';
import '../../widgets/sos_emergency_screen.dart';
import 'account_page.dart';
import 'history_page.dart';
import 'medication_page.dart';
import 'mood_page.dart';
import 'patient_home_page.dart';
import 'pharmacy_refill_page.dart';
import 'profile_page.dart';
import 'reminder_page.dart';
import 'role_dashboard.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.user});

  final UserModel user;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  final _reminderService = ReminderService();
  StreamSubscription<List<Medication>>? _medSub;
  StreamSubscription<List<Appointment>>? _aptSub;
  StreamSubscription<List<SosAlert>>? _sosSub;
  late final SosNotificationPolicy _sosNotificationPolicy;
  SosAlert? _activeSos; // frontmost in-app banner when _activeSos != null
  int _externalSosRequestSequence = 0;
  int _pendingExternalSosRequestId = 0;

  UserRole get _role => widget.user.role;

  String get _title {
    if (_index == 0) return '';
    return switch (_role) {
      UserRole.caregiver => ['', 'Refill Status', 'Account', 'Profile'][_index],
      UserRole.patient => ['', 'Reminders', 'Health', 'Profile'][_index],
      UserRole.family => ['', 'History', 'Profile'][_index],
      UserRole.pharmacist => ['', 'Refill Request', 'Profile'][_index],
    };
  }

  @override
  void initState() {
    super.initState();
    _sosNotificationPolicy = SosNotificationPolicy(startedAt: DateTime.now());
    _setupFcm();
    SosLaunchService.instance.onSosRequested = _requestExternalSos;
    final hasPendingSosRequest = SosLaunchService.instance
        .consumePendingSosRequest();
    // Notification taps are handled for every role: medication reminders jump
    // to the Reminders tab (patient), SOS taps surface the emergency screen.
    NotificationService.instance.tapNotifier.addListener(_onNotificationTap);
    if (_role == UserRole.patient) {
      if (hasPendingSosRequest) {
        _requestExternalSos();
      }
      if (NotificationService.instance.lastTappedMedicationId != null) {
        _index = 1;
      }
      _startReminderService();
    } else {
      _startSosListener();
      // Cold start from a tapped local SOS notification: present the emergency
      // screen after the first frame.
      final launchPayload =
          NotificationService.instance.lastTappedMedicationId;
      if (launchPayload != null && launchPayload.startsWith('sos:')) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _presentSosFromPayload(launchPayload);
        });
      }
    }
  }

  void _requestExternalSos() {
    if (!mounted || _role != UserRole.patient) return;
    setState(() {
      _index = 0;
      _externalSosRequestSequence++;
      _pendingExternalSosRequestId = _externalSosRequestSequence;
    });
  }

  void _consumeExternalSosRequest(int requestId) {
    if (!mounted || requestId != _pendingExternalSosRequestId) return;
    setState(() => _pendingExternalSosRequestId = 0);
  }

  Future<void> _setupFcm() async {
    final notif = NotificationService.instance;
    final firestore = FirestoreService();
    notif.onForegroundSos = (data) {
      // An SOS message arrived while the app is open: surface the full-screen
      // red emergency screen to caregiver / family instantly. Gated by the same
      // seen-once policy as the Firestore stream so a re-delivered FCM message
      // can never re-pop the screen after it has been resolved.
      final alert = _sosFromData(data);
      if (mounted && _role != UserRole.patient && alert != null) {
        if (!_sosNotificationPolicy.shouldSurface(
          alert,
          now: DateTime.now(),
        )) {
          return;
        }
        _presentSos(alert);
      }
    };
    notif.onSosOpened = (data) {
      // The user tapped a background SOS notification (cold start or warm
      // resume), so present the emergency screen even if the alert is older.
      final alert = _sosFromData(data);
      if (mounted && _role != UserRole.patient && alert != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _presentSos(alert);
        });
      }
    };
    notif.onTokenRefreshed = (token) {
      firestore.saveFcmToken(widget.user.uid, token);
    };
    try {
      await notif.initFcm();
      final token = await notif.getOrCreateFcmToken();
      if (token != null) {
        await firestore.saveFcmToken(widget.user.uid, token);
      }
      await notif.getTokenStream();
    } catch (_) {
      // FCM unavailable; local-notification + stream fallback still applies.
    }
  }

  SosAlert? _sosFromData(Map<String, dynamic> data) {
    final alertId = data['alertId'] as String?;
    if (alertId == null || alertId.isEmpty) return null;
    return SosAlert(
      id: alertId,
      patientId: data['patientId'] as String? ?? '',
      patientName: data['patientName'] as String? ?? 'Patient',
      caregiverId: widget.user.uid,
      alertUserIds: const [],
      status: 'active',
      createdAt: DateTime.now(),
    );
  }

  void _presentSos(SosAlert alert) {
    if (!mounted || _activeSos?.id == alert.id) return;
    setState(() => _activeSos = alert);
  }

  void _startSosListener() {
    final firestore = FirestoreService();
    // Background/killed-state presentation is owned by the FCM background
    // handler (`sosBackgroundMessageHandler`), which shows a full-screen alarm
    // notification. Here in the foreground we surface the full-screen red
    // emergency view; nothing to do while the app is backgrounded to avoid
    // double alarms.
    _sosSub?.cancel();
    _sosSub = firestore
        .streamActiveSosAlertsForUser(widget.user.uid)
        .listen(
          (alerts) {
            if (!mounted) return;
            if (WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed) {
              return;
            }
            // Keep the current alert on screen while it is still active; else
            // pick a fresh, not-yet-shown alert or clear the screen.
            SosAlert? target = _activeSos;
            for (final alert in alerts) {
              if (target?.id == alert.id) break;
              if (_sosNotificationPolicy.shouldSurface(
                alert,
                now: DateTime.now(),
              )) {
                target = alert;
                break;
              }
            }
            if (target?.id != _activeSos?.id) {
              setState(() => _activeSos = target);
            }
            debugPrint(
              'SOS stream: ${alerts.length} active alert(s) for ${widget.user.uid}: '
              '${alerts.map((a) => a.id).toList()}',
            );
          },
          onError: (Object e) {
            debugPrint('SOS stream error for ${widget.user.uid}: $e');
          },
        );
  }

  void _dismissSos() {
    setState(() => _activeSos = null);
  }

  void _presentSosFromPayload(String payload) {
    if (!mounted || !payload.startsWith('sos:')) return;
    final alertId = payload.substring(4);
    if (alertId.isEmpty) return;
    _presentSos(
      SosAlert(
        id: alertId,
        patientId: '',
        patientName: 'Patient',
        caregiverId: widget.user.uid,
        alertUserIds: const [],
        status: 'active',
        createdAt: DateTime.now(),
      ),
    );
  }

  void _onNotificationTap() {
    final payload = NotificationService.instance.lastTappedMedicationId;
    if (payload == null) return;
    if (payload.startsWith('sos:')) {
      _presentSosFromPayload(payload);
      return;
    }
    if (mounted) setState(() => _index = 1);
  }

  void _startReminderService() {
    final firestore = FirestoreService();
    _medSub?.cancel();
    _aptSub?.cancel();
    _medSub = firestore.getMedicationsByPatient(widget.user.uid).listen((meds) {
      _reminderService.updateMedications(meds);
      NotificationService.instance.scheduleDailyReminders(
        meds,
        patientId: widget.user.uid,
      );
    });
    _aptSub = firestore.getAppointmentsByPatient(widget.user.uid).listen((
      apts,
    ) {
      _reminderService.updateAppointments(apts);
      NotificationService.instance.scheduleAppointmentReminders(apts);
    });
    _reminderService.start(medications: []);
    NotificationService.instance.requestPermissions();
  }

  @override
  void dispose() {
    _medSub?.cancel();
    _aptSub?.cancel();
    _sosSub?.cancel();
    _reminderService.stop();
    NotificationService.instance.tapNotifier.removeListener(_onNotificationTap);
    SosLaunchService.instance.onSosRequested = null;
    super.dispose();
  }

  Widget _page() {
    if (_index == 0) {
      return switch (_role) {
        UserRole.patient => PatientHomePage(
          user: widget.user,
          onOpenMood: () => setState(() => _index = 2),
          externalSosRequestId: _pendingExternalSosRequestId,
          onExternalSosRequestHandled: _consumeExternalSosRequest,
        ),
        UserRole.caregiver => MedicationPage(user: widget.user),
        UserRole.family => MedicationPage(user: widget.user, readOnly: true),
        UserRole.pharmacist => RoleDashboard(
          role: _role,
          user: widget.user,
          onNavigateToRequest: _role == UserRole.pharmacist
              ? () => setState(() => _index = 1)
              : null,
        ),
      };
    }
    return switch (_role) {
      UserRole.caregiver => switch (_index) {
        1 => PharmacyRefillPage(user: widget.user),
        2 => AccountPage(user: widget.user),
        _ => ProfilePage(user: widget.user),
      },
      UserRole.patient => switch (_index) {
        1 => ReminderPage(user: widget.user),
        2 => MoodPage(user: widget.user),
        _ => ProfilePage(user: widget.user),
      },
      UserRole.family => switch (_index) {
        1 => HistoryPage(user: widget.user),
        _ => ProfilePage(user: widget.user),
      },
      UserRole.pharmacist => switch (_index) {
        1 => PharmacyRefillPage(user: widget.user),
        _ => ProfilePage(user: widget.user),
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    final isPatient = _role == UserRole.patient;
    // Caregivers and family see a full-screen red SOS emergency view while an
    // alert is active — no navigation, no banners, just the alarm.
    if (!isPatient && _activeSos != null) {
      return PhoneFrame(
        backgroundColor: AppTheme.paleBlue,
        child: SosEmergencyScreen(
          alertId: _activeSos!.id,
          patientName: _activeSos!.patientName,
          senderId: widget.user.uid,
          senderName: widget.user.name,
          senderRole: _role.name,
          onAcknowledge: () => _dismissSos(),
        ),
      );
    }
    return PhoneFrame(
      backgroundColor: AppTheme.paleBlue,
      child: Stack(
        children: [
          Column(
            children: [
              AppHeader(
                title: _index == 0 ? null : _title,
                greeting: _index == 0 ? 'Hi, ${widget.user.name}' : null,
                showAvatar: _index == 0,
              ),
              Expanded(child: _page()),
              MediCareBottomNavigation(
                index: _index,
                role: _role,
                onChanged: (index) => setState(() => _index = index),
              ),
            ],
          ),
          if (isPatient)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: NotificationOverlay(
                patientId: widget.user.uid,
                reminderService: _reminderService,
              ),
            ),
        ],
      ),
    );
  }
}
