import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../theme/app_theme.dart';
import 'brand_logo.dart';

class AppHeader extends StatefulWidget {
  const AppHeader({
    super.key,
    this.title,
    this.greeting,
    this.showAvatar = false,
    this.onTitleTripleTap,
  });

  final String? title;
  final String? greeting;
  final bool showAvatar;
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
    return Container(
      height: 70,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          const BrandLogo(compact: true, showName: false),
          const Spacer(),
          Semantics(
            customSemanticsActions: widget.onTitleTripleTap == null
                ? null
                : {
                    const CustomSemanticsAction(label: 'Open local database'):
                        widget.onTitleTripleTap!,
                  },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTitleTripleTap == null ? null : _tapTitle,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  widget.greeting ?? widget.title ?? '',
                  style: TextStyle(
                    color: widget.greeting != null
                        ? AppTheme.navy
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
          const Spacer(),
          if (widget.showAvatar)
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
