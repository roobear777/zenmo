import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Constants for color picker wheel
const double kCenterNeutralFraction = 0.11;
const int kRings = 10;
const int kAngleStep = 12;

/// HSV color representation with utility methods
class HSV {
  final double h; // Hue: 0-360 degrees
  final double s; // Saturation: 0.0-1.0
  final double v; // Value/Brightness: 0.0-1.0

  const HSV({required this.h, required this.s, required this.v});

  /// Create a copy with optional field overrides
  HSV copyWith({double? h, double? s, double? v}) =>
      HSV(h: h ?? this.h, s: s ?? this.s, v: v ?? this.v);

  /// Convert to Flutter Color
  Color toColor() => HSVColor.fromAHSV(1.0, h, s, v).toColor();

  @override
  String toString() =>
      'HSV(h: ${h.toStringAsFixed(1)}, s: ${s.toStringAsFixed(2)}, v: ${v.toStringAsFixed(2)})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HSV &&
          runtimeType == other.runtimeType &&
          (h - other.h).abs() < 0.001 &&
          (s - other.s).abs() < 0.001 &&
          (v - other.v).abs() < 0.001;

  @override
  int get hashCode => Object.hash(h, s, v);
}

/// Cluster definition for randomized mode color generation
class Cluster {
  final double sMin;
  final double sMax;
  final double vMin;
  final double vMax;

  const Cluster({
    required this.sMin,
    required this.sMax,
    required this.vMin,
    required this.vMax,
  });

  // Predefined clusters
  static const pastel = Cluster(sMin: 0.28, sMax: 0.50, vMin: 0.85, vMax: 0.98);
  static const mid = Cluster(sMin: 0.50, sMax: 0.75, vMin: 0.60, vMax: 0.85);
  static const vivid = Cluster(sMin: 0.75, sMax: 0.95, vMin: 0.60, vMax: 0.90);
  static const ink = Cluster(sMin: 0.75, sMax: 1.00, vMin: 0.30, vMax: 0.55);
  static const neon = Cluster(sMin: 0.95, sMax: 1.00, vMin: 0.97, vMax: 1.00);
}

/// Cluster weights for randomized mode
class ClusterWeights {
  final double pastel;
  final double mid;
  final double vivid;
  final double ink;
  final double neon;

  const ClusterWeights({
    this.pastel = 0.0,
    this.mid = 0.0,
    this.vivid = 0.0,
    this.ink = 0.0,
    this.neon = 0.0,
  });

  /// Ring-specific cluster weights (exact values from requirements)
  static const List<ClusterWeights> byRing = [
    ClusterWeights(mid: 0.20, vivid: 0.10, ink: 0.60, neon: 0.10), // ring 0
    ClusterWeights(mid: 0.35, vivid: 0.20, ink: 0.35, neon: 0.10), // ring 1
    ClusterWeights(mid: 0.40, vivid: 0.28, ink: 0.22, neon: 0.10), // ring 2
    ClusterWeights(mid: 0.45, vivid: 0.35, ink: 0.12, neon: 0.08), // ring 3
    ClusterWeights(
      vivid: 0.50,
      mid: 0.35,
      pastel: 0.07,
      ink: 0.05,
      neon: 0.03,
    ), // ring 4
    ClusterWeights(vivid: 0.55, mid: 0.30, pastel: 0.10, neon: 0.05), // ring 5
    ClusterWeights(vivid: 0.40, mid: 0.30, pastel: 0.25, neon: 0.05), // ring 6
    ClusterWeights(pastel: 0.40, mid: 0.35, vivid: 0.20, neon: 0.05), // ring 7
    ClusterWeights(pastel: 0.62, mid: 0.18, vivid: 0.08, neon: 0.12), // ring 8
    ClusterWeights(pastel: 0.68, mid: 0.16, vivid: 0.04, neon: 0.12), // ring 9
  ];

