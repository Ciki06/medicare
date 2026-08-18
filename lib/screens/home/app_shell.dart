import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/medication_model.dart';
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
import 'caregiver_home_page.dart';
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

  UserRole get _role => widget.user.role;

  String get _title {
    if (_index == 0) return '';
    return switch (_role) {
      UserRole.caregiver => ['', 'Medication', 'Account', 'Profile'][_index],
      UserRole.patient => ['', 'Reminders', 'Health', 'Profile'][_index],
      UserRole.family => ['', 'History', 'Profile'][_index],
      UserRole.pharmacist => ['', 'Refill Requests', 'Profile'][_index],
    };
  }

  @override
  void initState() {
    super.initState();
    if (_role == UserRole.patient) {
      if (NotificationService.instance.lastTappedMedicationId != null) {
        _index = 1;
      }
      NotificationService.instance.tapNotifier.addListener(_onNotificationTap);
      _startReminderService();
    }
  }

  void _onNotificationTap() {
    if (NotificationService.instance.lastTappedMedicationId == null) return;
    if (mounted) setState(() => _index = 1);
  }

  void _startReminderService() {
    final firestore = FirestoreService();
    _medSub?.cancel();
    _medSub = firestore.getMedicationsByPatient(widget.user.uid).listen((meds) {
      _reminderService.updateMedications(meds);
      NotificationService.instance
          .scheduleDailyReminders(meds, patientId: widget.user.uid);
    });
    _reminderService.start(medications: []);
    NotificationService.instance.requestPermissions();
  }

  @override
  void dispose() {
    _medSub?.cancel();
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
        UserRole.caregiver => CaregiverHomePage(
            user: widget.user,
            onNavigateToMedication: () => setState(() => _index = 1),
          ),
        UserRole.family || UserRole.pharmacist => RoleDashboard(role: _role, user: widget.user),
      };
    }
    return switch (_role) {
      UserRole.caregiver => switch (_index) {
          1 => MedicationPage(user: widget.user),
          2 => AccountPage(user: widget.user),
          _ => ProfilePage(user: widget.user),
        },
      UserRole.patient => switch (_index) {
          1 => ReminderPage(user: widget.user),
          2 => const MoodPage(),
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
    final isCaregiverHome = _role == UserRole.caregiver && _index == 0;
    final isPatient = _role == UserRole.patient;
    return PhoneFrame(
      backgroundColor: AppTheme.paleBlue,
      child: Stack(
        children: [
          Column(
            children: [
              if (!isCaregiverHome)
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
