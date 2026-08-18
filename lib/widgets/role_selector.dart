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
          children: [
            for (final role in UserRole.values) ...[
              Expanded(
                child: _RoleCard(
                  role: role,
                  active: selected == role,
                  onTap: () => onSelected(role),
                ),
              ),
              if (role != UserRole.pharmacist) const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.active,
    required this.onTap,
  });

  final UserRole role;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(5),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
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
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: AspectRatio(
                aspectRatio: 1,
                child: Image.asset(
                  role.image,
                  fit: BoxFit.cover,
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
    );
  }
}
