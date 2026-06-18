import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.compact = false, this.showName = true});

  final bool compact;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 40.0 : 96.0;

    final icon = Image.asset(
      'assets/MedicareLogo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );

    final logo = showName
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(height: 5),
              const Text(
                'MediCare',
                style: TextStyle(
                  color: Color(0xFF126BB3),
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Text(
                'Medication Reminder App',
                style: TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
            ],
          )
        : icon;

    // return IgnorePointer(
    //   child: ExcludeSemantics(
    //     child: logo,
    //   ),
    // );
    return logo;
  }
}
