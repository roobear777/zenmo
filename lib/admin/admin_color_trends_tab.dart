// lib/admin/admin_color_trends_tab.dart
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:color_wallet/admin/admin_components.dart'; // hue/hex helpers + tokens

/// One-page "Color Atlas" tab:
///  • Year-in-Color Tapestry (current calendar year, dominant hue per day)
///  • Hue Wheel (24 bins; area = freq; ring thickness = keep-rate)
///  • Hue Mosaic Bands (8 hue families; literal blocks from recent swatches)
///  • Sender→Recipient→Kept funnel (from the same all-time capped sample)
class AdminColorTrendsTab extends StatefulWidget {
  const AdminColorTrendsTab({
    super.key,
    required this.db,
    this.startUtc, // optional (ignored by current all-time sampling)
    this.endUtc, // optional (ignored by current all-time sampling)
    required this.maxDocs,
  });

  final FirebaseFirestore db;
  final Timestamp? startUtc; // optional
  final Timestamp? endUtc; // optional
  final int maxDocs;

  @override
  State<AdminColorTrendsTab> createState() => _AdminColorTrendsTabState();
}

class _AdminColorTrendsTabState extends State<AdminColorTrendsTab> {
  late Future<_AtlasData> _fut;
  static const TextStyle _subtle = TextStyle(
    fontSize: 12,
    color: Colors.black45,
  );

  @override
  void initState() {
    super.initState();
    _fut = _loadAtlas();
  }

  @override
  void didUpdateWidget(covariant AdminColorTrendsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // No-op for start/end updates: Trends uses an all-time capped sample now.
    if (oldWidget.db != widget.db || oldWidget.maxDocs != widget.maxDocs) {
      _fut = _loadAtlas();
      setState(() {});
    }
  }

