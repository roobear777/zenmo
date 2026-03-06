import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'color_generation_utils.dart';

/// CustomPainter that renders the circular color wheel with 10 rings and neutral hub
class HueValueDiscPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    final center = Offset(radius, radius);

    // Reserve inner 11% for neutral hub
    final double centerNeutralRadius = radius * kCenterNeutralFraction;
    final double available = radius - centerNeutralRadius;

    // Draw 10 colored rings
    for (int ring = 0; ring < kRings; ring++) {
      final double innerRadius =
          centerNeutralRadius + available * ring / kRings;
      final double outerRadius =
          centerNeutralRadius + available * (ring + 1) / kRings;
      final double value = calculateRingValueForDisplay(ring);
      final double opacity = calculateOpacity(ring);

      // Draw 30 segments per ring (12° each)
      for (int angle = 0; angle < 360; angle += kAngleStep) {
        final double startAngle = (angle - 90) * math.pi / 180;
        final double sweepAngle = kAngleStep * math.pi / 180;

        final paint = Paint()
          ..color = HSVColor.fromAHSV(
            opacity,
            angle.toDouble(),
            1.0,
            value,
          ).toColor()
          ..style = PaintingStyle.stroke
          ..strokeWidth = outerRadius - innerRadius;

        final double ringMidRadius = (innerRadius + outerRadius) / 2;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: ringMidRadius),
          startAngle,
          sweepAngle,
          false,
          paint,
        );
      }
    }

    // Draw neutral centre hub with 8 grey slices
    const int slices = 8;
    final double sliceSweep = 2 * math.pi / slices;
    final List<Color> greySlices = [
      const Color(0xFF101010),
      const Color(0xFF2A2A2A),
      const Color(0xFF505050),
      const Color(0xFF7A7A7A),
      const Color(0xFF9D9D9D),
      const Color(0xFFC3C3C3),
      const Color(0xFFE4E4E4),
      const Color(0xFFF8F8F8),
    ];

    for (int i = 0; i < slices; i++) {
      final double start = -math.pi / 2 + i * sliceSweep;
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = greySlices[i % greySlices.length];
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: centerNeutralRadius),
        start,
        sliceSweep,
        true,
        paint,
      );
    }

    // Optional subtle outline around the neutral hub for crispness
    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.black.withValues(alpha: 0.12);
    canvas.drawCircle(center, centerNeutralRadius, outlinePaint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
