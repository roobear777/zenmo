import 'dart:math' as math;
import 'package:flutter/material.dart';

enum NavigationButtonType { back, home, hexagon }

class NavigationButton extends StatelessWidget {
  final NavigationButtonType type;
  final VoidCallback onPressed;

  const NavigationButton({
    super.key,
    required this.type,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (type == NavigationButtonType.hexagon) {
      return GestureDetector(
        onTap: onPressed,
        child: CustomPaint(
          size: const Size(26, 26),
          painter: _HexOutlinePainter(),
        ),
      );
    }
    return IconButton(
      onPressed: onPressed,
      icon: Icon(
        type == NavigationButtonType.back ? Icons.chevron_left : Icons.home_outlined,
        color: const Color(0xFF6366F1),
        size: 32,
      ),
    );
  }
}

class _HexOutlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.height / 2 - 2;
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = math.pi / 6 + math.pi / 3 * i;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF555555)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_HexOutlinePainter old) => false;
}
