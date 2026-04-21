import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'color_generation_utils.dart';

// Target tile size in logical pixels — both angular width and radial height
const double _kTargetTilePx = 35.0;
const double _kMosaicFadeStartPx = 120.0;
const double _kMosaicFadeEndPx = 60.0;

class HueValueDiscPainter extends CustomPainter {
  final double zoom;
  const HueValueDiscPainter({this.zoom = 1.0});

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = size.width / 2;
    final Offset center = Offset(radius, radius);
    final double hubR = radius * kCenterNeutralFraction;
    final double available = radius - hubR;

    for (int ring = 0; ring < kRings; ring++) {
      final double ringInnerR = hubR + available * ring / kRings;
      final double ringOuterR = hubR + available * (ring + 1) / kRings;
      final double ringHeight = ringOuterR - ringInnerR; // px height of this ring

      // How many sub-rings fit in this ring at target tile height?
      final int subRings = math.max(1, (ringHeight / _kTargetTilePx).round());

      final double ringT = ring / (kRings - 1.0);

      for (int sub = 0; sub < subRings; sub++) {
        final double innerR = ringInnerR + ringHeight * sub / subRings;
        final double outerR = ringInnerR + ringHeight * (sub + 1) / subRings;
        final double midR = (innerR + outerR) / 2;
        final double strokeW = outerR - innerR;

        // Sub-ring position within parent ring (0=inner, 1=outer)
        final double subT = subRings > 1 ? sub / (subRings - 1.0) : 0.5;

        // Base color params for this sub-ring — vary value across sub-rings
        final double baseSat = 1.0 - ringT * 0.80;
        final double baseVal = calculateRingValueForDisplay(ring);
        final double displayVal = baseVal + ringT * (1.0 - baseVal) * 0.5;
        // Sub-rings vary value slightly: inner sub = slightly darker, outer = lighter
        final double subValOffset = (subT - 0.5) * 0.15;
        final double subVal = (displayVal + subValOffset).clamp(0.05, 1.0);

        // Angular tile size based on circumference — snap to power-of-2 degrees
        // to prevent tiles shifting position as zoom changes
        final double degPx = 2 * math.pi * midR / 360.0;
        final double rawTileAngle = _kTargetTilePx / degPx;
        // Snap to nearest value in [0.5, 1, 2, 3, 4, 6, 12] so tiles stay aligned
        const List<double> snapAngles = [0.5, 1.0, 2.0, 3.0, 4.0, 6.0, 12.0];
        double tileAngle = snapAngles.last;
        for (final snap in snapAngles) {
          if (rawTileAngle <= snap) { tileAngle = snap; break; }
        }
        final double tilePx = tileAngle * degPx;

        // Blend: large tiles = smooth, small tiles = mosaic
        final double t = ((tilePx - _kMosaicFadeEndPx) /
                (_kMosaicFadeStartPx - _kMosaicFadeEndPx))
            .clamp(0.0, 1.0);
        final double smoothAlpha = t;
        final double mosaicAlpha = 1.0 - t;

        final int numTiles = (360.0 / tileAngle).ceil();

        if (smoothAlpha > 0.01) {
          for (int angle = 0; angle < 360; angle++) {
            final Color c = HSVColor.fromAHSV(
              1.0, angle.toDouble(), baseSat, subVal,
            ).toColor();
            canvas.drawArc(
              Rect.fromCircle(center: center, radius: midR),
              (angle - 90) * math.pi / 180,
              math.pi / 180,
              false,
              Paint()
                ..color = smoothAlpha < 0.99 ? c.withValues(alpha: smoothAlpha) : c
                ..style = PaintingStyle.stroke
                ..strokeWidth = strokeW,
            );
          }
        }

        if (mosaicAlpha > 0.01) {
          for (int tile = 0; tile < numTiles; tile++) {
            final double hue = (tile * tileAngle) % 360;
            // Seed includes sub-ring so sub-rings get different colors
            final Color c = _sampleTileColor(ring, tile, hue, sub);
            canvas.drawArc(
              Rect.fromCircle(center: center, radius: midR),
              (tile * tileAngle - 90) * math.pi / 180,
              tileAngle * math.pi / 180,
              false,
              Paint()
                ..color = mosaicAlpha < 0.99 ? c.withValues(alpha: mosaicAlpha) : c
                ..style = PaintingStyle.stroke
                ..strokeWidth = strokeW,
            );
          }
        }
      }
    }

    _drawHub(canvas, center, hubR);
  }

  Color _sampleTileColor(int ring, int tile, double baseHue, int sub) {
    final int seed = ring * 1009 + tile * 97 + sub * 317;
    final rnd = math.Random(seed);
    final int ringKey = ring.clamp(0, 9);
    final ClusterWeights weights = ClusterWeights.byRing[ringKey];

    final double r = rnd.nextDouble();
    double cumulative = 0.0;
    Cluster cluster = Cluster.vivid;
    for (final entry in [
      (weights.pastel, Cluster.pastel),
      (weights.mid, Cluster.mid),
      (weights.vivid, Cluster.vivid),
      (weights.ink, Cluster.ink),
      (weights.neon, Cluster.neon),
    ]) {
      cumulative += entry.$1;
      if (r <= cumulative) { cluster = entry.$2; break; }
    }

    final double hueDrift = _hueDriftByRing[ringKey];
    final double hue = wrapHue(baseHue - hueDrift + rnd.nextDouble() * hueDrift * 2);
    final double s = cluster.sMin + rnd.nextDouble() * (cluster.sMax - cluster.sMin);
    final double v = cluster.vMin + rnd.nextDouble() * (cluster.vMax - cluster.vMin);
    return HSVColor.fromAHSV(1.0, hue, s.clamp(0.0, 1.0), v.clamp(0.0, 1.0)).toColor();
  }

  void _drawHub(Canvas canvas, Offset center, double hubR) {
    const int slices = 8;
    final double sliceSweep = 2 * math.pi / slices;
    final List<Color> greySlices = [
      const Color(0xFF101010), const Color(0xFF2A2A2A),
      const Color(0xFF505050), const Color(0xFF7A7A7A),
      const Color(0xFF9D9D9D), const Color(0xFFC3C3C3),
      const Color(0xFFE4E4E4), const Color(0xFFF8F8F8),
    ];
    for (int i = 0; i < slices; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: hubR),
        -math.pi / 2 + i * sliceSweep, sliceSweep, true,
        Paint()..style = PaintingStyle.fill..color = greySlices[i % greySlices.length],
      );
    }
    canvas.drawCircle(center, hubR, Paint()
      ..style = PaintingStyle.stroke..strokeWidth = 1.0
      ..color = Colors.black.withValues(alpha: 0.12));
  }

  @override
  bool shouldRepaint(HueValueDiscPainter old) => old.zoom != zoom;
}

const List<double> _hueDriftByRing = [12, 12, 10, 10, 8, 6, 5, 4, 3, 2];
