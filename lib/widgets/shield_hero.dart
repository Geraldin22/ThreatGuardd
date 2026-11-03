import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Signature AI shield: glass shield, pulsing halo rings, rotating light ring.
class ShieldHero extends StatefulWidget {
  const ShieldHero({super.key, this.size = 260});
  final double size;

  @override
  State<ShieldHero> createState() => _ShieldHeroState();
}

class _ShieldHeroState extends State<ShieldHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final side = c.maxWidth.isFinite
            ? math.min(widget.size, c.maxWidth)
            : widget.size;
        return RepaintBoundary(
          child: SizedBox.square(
            dimension: side,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) =>
                  CustomPaint(painter: _ShieldPainter(_controller.value)),
            ),
          ),
        );
      },
    );
  }
}

class _ShieldPainter extends CustomPainter {
  _ShieldPainter(this.t);
  final double t;

  Path _shield(double ox, double oy, double w, double h) => Path()
    ..moveTo(ox + 0.5 * w, oy)
    ..cubicTo(
      ox + 0.66 * w,
      oy + 0.09 * h,
      ox + 0.84 * w,
      oy + 0.13 * h,
      ox + w,
      oy + 0.13 * h,
    )
    ..lineTo(ox + w, oy + 0.5 * h)
    ..cubicTo(
      ox + w,
      oy + 0.78 * h,
      ox + 0.76 * w,
      oy + 0.93 * h,
      ox + 0.5 * w,
      oy + h,
    )
    ..cubicTo(ox + 0.24 * w, oy + 0.93 * h, ox, oy + 0.78 * h, ox, oy + 0.5 * h)
    ..lineTo(ox, oy + 0.13 * h)
    ..cubicTo(
      ox + 0.16 * w,
      oy + 0.13 * h,
      ox + 0.34 * w,
      oy + 0.09 * h,
      ox + 0.5 * w,
      oy,
    )
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);
    final twoPi = 2 * math.pi;

    // Ambient glow
    canvas.drawCircle(
      c,
      s * 0.5,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.primary.withAlpha(70),
            AppColors.primary.withAlpha(0),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: s * 0.5)),
    );

    // Halo rings (slow pulse)
    const radii = [0.48, 0.38, 0.29];
    for (var i = 0; i < radii.length; i++) {
      final pulse = 1 + 0.025 * math.sin(twoPi * t + i * 1.2);
      final r = s * radii[i] * pulse;
      final rect = Rect.fromCircle(center: c, radius: r);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [AppColors.white(0.02), AppColors.white(0.10 - i * 0.02)],
          ).createShader(rect),
      );
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = AppColors.white(0.16),
      );
    }

    // Rotating light ring
    final sweepR = s * 0.38;
    canvas.drawCircle(
      c,
      sweepR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..shader = SweepGradient(
          transform: GradientRotation(twoPi * t),
          colors: [
            AppColors.primary.withAlpha(0),
            AppColors.primary,
            AppColors.green.withAlpha(0),
          ],
          stops: const [0.0, 0.25, 0.5],
        ).createShader(Rect.fromCircle(center: c, radius: sweepR)),
    );

    // Glass shield
    final w = s * 0.36;
    final h = w * 1.18;
    final ox = c.dx - w / 2;
    final oy = c.dy - h / 2;
    final shield = _shield(ox, oy, w, h);

    canvas.drawPath(
      shield,
      Paint()
        ..color = AppColors.primary.withAlpha(110)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28),
    );
    canvas.drawPath(
      shield,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xE6D4F1FF), Color(0xB38FD3FF), Color(0xB3A8F0C4)],
        ).createShader(Rect.fromLTWH(ox, oy, w, h)),
    );
    canvas.drawPath(
      shield,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = AppColors.white(0.7),
    );
    canvas.drawPath(
      _shield(ox + w * 0.08, oy + h * 0.06, w * 0.84, h * 0.88),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.white(0.25),
    );

    // AI sparkle (4-point star)
    final r = w * 0.2 * (1 + 0.06 * math.sin(twoPi * t * 2));
    final k = r * 0.18;
    final star = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + k, c.dy - k, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + k, c.dy + k, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - k, c.dy + k, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - k, c.dy - k, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(
      star,
      Paint()
        ..color = AppColors.white(0.9)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawPath(star, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _ShieldPainter old) => old.t != t;
}
