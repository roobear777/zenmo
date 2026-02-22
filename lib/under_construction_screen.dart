import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Zenmo Under-Construction screen
/// - Color wheel + warning triangle
/// - Typewriter animation: types "zenmo", blinks, erases, repeats
class UnderConstructionScreen extends StatelessWidget {
  const UnderConstructionScreen({super.key, this.onRetry});
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWide = MediaQuery.of(context).size.width > 500;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AspectRatio(
                    aspectRatio: 1.2,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Color wheel behind
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: CustomPaint(painter: _ColorWheelPainter()),
                          ),
                        ),
                        // Warning sign in front (typewriter inside)
                        FractionallySizedBox(
                          widthFactor: isWide ? 0.66 : 0.78,
                          child: const AspectRatio(
                            aspectRatio: 1,
                            child: _AnimatedTypewriterSign(),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Title
                  Text(
                    "We’re mixing colors…",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Body
                  Text(
                    "Zenmo is getting a quick tune-up.\nCome back a little later.",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.textTheme.bodyLarge?.color?.withOpacity(0.8),
                      height: 1.35,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Optional spinner + button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        "Checking status…",
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.textTheme.bodyMedium?.color?.withOpacity(
                            0.7,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  if (onRetry != null)
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text("Try again"),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),

                  const SizedBox(height: 8),

                  // Tiny footer
                  Opacity(
                    opacity: 0.55,
                    child: Text(
                      "Tip: if you’re testing, clear cache or hard-reload.",
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall,
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

/// Rainbow wheel painter
class _ColorWheelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.46;
    final stroke = radius * 0.18;

    const slices = 24;
    final sweep = (2 * math.pi) / slices;

    for (int i = 0; i < slices; i++) {
      final hue = (i / slices) * 360.0;
      final color = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
      final paint =
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.butt
            ..color = color;
      final rect = Rect.fromCircle(center: center, radius: radius);
      final start = i * sweep + (-math.pi / 2);
      canvas.drawArc(rect, start, sweep * 0.92, false, paint);
    }

    final inner =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5)
          ..color = Colors.black.withOpacity(0.06);
    final rect = Rect.fromCircle(center: center, radius: radius * 0.985);
    canvas.drawArc(rect, 0, 2 * math.pi, false, inner);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Animated wrapper: drives type/hold/erase loop + cursor blink
class _AnimatedTypewriterSign extends StatefulWidget {
  const _AnimatedTypewriterSign();

  @override
  State<_AnimatedTypewriterSign> createState() =>
      _AnimatedTypewriterSignState();
}

class _AnimatedTypewriterSignState extends State<_AnimatedTypewriterSign>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;

  // Slower timings (ms)
  static const int typeMsPerChar = 220; // typing speed
  static const int holdMs = 900; // full word visible
  static const int eraseMsPerChar = 160; // backspace speed
  static const int blinkMs = 700; // cursor blink period
  static const String word = 'zenmo';

  late final int _typeTotal = typeMsPerChar * word.length;
  late final int _eraseTotal = eraseMsPerChar * word.length;
  late final int _cycleMs = _typeTotal + holdMs + _eraseTotal;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _cycleMs),
    )..repeat();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctl,
      builder: (_, __) {
        final tMs = (_ctl.value * _cycleMs).round();

        int shown; // number of characters visible
        bool cursorOn;

        if (tMs < _typeTotal) {
          // Typing forward
          shown = ((tMs / typeMsPerChar).floor()).clamp(0, word.length);
          cursorOn = true;
        } else if (tMs < _typeTotal + holdMs) {
          // Hold full word with blinking cursor
          shown = word.length;
          cursorOn = ((tMs ~/ (blinkMs / 2)) % 2) == 0;
        } else {
          // Erasing backward
          final intoErase = tMs - (_typeTotal + holdMs);
          final gone = ((intoErase / eraseMsPerChar).floor()).clamp(
            0,
            word.length,
          );
          shown = (word.length - gone).clamp(0, word.length);
          cursorOn = true;
        }

        return CustomPaint(
          painter: _TypewriterSignPainter(
            text: word.substring(0, shown),
            fullWord: word, // used for centering
            cursorVisible: cursorOn,
          ),
        );
      },
    );
  }
}

/// Draws the red warning triangle, clips inner, then types text + cursor
class _TypewriterSignPainter extends CustomPainter {
  _TypewriterSignPainter({
    required this.text,
    required this.fullWord,
    required this.cursorVisible,
  });

  final String text;
  final String fullWord;
  final bool cursorVisible;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // Triangle
    final p1 = Offset(w * 0.5, h * 0.06);
    final p2 = Offset(w * 0.06, h * 0.92);
    final p3 = Offset(w * 0.94, h * 0.92);

    final triStroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.11
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.red.shade600;

    final tri =
        Path()
          ..moveTo(p1.dx, p1.dy)
          ..lineTo(p2.dx, p2.dy)
          ..lineTo(p3.dx, p3.dy)
          ..close();
    canvas.drawPath(tri, triStroke);

    // Inner white + clip
    final inner =
        Path()
          ..moveTo(p1.dx, p1.dy + w * 0.05)
          ..lineTo(p2.dx + w * 0.06, p2.dy - w * 0.06)
          ..lineTo(p3.dx - w * 0.06, p3.dy - w * 0.06)
          ..close();
    canvas.save();
    canvas.clipPath(inner);
    canvas.drawPath(inner, Paint()..color = Colors.white);

    // Lane for the typewriter line
    final lane = Rect.fromLTWH(w * 0.12, h * 0.50, w * 0.76, h * 0.26);

    // Consistent text style (monospace typewriter feel)
    final textStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: w * 0.16,
      fontWeight: FontWeight.w700,
      color: Colors.black87,
      letterSpacing: 0.0,
    );

    // 1) Measure FULL word to find centered left edge
    final fullTp = TextPainter(
      text: TextSpan(text: fullWord, style: textStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: lane.width);

    final leftEdgeX = lane.left + (lane.width - fullTp.width) / 2;
    final baselineY = lane.top + (lane.height - fullTp.height) / 2;

    // 2) Layout only the currently typed substring
    final tp = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: lane.width);

    // Draw the substring starting from the centered left edge
    final baseOffset = Offset(leftEdgeX, baselineY);
    tp.paint(canvas, baseOffset);

    // 3) Cursor right after the typed substring
    if (cursorVisible) {
      final cursorX = leftEdgeX + tp.width + w * 0.008;
      final cursorTop = baselineY + h * 0.01;
      final cursorBottom = baselineY + tp.height - h * 0.01;
      final cursorPaint =
          Paint()
            ..color = Colors.black87
            ..strokeWidth = math.max(2.0, w * 0.008)
            ..strokeCap = StrokeCap.square;

      canvas.drawLine(
        Offset(cursorX, cursorTop),
        Offset(cursorX, cursorBottom),
        cursorPaint,
      );
    }

    canvas.restore(); // exit clip
  }

  @override
  bool shouldRepaint(covariant _TypewriterSignPainter old) =>
      old.text != text ||
      old.cursorVisible != cursorVisible ||
      old.fullWord != fullWord;
}
