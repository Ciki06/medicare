import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/medication_model.dart';
import '../../models/sos_alert.dart';
import '../../models/user_model.dart';
import '../../models/user_role.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';
import '../../services/reminder_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/bottom_navigation.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/phone_frame.dart';
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
  final Set<String> _notifiedSosIds = {};
  SosAlert? _activeSos; // frontmost in-app banner when _activeSos != null

  /// Alerts any newer than this (created after the shell loaded) are treated as
  /// brand-new SOS events and get a local notification. Alerts that already
  /// exist in Firestore when the user opens the app are surfaced only via the
  /// in-app banner, never as duplicate system popups.
  late final DateTime _listenerStart;

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
    _listenerStart = DateTime.now();
    _setupFcm();
    if (_role == UserRole.patient) {
      if (NotificationService.instance.lastTappedMedicationId != null) {
        _index = 1;
      }
      NotificationService.instance.tapNotifier.addListener(_onNotificationTap);
      _startReminderService();
    } else {
      _startSosListener();
    }
  }

  Future<void> _setupFcm() async {
    final notif = NotificationService.instance;
    final firestore = FirestoreService();
    notif.onForegroundSos = (patientName) {
      // Ensure an in-app banner is present when an FCM SOS arrives in the
      // foreground; the Firestore stream also sets it as a fallback.
      if (mounted && _activeSos == null) {
        setState(() {
          _activeSos = SosAlert(
            id: 'fcm-${DateTime.now().millisecondsSinceEpoch}',
            patientId: '',
            patientName: patientName,
            caregiverId: widget.user.uid,
            alertUserIds: const [],
            status: 'active',
            createdAt: DateTime.now(),
          );
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

  void _startSosListener() {
    final firestore = FirestoreService();
    _sosSub?.cancel();
    _sosSub = firestore
        .streamActiveSosAlertsForUser(widget.user.uid)
        .listen((alerts) {
      if (!mounted) return;
      for (final alert in alerts) {
        // Only raise a system popup for alerts that are recent (within the
        // last 5 minutes) and new to this session. This fires a notification
        // as soon as a fresh SOS arrives while the app is open, without
        // re-notifying old, still-active alerts every time the stream emits.
        final now = DateTime.now();
        final isRecent =
            now.difference(alert.createdAt).inMinutes <= 5 &&
            alert.createdAt.isAfter(_listenerStart);
        if (isRecent && _notifiedSosIds.add(alert.id)) {
          NotificationService.instance.showImmediateNotification(
            id: alert.createdAt.millisecondsSinceEpoch % 100000,
            title: '🚨 SOS Alert',
            body: '${alert.patientName} needs help immediately!',
            payload: 'sos:${alert.id}',
          );
        }
      }
      final banner = alerts.isNotEmpty ? alerts.first : null;
      if (banner?.id != _activeSos?.id) {
        setState(() => _activeSos = banner);
      }
      debugPrint(
        'SOS stream: ${alerts.length} active alert(s) for ${widget.user.uid}: '
        '${alerts.map((a) => a.id).toList()}',
      );
    }, onError: (Object e) {
      debugPrint('SOS stream error for ${widget.user.uid}: $e');
    });
  }

  void _dismissSos(SosAlert alert) async {
    setState(() => _activeSos = null);
    await FirestoreService().acknowledgeSos(alert.id);
  }

  void _onNotificationTap() {
    if (NotificationService.instance.lastTappedMedicationId == null) return;
    if (mounted) setState(() => _index = 1);
  }

  void _startReminderService() {
    final firestore = FirestoreService();
    _medSub?.cancel();
    _aptSub?.cancel();
    _medSub = firestore.getMedicationsByPatient(widget.user.uid).listen((meds) {
      _reminderService.updateMedications(meds);
      NotificationService.instance
          .scheduleDailyReminders(meds, patientId: widget.user.uid);
    });
    _aptSub = firestore.getAppointmentsByPatient(widget.user.uid).listen((apts) {
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
    super.dispose();
  }

  Widget _page() {
    if (_index == 0) {
      return switch (_role) {
        UserRole.patient => PatientHomePage(
            user: widget.user,
            onOpenMood: () => setState(() => _index = 2),
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
          if (!isPatient && _activeSos != null)
            Positioned(
              top: 8,
              left: 12,
              right: 12,
              child: _SosBanner(
                alert: _activeSos!,
                onAcknowledge: () => _dismissSos(_activeSos!),
              ),
            ),
        ],
      ),
    );
  }
}

class _SosBanner extends StatelessWidget {
  const _SosBanner({required this.alert, required this.onAcknowledge});

  final SosAlert alert;
  final VoidCallback onAcknowledge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFE85B61),
      elevation: 10,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.sos, color: Colors.white, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🚨 SOS Alert',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${alert.patientName} needs help immediately!',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onAcknowledge,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: .2),
              ),
              child: const Text(
                'Help',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