  /// Convert weights to counts for a given total
  ClusterCounts asCounts(int total) {
    final List<double> ws = [pastel, mid, vivid, ink, neon];
    final double sum = ws.fold(0.0, (a, b) => a + b);
    final List<int> raw = ws
        .map((w) => (w / (sum == 0 ? 1 : sum) * total).floor())
        .toList();

    int used = raw.fold(0, (a, b) => a + b);
    int idx = 0;
    while (used < total) {
      raw[idx % raw.length] += 1;
      used++;
      idx++;
    }

    return ClusterCounts(
      pastel: raw[0],
      mid: raw[1],
      vivid: raw[2],
      ink: raw[3],
      neon: raw[4],
    );
  }
}

/// Cluster counts after weight distribution
class ClusterCounts {
  final int pastel;
  final int mid;
  final int vivid;
  final int ink;
  final int neon;

  const ClusterCounts({
    required this.pastel,
    required this.mid,
    required this.vivid,
    required this.ink,
    required this.neon,
  });
}

/// Calculate hue from angle in radians
/// Formula: (angleRadians * 180 / pi + 360 + 90) % 360
double calculateHueFromAngle(double angleRadians) {
  return (angleRadians * 180 / math.pi + 360 + 90) % 360;
}

/// Calculate ring value for display (wheel rendering)
/// Formula: pow((ringIndex + 1) / 10, 0.5)
double calculateRingValueForDisplay(int ringIndex) {
  return math.pow((ringIndex + 1) / kRings, 0.5).toDouble();
}

/// Calculate ring value for mosaic generation (color selection)
/// Formula: pow((ringIndex + 1) / 10, 0.1)
double calculateRingValueForMosaic(int ringIndex) {
  return math.pow((ringIndex + 1) / kRings, 0.1).toDouble();
}

/// Calculate opacity for rings 5-9
/// Formula: 1.0 - ((ringIndex - 5 + 1) / 5).clamp(0.0, 1.0)
double calculateOpacity(int ringIndex) {
  const int fadeStartRing = 5;
  const int maxFadeRings = kRings - fadeStartRing;

  if (ringIndex < fadeStartRing) {
    return 1.0;
  }

  return 1.0 - ((ringIndex - fadeStartRing + 1) / maxFadeRings).clamp(0.0, 1.0);
}

/// Wrap hue to [0, 360) range
double wrapHue(double h) {
  final hh = h % 360.0;
  return hh < 0 ? hh + 360.0 : hh;
}

/// Clamp value to [0.0, 1.0] range
double clamp01(double x) => x < 0 ? 0 : (x > 1 ? 1 : x);

/// Apply ease function with gamma curve
double ease(double x, double gamma) =>
    math.pow(x.clamp(0.0, 1.0), gamma).toDouble();

/// Generate organized palette with deterministic saturation/value gradients
/// Returns exactly [tileCount] colors arranged in [cols] columns
List<Color> generateOrganizedPalette({
  required double baseHue,
  required int ringIndex,
  int tileCount = 600,
  int cols = 6,
}) {
  final int ringKey = ringIndex.clamp(0, 9);
  final int rows = (tileCount / cols).ceil();
  final double hue = baseHue;

  // Ring interpolation factor (0 = inner, 1 = outer)
  final double ringT = ringKey / 9.0;

  // Value (brightness) ramp parameters
  const double vMax = 1.00;
  const double vMinInner = 0.16;
  const double vMinOuter = 0.30;
  final double vMin = vMinInner + (vMinOuter - vMinInner) * ringT;

  const double vGammaInner = 0.78;
  const double vGammaOuter = 0.62;
  final double vGamma = vGammaInner + (vGammaOuter - vGammaInner) * ringT;

  // Saturation band parameters
  const double strongInner = 1.00;
  const double strongOuter = 0.70;
  const double weakInner = 0.20;
  const double weakOuter = 0.05;

  final double sStrong = strongInner + (strongOuter - strongInner) * ringT;
  final double sWeak = weakInner + (weakOuter - weakInner) * ringT;
  const double sGamma = 1.10;

  final List<Color> colors = List<Color>.generate(tileCount, (i) {
    final int row = i ~/ cols;
    final int col = i % cols;

    // Vertical value ramp (top = brightest, bottom = darkest)
    final double tV = rows <= 1 ? 0.0 : row / (rows - 1);
    final double tVFlipped = 1.0 - tV;
    double v = vMin + (vMax - vMin) * ease(tVFlipped, vGamma);

    // Horizontal saturation ramp (left = strongest, right = most washed-out)
    final double tS = cols <= 1 ? 0.0 : col / (cols - 1);
    final double sEdgeMax = sStrong;
    final double sEdgeMin = sWeak;
    double s = sEdgeMax + (sEdgeMin - sEdgeMax) * ease(tS, sGamma);
    s = clamp01(s);

    // Avoid extremely dead, muddy tiles
    if (s * v < 0.06) {
      v = (v + 0.035).clamp(vMin, vMax);
    }

    return HSVColor.fromAHSV(1.0, hue, s, v).toColor();
  });

  return colors;
}

