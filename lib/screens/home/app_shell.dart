import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../models/user_role.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/bottom_navigation.dart';
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
          1 => const HistoryPage(),
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
    return PhoneFrame(
      backgroundColor: AppTheme.paleBlue,
      child: Column(
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
    );
  }
}