  Future<_AtlasData> _loadAtlas() async {
    // ----- Query A: current calendar year (Tapestry) — still year-scoped by design
    final now = DateTime.now().toUtc();
    final jan1 = DateTime.utc(now.year, 1, 1);
    final jan1Next = DateTime.utc(now.year + 1, 1, 1);

    final yearSnap =
        await widget.db
            .collectionGroup('userSwatches')
            .where('status', isEqualTo: 'sent')
            .where('sentAt', isGreaterThanOrEqualTo: Timestamp.fromDate(jan1))
            .where('sentAt', isLessThan: Timestamp.fromDate(jan1Next))
            .orderBy('sentAt', descending: true)
            .limit(widget.maxDocs)
            .get();

    // Reduce to dominant hex per day (by hue-bin frequency, pick a representative hex).
    final Map<DateTime, Map<String, int>> byDayBin =
        {}; // dayUtc -> Hbin -> count
    final Map<DateTime, Map<String, String>> byDayBinHex =
        {}; // one hex per bin to display
    for (final d in yearSnap.docs) {
      final m = d.data();
      final ts = (m['sentAt'] as Timestamp?)?.toDate();
      final hex = (m['colorHex'] as String?) ?? '';
      if (ts == null || hex.isEmpty) continue;

      final dayUtc = DateTime.utc(ts.year, ts.month, ts.day);
      final bin = adminHueBinKey(hex); // H0..H11
      byDayBin.putIfAbsent(dayUtc, () => {});
      byDayBinHex.putIfAbsent(dayUtc, () => {});
      byDayBin[dayUtc]![bin] = (byDayBin[dayUtc]![bin] ?? 0) + 1;
      byDayBinHex[dayUtc]!.putIfAbsent(bin, () => adminNormalizeHex(hex));
    }

    final int daysInYear = _isLeap(now.year) ? 366 : 365;
    final DateTime firstDay = DateTime.utc(now.year, 1, 1);

    final List<_DayCell> tapestry = List.generate(daysInYear, (i) {
      final day = firstDay.add(Duration(days: i));
      final bins = byDayBin[day] ?? const {};
      if (bins.isEmpty) {
        // No data: render as a neutral gray chip.
        return _DayCell(dayUtc: day, hex: '#EEEEEE', hasKeep: false);
      }
      // pick max bin
      final bestBin =
          bins.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      final showHex = byDayBinHex[day]?[bestBin] ?? '#EEEEEE';
      // Visual hint for kept-days (heuristic; not re-scanning)
      final keptDay = true;
      return _DayCell(dayUtc: day, hex: showHex, hasKeep: keptDay);
    });

    // ----- Query B: All-time capped sample (Wheel + Bands + Funnel)
    final sampleSnap =
        await widget.db
            .collectionGroup('userSwatches')
            .where('status', isEqualTo: 'sent')
            .orderBy('sentAt', descending: true)
            .limit(widget.maxDocs)
            .get();

    // Wheel: 24 hue bins (15° each)
    final binsCount = List<int>.filled(24, 0);
    final binsKept = List<int>.filled(24, 0);

    // Bands: collect literal hexes per family
    final List<_HexChip> red = [],
        orange = [],
        yellow = [],
        green = [],
        teal = [],
        blue = [],
        purple = [],
        pinkNeu = [];

    // Funnel
    int sentTotal = 0;
    int receivedTotal = 0;
    int keptTotal = 0;

    for (final d in sampleSnap.docs) {
      final m = d.data();
      final hex = (m['colorHex'] as String?) ?? '';
      final kept = (m['kept'] as bool?) ?? false;
      final recipientId = (m['recipientId'] as String?) ?? '';

      // Funnel aggregates
      sentTotal += 1;
      if (recipientId.isNotEmpty) receivedTotal += 1;
      if (kept) keptTotal += 1;

      if (hex.isEmpty) continue;

      final hsv = adminHexToHsv(adminNormalizeHex(hex));
      final hue = hsv.h; // 0..360
      final bin24 = (hue ~/ 15).clamp(0, 23);
      binsCount[bin24] += 1;
      if (kept) binsKept[bin24] += 1;

      final fam = _hueFamily(hue);
      final chip = _HexChip(hex: adminNormalizeHex(hex), kept: kept);
      switch (fam) {
        case _HueFamily.red:
          red.add(chip);
          break;
        case _HueFamily.orange:
          orange.add(chip);
          break;
        case _HueFamily.yellow:
          yellow.add(chip);
          break;
        case _HueFamily.green:
          green.add(chip);
          break;
        case _HueFamily.teal:
          teal.add(chip);
          break;
        case _HueFamily.blue:
          blue.add(chip);
          break;
        case _HueFamily.purple:
          purple.add(chip);
          break;
        case _HueFamily.pinkNeutral:
          pinkNeu.add(chip);
          break;
      }
    }

    // Cap how many blocks we show per row to keep it neat.
    List<_HexChip> cap(List<_HexChip> list, [int n = 28]) =>
        list.length <= n ? list : list.sublist(0, n);

    return _AtlasData(
      tapestry: tapestry,
      wheelCounts: binsCount,
      wheelKept: binsKept,
      bands: _Bands(
        red: cap(red),
        orange: cap(orange),
        yellow: cap(yellow),
        green: cap(green),
        teal: cap(teal),
        blue: cap(blue),
        purple: cap(purple),
        pinkNeu: cap(pinkNeu),
      ),
      sentTotal: sentTotal,
      receivedTotal: receivedTotal,
      keptTotal: keptTotal,
      sampleCap: widget.maxDocs,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AtlasData>(
      future: _fut,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snap.data!;
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text('Color Atlas', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),

            // --- Tapestry label reflects year-scoped query ---
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 6),
              child: Text('Calendar year', style: _subtle),
            ),
            _TapestryCard(cells: data.tapestry),

            const SizedBox(height: 12),

            // --- Wheel/Bands label reflects capped all-time sample ---
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 6),
              child: Text(
                'All-time sample (max ${widget.maxDocs})',
                style: _subtle,
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _HueWheelCard(
                    counts: data.wheelCounts,
                    kept: data.wheelKept,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _HueBandsCard(bands: data.bands)),
              ],
            ),

            const SizedBox(height: 12),

            // --- Sender → Recipient → Kept funnel (same all-time sample window) ---
            _FunnelCard(
              sent: data.sentTotal,
              received: data.receivedTotal,
              kept: data.keptTotal,
              sampleCap: data.sampleCap,
            ),
          ],
        );
      },
    );
  }

  static bool _isLeap(int year) {
    if (year % 4 != 0) return false;
    if (year % 100 != 0) return true;
    return (year % 400 == 0);
  }
}

// === Data structs =================================================================

class _AtlasData {
  final List<_DayCell> tapestry;
  final List<int> wheelCounts; // 24 bins
  final List<int> wheelKept; // 24 bins
  final _Bands bands;
  final int sentTotal;
  final int receivedTotal;
  final int keptTotal;
  final int sampleCap;

  _AtlasData({
    required this.tapestry,
    required this.wheelCounts,
    required this.wheelKept,
    required this.bands,
    required this.sentTotal,
    required this.receivedTotal,
    required this.keptTotal,
    required this.sampleCap,
  });
}

class _DayCell {
  final DateTime dayUtc;
  final String hex;
  final bool hasKeep;
  _DayCell({required this.dayUtc, required this.hex, required this.hasKeep});
}

