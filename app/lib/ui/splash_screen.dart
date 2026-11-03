import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_core.dart';
import 'components.dart';

/// Branded boot / session-restore splash matching the ApnaSociety launch screen.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.label,
    this.error,
    this.onRetry,
  });

  final String label;
  final String? error;
  final VoidCallback? onRetry;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static const _surface = Color(0xFFFAF8FF);
  static const _primary = Color(0xFF00254C);
  static const _secondary = Color(0xFF325F9B);
  static const _onSurfaceVariant = Color(0xFF43474F);
  static const _outline = Color(0xFF737780);
  static const _surfaceContainer = Color(0xFFEAEDFF);
  static const _surfaceContainerHighest = Color(0xFFDAE2FD);
  static const _secondaryFixed = Color(0xFFD5E3FF);
  static const _appVersion = '1.0.6';

  late final AnimationController _orbit =
      AnimationController(vsync: this, duration: const Duration(seconds: 120))
        ..repeat();
  late final AnimationController _bounce =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat();
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 780),
  )..forward();

  @override
  void dispose() {
    _orbit.dispose();
    _bounce.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.error != null;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: _surface,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: _surface,
        body: SafeArea(
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _entrance,
              curve: Curves.easeOutCubic,
            ),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: _entrance,
                curve: Curves.easeOutCubic,
              )),
              child: Stack(
                children: [
                  const Positioned.fill(child: _SplashAtmosphere()),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _orbit,
                        builder: (context, child) => Transform.rotate(
                          angle: _orbit.value * 2 * math.pi,
                          child: child,
                        ),
                        child: CustomPaint(
                          painter: _ArchitecturalGridPainter(
                            color: _surfaceContainerHighest
                                .withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                    child: Column(
                      children: [
                        const Spacer(flex: 2),
                        const _BrandBlock(
                          primary: _primary,
                          secondary: _secondary,
                          onSurfaceVariant: _onSurfaceVariant,
                          surfaceContainer: _surfaceContainer,
                          secondaryFixed: _secondaryFixed,
                        ),
                        const Spacer(flex: 3),
                        if (!hasError)
                          _LoadingFooter(
                            label: widget.label,
                            bounce: _bounce,
                            primary: _primary,
                            secondary: _secondary,
                            outline: _outline,
                            onSurfaceVariant: _onSurfaceVariant,
                            version: _appVersion,
                          )
                        else
                          _ErrorFooter(
                            label: widget.label,
                            error: widget.error!,
                            onRetry: widget.onRetry,
                            primary: _primary,
                            onSurfaceVariant: _onSurfaceVariant,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SplashAtmosphere extends StatelessWidget {
  const _SplashAtmosphere();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.15),
          radius: 1.05,
          colors: [
            Color(0x66D5E3FF),
            Color(0xFFFAF8FF),
          ],
        ),
      ),
      child: Align(
        alignment: const Alignment(0, -0.08),
        child: Container(
          width: 280,
          height: 280,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF93BDFF).withValues(alpha: 0.18),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF93BDFF).withValues(alpha: 0.22),
                blurRadius: 80,
                spreadRadius: 10,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandBlock extends StatelessWidget {
  const _BrandBlock({
    required this.primary,
    required this.secondary,
    required this.onSurfaceVariant,
    required this.surfaceContainer,
    required this.secondaryFixed,
  });

  final Color primary;
  final Color secondary;
  final Color onSurfaceVariant;
  final Color surfaceContainer;
  final Color secondaryFixed;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 156,
            height: 156,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: secondaryFixed.withValues(alpha: 0.7),
                          blurRadius: 28,
                          spreadRadius: 2,
                        ),
                        BoxShadow(
                          color: primary.withValues(alpha: 0.08),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const BrandLogo(size: 128, radius: 999),
                  ),
                ),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: primary.withValues(alpha: 0.28),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.shield_rounded,
                      size: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text(
            kAppName,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              height: 34 / 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Simplifying Society Management',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 20 / 14,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
              color: onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: surfaceContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.domain_rounded, size: 16, color: secondary),
                const SizedBox(width: 6),
                Text(
                  'Executive Resident Portal',
                  style: TextStyle(
                    fontSize: 12,
                    height: 16 / 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingFooter extends StatelessWidget {
  const _LoadingFooter({
    required this.label,
    required this.bounce,
    required this.primary,
    required this.secondary,
    required this.outline,
    required this.onSurfaceVariant,
    required this.version,
  });

  final String label;
  final AnimationController bounce;
  final Color primary;
  final Color secondary;
  final Color outline;
  final Color onSurfaceVariant;
  final String version;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BounceDots(
            controller: bounce,
            colors: [
              primary,
              secondary,
              const Color(0xFFA7C8FE),
            ],
          ),
          if (label.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 16 / 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: outline,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            'Powered by SkyLine Tech Ventures',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 16 / 12,
              fontWeight: FontWeight.w600,
              color: onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_rounded, size: 12, color: outline),
              const SizedBox(width: 4),
              Text(
                'v$version',
                style: TextStyle(
                  fontSize: 10,
                  height: 14 / 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ErrorFooter extends StatelessWidget {
  const _ErrorFooter({
    required this.label,
    required this.error,
    required this.onRetry,
    required this.primary,
    required this.onSurfaceVariant,
  });

  final String label;
  final String error;
  final VoidCallback? onRetry;
  final Color primary;
  final Color onSurfaceVariant;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              height: 24 / 18,
              fontWeight: FontWeight.w700,
              color: primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 18 / 13,
              fontWeight: FontWeight.w500,
              color: onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Rd.lg),
              ),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try again'),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _BounceDots extends StatelessWidget {
  const _BounceDots({required this.controller, required this.colors});

  final AnimationController controller;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < colors.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Transform.translate(
                offset: Offset(
                  0,
                  -6 *
                      Curves.easeInOut.transform(
                        ((controller.value + i * 0.2) % 1.0) < 0.5
                            ? ((controller.value + i * 0.2) % 1.0) * 2
                            : 1 - (((controller.value + i * 0.2) % 1.0) - 0.5) * 2,
                      ),
                ),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colors[i],
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ArchitecturalGridPainter extends CustomPainter {
  const _ArchitecturalGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final dashed = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    _drawDashedCircle(canvas, center, 190, dashed, dash: 4, gap: 6);
    canvas.drawCircle(center, 140, paint..strokeWidth = 0.75);
    _drawDashedCircle(canvas, center, 80, dashed..strokeWidth = 1.25,
        dash: 2, gap: 4);

    final cross = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    _drawDashedLine(
      canvas,
      Offset(center.dx, center.dy - 190),
      Offset(center.dx, center.dy + 190),
      cross,
    );
    _drawDashedLine(
      canvas,
      Offset(center.dx - 190, center.dy),
      Offset(center.dx + 190, center.dy),
      cross,
    );

    final rectPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 140, height: 140),
        const Radius.circular(24),
      ),
      rectPaint,
    );
  }

  void _drawDashedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    final circumference = 2 * math.pi * radius;
    final count = (circumference / (dash + gap)).floor();
    final sweep = (dash / circumference) * 2 * math.pi;
    final step = 2 * math.pi / count;
    for (var i = 0; i < count; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * step,
        sweep,
        false,
        paint,
      );
    }
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 3.0;
    const gap = 3.0;
    final total = (b - a).distance;
    final direction = (b - a) / total;
    var drawn = 0.0;
    while (drawn < total) {
      final start = a + direction * drawn;
      final end = a + direction * math.min(drawn + dash, total);
      canvas.drawLine(start, end, paint);
      drawn += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _ArchitecturalGridPainter oldDelegate) =>
      oldDelegate.color != color;
}
