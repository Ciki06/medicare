import 'package:flutter/material.dart';

class MoodFaceArt extends StatelessWidget {
  const MoodFaceArt({
    super.key,
    this.size = 57,
    required this.moodIndex,
    required this.color,
  });

  final double size;
  final int moodIndex;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF8A8E84), width: 2),
      ),
      child: CustomPaint(
        painter: _FacePainter(moodIndex, size),
      ),
    );
  }
}

class _FacePainter extends CustomPainter {
  _FacePainter(this.moodIndex, this.s);
  final int moodIndex;
  final double s;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final sc = s * .018;

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.2 * sc;

    // --- Eyes ---
    final eyePaint = Paint()..color = const Color(0xFF5B5B5B);
    final lEye = Offset(cx - 6 * sc, cy - 3 * sc);
    final rEye = Offset(cx + 6 * sc, cy - 3 * sc);

    switch (moodIndex) {
      case 0: // Angry — narrowed slanted eyes
        stroke.color = const Color(0xFF5B5B5B);
        stroke.strokeWidth = 1.6 * sc;
        canvas.drawLine(Offset(cx - 8 * sc, cy - 5 * sc), Offset(cx - 4 * sc, cy - 2 * sc), stroke);
        canvas.drawLine(Offset(cx + 4 * sc, cy - 2 * sc), Offset(cx + 8 * sc, cy - 5 * sc), stroke);
        break;
      case 1: // Calm — half-closed dots
        canvas.drawOval(Rect.fromCenter(center: lEye, width: 2.5 * sc, height: 1.5 * sc), eyePaint);
        canvas.drawOval(Rect.fromCenter(center: rEye, width: 2.5 * sc, height: 1.5 * sc), eyePaint);
        break;
      case 2: // Happy — happy arc eyes
        stroke.color = const Color(0xFF5B5B5B);
        stroke.strokeWidth = 1.4 * sc;
        final arcL = Path()
          ..moveTo(cx - 8 * sc, cy - 2 * sc)
          ..quadraticBezierTo(cx - 6 * sc, cy - 5.5 * sc, cx - 4 * sc, cy - 2 * sc);
        final arcR = Path()
          ..moveTo(cx + 4 * sc, cy - 2 * sc)
          ..quadraticBezierTo(cx + 6 * sc, cy - 5.5 * sc, cx + 8 * sc, cy - 2 * sc);
        canvas.drawPath(arcL, stroke);
        canvas.drawPath(arcR, stroke);
        break;
      case 3: // Lovely — star/sparkle eyes
        _drawStar(canvas, lEye, 2.2 * sc, eyePaint);
        _drawStar(canvas, rEye, 2.2 * sc, eyePaint);
        break;
      case 4: // Neutral — flat line eyes
        stroke.color = const Color(0xFF5B5B5B);
        stroke.strokeWidth = 1.4 * sc;
        canvas.drawLine(Offset(cx - 8 * sc, cy - 3 * sc), Offset(cx - 4 * sc, cy - 3 * sc), stroke);
        canvas.drawLine(Offset(cx + 4 * sc, cy - 3 * sc), Offset(cx + 8 * sc, cy - 3 * sc), stroke);
        break;
      case 5: // Joyful — wide open sparkle eyes
        canvas.drawCircle(lEye, 2 * sc, eyePaint);
        canvas.drawCircle(rEye, 2 * sc, eyePaint);
        final shine = Paint()..color = Colors.white;
        canvas.drawCircle(Offset(cx - 5 * sc, cy - 4 * sc), .7 * sc, shine);
        canvas.drawCircle(Offset(cx + 7 * sc, cy - 4 * sc), .7 * sc, shine);
        break;
      case 6: // Sad — droopy big eyes
        canvas.drawCircle(lEye, 2.2 * sc, eyePaint);
        canvas.drawCircle(rEye, 2.2 * sc, eyePaint);
        final shine = Paint()..color = Colors.white;
        canvas.drawCircle(Offset(cx - 5 * sc, cy - 4 * sc), .8 * sc, shine);
        canvas.drawCircle(Offset(cx + 7 * sc, cy - 4 * sc), .8 * sc, shine);
        break;
      case 7: // Crying — closed down-curve eyes with tears
        stroke.color = const Color(0xFF5B5B5B);
        stroke.strokeWidth = 1.4 * sc;
        final cryL = Path()
          ..moveTo(cx - 8 * sc, cy - 3 * sc)
          ..quadraticBezierTo(cx - 6 * sc, cy - .5 * sc, cx - 4 * sc, cy - 3 * sc);
        final cryR = Path()
          ..moveTo(cx + 4 * sc, cy - 3 * sc)
          ..quadraticBezierTo(cx + 6 * sc, cy - .5 * sc, cx + 8 * sc, cy - 3 * sc);
        canvas.drawPath(cryL, stroke);
        canvas.drawPath(cryR, stroke);
        // tears
        final tearPaint = Paint()..color = const Color(0xFF5BA8E0);
        canvas.drawOval(Rect.fromCenter(center: Offset(cx - 8 * sc, cy + 1 * sc), width: 1.5 * sc, height: 3 * sc), tearPaint);
        canvas.drawOval(Rect.fromCenter(center: Offset(cx + 8 * sc, cy + 1 * sc), width: 1.5 * sc, height: 3 * sc), tearPaint);
        break;
      case 8: // Anxious — wide round eyes with sweat
        canvas.drawCircle(lEye, 2.2 * sc, eyePaint);
        canvas.drawCircle(rEye, 2.2 * sc, eyePaint);
        final shine = Paint()..color = Colors.white;
        canvas.drawCircle(Offset(cx - 5 * sc, cy - 4 * sc), .8 * sc, shine);
        canvas.drawCircle(Offset(cx + 7 * sc, cy - 4 * sc), .8 * sc, shine);
        // sweat drop
        final sweatPaint = Paint()..color = const Color(0xFF89CFF0);
        final drop = Path()
          ..moveTo(cx + 10 * sc, cy - 9 * sc)
          ..quadraticBezierTo(cx + 11.5 * sc, cy - 6 * sc, cx + 10 * sc, cy - 5 * sc)
          ..quadraticBezierTo(cx + 8.5 * sc, cy - 6 * sc, cx + 10 * sc, cy - 9 * sc);
        canvas.drawPath(drop, sweatPaint);
        break;
      default:
        canvas.drawCircle(lEye, 1.8 * sc, eyePaint);
        canvas.drawCircle(rEye, 1.8 * sc, eyePaint);
    }

