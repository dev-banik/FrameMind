import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Vector-drawn FrameMind logo: a gradient tile with a film frame, a play
/// triangle and a small "spark" (the AI idea).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppTheme.brandGradient,
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C4DF5).withAlpha(90),
            blurRadius: size * 0.3,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      child: CustomPaint(painter: _LogoPainter()),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final stroke = Paint()
      ..color = Colors.white.withAlpha(230)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.055
      ..strokeCap = StrokeCap.round;

    // Film frame.
    final frame = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.2, w * 0.27, w * 0.6, w * 0.46),
      Radius.circular(w * 0.08),
    );
    canvas.drawRRect(frame, stroke);

    // Play triangle.
    final play = Path()
      ..moveTo(w * 0.44, w * 0.39)
      ..lineTo(w * 0.60, w * 0.50)
      ..lineTo(w * 0.44, w * 0.61)
      ..close();
    canvas.drawPath(play, Paint()..color = Colors.white);

    // Spark (four-point star) at the top-right corner.
    final center = Offset(w * 0.78, w * 0.25);
    final r = w * 0.11;
    final spark = Path();
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4 - math.pi / 2;
      final radius = i.isEven ? r : r * 0.32;
      final point = center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      if (i == 0) {
        spark.moveTo(point.dx, point.dy);
      } else {
        spark.lineTo(point.dx, point.dy);
      }
    }
    spark.close();
    canvas.drawPath(spark, Paint()..color = const Color(0xFFFFE082));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Logo with a gentle pulsing animation, used on the splash screen.
class AnimatedAppLogo extends StatefulWidget {
  const AnimatedAppLogo({super.key, this.size = 96});

  final double size;

  @override
  State<AnimatedAppLogo> createState() => _AnimatedAppLogoState();
}

class _AnimatedAppLogoState extends State<AnimatedAppLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  late final Animation<double> _scale = Tween<double>(begin: 0.92, end: 1.06)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: AppLogo(size: widget.size),
    );
  }
}

/// Logo + wordmark.
class AppWordmark extends StatelessWidget {
  const AppWordmark({super.key, this.logoSize = 40});

  final double logoSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLogo(size: logoSize),
        const SizedBox(width: 10),
        Text(
          'FrameMind',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}