// Randomized mode constants
const double _sMinGlobal = 0.24;
const double _vMinGlobal = 0.32;
const double _vMaxGlobal = 0.98;
const double _antiClumpThreshold = 0.085;

// Ring-specific biases
const List<double> _vBiasByRing = [
  -0.10,
  -0.08,
  -0.06,
  -0.03,
  -0.01,
  0.01,
  0.03,
  0.06,
  0.08,
  0.10,
];
const List<double> _sBiasByRing = [
  0.04,
  0.03,
  0.02,
  0.01,
  0.00,
  -0.01,
  -0.02,
  -0.03,
  -0.04,
  -0.06,
];

// Hue drift per ring
const List<double> _hueDrift = [12, 12, 10, 10, 8, 6, 5, 4, 3, 2];

/// Apply ring-specific saturation and value bias
HSV _applyRingBias(HSV c, int ring) {
  final int r = ring.clamp(0, 9);
  final double s = math.max(_sMinGlobal, math.min(1.0, c.s + _sBiasByRing[r]));
  final double v = math.max(
    _vMinGlobal,
    math.min(_vMaxGlobal, c.v + _vBiasByRing[r]),
  );
  return c.copyWith(s: s, v: v);
}

/// Apply anti-brown adjustment to prevent muddy colors
HSV _antiBrownAdjust(HSV c) {
  final double h = (c.h % 360);
  final bool inOrangeRed = (h >= 350 || h < 30) || (h >= 30 && h < 50);
  final bool inOliveZone = (h >= 50 && h < 95);

  HSV result = c;
  if (inOrangeRed && c.v < 0.58) {
    result = result.copyWith(v: 0.60 + c.v * 0.05);
  }
  if (inOliveZone && c.v < 0.50) {
    result = result.copyWith(v: 0.58 + c.v * 0.04);
  }
  if (c.s < 0.30) {
    result = result.copyWith(s: 0.30);
  }
  return result;
}

/// Calculate HSV distance between two colors
double _hsvDistance(HSV a, HSV b) {
  final double dh = (a.h - b.h).abs();
  final double hueDiff = (dh > 180 ? 360 - dh : dh) / 180.0;
  final double ds = (a.s - b.s).abs();
  final double dv = (a.v - b.v).abs();
  const double wH = 0.6, wS = 1.0, wV = 1.0;
  return math.sqrt(
    (hueDiff * wH) * (hueDiff * wH) +
        (ds * wS) * (ds * wS) +
        (dv * wV) * (dv * wV),
  );
}

