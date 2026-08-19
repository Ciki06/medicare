import 'package:flutter/material.dart';

class MoodArt extends StatelessWidget {
  const MoodArt({
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
        color: const Color(0xFFE8F8F0),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFF8A8E84), width: 2),
      ),
      child: CustomPaint(
        painter: _HeartPainter(s),
      ),
    );
  }
}

class _HeartPainter extends CustomPainter {
  _HeartPainter(this.s);
  final double s;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 + s * .04;
    final scale = s * .03;

    final path = Path();
    path.moveTo(cx, cy + 8 * scale);
    path.cubicTo(cx - 1.5 * scale, cy + 4 * scale, cx - 8 * scale, cy - 1 * scale, cx - 8 * scale, cy - 6 * scale);
    path.cubicTo(cx - 8 * scale, cy - 11 * scale, cx - 3 * scale, cy - 13 * scale, cx, cy - 9 * scale);
    path.cubicTo(cx + 3 * scale, cy - 13 * scale, cx + 8 * scale, cy - 11 * scale, cx + 8 * scale, cy - 6 * scale);
    path.cubicTo(cx + 8 * scale, cy - 1 * scale, cx + 1.5 * scale, cy + 4 * scale, cx, cy + 8 * scale);
    path.close();

    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFFE85B61),
        const Color(0xFFF2AE36),
      ],
    );
    final paint = Paint()
      ..shader = gradient.createShader(path.getBounds())
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);

    final strokePaint = Paint()
      ..color = const Color(0xFF5B5B5B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(path, strokePaint);

    // eyes
    final eyePaint = Paint()..color = const Color(0xFF5B5B5B);
    canvas.drawCircle(Offset(cx - 3 * scale, cy - 5 * scale), 1 * scale, eyePaint);
    canvas.drawCircle(Offset(cx + 3 * scale, cy - 5 * scale), 1 * scale, eyePaint);

    // smile
    final smilePaint = Paint()
      ..color = const Color(0xFF5B5B5B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8 * scale
      ..strokeCap = StrokeCap.round;
    final smilePath = Path();
    smilePath.moveTo(cx - 2.5 * scale, cy - 1.5 * scale);
    smilePath.quadraticBezierTo(cx, cy + 1.5 * scale, cx + 2.5 * scale, cy - 1.5 * scale);
    canvas.drawPath(smilePath, smilePaint);
  }

  @override
  bool shouldRepaint(covariant _HeartPainter old) => old.s != s;
}
