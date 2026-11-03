import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Large segmented radial gauge with a counting-up number in the centre.
class ThreatGauge extends StatelessWidget {
  const ThreatGauge({
    super.key,
    required this.value,
    this.label = 'Threat Likelihood',
    this.width = 280,
  });

  final double value; // 0 – 100
  final String label;
  final double width; // maximum width

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth.isFinite ? math.min(width, c.maxWidth) : width;
        final arcHeight = w * 0.6;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value),
          duration: const Duration(milliseconds: 1400),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => SizedBox(
            width: w,
            height: arcHeight + 40,
            child: Stack(
              children: [
                CustomPaint(
                  size: Size(w, arcHeight),
                  painter: _GaugePainter(v / 100),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            v.round().toString(),
                            style: const TextStyle(
                              fontSize: 60,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Text(
                            '%',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.progress);
  final double progress; // 0 – 1

  static const _segments = 18;
  static const _stops = [
    AppColors.blue,
    AppColors.primary,
    AppColors.green,
    AppColors.lime,
  ];

  Color _segmentColor(double t) {
    final p = t * (_stops.length - 1);
    final i = p.floor().clamp(0, _stops.length - 2);
    return Color.lerp(_stops[i], _stops[i + 1], p - i)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.1;
    final center = Offset(size.width / 2, size.height);
    final radius = size.width / 2 - stroke / 2 - 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    const gap = 0.035;
    final sweep = (math.pi - gap * (_segments - 1)) / _segments;
    final filled = (progress * _segments).round();

    for (var i = 0; i < _segments; i++) {
      final start = math.pi + i * (sweep + gap);
      final on = i < filled;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt
        ..color = on
            ? _segmentColor(i / (_segments - 1))
            : AppColors.white(0.08);
      canvas.drawArc(rect, start, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) => old.progress != progress;
}

/// Small circular progress ring with the value inside
/// (used for "Threat Confidence" and "Behavior Match").
class MiniRing extends StatelessWidget {
  const MiniRing({
    super.key,
    required this.value,
    this.color = AppColors.green,
    this.size = 64,
    this.text,
  });

  final double value; // 0 – 100
  final Color color;
  final double size;

  /// Replaces the "NN%" label (for example "—" when no value exists yet).
  final String? text;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingPainter(v / 100, color),
          child: Center(
            child: text != null
                ? Text(
                    text!,
                    style: TextStyle(
                      fontSize: size * 0.3,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        v.round().toString(),
                        style: TextStyle(
                          fontSize: size * 0.3,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '%',
                        style: TextStyle(
                          fontSize: size * 0.17,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.color);
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 5.0;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.width / 2 - stroke,
    );
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = AppColors.white(0.1),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color;
}
