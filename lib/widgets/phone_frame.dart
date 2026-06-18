import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class PhoneFrame extends StatelessWidget {
  const PhoneFrame({
    super.key,
    required this.child,
    this.backgroundColor = AppTheme.lightBlue,
  });

  final Widget child;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F3F3),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 520;
          return Center(
            child: Container(
              width: wide ? 390 : constraints.maxWidth,
              height: wide
                  ? constraints.maxHeight.clamp(650, 820).toDouble()
                  : constraints.maxHeight,
              margin: wide ? const EdgeInsets.all(12) : EdgeInsets.zero,
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(wide ? 28 : 0),
                border: wide
                    ? Border.all(color: const Color(0xFF2D3032), width: 6)
                    : null,
                boxShadow: wide
                    ? const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 5,
                          offset: Offset(1, 2),
                        ),
                      ]
                    : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(bottom: false, child: child),
            ),
          );
        },
      ),
    );
  }
}
