import 'package:flutter/material.dart';

class CalendarArt extends StatelessWidget {
  const CalendarArt({
    super.key,
    this.size = 48,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    final s = size;
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        color: const Color(0xFFE8F4FD),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFF8A8E84), width: 2),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Calendar body
          Positioned(
            top: s * .22,
            child: Container(
              width: s * .6,
              height: s * .52,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: const Color(0xFF5B5B5B), width: 1),
              ),
            ),
          ),
          // Calendar header bar
          Positioned(
            top: s * .18,
            child: Container(
              width: s * .6,
              height: s * .18,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                gradient: const LinearGradient(
                  colors: [Color(0xFF193D82), Color(0xFF315CF4)],
                ),
                border: Border.all(color: const Color(0xFF5B5B5B), width: 1),
              ),
            ),
          ),
          // Calendar ring left
          Positioned(
            top: s * .12,
            left: s * .32,
            child: Container(
              width: s * .07,
              height: s * .14,
              decoration: BoxDecoration(
                color: const Color(0xFF5B5B5B),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Calendar ring right
          Positioned(
            top: s * .12,
            right: s * .32,
            child: Container(
              width: s * .07,
              height: s * .14,
              decoration: BoxDecoration(
                color: const Color(0xFF5B5B5B),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Dot on calendar
          Positioned(
            top: s * .5,
            child: Container(
              width: s * .12,
              height: s * .12,
              decoration: const BoxDecoration(
                color: Color(0xFFE23E37),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
