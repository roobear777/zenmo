// lib/widgets/scroll_hint_overlay.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

enum ScrollHintVisual { pillCaret, nakedSingle, nakedDouble }

class ScrollHintOverlay extends StatefulWidget {
  const ScrollHintOverlay({
    super.key,
    required this.child,
    this.initialDelay = const Duration(milliseconds: 500),
    this.maxShowDuration = const Duration(seconds: 5),
    this.hideAfterScrollDelta = 30.0,
    this.bottomPadding = 12.0,
    this.visual = ScrollHintVisual.pillCaret,
    this.chipSize = 56.0,
    this.brandColor,
    this.showBottomGradient = true,
    this.alwaysShow = false,
  });

  final Widget child;
  final Duration initialDelay;
  final Duration maxShowDuration;
  final double hideAfterScrollDelta;
  final double bottomPadding;

  final ScrollHintVisual visual;
  final double chipSize;
  final Color? brandColor;
  final bool showBottomGradient;

  /// If true, show the hint immediately and keep it until the user scrolls.
  /// Skips the auto-hide timer. Still hides on user scroll.
  final bool alwaysShow;

  @override
  State<ScrollHintOverlay> createState() => _ScrollHintOverlayState();
}

class _ScrollHintOverlayState extends State<ScrollHintOverlay>
    with SingleTickerProviderStateMixin {
  bool _canScroll = false;
  bool _forcedShow = false;
  bool _userScrolled = false;
  double _accumulatedDelta = 0.0;

  Timer? _delayTimer;
  Timer? _maxTimer;

  late final AnimationController _chevCtl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startTimers();
    });
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _maxTimer?.cancel();
    _chevCtl.dispose();
    super.dispose();
  }

  Duration _safeMax(Duration d) {
    // JS setTimeout cap ≈ 2^31−1 ms (~24.8 days). Stay below with margin.
    const webCap = Duration(days: 20);
    if (kIsWeb && d > webCap) return webCap;
    return d;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.maxScrollExtent > 0 && !_canScroll) {
          setState(() => _canScroll = true);
          _startTimers();
        }
        if (n is ScrollUpdateNotification) {
          final delta = n.scrollDelta ?? 0.0;
          if (delta.abs() > 0) {
            _accumulatedDelta += delta.abs();
            if (_accumulatedDelta >= widget.hideAfterScrollDelta) _hideNow();
          }
        }
        return false;
      },
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          widget.child,

          if (widget.showBottomGradient)
            const Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: 48,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(0, 0.2),
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.white],
                    ),
                  ),
                ),
              ),
            ),

          Positioned(
            left: 0,
            right: 0,
            bottom: widget.bottomPadding,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity:
                    ((widget.alwaysShow || _canScroll || _forcedShow) &&
                            !_userScrolled)
                        ? 1.0
                        : 0.0,
                duration: const Duration(milliseconds: 220),
                child: Center(child: _buildHint()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHint() {
    switch (widget.visual) {
      case ScrollHintVisual.nakedSingle:
        return _NakedSingleChevronVector(
          animation: _chevCtl,
          size: widget.chipSize,
          color: widget.brandColor ?? Colors.black,
        );
      case ScrollHintVisual.nakedDouble:
        return _NakedDoubleChevronVector(
          animation: _chevCtl,
          size: widget.chipSize,
          color: widget.brandColor ?? Colors.black,
        );
      case ScrollHintVisual.pillCaret:
      default:
        return _CaretChip(
          animation: _chevCtl,
          size: widget.chipSize,
          brandColor: widget.brandColor ?? Colors.white,
          textColor: Colors.black87,
        );
    }
  }

  void _startTimers() {
    _delayTimer?.cancel();
    _maxTimer?.cancel();

    _delayTimer = Timer(
      widget.alwaysShow ? Duration.zero : widget.initialDelay,
      () {
        if (!mounted || _userScrolled) return;
        if (widget.alwaysShow) {
          setState(() => _forcedShow = true);
        } else if (!_canScroll) {
          setState(() => _forcedShow = true);
        } else {
          setState(() {});
        }
      },
    );

    if (!widget.alwaysShow) {
      _maxTimer = Timer(_safeMax(widget.maxShowDuration), _hideNow);
    }
  }

  void _hideNow() {
    if (!_userScrolled && mounted) setState(() => _userScrolled = true);
    _delayTimer?.cancel();
    _maxTimer?.cancel();
  }
}

class _CaretChip extends StatelessWidget {
  const _CaretChip({
    required this.animation,
    required this.size,
    required this.brandColor,
    required this.textColor,
  });

  final Animation<double> animation;
  final double size;
  final Color brandColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.10),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeInOut));
    final fade = Tween<double>(
      begin: 0.25,
      end: 0.85,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeInOut));

    return SlideTransition(
      position: slide,
      child: FadeTransition(
        opacity: fade,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: brandColor.withOpacity(0.95),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.07),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: size * 0.35,
              vertical: size * 0.18,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: size * 0.45,
                  height: size * 0.45,
                  child: CustomPaint(
                    painter: _ChevronPainter(color: textColor),
                  ),
                ),
                SizedBox(width: size * 0.06),
                Text(
                  'Scroll',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                    color: textColor,
                    fontSize: size * 0.32,
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

/// Vector-drawn single chevron (no fonts).
class _NakedSingleChevronVector extends StatelessWidget {
  const _NakedSingleChevronVector({
    required this.animation,
    required this.size,
    required this.color,
  });

  final Animation<double> animation;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeInOut));
    final fade = Tween<double>(
      begin: 0.25,
      end: 0.95,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeInOut));

    return SlideTransition(
      position: slide,
      child: FadeTransition(
        opacity: fade,
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _ChevronPainter(color: color)),
        ),
      ),
    );
  }
}

/// Vector-drawn double chevrons (no fonts).
class _NakedDoubleChevronVector extends StatelessWidget {
  const _NakedDoubleChevronVector({
    required this.animation,
    required this.size,
    required this.color,
  });

  final Animation<double> animation;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeInOut));
    final fade = Tween<double>(
      begin: 0.25,
      end: 0.95,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeInOut));

    return SlideTransition(
      position: slide,
      child: FadeTransition(
        opacity: fade,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: CustomPaint(painter: _ChevronPainter(color: color)),
            ),
            SizedBox(height: size * 0.05),
            SizedBox(
              width: size,
              height: size,
              child: CustomPaint(painter: _ChevronPainter(color: color)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints a down chevron using strokes to mimic Material chevrons.
class _ChevronPainter extends CustomPainter {
  _ChevronPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.12
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;
    final y = h * 0.45;
    final xPad = w * 0.20;

    final p1 = Offset(xPad, y - h * 0.12);
    final p2 = Offset(w * 0.50, y + h * 0.12);
    final p3 = Offset(w - xPad, y - h * 0.12);

    final path =
        Path()
          ..moveTo(p1.dx, p1.dy)
          ..lineTo(p2.dx, p2.dy)
          ..lineTo(p3.dx, p3.dy);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ChevronPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
