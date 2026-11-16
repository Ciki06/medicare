import 'package:flutter/material.dart';

import '../../widgets/brand_logo.dart';
import '../../widgets/phone_frame.dart';

/// Shared logo and page layout for sign-in, sign-up, and password reset.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.children,
    this.logoTopSpacing = 18,
    this.logoSize,
    this.topPadding = 120,
    this.scrollable = true,
  });

  final List<Widget> children;
  final double logoTopSpacing;
  final double? logoSize;
  final double topPadding;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    /// Place the shared logo above the screen content.
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          SizedBox(height: topPadding),
          SizedBox(height: logoTopSpacing),
          BrandLogo(iconSize: logoSize),
          const SizedBox(height: 18),
          ...children,
          const SizedBox(height: 20),
        ],
      ),
    );

    /// Allow longer forms to scroll on smaller screens.
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

/// A short prompt with a link to another auth screen.
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
    /// Let the prompt and link wrap on narrow screens.
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
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
