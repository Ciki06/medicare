import 'package:flutter/material.dart';

class MedicineArt extends StatelessWidget {
  const MedicineArt({
    super.key,
    this.size = 48,
    this.color = const Color(0xFFF0B42F),
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAF1),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFF8A8E84), width: 2),
      ),
      child: Center(
        child: Transform.rotate(
          angle: -.7,
          child: Container(
            width: size * .55,
            height: size * .22,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(50),
              gradient: LinearGradient(
                colors: [const Color(0xFFE23E37), color],
                stops: const [.49, .51],
              ),
              border: Border.all(color: const Color(0xFF5B5B5B), width: 1),
            ),
          ),
        ),
      ),
    );
  }
}
