// lib/utils/mosaic_palette.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

enum MosaicMode { random, ordered }

/// Build colors for the mosaic.
/// - random: same behavior as before (mid–high S/V).
/// - ordered: even hue spread within an arc around `baseHue`, lively S/V,
///            farthest-point sampled (optimized) for local contrast.
List<Color> buildMosaicColors({
  required int count,
  required MosaicMode mode,
  // Needed for ordered mode to keep within the chosen color family:
  double? baseHueDeg, // 0..360
  int? ringIndex, // 0..9 (we clamp)
  int? seed, // optional, used by random
}) {
  if (mode == MosaicMode.ordered) {
    return _buildOrderedMosaicColors(
      count,
      baseHueDeg: baseHueDeg ?? 0.0,
      ringIndex: (ringIndex ?? 5).clamp(0, 9),
    );
  } else {
    return _buildRandomMosaicColors(count, seed: seed);
  }
}

/// Your existing randomized approach, kept stable; seed optional.
List<Color> _buildRandomMosaicColors(int n, {int? seed}) {
  final rnd = seed != null ? math.Random(seed) : math.Random();
  final List<Color> out = [];
  for (var i = 0; i < n; i++) {
    // Bias away from mud: clamp S,V to mid–high bands.
    final h = rnd.nextDouble() * 360.0;
    final s = 0.55 + rnd.nextDouble() * 0.45; // [0.55, 1.0]
    final v = 0.58 + rnd.nextDouble() * 0.39; // [0.58, 0.97]
    out.add(HSVColor.fromAHSV(1.0, h, s, v).toColor());
  }
  return out;
}

/// Ordered palette: build candidates in a hue *window* around baseHue, then
/// farthest-point sample to `n`. Avoid near-black/near-white mud.
List<Color> _buildOrderedMosaicColors(
  int n, {
  required double baseHueDeg,
  required int ringIndex,
}) {
  // ===== Step 1: select grid sizes to comfortably oversample (≈1.3×N). =====
  final int target = (n * 13 ~/ 10); // ~1.3x
  List<double> sLadder = [0.55, 0.70, 0.85, 1.0];
  List<double> vLadder = [0.55, 0.70, 0.85];

  // Expand ladders if total combinations are too small.
  int gridCount = sLadder.length * vLadder.length;
  while (gridCount < target ~/ 12) {
    if (vLadder.length <= sLadder.length) {
      vLadder = _expandLadder(vLadder, preferHigh: true);
    } else {
      sLadder = _expandLadder(sLadder, preferHigh: true);
    }
    gridCount = sLadder.length * vLadder.length;
  }

  // ===== Step 2: build candidates within a hue window centered on base hue. =====
  // Window width by ring (deg): inner rings wider, outer rings tighter.
  const List<double> spanByRingDeg = <double>[
    92,
    84,
    76,
    68,
    60,
    56,
    52,
    48,
    44,
    40,
  ];
  final double spanDeg = spanByRingDeg[ringIndex.clamp(0, 9)];
  final double startDeg = baseHueDeg - (spanDeg / 2);

  // Hue steps needed to reach the target candidate count.
  final int hueStepsNeeded = (target / (sLadder.length * vLadder.length))
      .ceil()
      .clamp(12, 96);
  final double stepDeg = spanDeg / hueStepsNeeded;

  double wrap(double h) => (h % 360.0 + 360.0) % 360.0;

  final List<_HSV> candidates = [];
  for (int hi = 0; hi < hueStepsNeeded; hi++) {
    final double h = wrap(startDeg + hi * stepDeg);
    for (final s in sLadder) {
      for (final v in vLadder) {
        if (s < 0.45 || v < 0.50 || v > 0.98) {
          continue; // avoid mud & near-white
        }
        candidates.add(_HSV(h: h, s: s, v: v));
      }
    }
  }
  if (candidates.isEmpty) {
    // Fallback: ensure we return something.
    return _buildRandomMosaicColors(n);
  }

  // ===== Step 3: farthest-point sampling (optimized; no removeAt in hot loop). =====
  final int want = math.min(n, candidates.length);
  final int m = candidates.length;
  final List<_HSV> picked = [];
  final List<bool> used = List<bool>.filled(m, false);
  final List<double> minDist = List<double>.filled(m, double.infinity);

  // Seed with 6 evenly spaced candidates.
  final int seedCount = math.min(6, m);
  for (var s = 0; s < seedCount && picked.length < want; s++) {
    final int idx = ((s * m) / seedCount).floor();
    if (!used[idx]) {
      used[idx] = true;
      picked.add(candidates[idx]);
      // update minDist against this seed
      for (int i = 0; i < m; i++) {
        if (used[i]) continue;
        final d = _hsvDistance(candidates[i], candidates[idx]);
        if (d < minDist[i]) minDist[i] = d;
      }
    }
  }

  // Greedy farthest picks
  while (picked.length < want) {
    double best = -1.0;
    int bestIdx = -1;
    for (int i = 0; i < m; i++) {
      if (used[i]) continue;
      if (minDist[i] > best) {
        best = minDist[i];
        bestIdx = i;
      }
    }
    if (bestIdx == -1) break;
    used[bestIdx] = true;
    picked.add(candidates[bestIdx]);
    // update minDist only against the newly added point
    for (int i = 0; i < m; i++) {
      if (used[i]) continue;
      final d = _hsvDistance(candidates[i], candidates[bestIdx]);
      if (d < minDist[i]) minDist[i] = d;
    }
  }

  // ===== Step 4: serpentine ordering to increase local contrast on Masonry rows. =====
  final ordered = _serpentineByHueSV(picked);

  return ordered
      .map((e) => HSVColor.fromAHSV(1.0, e.h, e.s, e.v).toColor())
      .toList(growable: false);
}