class _HexChip {
  final String hex;
  final bool kept;
  _HexChip({required this.hex, required this.kept});
}

class _Bands {
  final List<_HexChip> red, orange, yellow, green, teal, blue, purple, pinkNeu;
  _Bands({
    required this.red,
    required this.orange,
    required this.yellow,
    required this.green,
    required this.teal,
    required this.blue,
    required this.purple,
    required this.pinkNeu,
  });
}

enum _HueFamily { red, orange, yellow, green, teal, blue, purple, pinkNeutral }

// Hue family mapping (broad, human-readable)
_HueFamily _hueFamily(double hueDeg) {
  final h = (hueDeg % 360.0);
  if (h >= 350 || h < 10) return _HueFamily.red;
  if (h < 40) return _HueFamily.orange;
  if (h < 70) return _HueFamily.yellow;
  if (h < 160) return _HueFamily.green;
  if (h < 190) return _HueFamily.teal;
  if (h < 250) return _HueFamily.blue;
  if (h < 300) return _HueFamily.purple;
  return _HueFamily.pinkNeutral;
}

// === UI Cards =====================================================================

class _TapestryCard extends StatelessWidget {
  const _TapestryCard({required this.cells});
  final List<_DayCell> cells;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kAdminBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Year-in-Color (dominant hue per day)'),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                const baseGap = 1.0; // desired gap between chips
                final gaps = math.max(0, cells.length - 1);
                final rawW = (w - gaps * baseGap) / cells.length;
                final cellW = rawW.clamp(2.0, 10.0);
                const cellH = 28.0;

                // Recompute gap to absorb rounding error (prevents overflow)
                final usedGap =
                    gaps == 0 ? 0.0 : (w - cellW * cells.length) / gaps;

                return SizedBox(
                  height: cellH + 8,
                  child: Row(
                    children: List.generate(cells.length, (i) {
                      final c = cells[i];
                      final color = adminColorFromHex(c.hex);
                      return Padding(
                        padding: EdgeInsets.only(
                          right: i == cells.length - 1 ? 0 : usedGap,
                        ),
                        child: Container(
                          width: cellW,
                          height: cellH,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(3),
                            border:
                                c.hasKeep
                                    ? Border.all(
                                      color: Colors.white,
                                      width: 1.5,
                                    )
                                    : Border.all(
                                      color: Colors.black12,
                                      width: 0.5,
                                    ),
                          ),
                        ),
                      );
                    }),
                  ),
                );
              },
            ),
            const SizedBox(height: 6),
            // Month ticks (visual only)
            _MonthTicksRow(),
          ],
        ),
      ),
    );
  }
}

class _MonthTicksRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final yearStart = DateTime.utc(now.year, 1, 1);
    final totalDays = ((DateTime.utc(
          now.year + 1,
          1,
          1,
        )).difference(yearStart).inDays)
        .clamp(365, 366);
    final months = List.generate(12, (i) => i + 1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        return SizedBox(
          height: 20,
          child: Stack(
            children: [
              for (final m in months)
                Positioned(
                  left:
                      (w * _dayIndexOfMonthStart(now.year, m) / totalDays)
                          .toDouble(),
                  child: Container(width: 1, height: 10, color: kAdminDivider),
                ),
              Align(
                alignment: Alignment.center,
                child: Text(
                  '${now.year}',
                  style: const TextStyle(fontSize: 12, color: kAdminMuted),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static int _dayIndexOfMonthStart(int year, int month) {
    final start = DateTime.utc(year, 1, 1);
    final that = DateTime.utc(year, month, 1);
    return that.difference(start).inDays;
  }
}

class _HueWheelCard extends StatelessWidget {
  const _HueWheelCard({required this.counts, required this.kept});
  final List<int> counts; // 24
  final List<int> kept; // 24

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kAdminBorder),
      ),
      child: AspectRatio(
        aspectRatio: 1,
        child: CustomPaint(
          painter: _HueWheelPainter(counts: counts, kept: kept),
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Align(
              alignment: Alignment.topCenter,
              child: Text('Hue Wheel (area = freq, ring = kept)'),
            ),
          ),
        ),
      ),
    );
  }
}

class _HueWheelPainter extends CustomPainter {
  _HueWheelPainter({required this.counts, required this.kept});
  final List<int> counts; // 24
  final List<int> kept; // 24

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radiusMax = math.min(cx, cy) - 16;

    final maxCount = counts.fold<int>(1, (m, v) => math.max(m, v));
    final sweep = 2 * math.pi / 24;

    final fill = Paint()..style = PaintingStyle.fill;
    final ring =
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.white
          ..strokeCap = StrokeCap.butt;

