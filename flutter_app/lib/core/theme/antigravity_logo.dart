import 'package:flutter/material.dart';

/// Pixel-perfect Antigravity arch logo rendered as high-performance vector
class AntigravityLogo extends StatelessWidget {
  final double size;
  final Color? color;

  const AntigravityLogo({
    super.key,
    this.size = 24.0,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _AntigravityLogoPainter(effectiveColor),
      ),
    );
  }
}

class _AntigravityLogoPainter extends CustomPainter {
  final Color color;

  _AntigravityLogoPainter(this.color);

  static const List<Offset> _pts = [
    Offset(41.23, 11.28), Offset(36.85, 15.67), Offset(32.76, 22.68), Offset(28.08, 35.54), Offset(23.12, 53.94), Offset(18.15, 68.26), Offset(15.23, 74.4), Offset(12.31, 79.07), Offset(5.58, 86.96), Offset(5.0, 88.72), Offset(5.29, 90.18), Offset(6.75, 91.35), Offset(10.26, 91.35), Offset(13.18, 90.18), Offset(16.4, 87.84), Offset(21.66, 82.87), Offset(25.16, 78.49), Offset(29.84, 71.19), Offset(33.34, 64.76), Offset(36.85, 59.79), Offset(40.36, 56.28), Offset(43.86, 54.24), Offset(46.79, 53.36), Offset(50.88, 53.07), Offset(54.68, 53.65), Offset(58.18, 55.11), Offset(59.94, 56.28), Offset(63.73, 60.08), Offset(66.95, 64.76), Offset(70.45, 71.19), Offset(75.13, 78.49), Offset(78.64, 82.87), Offset(81.85, 86.09), Offset(85.06, 88.72), Offset(88.28, 90.76), Offset(90.32, 91.35), Offset(92.66, 91.35), Offset(94.12, 90.76), Offset(95.0, 89.3), Offset(95.0, 88.13), Offset(94.12, 86.09), Offset(90.03, 81.7), Offset(86.82, 77.32), Offset(84.77, 73.81), Offset(81.56, 66.8), Offset(79.22, 60.37), Offset(78.93, 58.62), Offset(78.05, 56.87), Offset(72.5, 36.41), Offset(70.16, 29.11), Offset(67.82, 23.26), Offset(64.9, 17.71), Offset(62.27, 14.2), Offset(59.06, 11.28), Offset(56.43, 9.82), Offset(53.8, 8.94), Offset(52.05, 8.65), Offset(46.49, 8.94), Offset(43.86, 9.82)
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final path = Path();
    final scaleX = size.width / 100.0;
    final scaleY = size.height / 100.0;

    final n = _pts.length;
    final firstMid = Offset(
      (_pts[0].dx + _pts[1].dx) / 2 * scaleX,
      (_pts[0].dy + _pts[1].dy) / 2 * scaleY,
    );
    path.moveTo(firstMid.dx, firstMid.dy);

    for (int i = 1; i < n; i++) {
      final pCurr = Offset(_pts[i].dx * scaleX, _pts[i].dy * scaleY);
      final pNext = Offset(_pts[(i + 1) % n].dx * scaleX, _pts[(i + 1) % n].dy * scaleY);
      final mid = Offset((pCurr.dx + pNext.dx) / 2, (pCurr.dy + pNext.dy) / 2);
      path.quadraticBezierTo(pCurr.dx, pCurr.dy, mid.dx, mid.dy);
    }

    final p0 = Offset(_pts[0].dx * scaleX, _pts[0].dy * scaleY);
    final p1 = Offset(_pts[1].dx * scaleX, _pts[1].dy * scaleY);
    final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
    path.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _AntigravityLogoPainter oldDelegate) =>
      oldDelegate.color != color;
}