class _HSV {
  final double h, s, v;
  const _HSV({required this.h, required this.s, required this.v});
}

double _hsvDistance(_HSV a, _HSV b) {
  // Circular hue distance scaled to [0,1]
  final diff = (a.h - b.h).abs();
  final dh = math.min(diff, 360.0 - diff) / 180.0; // max 1.0
  final ds = (a.s - b.s).abs(); // [0..1]
  final dv = (a.v - b.v).abs(); // [0..1]
  // Weight hue a bit more; value next; saturation last.
  return (1.6 * dh) + (1.2 * dv) + (1.0 * ds);
}

List<_HSV> _serpentineByHueSV(List<_HSV> list) {
  // Sort by hue, then chunk into rows and alternate S/V within rows.
  final sorted = list.toList()..sort((a, b) => a.h.compareTo(b.h));
  // Estimate row size similar to Masonry average (≈ 8–14).
  final rowSize = math.max(8, (sorted.length / 10).round());
  final out = <_HSV>[];

  for (var i = 0; i < sorted.length; i += rowSize) {
    final row = sorted.sublist(i, math.min(i + rowSize, sorted.length));
    // Alternate by (s then v) within the row for contrast.
    row.sort((a, b) {
      final sh = a.h.compareTo(b.h);
      if (sh != 0) return sh;
      final sv = b.s.compareTo(a.s); // high S first
      if (sv != 0) return sv;
      return b.v.compareTo(a.v); // then high V
    });
    out.addAll((((i ~/ rowSize) % 2) == 1) ? row.reversed : row);
  }
  return out;
}

int _nearestDivisible(int x, int by) {
  if (x % by == 0) return x;
  return x + (by - (x % by));
}

List<double> _expandLadder(List<double> ladder, {bool preferHigh = false}) {
  // Insert midpoints between existing values; prefer adding near the high end.
  final out = <double>[];
  for (var i = 0; i < ladder.length - 1; i++) {
    final a = ladder[i];
    final b = ladder[i + 1];
    out
      ..add(a)
      ..add((a + b) / 2.0);
  }
  out.add(ladder.last);
  if (preferHigh && out.length == ladder.length) {
    final last = ladder.last;
    final extra = math.min(0.98, last + 0.07);
    if (!out.contains(extra)) out.add(extra);
  }
  // Clamp to [0,1]
  return out.map((v) => v.clamp(0.0, 1.0)).toList();
}