    for (int i = 0; i < 24; i++) {
      final hue = i * 15.0;
      final ratio = counts[i] / maxCount;
      final r = radiusMax * (0.35 + 0.65 * ratio);
      fill.color = _hsvToColor(hue, 0.85, 0.6);

      final start = -math.pi / 2 + i * sweep;
      final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
      canvas.drawArc(rect, start, sweep, true, fill);

      final keptRate = counts[i] == 0 ? 0.0 : kept[i] / counts[i];
      if (keptRate > 0) {
        ring.strokeWidth = 1.5 + 3.5 * keptRate;
        final outer = Rect.fromCircle(center: Offset(cx, cy), radius: r);
        canvas.drawArc(outer, start, sweep, false, ring);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HueWheelPainter old) {
    return old.counts != counts || old.kept != kept;
  }

  static Color _hsvToColor(double h, double s, double v) {
    // Simple HSV→RGB conversion
    final c = v * s;
    final x = c * (1 - ((h / 60) % 2 - 1).abs());
    final m = v - c;
    double r = 0, g = 0, b = 0;
    if (h < 60) {
      r = c;
      g = x;
    } else if (h < 120) {
      r = x;
      g = c;
    } else if (h < 180) {
      g = c;
      b = x;
    } else if (h < 240) {
      g = x;
      b = c;
    } else if (h < 300) {
      r = x;
      b = c;
    } else {
      r = c;
      b = x;
    }
    return Color.fromARGB(
      0xFF,
      ((r + m) * 255).round(),
      ((g + m) * 255).round(),
      ((b + m) * 255).round(),
    );
  }
}

class _HueBandsCard extends StatelessWidget {
  const _HueBandsCard({required this.bands});
  final _Bands bands;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, List<_HexChip> chips) {
      final items = chips;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 84,
              child: Text(label, style: const TextStyle(color: kAdminText)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children:
                    items.map((c) {
                      final color = adminColorFromHex(c.hex);
                      return Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: c.kept ? Colors.white : Colors.black12,
                            width: c.kept ? 2 : 1,
                          ),
                        ),
                      );
                    }).toList(),
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      elevation: 0,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kAdminBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Hue Mosaic Bands (recent)'),
            const SizedBox(height: 8),
            row('Red', bands.red),
            row('Orange', bands.orange),
            row('Yellow', bands.yellow),
            row('Green', bands.green),
            row('Teal', bands.teal),
            row('Blue', bands.blue),
            row('Purple', bands.purple),
            row('Pink/Neu', bands.pinkNeu),
          ],
        ),
      ),
    );
  }
}

// === Funnel UI ====================================================================

class _FunnelCard extends StatelessWidget {
  const _FunnelCard({
    required this.sent,
    required this.received,
    required this.kept,
    required this.sampleCap,
  });

  final int sent;
  final int received;
  final int kept;
  final int sampleCap;

  double _safePct(int num, int den) => den <= 0 ? 0.0 : (num / den);

  @override
  Widget build(BuildContext context) {
    final recvRate = _safePct(received, sent);
    final keepRate = _safePct(kept, sent);
    final recvToKeepRate = _safePct(kept, received);

    Widget bar(String label, int v, int den) {
      final pct = _safePct(v, den);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$label • $v  (${(pct * 100).round()}%)',
              style: const TextStyle(color: kAdminText),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: pct.isNaN ? 0 : pct,
                minHeight: 10,
                backgroundColor: const Color(0xFFF0F2F5),
                color: const Color(0xFF4C9AFF),
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      elevation: 0,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kAdminBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sender → Recipient → Kept (all-time sample)'),
            const SizedBox(height: 6),
            Text(
              'Sampled up to $sampleCap recent swatches',
              style: const TextStyle(fontSize: 12, color: Colors.black45),
            ),

            const SizedBox(height: 12),
            // Bars (normalized to Sent for first two; Kept also shown vs Received)
            bar('Sent', sent, sent <= 0 ? 1 : sent),
            bar('Received', received, sent <= 0 ? 1 : sent),
            bar('Kept', kept, sent <= 0 ? 1 : sent),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _Kpi(
                  label: 'Received / Sent',
                  value: '${(recvRate * 100).round()}%',
                ),
                _Kpi(
                  label: 'Kept / Sent',
                  value: '${(keepRate * 100).round()}%',
                ),
                _Kpi(
                  label: 'Kept / Received',
                  value:
                      received == 0
                          ? '—'
                          : '${(recvToKeepRate * 100).round()}%',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: kAdminChipBg,
        border: Border.all(color: kAdminBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: kAdminText)),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              color: kAdminText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
