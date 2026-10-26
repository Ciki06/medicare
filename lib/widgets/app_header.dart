import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../theme/app_theme.dart';
import 'brand_logo.dart';
import 'offline_image.dart';

class AppHeader extends StatefulWidget {
  const AppHeader({
    super.key,
    this.title,
    this.greeting,
    this.greetingColor,
    this.showAvatar = false,
    this.profilePicUrl,
    this.onTitleTripleTap,
  });

  final String? title;
  final String? greeting;
  final Color? greetingColor;
  final bool showAvatar;
  final String? profilePicUrl;
  final VoidCallback? onTitleTripleTap;

  @override
  State<AppHeader> createState() => _AppHeaderState();
}

class _AppHeaderState extends State<AppHeader> {
  Timer? _tapWindow;
  int _taps = 0;

  void _resetTaps() {
    _tapWindow?.cancel();
    _tapWindow = null;
    _taps = 0;
  }

  void _tapTitle() {
    if (widget.onTitleTripleTap == null) return;
    if (_taps == 0) {
      _tapWindow = Timer(const Duration(milliseconds: 1200), _resetTaps);
    }
    if (++_taps == 3) {
      _resetTaps();
      widget.onTitleTripleTap!();
    }
  }

  @override
  void didUpdateWidget(covariant AppHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title ||
        oldWidget.greeting != widget.greeting ||
        (oldWidget.onTitleTripleTap == null) !=
            (widget.onTitleTripleTap == null)) {
      _resetTaps();
    }
  }

  @override
  void dispose() {
    _resetTaps();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profilePicUrl = widget.profilePicUrl?.trim();
    final avatarImage = profilePicUrl != null && profilePicUrl.isNotEmpty
        ? cachedImageProvider(profilePicUrl)
        : null;
    return Container(
      height: 70,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            const BrandLogo(compact: true, showName: false),
            const Spacer(),
            ConstrainedBox(
              // Keep the original centered row while fitting longer greetings
              // inside the space between the existing logo and avatar.
              constraints: BoxConstraints(
                maxWidth: (constraints.maxWidth - 82).clamp(0, double.infinity),
              ),
              child: Semantics(
                customSemanticsActions: widget.onTitleTripleTap == null
                    ? null
                    : {
                        const CustomSemanticsAction(
                          label: 'Open local database',
                        ): widget.onTitleTripleTap!,
                      },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onTitleTripleTap == null ? null : _tapTitle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        widget.greeting ?? widget.title ?? '',
                        maxLines: 1,
                        style: TextStyle(
                          color: widget.greeting != null
                              ? widget.greetingColor ?? AppTheme.navy
                              : const Color(0xFF3E3B3B),
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          fontStyle: FontStyle.italic,
                          fontFamily: 'serif',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(),
            if (widget.showAvatar)
              CircleAvatar(
                radius: 21,
                backgroundColor: const Color(0xFFD1D1D1),
                foregroundImage: avatarImage,
                onForegroundImageError: avatarImage == null ? null : (_, _) {},
                child: const Icon(Icons.person, color: Colors.white, size: 31),
              )
            else
              const SizedBox(width: 42),
          ],
        ),
      ),
    );
  }
}
