import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../theme/app_theme.dart';

class MediCareBottomNavigation extends StatelessWidget {
  const MediCareBottomNavigation({
    super.key,
    required this.index,
    required this.onChanged,
    this.role = UserRole.patient,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final items = switch (role) {
      UserRole.caregiver => const [
          (Icons.medication_outlined, 'Medication'),
          (Icons.local_pharmacy_outlined, 'Refill Status'),
          (Icons.account_circle_outlined, 'Account'),
          (Icons.person_outline, 'Profile'),
        ],
      UserRole.patient => const [
          (Icons.home_outlined, 'Home'),
          (Icons.notifications_outlined, 'Reminder'),
          (Icons.health_and_safety_outlined, 'Health'),
          (Icons.person_outline, 'Profile'),
        ],
      UserRole.family => const [
          (Icons.home_outlined, 'Home'),
          (Icons.history_outlined, 'History'),
          (Icons.person_outline, 'Profile'),
        ],
      UserRole.pharmacist => const [
          (Icons.home_outlined, 'Home'),
          (Icons.receipt_long_outlined, 'Refill Request'),
          (Icons.person_outline, 'Profile'),
        ],
    };
    return Container(
      height: 64,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      child: Row(
        children: List.generate(items.length, (itemIndex) {
          final active = itemIndex == index;
          return Expanded(
            child: InkWell(
              key: Key('nav-$itemIndex'),
              borderRadius: BorderRadius.circular(28),
              onTap: () => onChanged(itemIndex),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                decoration: BoxDecoration(
                  color: active ? const Color(0xFFDCEBFA) : Colors.transparent,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      items[itemIndex].$1,
                      color: active ? AppTheme.navy : Colors.black,
                      size: 25,
                    ),
                    Text(
                      items[itemIndex].$2,
                      style: TextStyle(
                        color: active ? AppTheme.navy : Colors.black,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
