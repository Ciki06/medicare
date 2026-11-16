import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shows the shared MediCare logo at the size requested by the screen.
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.compact = false,
    this.showName = true,
    this.iconSize,
  });

  final bool compact;
  final bool showName;
  final double? iconSize;

  /// Build the reusable logo used on the authentication screens.
  @override
  Widget build(BuildContext context) {
    final size = iconSize ?? (compact ? 40.0 : 96.0);

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

    /// return IgnorePointer(
    ///   child: ExcludeSemantics(
    ///     child: logo,
    ///   ),
    /// );
    return logo;
  }
}
