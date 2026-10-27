import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/scheduler.dart';

import 'i18n.dart';
import 'theme.dart';

/// Global switch for decorative motion (Settings > Animations). Also honoured:
/// the phone's own "remove animations" accessibility option.
bool motionOn = true;

bool animOn(BuildContext context) =>
    motionOn && !MediaQuery.of(context).disableAnimations;

// ---------------------------------------------------------------- page transition

/// Direction-aware shared-axis slide + fade used for every screen push.
class SharedAxisBuilder extends PageTransitionsBuilder {
  const SharedAxisBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (!animOn(context)) return child;
    final dx = Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;
    final enter = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final leave = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeInOutCubic);
    return SlideTransition(
      position: Tween<Offset>(begin: Offset(0.10 * dx, 0), end: Offset.zero).animate(enter),
      child: FadeTransition(
        opacity: enter,
        child: SlideTransition(
          position: Tween<Offset>(begin: Offset.zero, end: Offset(-0.05 * dx, 0)).animate(leave),
          child: child,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- list entrance

/// Fades and lifts its child into place. [index] staggers a list.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int index;
  const FadeSlideIn({super.key, required this.child, this.index = 0});

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  Timer? _t;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!animOn(context)) {
      _c.value = 1;
      return;
    }
    final delay = math.min(widget.index, 8) * 55;
    if (delay == 0) {
      _c.forward();
    } else {
      _t = Timer(Duration(milliseconds: delay), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero).animate(a),
        child: widget.child,
      ),
    );
  }
}

// ---------------------------------------------------------------- numbers & bars

class CountUp extends StatelessWidget {
  final int value;
  final TextStyle? style;
  const CountUp(this.value, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    if (!animOn(context)) return Text('$value', style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => Text('${v.round()}', style: style),
    );
  }
}

class AnimatedBar extends StatelessWidget {
  final double value; // 0..1
  final double height;
  final Color? color;
  const AnimatedBar(this.value, {super.key, this.height = 10, this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final on = animOn(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: on ? 0 : value, end: value),
      duration: on ? const Duration(milliseconds: 900) : Duration.zero,
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: LinearProgressIndicator(
          value: v,
          minHeight: height,
          color: color ?? cs.primary,
          backgroundColor: cs.surfaceContainerHighest,
        ),
      ),
    );
  }
}

/// Circular progress that sweeps in, with a centre label.
class AnimatedRing extends StatelessWidget {
  final double value; // 0..1
  final double size;
  final Widget? center;
  final Color? color;
  const AnimatedRing(this.value, {super.key, this.size = 64, this.center, this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final on = animOn(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: on ? 0 : value, end: value),
      duration: on ? const Duration(milliseconds: 1000) : Duration.zero,
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                value: v,
                strokeWidth: size / 9,
                strokeCap: StrokeCap.round,
                color: color ?? cs.primary,
                backgroundColor: cs.surfaceContainerHighest,
              ),
            ),
            if (center != null) center!,
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- ECG motion graphic

/// One heartbeat cycle sampled over [0, 1] (baseline 0, up is positive).
double _beat(double x) {
  double g(double c, double w, double a) => a * math.exp(-math.pow((x - c) / w, 2));
  return g(0.18, 0.045, 0.16) + // P
      g(0.38, 0.012, -0.12) + // Q
      g(0.42, 0.014, 1.0) + // R
      g(0.46, 0.012, -0.28) + // S
      g(0.68, 0.07, 0.28); // T
}

class _EcgPainter extends CustomPainter {
  final double t; // 0..1 head position (scanner)
  final Color color;
  final double beats;
  final double strokeWidth;
  final bool animated;
  _EcgPainter(this.t, this.color, this.beats, this.strokeWidth, this.animated);

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height * 0.62;
    final amp = size.height * 0.52;
    final n = (size.width / 2).ceil();
    final pts = <Offset>[];
    for (var i = 0; i <= n; i++) {
      final u = i / n;
      final ph = (u * beats) % 1.0;
      pts.add(Offset(u * size.width, mid - _beat(ph) * amp));
    }
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color.withAlpha(animated ? 55 : 220);
    final full = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      full.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(full, base);
    if (!animated) return;

