import 'package:flutter/material.dart';

import '../models/user_role.dart';

class RoleSelector extends StatelessWidget {
  const RoleSelector({
    super.key,
    required this.selected,
    required this.onSelected,
    this.label = 'Login As:',
  });

  final UserRole selected;
  final ValueChanged<UserRole> onSelected;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF5F6670),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 9),
        Row(
          children: UserRole.values.map((role) {
            final active = selected == role;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: role == UserRole.pharmacist ? 0 : 8,
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(5),
                  onTap: () => onSelected(role),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: 68,
                    decoration: BoxDecoration(
                      color: role.color.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: active ? role.color : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        Expanded(
                          child: Center(
                            child: Text(
                              role.emoji,
                              style: const TextStyle(fontSize: 28),
                            ),
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          color: role.color,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            role.label,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