    // --- Blush for lovely ---
    if (moodIndex == 3) {
      final blush = Paint()..color = const Color(0xFFF28080).withValues(alpha: .35);
      canvas.drawOval(Rect.fromCenter(center: Offset(cx - 8 * sc, cy + 1 * sc), width: 4 * sc, height: 2 * sc), blush);
      canvas.drawOval(Rect.fromCenter(center: Offset(cx + 8 * sc, cy + 1 * sc), width: 4 * sc, height: 2 * sc), blush);
    }

    // --- Mouth ---
    stroke.color = const Color(0xFF5B5B5B);
    stroke.style = PaintingStyle.stroke;
    stroke.strokeWidth = 1.2 * sc;

    switch (moodIndex) {
      case 0: // Angry — zigzag frown
        final frown = Path()
          ..moveTo(cx - 5 * sc, cy + 4 * sc)
          ..lineTo(cx - 2 * sc, cy + 2.5 * sc)
          ..lineTo(cx, cy + 5 * sc)
          ..lineTo(cx + 2 * sc, cy + 2.5 * sc)
          ..lineTo(cx + 5 * sc, cy + 4 * sc);
        canvas.drawPath(frown, stroke);
        break;
      case 1: // Calm — gentle smile
        final smile = Path()
          ..moveTo(cx - 4 * sc, cy + 2 * sc)
          ..quadraticBezierTo(cx, cy + 5 * sc, cx + 4 * sc, cy + 2 * sc);
        canvas.drawPath(smile, stroke);
        break;
      case 2: // Happy — big open smile
        final smile = Path()
          ..moveTo(cx - 5 * sc, cy + 1 * sc)
          ..quadraticBezierTo(cx, cy + 8 * sc, cx + 5 * sc, cy + 1 * sc);
        canvas.drawPath(smile, stroke);
        // fill smile
        final smileFill = Paint()..color = const Color(0xFFE85B61).withValues(alpha: .6);
        canvas.drawPath(smile, smileFill);
        canvas.drawPath(smile, stroke);
        break;
      case 3: // Lovely — cat smile :3
        final cat = Path()
          ..moveTo(cx - 5 * sc, cy + 2 * sc)
          ..quadraticBezierTo(cx - 2.5 * sc, cy + 5 * sc, cx, cy + 2.5 * sc)
          ..quadraticBezierTo(cx + 2.5 * sc, cy + 5 * sc, cx + 5 * sc, cy + 2 * sc);
        canvas.drawPath(cat, stroke);
        break;
      case 4: // Neutral — flat line
        canvas.drawLine(Offset(cx - 4 * sc, cy + 3 * sc), Offset(cx + 4 * sc, cy + 3 * sc), stroke);
        break;
      case 5: // Joyful — wide open laughing mouth
        final laugh = Path()
          ..moveTo(cx - 5 * sc, cy + 1 * sc)
          ..quadraticBezierTo(cx, cy + 9 * sc, cx + 5 * sc, cy + 1 * sc)
          ..close();
        final laughFill = Paint()..color = const Color(0xFFE85B61).withValues(alpha: .6);
        canvas.drawPath(laugh, laughFill);
        canvas.drawPath(laugh, stroke);
        // tongue
        final tongue = Paint()..color = const Color(0xFFF28080);
        canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy + 6 * sc), width: 3 * sc, height: 2 * sc), tongue);
        break;
      case 6: // Sad — wavy frown
        final sad = Path()
          ..moveTo(cx - 4 * sc, cy + 5 * sc)
          ..quadraticBezierTo(cx, cy + 1 * sc, cx + 4 * sc, cy + 5 * sc);
        canvas.drawPath(sad, stroke);
        break;
      case 7: // Crying — open sad mouth
        final cry = Path()
          ..moveTo(cx - 3.5 * sc, cy + 3 * sc)
          ..quadraticBezierTo(cx, cy + 8 * sc, cx + 3.5 * sc, cy + 3 * sc);
        canvas.drawPath(cry, stroke);
        final cryFill = Paint()..color = const Color(0xFFE85B61).withValues(alpha: .5);
        canvas.drawPath(cry, cryFill);
        canvas.drawPath(cry, stroke);
        break;
      case 8: // Anxious — wobbly open mouth
        final worry = Path()
          ..moveTo(cx - 3 * sc, cy + 3 * sc)
          ..quadraticBezierTo(cx - 1 * sc, cy + 7 * sc, cx + 1 * sc, cy + 3 * sc)
          ..quadraticBezierTo(cx + 2 * sc, cy + 7 * sc, cx + 3 * sc, cy + 3 * sc);
        canvas.drawPath(worry, stroke);
        break;
      default:
        canvas.drawLine(Offset(cx - 4 * sc, cy + 3 * sc), Offset(cx + 4 * sc, cy + 3 * sc), stroke);
    }
  }

  void _drawStar(Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path();
    for (var i = 0; i < 4; i++) {
      final tip = Offset(
        center.dx + r * (i.isEven ? 0 : (i == 1 ? 1 : -1)),
        center.dy + r * (i.isEven ? (i == 0 ? -1 : 1) : 0),
      );
      if (i == 0) {
        path.moveTo(tip.dx, tip.dy);
      } else {
        path.lineTo(tip.dx, tip.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _FacePainter old) =>
      old.moodIndex != moodIndex || old.s != s;
}