    // bright trailing segment + glowing head
    final headIdx = (t * n).floor().clamp(0, n);
    final tail = (n * 0.28).round();
    final start = math.max(0, headIdx - tail);
    for (var i = start; i < headIdx; i++) {
      final f = (i - start) / math.max(1, headIdx - start);
      final seg = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * (1.0 + f * 0.6)
        ..strokeCap = StrokeCap.round
        ..color = color.withAlpha((40 + 215 * f).round());
      canvas.drawLine(pts[i], pts[i + 1], seg);
    }
    final head = pts[headIdx];
    canvas.drawCircle(head, strokeWidth * 3.2, Paint()..color = color.withAlpha(60));
    canvas.drawCircle(head, strokeWidth * 1.6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_EcgPainter old) =>
      old.t != t || old.color != color || old.beats != beats || old.animated != animated;
}

/// Looping heartbeat line. Cheap: one controller, one painter.
class EcgBanner extends StatefulWidget {
  final double height;
  final Color color;
  final double beats;
  final double strokeWidth;
  const EcgBanner({
    super.key,
    this.height = 56,
    required this.color,
    this.beats = 3,
    this.strokeWidth = 2.2,
  });

  @override
  State<EcgBanner> createState() => _EcgBannerState();
}

class _EcgBannerState extends State<EcgBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));

  @override
  void initState() {
    super.initState();
    _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = animOn(context);
    // the heartbeat itself is a medical symbol: never mirror it in RTL
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(
            painter: _EcgPainter(
              on ? _c.value : 1,
              widget.color,
              widget.beats,
              widget.strokeWidth,
              on,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- empty states

enum EmptyKind { cases, learn, calendar, search, generic }

IconData _emptyIcon(EmptyKind k) {
  switch (k) {
    case EmptyKind.cases:
      return Icons.assignment_outlined;
    case EmptyKind.learn:
      return Icons.menu_book_outlined;
    case EmptyKind.calendar:
      return Icons.event_available_outlined;
    case EmptyKind.search:
      return Icons.search_off;
    case EmptyKind.generic:
      return Icons.inbox_outlined;
  }
}

/// Animated illustration for empty lists: expanding pulse rings, a floating icon.
class EmptyState extends StatefulWidget {
  final EmptyKind kind;
  final String title;
  final String message;
  final Widget? action;
  const EmptyState({
    super.key,
    this.kind = EmptyKind.generic,
    this.title = '',
    this.message = '',
    this.action,
  });

  @override
  State<EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<EmptyState> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 3));

  @override
  void initState() {
    super.initState();
    _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final on = animOn(context);
    return FadeSlideIn(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 150,
                height: 150,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, __) {
                    final bob = on ? math.sin(_c.value * 2 * math.pi) * 5 : 0.0;
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size(150, 150),
                          painter: _RingsPainter(on ? _c.value : 0.4, cs.primary),
                        ),
                        Transform.translate(
                          offset: Offset(0, bob),
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              gradient: paletteGradient(context, soft: true),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Icon(_emptyIcon(widget.kind), size: 36, color: cs.primary),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              if (widget.title.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(widget.title,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center),
              ],
              if (widget.message.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(widget.message,
                    style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    textAlign: TextAlign.center),
              ],
              if (widget.action != null) ...[
                const SizedBox(height: 16),
                widget.action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  final double t;
  final Color color;
  _RingsPainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1.0;
      final r = 36 + p * 39;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withAlpha(((1 - p) * 90).round()),
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.t != t || old.color != color;
}

// ---------------------------------------------------------------- logo + splash

/// App mark: gradient tile, medical cross and a heartbeat line.
class MedLogMark extends StatelessWidget {
  final double size;
  const MedLogMark({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: paletteGradient(context),
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withAlpha(90),
            blurRadius: size * 0.3,
            offset: Offset(0, size * 0.1),
          ),
        ],
      ),
      child: CustomPaint(painter: _MarkPainter()),
    );
  }
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width * 0.075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // cross
    final cx = s.width * 0.5, cy = s.height * 0.34, a = s.width * 0.12;
    canvas.drawLine(Offset(cx - a, cy), Offset(cx + a, cy), w);
    canvas.drawLine(Offset(cx, cy - a), Offset(cx, cy + a), w);
    // heartbeat
    final y = s.height * 0.68;
    final p = Path()
      ..moveTo(s.width * 0.14, y)
      ..lineTo(s.width * 0.36, y)
      ..lineTo(s.width * 0.43, y - s.height * 0.10)
      ..lineTo(s.width * 0.52, y + s.height * 0.16)
      ..lineTo(s.width * 0.60, y - s.height * 0.22)
      ..lineTo(s.width * 0.67, y)
      ..lineTo(s.width * 0.86, y);
    canvas.drawPath(p, w);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => false;
}

/// First thing the user sees: ECG draws across, logo pops in, designer credit fades up.
class SplashScreen extends StatefulWidget {
  final VoidCallback onDone;
  const SplashScreen({super.key, required this.onDone});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _finish();
    });
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!animOn(context)) {
        _finish();
      } else {
        _c.forward();
      }
    });
  }

  void _finish() {
    if (_fired) return;
    _fired = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _finish,
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(gradient: paletteGradient(context, soft: true)),
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) {
              final t = _c.value;
              double iv(double a, double b, [Curve c = Curves.easeOutCubic]) =>
                  c.transform(((t - a) / (b - a)).clamp(0.0, 1.0));
              final line = iv(0.0, 0.45, Curves.easeInOut);
              final logo = iv(0.30, 0.62, Curves.elasticOut);
              final name = iv(0.50, 0.75);
              final credit = iv(0.68, 0.92);
              return SafeArea(
                child: Column(
                  children: [
                    const Spacer(flex: 3),
                    Transform.scale(
                      scale: 0.4 + 0.6 * logo,
                      child: Opacity(
                        opacity: iv(0.30, 0.45).clamp(0.0, 1.0),
                        child: const MedLogMark(size: 116),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Opacity(
                      opacity: name,
                      child: Transform.translate(
                        offset: Offset(0, 14 * (1 - name)),
                        child: Text('MedLog',
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: cs.onSurface,
                            )),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Opacity(
                      opacity: name,
                      child: Text('Your clinical logbook',
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15)),
                    ),
                    const SizedBox(height: 36),
                    SizedBox(
                      height: 56,
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: ClipRect(
                          clipper: _RevealClipper(line),
                          child: CustomPaint(
                            size: const Size(double.infinity, 56),
                            painter: _EcgPainter(1, cs.primary, 4, 2.4, false),
                          ),
                        ),
                      ),
                    ),
                    const Spacer(flex: 3),
                    Opacity(
                      opacity: credit,
                      child: Transform.translate(
                        offset: Offset(0, 10 * (1 - credit)),
                        child: Column(
                          children: [
                            m(designedBy, cs.onSurfaceVariant, 13, FontWeight.w500),
                            const SizedBox(height: 4),
                            m(designerName, cs.onSurface, 17, FontWeight.w700),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

Widget m(String s, Color c, double size, FontWeight w, {TextAlign align = TextAlign.center}) =>
    Text(s, textAlign: align, style: TextStyle(color: c, fontSize: size, fontWeight: w));

class _RevealClipper extends CustomClipper<Rect> {
  final double f;
  _RevealClipper(this.f);
  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * f, size.height);
  @override
  bool shouldReclip(_RevealClipper old) => old.f != f;
}