/// Apply anti-clumping algorithm to prevent similar adjacent colors
void _antiClump(List<HSV> list, math.Random rnd, {required double threshold}) {
  for (int i = 1; i < list.length; i++) {
    final HSV a = list[i - 1];
    final HSV b = list[i];
    if (_hsvDistance(a, b) < threshold) {
      bool swapped = false;
      final int maxLook = math.min(list.length - 1, i + 12);

      for (int j = i + 1; j <= maxLook; j++) {
        if (_hsvDistance(a, list[j]) >= threshold) {
          final tmp = list[i];
          list[i] = list[j];
          list[j] = tmp;
          swapped = true;
          break;
        }
      }
      if (!swapped) {
        final int ahead = list.length - i - 1;
        if (ahead > 0) {
          final int span = math.min(8, ahead);
          final int j = i + 1 + rnd.nextInt(span);
          final tmp = list[i];
          list[i] = list[j];
          list[j] = tmp;
        }
      }
    }
  }
}

/// Convert HSV samples to unique colors with jitter
List<Color> _toUniqueColors(
  List<HSV> samples,
  math.Random rnd,
  Map<int, int> counts, {
  int maxPerColor = 1,
}) {
  final Set<int> seen = <int>{};
  final List<Color> out = [];

  for (var c in samples) {
    HSV candidate = c;
    Color col = candidate.toColor();

    int tries = 0;
    while (seen.contains(col.toARGB32()) && tries < 10) {
      final dh = (rnd.nextDouble() * 0.50) - 0.25; // ±0.25°
      final ds = (rnd.nextDouble() * 0.02) - 0.01; // ±1%
      final dv = (rnd.nextDouble() * 0.02) - 0.01; // ±1%
      candidate = HSV(
        h: wrapHue(candidate.h + dh),
        s: clamp01(candidate.s + ds).clamp(_sMinGlobal, 1.0),
        v: clamp01(candidate.v + dv).clamp(_vMinGlobal, _vMaxGlobal),
      );
      col = candidate.toColor();
      tries++;
    }
    if (seen.contains(col.toARGB32())) {
      candidate = candidate.copyWith(h: wrapHue(candidate.h + 0.33));
      col = candidate.toColor();
    }

    out.add(col);
    seen.add(col.toARGB32());
    counts[col.toARGB32()] = 1;
  }
  return out;
}

/// Generate neutral greys using bucket distribution
List<Color> _makeNeutralsUnique(
  int n,
  math.Random rnd,
  Map<int, int> counts, {
  int maxPerColor = 1,
}) {
  final buckets = [
    _Bucket(0.00, 0.06, 0.15),
    _Bucket(0.06, 0.25, 0.25),
    _Bucket(0.25, 0.55, 0.25),
    _Bucket(0.55, 0.85, 0.20),
    _Bucket(0.85, 1.00, 0.15),
  ];
  final double totalW = buckets.fold(0.0, (a, b) => a + b.w);

  double pickV() {
    double pick = rnd.nextDouble() * totalW;
    _Bucket chosen = buckets.first;
    for (final b in buckets) {
      if (pick <= b.w) {
        chosen = b;
        break;
      }
      pick -= b.w;
    }
    return chosen.lo + rnd.nextDouble() * (chosen.hi - chosen.lo);
  }

  final Set<int> seen = counts.keys.toSet();
  final List<Color> out = [];
  for (int i = 0; i < n; i++) {
    double v = pickV();
    Color c = HSVColor.fromAHSV(1.0, 0.0, 0.0, v).toColor();

    int tries = 0;
    while (seen.contains(c.toARGB32()) && tries < 10) {
      v = (v + (rnd.nextDouble() * 0.015) - 0.0075).clamp(0.0, 1.0);
      c = HSVColor.fromAHSV(1.0, 0.0, 0.0, v).toColor();
      tries++;
    }
    if (seen.contains(c.toARGB32())) {
      v = (v + 0.004).clamp(0.0, 1.0);
      c = HSVColor.fromAHSV(1.0, 0.0, 0.0, v).toColor();
    }

    out.add(c);
    seen.add(c.toARGB32());
    counts[c.toARGB32()] = 1;
  }
  return out;
}

