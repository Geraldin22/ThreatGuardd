import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Slowly drifting aurora glow behind the whole app.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key, this.child});
  final Widget? child;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _blob(Alignment center, Color color, int alpha, double radius) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: center,
            radius: radius,
            colors: [color.withAlpha(alpha), color.withAlpha(0)],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = _controller.value * 2 * math.pi;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    _blob(
                      Alignment(
                        -0.8 + 0.25 * math.sin(t),
                        -0.9 + 0.15 * math.cos(t),
                      ),
                      AppColors.blue,
                      90,
                      1.1,
                    ),
                    _blob(
                      Alignment(
                        0.9 + 0.2 * math.cos(t),
                        -0.3 + 0.2 * math.sin(t),
                      ),
                      AppColors.primary,
                      60,
                      0.9,
                    ),
                    _blob(
                      Alignment(
                        -0.3 + 0.3 * math.sin(t + 2),
                        1.0 + 0.1 * math.cos(t),
                      ),
                      AppColors.violet,
                      70,
                      1.1,
                    ),
                  ],
                );
              },
            ),
          ),
          if (widget.child != null) widget.child!,
        ],
      ),
    );
  }
}
