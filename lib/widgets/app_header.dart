import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'brand_logo.dart';

class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    this.title,
    this.greeting,
    this.showAvatar = false,
  });

  final String? title;
  final String? greeting;
  final bool showAvatar;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          const BrandLogo(compact: true, showName: false),
          const Spacer(),
          Text(
            greeting ?? title ?? '',
            style: TextStyle(
              color: greeting != null ? AppTheme.navy : const Color(0xFF3E3B3B),
              fontSize: 21,
              fontWeight: FontWeight.w800,
              fontStyle: FontStyle.italic,
              fontFamily: 'serif',
            ),
          ),
          const Spacer(),
          if (showAvatar)
            const CircleAvatar(
              radius: 21,
              backgroundColor: Color(0xFFD1D1D1),
              child: Icon(Icons.person, color: Colors.white, size: 31),
            )
          else
            const SizedBox(width: 42),
        ],
      ),
    );
  }
}