/// Internal bucket class for neutral grey generation
class _Bucket {
  final double lo, hi, w;
  const _Bucket(this.lo, this.hi, this.w);
}

/// Generate randomized palette with cluster-based sampling
List<Color> generateRandomizedPalette({
  required double baseHue,
  required int ringIndex,
  required int seed,
  int tileCount = 600,
}) {
  final rnd = math.Random(seed);
  final int ringKey = ringIndex.clamp(0, 9);
  final ClusterWeights weights = ClusterWeights.byRing[ringKey];
  final ClusterCounts counts = weights.asCounts(tileCount);
  final double hueJitter = _hueDrift[ringKey];

  final List<HSV> samples = [];

  void addCluster(Cluster cluster, int n) {
    for (int i = 0; i < n; i++) {
      final double h =
          (baseHue - hueJitter + rnd.nextDouble() * (2 * hueJitter)) % 360;
      double s =
          cluster.sMin + rnd.nextDouble() * (cluster.sMax - cluster.sMin);
      double v =
          cluster.vMin + rnd.nextDouble() * (cluster.vMax - cluster.vMin);

      if (s < _sMinGlobal) s = _sMinGlobal;
      if (v < _vMinGlobal) v = _vMinGlobal;
      if (v > _vMaxGlobal) v = _vMaxGlobal;

      final HSV adjusted0 = _antiBrownAdjust(HSV(h: h, s: s, v: v));
      final HSV adjusted = _applyRingBias(adjusted0, ringKey);
      samples.add(adjusted);
    }
  }

  addCluster(Cluster.pastel, counts.pastel);
  addCluster(Cluster.mid, counts.mid);
  addCluster(Cluster.vivid, counts.vivid);
  addCluster(Cluster.ink, counts.ink);
  addCluster(Cluster.neon, counts.neon);

  samples.shuffle(rnd);
  _antiClump(samples, rnd, threshold: _antiClumpThreshold);

  final Map<int, int> colorCounts = <int, int>{};
  List<Color> colors = _toUniqueColors(
    samples,
    rnd,
    colorCounts,
    maxPerColor: 1,
  );

  // Sprinkle neutrals for inner rings
  if (ringIndex <= 2) {
    final int L = colors.length;
    final int N = (L * 0.05).round().clamp(6, 9999);

    final Set<int> pos = <int>{};
    final int start = (L * 0.05).floor();
    while (pos.length < N) {
      final int span = (L - start) <= 1 ? 1 : (L - start);
      pos.add(start + rnd.nextInt(span));
    }
    final List<int> sortedPos = pos.toList()..sort();
    final List<Color> neutrals = _makeNeutralsUnique(
      N,
      rnd,
      colorCounts,
      maxPerColor: 1,
    );

    // Shuffle neutrals
    for (int i = 0; i < neutrals.length - 1; i++) {
      final int j = i + rnd.nextInt(neutrals.length - i);
      final tmp = neutrals[i];
      neutrals[i] = neutrals[j];
      neutrals[j] = tmp;
    }

    for (int i = 0; i < sortedPos.length; i++) {
      final int at = sortedPos[i] + i;
      final Color c = neutrals[i];
      colors.insert(at, c);
      colorCounts[c.toARGB32()] = 1;
    }
  }

  return colors;
}

/// Assign tile heights for masonry grid
List<int> assignTileHeights({required math.Random rnd, required int count}) {
  const double heroRate = 0.04;
  const int minUnits = 1;
  const int maxUnits = 3;

  final List<int> heights = List<int>.filled(count, minUnits);
  final int heroCount = (count * heroRate).round();
  final Set<int> heroIdx = <int>{};
  while (heroIdx.length < heroCount) {
    heroIdx.add(rnd.nextInt(count));
  }
  for (int i = 0; i < count; i++) {
    if (heroIdx.contains(i)) {
      heights[i] = 4;
    } else {
      heights[i] = minUnits + rnd.nextInt(maxUnits - minUnits + 1);
    }
  }
  return heights;
}
