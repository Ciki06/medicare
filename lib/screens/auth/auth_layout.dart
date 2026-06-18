import 'package:flutter/material.dart';

import '../../widgets/brand_logo.dart';
import '../../widgets/phone_frame.dart';

class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.children,
    this.logoTopSpacing = 18,
    this.scrollable = true,
  });

  final List<Widget> children;
  final double logoTopSpacing;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          SizedBox(height: 120),
          SizedBox(height: logoTopSpacing),
          const BrandLogo(),
          const SizedBox(height: 18),
          ...children,
          const SizedBox(height: 20),
        ],
      ),
    );

    return PhoneFrame(
      child: scrollable
          ? SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: body,
            )
          : body,
    );
  }
}

class AuthFooterLink extends StatelessWidget {
  const AuthFooterLink({
    super.key,
    required this.prompt,
    required this.action,
    required this.onTap,
  });

  final String prompt;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          prompt,
          style: const TextStyle(color: Color(0xFF777777), fontSize: 12),
        ),
        InkWell(
          onTap: onTap,
          child: Text(
            action,
            style: const TextStyle(
              color: Color(0xFF52863A),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }
}
